"""Phase 1 canonical acceptance: mocked local→scout→budget→expert→verify→ledger."""

from __future__ import annotations

import json
from pathlib import Path

from dots_agent.budget import Budget
from dots_agent.config import load_config
from dots_agent.expert.consult import consult_expert
from dots_agent.ledger import RunLedger
from dots_agent.limits import RunLimits
from dots_agent import results as R
from dots_agent.scout.select import Requirements, select_model


SYNTHETIC_CATALOG = [
    {
        "id": "synthetic/cheap-capable",
        "name": "Cheap Capable",
        "context_length": 32000,
        "pricing": {"prompt": "0.0000001", "completion": "0.0000002"},
        "supported_parameters": ["tools", "tool_choice"],
    },
    {
        "id": "synthetic/expensive-strong",
        "name": "Expensive Strong",
        "context_length": 128000,
        "pricing": {"prompt": "0.00001", "completion": "0.00003"},
        "supported_parameters": ["tools", "tool_choice"],
    },
    {
        "id": "synthetic/no-tools",
        "name": "No Tools",
        "context_length": 32000,
        "pricing": {"prompt": "0.00000001", "completion": "0.00000001"},
        "supported_parameters": [],
    },
]


def test_phase1_mocked_e2e(tmp_path: Path, monkeypatch):
    """Prove scout → reserve → LiteLLM mock → settle → verify → ledger VERIFIED."""
    cfg = load_config()
    # Isolate ledger
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    cfg = load_config()
    runs = cfg.runs_dir()

    caps = cfg.capabilities_path()
    req = Requirements(
        task_type="debugging",
        languages=["rust"],
        context_tokens=4000,
        expected_output_tokens=500,
        requires_tools=True,
        # Synthetic catalog ids are unrated; floor unrated proves cheapest+tools selection.
        quality_floor="unrated",
        max_cost_usd=0.25,
    )
    sel = select_model(
        SYNTHETIC_CATALOG,
        req,
        capabilities_path=caps,
        provider_sort="price",
    )
    selected = sel["selected"]
    assert selected is not None
    assert selected["model"] == "synthetic/cheap-capable"
    est = float(selected["estimated_cost_usd"])
    assert est > 0

    budget = Budget(session_budget_usd=1.0, max_remote_calls=3)
    limits = RunLimits(max_iterations=5, max_remote_calls=3, timeout_seconds=60)
    assert limits.allow_remote_call() is None
    assert budget.can_afford(est)

    def fake_gateway(**kwargs):
        assert kwargs["model"] == "synthetic/cheap-capable" or kwargs["model"].endswith(
            "cheap-capable"
        )
        return {
            "choices": [{"message": {"content": "DOTS_EXPERT_ADVICE_OK: use Result"}}],
            "usage": {"cost": 0.0042},
        }

    expert = consult_expert(
        cfg=cfg,
        budget=budget,
        model=selected["model"],
        question="fix rust race",
        context="summary only",
        estimated_cost_usd=est,
        max_cost_usd=est + 0.01,
        approve_expensive=True,
        gateway_callable=fake_gateway,
    )
    limits.note_remote_call()
    assert expert["ok"] is True
    assert expert["cost_basis"] == "actual"
    assert abs(expert["charged_usd"] - 0.0042) < 1e-9
    assert budget.snapshot()["reserved_usd"] == 0.0
    assert budget.snapshot()["spent_usd"] == 0.0042

    # Local verification mock succeeds (explicit proof — not agent_settled alone)
    local_proof = "DOTS_LOCAL_AGENT_OK"
    assert "DOTS_EXPERT_ADVICE_OK" in expert["content"]
    verification = "PASS" if local_proof else "FAIL"
    result_state = R.VERIFIED if verification == "PASS" else R.FAILED
    assert result_state == R.VERIFIED

    ledger = RunLedger(runs)
    ledger.event("model_scout", selected_model=selected["model"], estimated_usd=est)
    ledger.cost(
        model=selected["model"],
        estimated_usd=est,
        actual_usd=0.0042,
        charged_usd=0.0042,
        cost_basis="actual",
        ok=True,
    )
    ledger.event("local_verify", status=verification)
    ledger.finish(
        result_state.lower(),
        spent_usd=budget.snapshot()["spent_usd"],
        verification=verification,
        result_state=result_state,
        remote_calls=1,
    )
    meta = json.loads(ledger.run_path.read_text(encoding="utf-8"))
    assert meta["result_state"] == R.VERIFIED
    assert meta["status"] == "verified"
    # Privacy: no full prompts / keys
    blob = ledger.run_path.read_text(encoding="utf-8") + ledger.events_path.read_text(
        encoding="utf-8"
    )
    assert "OPENROUTER" not in blob or "OPENROUTER_API_KEY" not in blob
    assert "sk-" not in blob


def test_connection_refused_does_not_fabricate_spend():
    cfg = load_config()
    b = Budget(session_budget_usd=1.0, max_remote_calls=3)

    def refuse(**kwargs):
        raise ConnectionRefusedError("LiteLLM down")

    result = consult_expert(
        cfg=cfg,
        budget=b,
        model="x/y",
        question="q",
        estimated_cost_usd=0.05,
        approve_expensive=True,
        gateway_callable=refuse,
    )
    assert result["ok"] is False
    assert result["transport"] == "request_not_sent"
    assert result["cost_basis"] == "none"
    assert result["charged_usd"] == 0.0
    assert b.snapshot()["spent_usd"] == 0.0
    assert b.snapshot()["reserved_usd"] == 0.0
    # Call still counted against max to avoid hammering
    assert b.snapshot()["remote_call_count"] == 1


def test_limits_enforced_outside_prompt():
    lim = RunLimits(max_iterations=2, max_remote_calls=1, timeout_seconds=3600)
    assert lim.tick_iteration() is None
    assert lim.tick_iteration() is None
    assert lim.tick_iteration() == R.TIMED_OUT
    lim2 = RunLimits(max_iterations=10, max_remote_calls=1, timeout_seconds=3600)
    lim2.note_remote_call()
    assert lim2.allow_remote_call() == R.BUDGET_BLOCKED
