"""Cost estimation from OpenRouter pricing metadata."""

from __future__ import annotations

from typing import Any


def _f(x: Any) -> float | None:
    if x is None:
        return None
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def extract_prices(model: dict[str, Any]) -> tuple[float | None, float | None]:
    """Return (prompt_price_per_token, completion_price_per_token).

    OpenRouter exposes pricing as USD per token strings under pricing.prompt /
    pricing.completion (sometimes nested).
    """
    pricing = model.get("pricing") or {}
    if not isinstance(pricing, dict):
        return None, None
    inp = _f(pricing.get("prompt") or pricing.get("input"))
    out = _f(pricing.get("completion") or pricing.get("output"))
    return inp, out


def estimate_cost(
    model: dict[str, Any],
    *,
    input_tokens: int,
    output_tokens: int,
) -> dict[str, Any]:
    inp_p, out_p = extract_prices(model)
    if inp_p is None or out_p is None:
        return {
            "ok": False,
            "reason": "missing_price_metadata",
            "estimated_input_cost": None,
            "estimated_output_cost": None,
            "estimated_total_cost": None,
            "estimate": True,
        }
    in_c = input_tokens * inp_p
    out_c = output_tokens * out_p
    total = in_c + out_c
    return {
        "ok": True,
        "estimated_input_cost": round(in_c, 8),
        "estimated_output_cost": round(out_c, 8),
        "estimated_total_cost": round(total, 8),
        "estimate": True,
        "input_price_per_token": inp_p,
        "output_price_per_token": out_p,
    }
