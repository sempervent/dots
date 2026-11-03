"""Model selection — expected cost-to-success when empirical evidence exists."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable

from dots_agent.routing.evidence import (
    EvidenceType,
    ModelClassEvidence,
    empirical_meets_floor,
)
from dots_agent.stats import expected_cost_to_success

from .capabilities import (
    load_capabilities,
    meets_floor,
    quality_of,
    supports_task,
)
from .cost import estimate_cost, extract_prices

ROUTING_POLICY_VERSION = 1
QUALITY_FLOOR_DEFAULT = "capable"

EvidenceLookup = Callable[[str, str], ModelClassEvidence | None]


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
    params = model.get("supported_parameters") or []
    if isinstance(params, list):
        lowered = {str(p).lower() for p in params}
        if "tools" in lowered or "tool_choice" in lowered:
            return True
    if params:
        return "tools" in {str(p).lower() for p in params}
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


def _default_quality_cfg() -> dict[str, float]:
    return {
        "basic": 0.40,
        "capable": 0.60,
        "strong": 0.80,
        "frontier": 0.90,
    }


def select_model(
    models: list[dict[str, Any]],
    req: Requirements,
    *,
    capabilities_path,
    max_candidates: int = 5,
    provider_sort: str = "price",
    evidence_lookup: EvidenceLookup | None = None,
    quality_cfg: dict[str, float] | None = None,
    minimum_attempts: int = 5,
    preference: str = "economy",
    routing_policy_version: int = ROUTING_POLICY_VERSION,
) -> dict[str, Any]:
    """Lexicographic selection with empirical expected-cost ranking.

    Order:
      1. hard API capability constraints
      2. quality/reliability floor (Wilson lower bound when adequate empirical)
      3. context requirement (already filtered)
      4. budget
      5. minimize expected cost-to-success (empirical) else request cost (curated)
      6. latency tie-breaker (balanced preference)
      7. model ID deterministic final tie-break
    """
    rules, tiers = load_capabilities(capabilities_path)
    qcfg = quality_cfg or _default_quality_cfg()
    rejected = {
        "context": 0,
        "tools": 0,
        "structured_output": 0,
        "vision": 0,
        "quality_floor": 0,
        "budget": 0,
        "missing_price": 0,
        "task_class": 0,
        "empirical_floor": 0,
    }
    survivors: list[dict[str, Any]] = []

    for m in models:
        mid = str(m.get("id") or m.get("name") or "")
        if not mid:
            continue

        if req.requires_vision and not _supports_vision(m):
            rejected["vision"] += 1
            continue
        ctx = _context_length(m)
        if ctx and ctx < req.context_tokens:
            rejected["context"] += 1
            continue
        if not ctx and req.context_tokens > 4096:
            rejected["context"] += 1
            continue
        if req.requires_tools and not _supports_tools(m):
            rejected["tools"] += 1
            continue
        if req.requires_structured_output and not _supports_structured(m):
            rejected["structured_output"] += 1
            continue

        curated_q = quality_of(mid, rules)
        task_ok = supports_task(mid, req.task_type, rules)
        if task_ok is False:
            rejected["task_class"] += 1
            continue

        est = estimate_cost(
            m,
            input_tokens=req.context_tokens,
            output_tokens=req.expected_output_tokens,
        )
        # Local / zero-price models: treat missing price as $0 when marked local
        is_local = bool(m.get("_dots_local")) or mid.startswith("local/")
        if not est.get("ok"):
            if is_local:
                est = {
                    "ok": True,
                    "estimated_input_cost": 0.0,
                    "estimated_output_cost": 0.0,
                    "estimated_total_cost": 0.0,
                }
            else:
                rejected["missing_price"] += 1
                continue
        total = float(est["estimated_total_cost"])
        if req.max_cost_usd is not None and total > float(req.max_cost_usd) + 1e-12:
            rejected["budget"] += 1
            continue

        evidence_type = EvidenceType.CURATED if curated_q != "unrated" else EvidenceType.UNRATED
        attempts = 0
        successes = 0
        raw_p: float | None = None
        cons_p: float | None = None
        expected_success: float | None = None
        median_lat: float | None = None
        used_empirical = False

        if evidence_lookup is not None:
            ev = evidence_lookup(mid, req.task_type)
            if ev is not None and ev.attempts > 0:
                attempts = ev.attempts
                successes = ev.successes
                raw_p = ev.raw_success_rate
                cons_p = ev.conservative_success_rate
                median_lat = ev.median_latency
                if ev.adequate(minimum_attempts):
                    used_empirical = True
                    evidence_type = EvidenceType.EMPIRICAL
                    if not empirical_meets_floor(cons_p, req.quality_floor, qcfg):
                        rejected["empirical_floor"] += 1
                        continue
                    expected_success = expected_cost_to_success(total, cons_p)
                elif ev.evidence is EvidenceType.EXTERNAL and ev.external_score is not None:
                    evidence_type = EvidenceType.EXTERNAL
                    # External never masquerades as success probability

        if not used_empirical:
            if not meets_floor(curated_q, req.quality_floor, tiers):
                rejected["quality_floor"] += 1
                continue
            # Curated path: request-cost ranking (no fabricated success probability)
            expected_success = None

        sort_cost = (
            expected_success
            if used_empirical and expected_success is not None
            else total
        )
        # Infinite sentinel for empirical with zero probability (should already be filtered)
        if used_empirical and expected_success is None:
            rejected["empirical_floor"] += 1
            continue

        survivors.append(
            {
                "model": mid,
                "quality": curated_q if not used_empirical else req.quality_floor,
                "curated_quality": curated_q,
                "evidence": evidence_type.value,
                "task_class": req.task_type,
                "attempts": attempts,
                "successes": successes,
                "raw_success_rate": raw_p,
                "conservative_success_rate": cons_p,
                "estimated_attempt_cost_usd": total,
                "estimated_cost_usd": total,  # backward compatible
                "expected_cost_to_success_usd": expected_success,
                "quality_floor": req.quality_floor,
                "estimated_input_cost": est["estimated_input_cost"],
                "estimated_output_cost": est["estimated_output_cost"],
                "context_length": ctx,
                "supports_tools": _supports_tools(m),
                "supports_structured_output": _supports_structured(m),
                "supports_vision": _supports_vision(m),
                "median_latency": median_lat,
                "estimate": True,
                "_sort_cost": sort_cost,
                "_empirical": used_empirical,
            }
        )

    def sort_key(r: dict[str, Any]) -> tuple:
        cost = float(r["_sort_cost"])
        lat = r.get("median_latency")
        # economy: cost only; balanced: tiny latency weight when present
        if preference == "balanced" and lat is not None:
            return (cost, float(lat), r["model"])
        return (cost, r["model"])

    survivors.sort(key=sort_key)
    selected = survivors[0] if survivors else None
    alternatives = survivors[1:max_candidates]

    why: list[str] = []
    if selected:
        if selected.get("_empirical"):
            why.append(
                f"{selected['model']} selected by expected cost-to-success "
                f"(~${selected['expected_cost_to_success_usd']:.4f}) "
                f"with conservative success {100 * (selected['conservative_success_rate'] or 0):.1f}%."
            )
        else:
            why.append(
                f"{selected['model']} selected as cheapest qualifying curated model "
                f"(~${selected['estimated_cost_usd']:.4f}, evidence={selected['evidence']})."
            )
        for alt in survivors[1:6]:
            if alt.get("_empirical") and selected.get("_empirical"):
                if float(alt["estimated_attempt_cost_usd"]) < float(
                    selected["estimated_attempt_cost_usd"]
                ):
                    why.append(
                        f"{alt['model']} was cheaper/call "
                        f"(${alt['estimated_attempt_cost_usd']:.4f}) but less reliable "
                        f"(conservative {100 * (alt['conservative_success_rate'] or 0):.1f}% → "
                        f"expected ${alt['expected_cost_to_success_usd']:.4f})."
                    )
            elif float(alt["estimated_cost_usd"]) < float(selected["estimated_cost_usd"]):
                why.append(
                    f"{alt['model']} cheaper/call but lost on quality/evidence ranking."
                )

    # Strip internal keys
    def public(row: dict[str, Any] | None) -> dict[str, Any] | None:
        if row is None:
            return None
        return {k: v for k, v in row.items() if not k.startswith("_")}

    return {
        "selected": public(selected),
        "routing": {
            "provider_sort": provider_sort,
            "policy_version": routing_policy_version,
            "preference": preference,
            "minimum_attempts": minimum_attempts,
        },
        "alternatives": [public(a) for a in alternatives],
        "rejected_summary": rejected,
        "candidate_count": len(survivors),
        "explanation": why,
    }


def explain_choice(
    models: list[dict[str, Any]],
    req: Requirements,
    *,
    capabilities_path,
    model_id: str | None = None,
    evidence_lookup: EvidenceLookup | None = None,
    quality_cfg: dict[str, float] | None = None,
    minimum_attempts: int = 5,
    preference: str = "economy",
) -> dict[str, Any]:
    result = select_model(
        models,
        req,
        capabilities_path=capabilities_path,
        evidence_lookup=evidence_lookup,
        quality_cfg=quality_cfg,
        minimum_attempts=minimum_attempts,
        preference=preference,
    )
    selected = result.get("selected")
    rules, tiers = load_capabilities(capabilities_path)
    lines: list[str] = list(result.get("explanation") or [])
    if not lines:
        if selected:
            lines.append(
                f"{selected['model']} won "
                f"(evidence={selected.get('evidence')}, "
                f"~${selected.get('estimated_cost_usd', 0):.4f})."
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
            if extract_prices(match) == (None, None) and not match.get("_dots_local"):
                why.append("missing price metadata")
            if why:
                lines.append(f"{model_id} excluded: {', '.join(why)}.")
            elif selected and selected["model"] != model_id:
                lines.append(
                    f"{model_id} qualified but lost ranking to {selected['model']}."
                )
            else:
                lines.append(f"{model_id} is the selected model.")
    cheaper_failed = []
    for m in models:
        mid = str(m.get("id") or "")
        est = estimate_cost(
            m, input_tokens=req.context_tokens, output_tokens=req.expected_output_tokens
        )
        if not est.get("ok"):
            continue
        if selected and float(est["estimated_total_cost"]) >= float(
            selected.get("estimated_cost_usd") or selected.get("estimated_attempt_cost_usd") or 0
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
            evidence_lookup=evidence_lookup,
            quality_cfg=quality_cfg,
            minimum_attempts=minimum_attempts,
            preference=preference,
        ).get("selected"),
    }


def local_satisfies_floor(
    *,
    model_id: str,
    task_class: str,
    quality_floor: str,
    evidence_lookup: EvidenceLookup,
    quality_cfg: dict[str, float] | None = None,
    minimum_attempts: int = 5,
) -> dict[str, Any]:
    """Pre-task local-first check using empirical evidence only."""
    qcfg = quality_cfg or _default_quality_cfg()
    ev = evidence_lookup(model_id, task_class)
    if ev is None or not ev.adequate(minimum_attempts):
        return {
            "ok": False,
            "reason": "insufficient_empirical",
            "evidence": ev.evidence.value if ev else EvidenceType.UNRATED.value,
            "attempts": ev.attempts if ev else 0,
        }
    ok = empirical_meets_floor(ev.conservative_success_rate, quality_floor, qcfg)
    return {
        "ok": ok,
        "reason": "meets_floor" if ok else "below_floor",
        "evidence": EvidenceType.EMPIRICAL.value,
        "attempts": ev.attempts,
        "conservative_success_rate": ev.conservative_success_rate,
        "raw_success_rate": ev.raw_success_rate,
    }
