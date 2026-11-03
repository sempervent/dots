"""Model selection algorithm — cheapest qualifying OpenRouter model."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from .capabilities import (
    load_capabilities,
    meets_floor,
    quality_of,
    supports_task,
)
from .cost import estimate_cost, extract_prices


QUALITY_FLOOR_DEFAULT = "capable"


@dataclass
class Requirements:
    task_type: str = "general"
    languages: list[str] = field(default_factory=list)
    context_tokens: int = 8000
    expected_output_tokens: int = 2000
    requires_tools: bool = False
    requires_structured_output: bool = False
    requires_vision: bool = False
    quality_floor: str = "strong"
    max_cost_usd: float | None = 0.5
    latency_preference: str = "balanced"
    privacy_requirement: str = "default"

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> Requirements:
        return cls(
            task_type=str(d.get("task_type") or "general"),
            languages=[str(x) for x in (d.get("languages") or [])],
            context_tokens=int(d.get("context_tokens") or 8000),
            expected_output_tokens=int(d.get("expected_output_tokens") or 2000),
            requires_tools=bool(d.get("requires_tools")),
            requires_structured_output=bool(d.get("requires_structured_output")),
            requires_vision=bool(d.get("requires_vision")),
            quality_floor=str(d.get("quality_floor") or "strong"),
            max_cost_usd=(
                float(d["max_cost_usd"]) if d.get("max_cost_usd") is not None else None
            ),
            latency_preference=str(d.get("latency_preference") or "balanced"),
            privacy_requirement=str(d.get("privacy_requirement") or "default"),
        )


def _context_length(model: dict[str, Any]) -> int:
    for key in ("context_length", "context_window", "max_context_length"):
        v = model.get(key)
        if v is not None:
            try:
                return int(v)
            except (TypeError, ValueError):
                pass
    top = model.get("top_provider") or {}
    if isinstance(top, dict) and top.get("context_length") is not None:
        try:
            return int(top["context_length"])
        except (TypeError, ValueError):
            pass
    return 0


def _arch(model: dict[str, Any]) -> dict[str, Any]:
    a = model.get("architecture") or {}
    return a if isinstance(a, dict) else {}


def _supports_tools(model: dict[str, Any]) -> bool:
    # OpenRouter exposes supported_parameters including tools / tool_choice
    params = model.get("supported_parameters") or []
    if isinstance(params, list):
        lowered = {str(p).lower() for p in params}
        if "tools" in lowered or "tool_choice" in lowered:
            return True
    # Some payloads nest under architecture
    arch = _arch(model)
    mods = arch.get("modality") or arch.get("input_modalities") or []
    _ = mods
    # If explicitly listed in supported_parameters as empty → unknown/false
    if params:
        return "tools" in {str(p).lower() for p in params}
    # Unknown → do not claim support
    return False


def _supports_structured(model: dict[str, Any]) -> bool:
    params = model.get("supported_parameters") or []
    if isinstance(params, list):
        lowered = {str(p).lower() for p in params}
        if "response_format" in lowered or "structured_outputs" in lowered:
            return True
    return False


def _supports_vision(model: dict[str, Any]) -> bool:
    arch = _arch(model)
    inputs = arch.get("input_modalities") or []
    if isinstance(inputs, list) and "image" in inputs:
        return True
    modality = str(arch.get("modality") or "")
    return "image" in modality


def select_model(
    models: list[dict[str, Any]],
    req: Requirements,
    *,
    capabilities_path,
    max_candidates: int = 5,
    provider_sort: str = "price",
) -> dict[str, Any]:
    rules, tiers = load_capabilities(capabilities_path)
    rejected = {
        "context": 0,
        "tools": 0,
        "structured_output": 0,
        "vision": 0,
        "quality_floor": 0,
        "budget": 0,
        "missing_price": 0,
        "task_class": 0,
    }
    survivors: list[dict[str, Any]] = []

    for m in models:
        mid = str(m.get("id") or m.get("name") or "")
        if not mid:
            continue

        # 1. Account availability — catalog already filtered when using /models/user
        # 2. Modality
        if req.requires_vision and not _supports_vision(m):
            rejected["vision"] += 1
            continue
        # 3. Context length
        ctx = _context_length(m)
        if ctx and ctx < req.context_tokens:
            rejected["context"] += 1
            continue
        if not ctx:
            # Missing context metadata → reject for safety when large context requested
            if req.context_tokens > 4096:
                rejected["context"] += 1
                continue
        # 4. Tools / structured
        if req.requires_tools and not _supports_tools(m):
            rejected["tools"] += 1
            continue
        if req.requires_structured_output and not _supports_structured(m):
            rejected["structured_output"] += 1
            continue
        # 5. Local quality floor
        q = quality_of(mid, rules)
        if not meets_floor(q, req.quality_floor, tiers):
            rejected["quality_floor"] += 1
            continue
        task_ok = supports_task(mid, req.task_type, rules)
        if task_ok is False:
            rejected["task_class"] += 1
            continue
        # 6. Cost
        est = estimate_cost(
            m,
            input_tokens=req.context_tokens,
            output_tokens=req.expected_output_tokens,
        )
        if not est.get("ok"):
            rejected["missing_price"] += 1
            continue
        total = float(est["estimated_total_cost"])
        if req.max_cost_usd is not None and total > float(req.max_cost_usd) + 1e-12:
            rejected["budget"] += 1
            continue

        survivors.append(
            {
                "model": mid,
                "quality": q,
                "estimated_cost_usd": total,
                "estimated_input_cost": est["estimated_input_cost"],
                "estimated_output_cost": est["estimated_output_cost"],
                "context_length": ctx,
                "supports_tools": _supports_tools(m),
                "supports_structured_output": _supports_structured(m),
                "supports_vision": _supports_vision(m),
                "estimate": True,
            }
        )

    survivors.sort(key=lambda r: (r["estimated_cost_usd"], r["model"]))
    selected = survivors[0] if survivors else None
    alternatives = survivors[1:max_candidates]

    return {
        "selected": selected,
        "routing": {"provider_sort": provider_sort},
        "alternatives": alternatives,
        "rejected_summary": rejected,
        "candidate_count": len(survivors),
    }


def explain_choice(
    models: list[dict[str, Any]],
    req: Requirements,
    *,
    capabilities_path,
    model_id: str | None = None,
) -> dict[str, Any]:
    result = select_model(models, req, capabilities_path=capabilities_path)
    selected = result.get("selected")
    rules, tiers = load_capabilities(capabilities_path)
    lines: list[str] = []
    if selected:
        lines.append(
            f"{selected['model']} won as cheapest qualifying model "
            f"(~${selected['estimated_cost_usd']:.4f}, quality={selected['quality']})."
        )
    else:
        lines.append("No model satisfied all requirements.")
    if model_id:
        q = quality_of(model_id, rules)
        match = next((m for m in models if str(m.get("id")) == model_id), None)
        if not match:
            lines.append(f"{model_id} was not in the catalog.")
        else:
            why: list[str] = []
            if _context_length(match) < req.context_tokens:
                why.append("insufficient context")
            if req.requires_tools and not _supports_tools(match):
                why.append("missing tool support")
            if not meets_floor(q, req.quality_floor, tiers):
                why.append(f"quality {q} below floor {req.quality_floor}")
            est = estimate_cost(
                match,
                input_tokens=req.context_tokens,
                output_tokens=req.expected_output_tokens,
            )
            if est.get("ok") and req.max_cost_usd is not None:
                if float(est["estimated_total_cost"]) > float(req.max_cost_usd):
                    why.append("over budget")
            if extract_prices(match) == (None, None):
                why.append("missing price metadata")
            if why:
                lines.append(f"{model_id} excluded: {', '.join(why)}.")
            elif selected and selected["model"] != model_id:
                lines.append(
                    f"{model_id} qualified but was more expensive than {selected['model']}."
                )
            else:
                lines.append(f"{model_id} is the selected model.")
    # Cheaper but failed quality
    cheaper_failed = []
    for m in models:
        mid = str(m.get("id") or "")
        est = estimate_cost(
            m, input_tokens=req.context_tokens, output_tokens=req.expected_output_tokens
        )
        if not est.get("ok"):
            continue
        if selected and float(est["estimated_total_cost"]) >= float(
            selected["estimated_cost_usd"]
        ):
            continue
        q = quality_of(mid, rules)
        if not meets_floor(q, req.quality_floor, tiers):
            cheaper_failed.append((mid, est["estimated_total_cost"], q))
    cheaper_failed.sort(key=lambda x: x[1])
    for mid, cost, q in cheaper_failed[:5]:
        lines.append(
            f"Cheaper but below quality floor: {mid} (~${cost:.4f}, quality={q})."
        )
    return {
        "explanation": lines,
        "selection": result,
        "what_if_budget_0_25": select_model(
            models,
            Requirements(
                **{
                    **req.__dict__,
                    "max_cost_usd": 0.25,
                }
            ),
            capabilities_path=capabilities_path,
        ).get("selected"),
    }
