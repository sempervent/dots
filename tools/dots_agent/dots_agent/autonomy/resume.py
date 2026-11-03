"""Resume runs without refreshing allowances."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from dots_agent.budget import Budget

from .checkpoint import load_checkpoint
from .policy import RecoveryCounters, load_autonomy_policy
from .progress import ProgressState
from .types import AutonomyMode, Outcome


@dataclass
class ResumedRun:
    run_id: str
    autonomy_mode: AutonomyMode
    policy_version: int
    budget: Budget
    counters: RecoveryCounters
    progress: ProgressState
    outcome: str
    worktree_path: str | None
    expert_packet_hashes: list[str]
    pending_billable: dict[str, Any] | None
    checkpoint: dict[str, Any]


class ResumeError(RuntimeError):
    pass


def resume_run(runs_dir: Path, run_id: str) -> ResumedRun:
    """Load checkpoint and restore budget/counters. Does NOT reset allowances."""
    run_dir = runs_dir / run_id
    if not run_dir.is_dir():
        raise ResumeError(f"run not found: {run_id}")
    ckpt = load_checkpoint(run_dir)
    if ckpt is None:
        raise ResumeError(f"no checkpoint for run: {run_id}")

    policy = load_autonomy_policy()
    stored_pv = int(ckpt.get("policy_version") or 0)
    if stored_pv and stored_pv != policy.policy_version:
        # Policy changed — resume allowed but flagged; caller must note
        pass

    b = ckpt.get("budget") or {}
    budget = Budget(
        session_budget_usd=float(b.get("session_budget_usd") or 0),
        spent_usd=float(b.get("spent_usd") or 0),
        reserved_usd=float(b.get("reserved_usd") or 0),
        remote_call_count=int(b.get("remote_call_count") or 0),
        max_remote_calls=int(b.get("max_remote_calls") or 0),
    )
    mode_s = str(ckpt.get("autonomy_mode") or "guarded")
    try:
        mode = AutonomyMode(mode_s)
    except ValueError:
        mode = AutonomyMode.GUARDED

    return ResumedRun(
        run_id=run_id,
        autonomy_mode=mode,
        policy_version=stored_pv or policy.policy_version,
        budget=budget,
        counters=RecoveryCounters.from_dict(ckpt.get("counters") or {}),
        progress=ProgressState.from_dict(ckpt.get("progress") or {}),
        outcome=str(ckpt.get("outcome") or Outcome.RUNNING.value),
        worktree_path=ckpt.get("worktree_path"),
        expert_packet_hashes=list(ckpt.get("expert_packet_hashes") or []),
        pending_billable=ckpt.get("pending_billable"),
        checkpoint=ckpt,
    )
