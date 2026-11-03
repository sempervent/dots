"""consult_expert — LiteLLM → OpenRouter with DOTS budget enforcement."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any

from dots_agent.budget import Budget
from dots_agent.config import AgentConfig
from dots_agent.secrets import reject_or_redact


def _gateway_chat(
    *,
    base_url: str,
    model: str,
    messages: list[dict[str, str]],
    provider_sort: str = "price",
    master_key: str | None = None,
    timeout: float = 120.0,
) -> dict[str, Any]:
    url = base_url.rstrip("/") + "/v1/chat/completions"
    # LiteLLM OpenRouter naming: openrouter/<provider>/<model>
    litellm_model = model if model.startswith("openrouter/") else f"openrouter/{model}"
    body: dict[str, Any] = {
        "model": litellm_model,
        "messages": messages,
        # OpenRouter provider price sort (verified provider.sort="price")
        "provider": {"sort": provider_sort},
    }
    data = json.dumps(body).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "dots-expert/0.1",
    }
    key = master_key or os.environ.get("LITELLM_MASTER_KEY") or "sk-dots-litellm-local"
    headers["Authorization"] = f"Bearer {key}"
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def extract_actual_cost(response: dict[str, Any]) -> float | None:
    usage = response.get("usage") or {}
    if isinstance(usage, dict) and usage.get("cost") is not None:
        try:
            return float(usage["cost"])
        except (TypeError, ValueError):
            pass
    # LiteLLM sometimes nests
    hidden = response.get("_hidden_params") or {}
    if isinstance(hidden, dict) and hidden.get("response_cost") is not None:
        try:
            return float(hidden["response_cost"])
        except (TypeError, ValueError):
            pass
    return None


def consult_expert(
    *,
    cfg: AgentConfig,
    budget: Budget,
    model: str,
    question: str,
    context: str = "",
    desired_output: str = "concise actionable advice",
    max_cost_usd: float | None = None,
    estimated_cost_usd: float | None = None,
    allow_network: bool = True,
    dry_run: bool = False,
    approve_expensive: bool = False,
    interactive: bool = False,
    gateway_callable=None,
) -> dict[str, Any]:
    """Billable remote consultation. No filesystem/shell access."""
    if not allow_network:
        return {"ok": False, "error": "remote consultation disabled (--local)"}

    packet = (
        f"Goal/question:\n{question}\n\n"
        f"Desired output:\n{desired_output}\n\n"
        f"Context packet:\n{context}\n"
    )
    try:
        packet, hits = reject_or_redact(packet, reject=True)
    except ValueError as exc:
        return {"ok": False, "error": str(exc)}

    est = estimated_cost_usd
    if est is None:
        est = max_cost_usd if max_cost_usd is not None else 0.05
    if max_cost_usd is not None and est > max_cost_usd + 1e-12:
        return {
            "ok": False,
            "error": f"estimated ${est:.4f} exceeds max_cost_usd ${max_cost_usd:.4f}",
        }

    threshold = cfg.approval_threshold_usd
    if est > threshold + 1e-12:
        if interactive:
            # Caller must have pre-approved; we don't prompt here in library form
            if not approve_expensive:
                return {
                    "ok": False,
                    "error": f"estimated ${est:.4f} exceeds approval threshold "
                    f"${threshold:.2f}; pass approve_expensive",
                }
        elif not approve_expensive:
            return {
                "ok": False,
                "error": f"estimated ${est:.4f} exceeds approval threshold "
                f"${threshold:.2f}; use --approve-expensive",
            }

    if not budget.can_afford(est):
        return {
            "ok": False,
            "error": "session budget exhausted or max remote calls reached",
            "budget": budget.snapshot(),
        }

    try:
        budget.reserve(est)
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc), "budget": budget.snapshot()}

    if dry_run:
        budget.settle(est, 0.0)
        return {
            "ok": True,
            "dry_run": True,
            "model": model,
            "estimated_cost_usd": est,
            "budget": budget.snapshot(),
        }

    messages = [
        {
            "role": "system",
            "content": (
                "You are a remote expert consultant. You have NO filesystem or shell. "
                "Give concrete advice for the local agent to apply. Be concise."
            ),
        },
        {"role": "user", "content": packet},
    ]

    call = gateway_callable or _gateway_chat
    try:
        resp = call(
            base_url=cfg.gateway_base_url,
            model=model,
            messages=messages,
            provider_sort=cfg.provider_sort,
        )
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        budget.settle(est, est)  # conservative: keep reserved as spent on failure path? 
        # Better: release reservation without charging if call never reached provider.
        # We already incremented remote_call_count; charge estimate to prevent loops.
        return {
            "ok": False,
            "error": f"LiteLLM/OpenRouter call failed: {exc}",
            "budget": budget.snapshot(),
            "secret_hits_redacted": len(hits),
        }

    actual = extract_actual_cost(resp)
    charged = budget.settle(est, actual)
    content = ""
    choices = resp.get("choices") or []
    if choices and isinstance(choices[0], dict):
        msg = choices[0].get("message") or {}
        content = str(msg.get("content") or "")

    return {
        "ok": True,
        "model": model,
        "content": content,
        "estimated_cost_usd": est,
        "actual_cost_usd": actual,
        "charged_usd": charged,
        "budget": budget.snapshot(),
        "routing": {"provider_sort": cfg.provider_sort, "via": "litellm"},
        "secret_hits_redacted": len(hits),
        "filesystem_access": None,
    }
