"""Empirical / external / curated evidence for model routing."""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any

from dots_agent.evals.storage import EvalStore
from dots_agent.stats import (
    bounded_expected_spend,
    expected_cost_to_success,
    summarize_binomial,
)


class EvidenceType(str, Enum):
    EMPIRICAL = "empirical"
    EXTERNAL = "external"
    CURATED = "curated"
    UNRATED = "unrated"


@dataclass
class ModelClassEvidence:
    model_id: str
    task_class: str
    evidence: EvidenceType
    attempts: int = 0
    successes: int = 0
    raw_success_rate: float | None = None
    conservative_success_rate: float | None = None
    median_latency: float | None = None
    p90_latency: float | None = None
    age_days: float | None = None
    stale: bool = False
    external_score: float | None = None
    external_source: str | None = None
    curated_quality: str | None = None

    def adequate(self, minimum_attempts: int) -> bool:
        return (
            self.evidence is EvidenceType.EMPIRICAL
            and self.attempts >= minimum_attempts
            and not self.stale
        )


def load_empirical_evidence(
    store: EvalStore,
    *,
    model_id: str,
    task_class: str,
    minimum_attempts: int = 5,
    max_age_days: float | None = 90.0,
    wilson_z: float = 1.96,
) -> ModelClassEvidence:
    now = time.time()
    attempts = 0
    successes = 0
    latencies: list[float] = []
    latest = 0.0
    for rec in store.iter_attempts():
        if rec.model_id != model_id:
            continue
        if rec.task_class != task_class:
            continue
        from dots_agent.evals.types import counts_toward_success, is_success

        if not counts_toward_success(rec.status):
            continue
        if max_age_days is not None and rec.started_at:
            age = (now - rec.started_at) / 86400.0
            if age > max_age_days:
                continue
        attempts += 1
        if is_success(rec.status):
            successes += 1
        latencies.append(rec.duration_seconds)
        latest = max(latest, rec.started_at or 0.0)

    summary = summarize_binomial(successes, attempts, z=wilson_z)
    age_days = ((now - latest) / 86400.0) if latest else None
    stale = False
    if max_age_days is not None and age_days is not None and age_days > max_age_days:
        stale = True
    latencies.sort()
    median = latencies[len(latencies) // 2] if latencies else None
    p90 = latencies[int(0.9 * (len(latencies) - 1))] if len(latencies) >= 5 else None
    evidence = EvidenceType.EMPIRICAL if attempts else EvidenceType.UNRATED
    ev = ModelClassEvidence(
        model_id=model_id,
        task_class=task_class,
        evidence=evidence,
        attempts=attempts,
        successes=successes,
        raw_success_rate=summary.raw_rate,
        conservative_success_rate=summary.wilson_lower,
        median_latency=median,
        p90_latency=p90,
        age_days=age_days,
        stale=stale,
    )
    if attempts and attempts < minimum_attempts:
        # Provisional empirical — not authoritative
        pass
    return ev


def load_external_benchmarks(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    rows = data.get("benchmarks") if isinstance(data, dict) else data
    return list(rows or [])


def quality_floor_probability(floor: str, quality_cfg: dict[str, float]) -> float:
    return float(quality_cfg.get(floor, quality_cfg.get("capable", 0.6)))


def empirical_meets_floor(
    conservative_p: float | None,
    floor: str,
    quality_cfg: dict[str, float],
) -> bool:
    if conservative_p is None:
        return False
    need = quality_floor_probability(floor, quality_cfg)
    return conservative_p + 1e-12 >= need


def annotate_economics(
    attempt_cost: float,
    evidence: ModelClassEvidence,
    *,
    max_attempts: int = 3,
) -> dict[str, Any]:
    p = evidence.conservative_success_rate
    return {
        "estimated_attempt_cost_usd": attempt_cost,
        "expected_cost_to_success_usd": expected_cost_to_success(attempt_cost, p),
        "bounded_expected_spend_usd": bounded_expected_spend(
            attempt_cost, p, max_attempts=max_attempts
        ),
        "conservative_success_rate": p,
        "raw_success_rate": evidence.raw_success_rate,
        "attempts": evidence.attempts,
        "successes": evidence.successes,
    }
