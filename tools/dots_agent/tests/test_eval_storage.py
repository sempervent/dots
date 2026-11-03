"""Eval storage and regression helpers."""

from __future__ import annotations

import time
from pathlib import Path

from dots_agent.evals.storage import AttemptRecord, EvalStore, SCHEMA_VERSION


def _rec(run_id: str, model: str, cls: str, passed: bool, **kw) -> AttemptRecord:
    return AttemptRecord(
        schema_version=SCHEMA_VERSION,
        eval_run_id=run_id,
        task_id="t1",
        model_id=model,
        provider="mock",
        task_class=cls,
        language="python",
        difficulty="basic",
        started_at=time.time(),
        duration_seconds=0.5,
        status="PASS" if passed else "MODEL_FAIL",
        passed=passed,
        failure_reason="" if passed else "fail",
        input_tokens=1,
        output_tokens=1,
        estimated_cost_usd=0.01,
        actual_cost_usd=0.01,
        cost_source="estimated",
        tool_calls=0,
        iterations=1,
        scorer_summary="ok",
        temperature=0.0,
        seed=None,
        quantization=kw.get("quantization", ""),
        backend=kw.get("backend", ""),
        context_config="",
    )


def test_append_and_results(tmp_path: Path):
    store = EvalStore(tmp_path)
    rid = store.new_run_id()
    for i in range(6):
        store.append_attempt(_rec(rid, "m/a", "debugging", passed=i < 5))
    rows = store.results_table()
    assert len(rows) == 1
    assert rows[0]["attempts"] == 6
    assert rows[0]["successes"] == 5
    assert rows[0]["conservative_success_rate"] is not None


def test_quantization_buckets_separate(tmp_path: Path):
    store = EvalStore(tmp_path)
    rid = store.new_run_id()
    store.append_attempt(_rec(rid, "local/qwen", "coding", True, quantization="q4", backend="ollama"))
    store.append_attempt(_rec(rid, "local/qwen", "coding", False, quantization="q8", backend="ollama"))
    # summaries keyed separately
    files = list((tmp_path / "summary").glob("*.json"))
    assert len(files) == 2


def test_baseline_regression(tmp_path: Path):
    store = EvalStore(tmp_path)
    base = "run-base"
    cur = "run-cur"
    for _ in range(10):
        store.append_attempt(_rec(base, "m/x", "coding", True))
    for i in range(10):
        store.append_attempt(_rec(cur, "m/x", "coding", passed=i < 3))
    store.set_baseline(base)
    findings = store.detect_regressions(current_run_id=cur, min_attempts=5, drop_threshold=0.2)
    assert findings
    assert findings[0]["model"] == "m/x"
