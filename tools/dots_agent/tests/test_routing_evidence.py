"""Evidence hierarchy and staleness."""

from __future__ import annotations

import time
from pathlib import Path

from dots_agent.evals.storage import AttemptRecord, EvalStore, SCHEMA_VERSION
from dots_agent.routing.evidence import (
    EvidenceType,
    empirical_meets_floor,
    load_empirical_evidence,
)
from dots_agent.scout.select import Requirements, select_model


ROOT = Path(__file__).resolve().parents[3]
CAPS = ROOT / "configs" / "agents" / "model-capabilities.toml"


def test_insufficient_evidence_falls_back_curated():
    # Without evidence_lookup, unrated cannot meet strong (existing rule)
    models = [
        {
            "id": "test/unrated-cheap",
            "context_length": 32000,
            "supported_parameters": ["tools"],
            "pricing": {"prompt": "0.000001", "completion": "0.000001"},
        }
    ]
    req = Requirements(
        task_type="coding",
        context_tokens=1000,
        expected_output_tokens=100,
        requires_tools=True,
        quality_floor="strong",
        max_cost_usd=1.0,
    )
    result = select_model(models, req, capabilities_path=CAPS)
    assert result["selected"] is None
    assert result["rejected_summary"]["quality_floor"] >= 1


def test_wilson_floor_rejects_overconfident_small_sample():
    # 1/1 raw 100% but Wilson lower below strong=0.80
    assert not empirical_meets_floor(0.20, "strong", {"strong": 0.80})
    assert empirical_meets_floor(0.85, "strong", {"strong": 0.80})


def test_stale_evidence_not_adequate(tmp_path: Path):
    store = EvalStore(tmp_path)
    rid = "old"
    old = time.time() - 200 * 86400
    for _ in range(10):
        store.append_attempt(
            AttemptRecord(
                schema_version=SCHEMA_VERSION,
                eval_run_id=rid,
                task_id="t",
                model_id="m/stale",
                provider="x",
                task_class="debugging",
                language="",
                difficulty="basic",
                started_at=old,
                duration_seconds=1.0,
                status="PASS",
                passed=True,
                failure_reason="",
                input_tokens=0,
                output_tokens=0,
                estimated_cost_usd=0.0,
                actual_cost_usd=0.0,
                cost_source="estimated",
                tool_calls=0,
                iterations=1,
                scorer_summary="ok",
                temperature=0.0,
                seed=None,
                quantization="",
                backend="",
                context_config="",
            )
        )
    ev = load_empirical_evidence(
        store,
        model_id="m/stale",
        task_class="debugging",
        minimum_attempts=5,
        max_age_days=90,
    )
    # Filtered by age → no attempts counted
    assert ev.attempts == 0 or not ev.adequate(5)


def test_evidence_types_enum():
    assert EvidenceType.EMPIRICAL.value == "empirical"
    assert EvidenceType.CURATED.value == "curated"
    assert EvidenceType.EXTERNAL.value == "external"
    assert EvidenceType.UNRATED.value == "unrated"
