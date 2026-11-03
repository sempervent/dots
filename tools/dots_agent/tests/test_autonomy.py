"""Phase 5 autonomy / recovery / resume / replay / observability tests."""

from __future__ import annotations

import json
from pathlib import Path

from dots_agent.autonomy.checkpoint import load_checkpoint, save_checkpoint
from dots_agent.autonomy.engine import decide
from dots_agent.autonomy.fingerprint import classify_domain, make_fingerprint
from dots_agent.autonomy.idempotency import (
    BillableState,
    PendingBillable,
    mark_sent_unknown,
    on_resume_pending,
    packet_hash,
    should_skip_duplicate_expert,
)
from dots_agent.autonomy.observability import (
    cancel_run,
    inspect_run,
    list_attention,
    list_failures,
    metrics,
    timeline,
)
from dots_agent.autonomy.policy import (
    FORBIDDEN_OPS,
    AutonomyBounds,
    AutonomyPolicy,
    RecoveryCounters,
    apply_action_counter,
    backoff_seconds,
    load_autonomy_policy,
    next_recovery_action,
)
from dots_agent.autonomy.progress import ProgressState, is_stuck, observe
from dots_agent.autonomy.replay import replay_run
from dots_agent.autonomy.resume import resume_run
from dots_agent.autonomy.types import (
    AutonomyMode,
    FailureDomain,
    Outcome,
    RecoveryAction,
)


def test_default_mode_is_guarded():
    p = load_autonomy_policy()
    assert p.mode is AutonomyMode.GUARDED
    assert p.policy_version >= 1


def test_ladder_order():
    p = load_autonomy_policy()
    assert list(p.ladder) == [
        RecoveryAction.TRANSIENT_RETRY,
        RecoveryAction.LOCAL_REPLAN,
        RecoveryAction.REMOTE_EXPERT,
        RecoveryAction.TEAM_REROUTE,
        RecoveryAction.HUMAN_ATTENTION,
    ]


def test_forbidden_ops_gate():
    p = load_autonomy_policy()
    for op in (
        "increase_budget",
        "disable_sandbox",
        "switch_to_unsafe_host",
        "read_protected_secrets",
        "broaden_filesystem",
        "broaden_network",
        "run_sudo",
        "git_push",
        "git_force_push",
        "external_deploy",
    ):
        assert p.forbid(op)
        assert op in FORBIDDEN_OPS


def test_structural_domain_not_nl():
    # NL phrases must never drive classification — only flags/exit codes
    d = classify_domain(exit_code=1)
    assert d is FailureDomain.TOOL_ERROR
    assert classify_domain(sandbox_violation=True) is FailureDomain.SANDBOX_VIOLATION
    assert classify_domain(budget_blocked=True) is FailureDomain.BUDGET
    assert classify_domain(transient_network=True) is FailureDomain.TRANSIENT_NETWORK
    assert classify_domain(human_required=True) is FailureDomain.HUMAN_REQUIRED


def test_fingerprint_deterministic():
    a = make_fingerprint(domain=FailureDomain.TOOL_ERROR, exit_code=1, tool="bash", iteration=2)
    b = make_fingerprint(domain=FailureDomain.TOOL_ERROR, exit_code=1, tool="bash", iteration=2)
    assert a.digest() == b.digest()
    c = make_fingerprint(domain=FailureDomain.TOOL_ERROR, exit_code=2, tool="bash", iteration=2)
    assert a.digest() != c.digest()


def test_recovery_ladder_bounds():
    policy = load_autonomy_policy()
    counters = RecoveryCounters()
    # Transient network → retry while under bound
    a1 = next_recovery_action(FailureDomain.TRANSIENT_NETWORK, counters, policy)
    assert a1 is RecoveryAction.TRANSIENT_RETRY
    apply_action_counter(a1, counters)
    apply_action_counter(RecoveryAction.TRANSIENT_RETRY, counters)
    # Exhausted retries → walk ladder
    a2 = next_recovery_action(FailureDomain.TRANSIENT_NETWORK, counters, policy)
    assert a2 is RecoveryAction.LOCAL_REPLAN


def test_sandbox_violation_never_auto_escalates():
    d = decide(sandbox_violation=True, apply=True)
    assert d.action is RecoveryAction.HUMAN_ATTENTION
    assert d.outcome_hint is Outcome.SANDBOX_BLOCKED
    assert d.applied is False


def test_budget_blocked_stops():
    d = decide(budget_blocked=True, apply=True)
    assert d.action is RecoveryAction.STOP
    assert d.outcome_hint is Outcome.BUDGET_BLOCKED


def test_manual_mode_forces_attention():
    policy = AutonomyPolicy(
        mode=AutonomyMode.MANUAL,
        bounds=AutonomyBounds(),
        ladder=(
            RecoveryAction.TRANSIENT_RETRY,
            RecoveryAction.LOCAL_REPLAN,
            RecoveryAction.REMOTE_EXPERT,
            RecoveryAction.TEAM_REROUTE,
            RecoveryAction.HUMAN_ATTENTION,
        ),
    )
    d = decide(transient_network=True, policy=policy, apply=True)
    assert d.action is RecoveryAction.HUMAN_ATTENTION
    assert d.applied is False


def test_guarded_blocks_team_reroute_auto():
    policy = load_autonomy_policy()
    assert policy.mode is AutonomyMode.GUARDED
    counters = RecoveryCounters(
        transient_retries=99,
        local_replans=99,
        expert_escalations=99,
    )
    action = next_recovery_action(FailureDomain.NO_PROGRESS, counters, policy)
    assert action is RecoveryAction.HUMAN_ATTENTION


def test_auto_allows_team_reroute():
    policy = AutonomyPolicy(
        mode=AutonomyMode.AUTO,
        bounds=AutonomyBounds(max_team_reroutes=1),
        ladder=(
            RecoveryAction.TRANSIENT_RETRY,
            RecoveryAction.LOCAL_REPLAN,
            RecoveryAction.REMOTE_EXPERT,
            RecoveryAction.TEAM_REROUTE,
            RecoveryAction.HUMAN_ATTENTION,
        ),
    )
    counters = RecoveryCounters(
        transient_retries=99,
        local_replans=99,
        expert_escalations=99,
    )
    action = next_recovery_action(FailureDomain.PROVIDER_ERROR, counters, policy)
    assert action is RecoveryAction.TEAM_REROUTE


def test_identical_fingerprint_escalates_to_attention():
    policy = load_autonomy_policy()
    counters = RecoveryCounters()
    fp = make_fingerprint(domain=FailureDomain.TOOL_ERROR, exit_code=7, tool="x")
    last = None
    for _ in range(policy.bounds.max_identical_fingerprints):
        last = next_recovery_action(
            FailureDomain.TOOL_ERROR, counters, policy, fingerprint=fp
        )
    assert last is RecoveryAction.HUMAN_ATTENTION


def test_no_progress_detection_structural():
    state = ProgressState()
    fp = "deadbeef"
    observe(state, fingerprint_digest=fp, verification_status="FAIL")
    observe(state, fingerprint_digest=fp, verification_status="FAIL")
    assert is_stuck(state, min_iterations=2)
    # Verification delta clears stuck
    observe(state, fingerprint_digest=fp, verification_status="PASS")
    assert not is_stuck(state, min_iterations=2)


def test_completed_vs_verified_distinct():
    from dots_agent import results as R

    assert R.COMPLETED != R.VERIFIED
    assert "VERIFIED" in R.ALL
    assert "COMPLETED" in R.ALL


def test_checkpoint_resume_preserves_budget_and_counters(tmp_path: Path):
    run_dir = tmp_path / "run-a"
    run_dir.mkdir()
    counters = RecoveryCounters(transient_retries=2, local_replans=1, expert_escalations=1)
    progress = ProgressState(iterations_without_delta=1)
    save_checkpoint(
        run_dir,
        autonomy_mode=AutonomyMode.GUARDED,
        policy_version=1,
        budget_spent_usd=0.37,
        budget_reserved_usd=0.0,
        budget_remaining_usd=0.63,
        session_budget_usd=1.0,
        remote_call_count=2,
        max_remote_calls=3,
        counters=counters,
        progress=progress,
        outcome="FAILED",
        worktree_path="/tmp/wt",
        expert_packet_hashes=["abc"],
    )
    runs = tmp_path
    # resume expects runs_dir / run_id
    resumed = resume_run(runs, "run-a")
    snap = resumed.budget.snapshot()
    assert snap["spent_usd"] == 0.37
    assert snap["remaining_usd"] == 0.63
    assert snap["remote_call_count"] == 2
    assert snap["max_remote_calls"] == 3
    assert resumed.counters.transient_retries == 2
    assert resumed.counters.local_replans == 1
    assert resumed.counters.expert_escalations == 1
    assert resumed.autonomy_mode is AutonomyMode.GUARDED
    # Allowances NOT refreshed
    assert snap["session_budget_usd"] == 1.0


def test_idempotency_sent_unknown_requires_reconciliation():
    pending = PendingBillable(
        reservation_id="r1",
        estimated_usd=0.05,
        model="test/model",
        packet_hash="hh",
        state=BillableState.RESERVED.value,
    )
    mark_sent_unknown(pending)
    outcome = on_resume_pending(pending.to_dict())
    assert outcome is Outcome.RECONCILIATION_REQUIRED


def test_expert_packet_dedup():
    h = packet_hash({"q": "fix race", "ctx": "x"})
    assert should_skip_duplicate_expert(h, [h])
    assert not should_skip_duplicate_expert(h, ["other"])


def test_replay_zero_side_effects(tmp_path: Path):
    run_dir = tmp_path / "run-replay"
    run_dir.mkdir()
    events = [
        {
            "kind": "failure",
            "domain": "transient_network",
            "exit_code": None,
            "tool": "",
            "error_class": "timeout",
            "verification_status": "",
            "iteration": 0,
            "ts": "t0",
        },
        {
            "kind": "recovery_decision",
            "domain": "transient_network",
            "action": "transient_retry",
            "applied": True,
            "ts": "t1",
        },
        {
            "kind": "failure",
            "domain": "verification_fail",
            "exit_code": 1,
            "tool": "pytest",
            "error_class": "assert",
            "verification_status": "FAIL",
            "iteration": 1,
            "ts": "t2",
        },
    ]
    (run_dir / "events.jsonl").write_text(
        "\n".join(json.dumps(e) for e in events) + "\n", encoding="utf-8"
    )
    (run_dir / "run.json").write_text(
        json.dumps({"run_id": "run-replay", "status": "failed"}) + "\n", encoding="utf-8"
    )
    result = replay_run(tmp_path, "run-replay")
    assert result.model_calls == 0
    assert result.network_calls == 0
    assert result.billable_calls == 0
    assert result.mutations == 0
    assert len(result.decisions) >= 1


def test_observability_inspect_timeline_metrics(tmp_path: Path):
    run_dir = tmp_path / "run-obs"
    run_dir.mkdir()
    (run_dir / "run.json").write_text(
        json.dumps({"run_id": "run-obs", "status": "failed"}) + "\n", encoding="utf-8"
    )
    rows = [
        {"kind": "failure", "domain": "tool_error", "fingerprint": "aaa", "ts": "t0"},
        {
            "kind": "recovery_decision",
            "action": "local_replan",
            "applied": True,
            "ts": "t1",
        },
        {"kind": "attention", "reason": "needs human", "ts": "t2"},
    ]
    (run_dir / "events.jsonl").write_text(
        "\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8"
    )
    data = inspect_run(tmp_path, "run-obs")
    assert data["ok"] is True
    assert len(timeline(tmp_path, "run-obs")) == 3
    fails = list_failures(tmp_path)
    assert any(f["run_id"] == "run-obs" for f in fails)
    atts = list_attention(tmp_path)
    assert any(a["run_id"] == "run-obs" for a in atts)
    m = metrics(tmp_path)
    assert m["runs"] >= 1
    assert m["attention_events"] >= 1
    cancel = cancel_run(tmp_path, "run-obs")
    assert cancel["ok"] is True
    assert (run_dir / "CANCEL").is_file()


def test_backoff_bounded():
    b = AutonomyBounds(backoff_base_seconds=1.0, backoff_max_seconds=30.0)
    assert backoff_seconds(1, b) == 1.0
    assert backoff_seconds(2, b) == 2.0
    assert backoff_seconds(10, b) == 30.0


def test_decide_provider_error_expert_in_guarded():
    d = decide(provider_error=True, apply=True)
    assert d.action is RecoveryAction.REMOTE_EXPERT
    assert d.applied is True


def test_checkpoint_atomic_roundtrip(tmp_path: Path):
    run_dir = tmp_path / "ck"
    run_dir.mkdir()
    save_checkpoint(
        run_dir,
        autonomy_mode="guarded",
        policy_version=1,
        budget_spent_usd=0.1,
        budget_reserved_usd=0.0,
        budget_remaining_usd=0.9,
        session_budget_usd=1.0,
        remote_call_count=1,
        max_remote_calls=3,
        counters=RecoveryCounters(),
        progress=ProgressState(),
        outcome="RUNNING",
        pending_billable={"state": "sent_unknown"},
    )
    ck = load_checkpoint(run_dir)
    assert ck is not None
    assert ck["pending_billable"]["state"] == "sent_unknown"
    assert ck["budget"]["spent_usd"] == 0.1
