"""Lightweight binomial statistics for eval evidence (stdlib only)."""

from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass(frozen=True)
class BinomialSummary:
    attempts: int
    successes: int
    raw_rate: float | None
    wilson_lower: float | None
    wilson_upper: float | None


def wilson_interval(
    successes: int,
    attempts: int,
    *,
    z: float = 1.96,
) -> tuple[float | None, float | None]:
    """Wilson score interval for a binomial proportion.

    Returns (lower, upper). For attempts == 0 returns (None, None).
    """
    if attempts < 0 or successes < 0 or successes > attempts:
        raise ValueError("invalid successes/attempts")
    if attempts == 0:
        return None, None
    p = successes / attempts
    z2 = z * z
    denom = 1.0 + z2 / attempts
    center = p + z2 / (2.0 * attempts)
    rad = z * math.sqrt((p * (1.0 - p) / attempts) + (z2 / (4.0 * attempts * attempts)))
    lower = (center - rad) / denom
    upper = (center + rad) / denom
    # Clamp numerical noise
    return max(0.0, min(1.0, lower)), max(0.0, min(1.0, upper))


def summarize_binomial(
    successes: int,
    attempts: int,
    *,
    z: float = 1.96,
) -> BinomialSummary:
    raw = (successes / attempts) if attempts else None
    lo, hi = wilson_interval(successes, attempts, z=z)
    return BinomialSummary(
        attempts=attempts,
        successes=successes,
        raw_rate=raw,
        wilson_lower=lo,
        wilson_upper=hi,
    )


def expected_cost_to_success(
    attempt_cost: float,
    conservative_p: float | None,
) -> float | None:
    """attempt_cost / p; None when p is missing or non-positive."""
    if conservative_p is None or conservative_p <= 0.0:
        return None
    if attempt_cost < 0:
        raise ValueError("attempt_cost must be >= 0")
    return attempt_cost / conservative_p


def bounded_expected_spend(
    attempt_cost: float,
    p: float | None,
    *,
    max_attempts: int,
) -> float | None:
    """Expected spend over at most N independent attempts (geometric truncated).

    E[spend] = c * (1 - (1-p)^N) / p   for p in (0,1]
    For p == 1: c (one attempt)
    For p is None or <= 0: None
    """
    if p is None or p <= 0.0:
        return None
    if max_attempts < 1:
        raise ValueError("max_attempts must be >= 1")
    if attempt_cost < 0:
        raise ValueError("attempt_cost must be >= 0")
    if p >= 1.0:
        return float(attempt_cost)
    # Expected number of attempts until success truncated at N:
    # sum_{k=1..N} k * p * (1-p)^{k-1}  +  N*(1-p)^N
    # Equivalent spend = c * that quantity.
    q = 1.0 - p
    expected_attempts = 0.0
    for k in range(1, max_attempts + 1):
        expected_attempts += k * p * (q ** (k - 1))
    expected_attempts += max_attempts * (q**max_attempts)
    return attempt_cost * expected_attempts
