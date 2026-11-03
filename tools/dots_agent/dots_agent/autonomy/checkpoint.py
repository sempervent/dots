"""Crash-safe run checkpoints — preserve budget/counters/autonomy state."""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

from .policy import RecoveryCounters
from .progress import ProgressState
from .types import AutonomyMode


SCHEMA_VERSION = 1


def checkpoint_path(run_dir: Path) -> Path:
    return run_dir / "checkpoint.json"


def atomic_write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".ckpt-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, sort_keys=True)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass


def save_checkpoint(
    run_dir: Path,
    *,
    autonomy_mode: AutonomyMode | str,
    policy_version: int,
    budget_spent_usd: float,
    budget_reserved_usd: float,
    budget_remaining_usd: float,
    session_budget_usd: float,
    remote_call_count: int,
    max_remote_calls: int,
    counters: RecoveryCounters,
    progress: ProgressState,
    outcome: str,
    worktree_path: str | None = None,
    expert_packet_hashes: list[str] | None = None,
    pending_billable: dict[str, Any] | None = None,
    extra: dict[str, Any] | None = None,
) -> Path:
    data: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "autonomy_mode": str(
            autonomy_mode.value if isinstance(autonomy_mode, AutonomyMode) else autonomy_mode
        ),
        "policy_version": policy_version,
        "budget": {
            "session_budget_usd": session_budget_usd,
            "spent_usd": budget_spent_usd,
            "reserved_usd": budget_reserved_usd,
            "remaining_usd": budget_remaining_usd,
            "remote_call_count": remote_call_count,
            "max_remote_calls": max_remote_calls,
        },
        "counters": counters.to_dict(),
        "progress": progress.to_dict(),
        "outcome": outcome,
        "worktree_path": worktree_path,
        "expert_packet_hashes": list(expert_packet_hashes or []),
        "pending_billable": pending_billable,
    }
    if extra:
        data["extra"] = extra
    path = checkpoint_path(run_dir)
    atomic_write_json(path, data)
    return path


def load_checkpoint(run_dir: Path) -> dict[str, Any] | None:
    path = checkpoint_path(run_dir)
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))
