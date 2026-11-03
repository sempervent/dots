"""consult_expert — LiteLLM → OpenRouter with DOTS budget enforcement."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any

from dots_agent.budget import Budget
from dots_agent.config import AgentConfig
from dots_agent.secrets import load_litellm_master_key, reject_or_redact


def _classify_transport_failure(exc: BaseException) -> str:
    """Distinguish pre-provider failures from ambiguous/provider responses."""
    if isinstance(exc, urllib.error.HTTPError):
        # HTTP response received from gateway/provider path
        return "provider_responded"
    if isinstance(exc, urllib.error.URLError):
        reason = getattr(exc, "reason", None)
        msg = str(reason or exc).lower()
        if isinstance(reason, ConnectionRefusedError) or "connection refused" in msg:
            return "request_not_sent"
        if isinstance(reason, TimeoutError) or "timed out" in msg or "timeout" in msg:
            return "request_status_unknown"
        if "name or service not known" in msg or "nodename nor servname" in msg or "dns" in msg:
            return "request_not_sent"
        if isinstance(reason, OSError):
            return "request_not_sent"
        return "request_status_unknown"
    if isinstance(exc, TimeoutError):
        return "request_status_unknown"
    if isinstance(exc, ConnectionRefusedError):
        return "request_not_sent"
    if isinstance(exc, OSError):
        return "request_not_sent"
    if isinstance(exc, json.JSONDecodeError):
        return "provider_responded"
    return "request_status_unknown"


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
    key = master_key or load_litellm_master_key()
    if not key:
        raise RuntimeError(
            "LITELLM_MASTER_KEY unset — run ./dots setup --with litellm "
            "(or export LITELLM_MASTER_KEY)"
        )
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
            "result_state": "BUDGET_BLOCKED",
        }

    try:
        budget.reserve(est)
    except RuntimeError as exc:
        return {
            "ok": False,
            "error": str(exc),
            "budget": budget.snapshot(),
            "result_state": "BUDGET_BLOCKED",
        }

    if dry_run:
        budget.settle(est, 0.0)
        return {
            "ok": True,
            "dry_run": True,
            "model": model,
            "estimated_cost_usd": est,
            "budget": budget.snapshot(),
            "cost_basis": "none",
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
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError, RuntimeError) as exc:
        kind = _classify_transport_failure(exc)
        if kind == "request_not_sent":
            # Definitely never reached provider — do not fabricate spend.
            budget.release_reservation(est, count_against_max=True)
            cost_basis = "none"
            charged = 0.0
        elif kind == "provider_responded":
            # Provider/gateway answered with an error — conservative: charge estimate.
            charged = budget.settle(est, est)
            cost_basis = "estimated"
        else:
            # Ambiguous (timeout mid-flight etc.) — conservative unknown charge.
            charged = budget.settle(est, est)
            cost_basis = "unknown"
        return {
            "ok": False,
            "error": f"LiteLLM/OpenRouter call failed: {exc}",
            "budget": budget.snapshot(),
            "secret_hits_redacted": len(hits),
            "transport": kind,
            "cost_basis": cost_basis,
            "charged_usd": charged,
            "result_state": "FAILED",
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
        "cost_basis": "actual" if actual is not None else "estimated",
        "budget": budget.snapshot(),
        "routing": {"provider_sort": cfg.provider_sort, "via": "litellm"},
        "secret_hits_redacted": len(hits),
        "filesystem_access": None,
        "result_state": "COMPLETED",
    }
