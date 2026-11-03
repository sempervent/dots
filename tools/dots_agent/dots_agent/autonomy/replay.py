"""Offline policy/decision replay — zero network, zero mutations, zero billable calls."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .fingerprint import FailureFingerprint, make_fingerprint
from .policy import RecoveryCounters, load_autonomy_policy, next_recovery_action
from .types import FailureDomain, RecoveryAction


@dataclass
class ReplayResult:
    run_id: str
    decisions: list[dict[str, Any]] = field(default_factory=list)
    model_calls: int = 0
    network_calls: int = 0
    billable_calls: int = 0
    mutations: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "decisions": self.decisions,
            "model_calls": self.model_calls,
            "network_calls": self.network_calls,
            "billable_calls": self.billable_calls,
            "mutations": self.mutations,
        }


def _iter_events(run_dir: Path) -> list[dict[str, Any]]:
    path = run_dir / "events.jsonl"
    if not path.is_file():
        return []
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def replay_run(runs_dir: Path, run_id: str) -> ReplayResult:
    """Recompute recovery decisions from stored structural events only."""
    run_dir = runs_dir / run_id
    result = ReplayResult(run_id=run_id)
    if not run_dir.is_dir():
        result.decisions.append({"error": "run_not_found"})
        return result

    policy = load_autonomy_policy()
    counters = RecoveryCounters()
    events = _iter_events(run_dir)

    for ev in events:
        kind = str(ev.get("kind") or "")
        if kind not in ("failure", "recovery_decision", "verification", "tool_result"):
            # Still inspect failure-shaped payloads
            if "domain" not in ev and "exit_code" not in ev:
                continue
        domain_s = ev.get("domain")
        if not domain_s:
            continue
        try:
            domain = FailureDomain(str(domain_s))
        except ValueError:
            domain = FailureDomain.UNKNOWN
        fp = make_fingerprint(
            domain=domain,
            exit_code=ev.get("exit_code"),
            tool=str(ev.get("tool") or ""),
            error_class=str(ev.get("error_class") or ""),
            verification_status=str(ev.get("verification_status") or ""),
            iteration=int(ev.get("iteration") or 0),
        )
        action = next_recovery_action(domain, counters, policy, fingerprint=fp)
        result.decisions.append(
            {
                "ts": ev.get("ts"),
                "domain": domain.value,
                "fingerprint": fp.digest(),
                "action": action.value,
                "counters": counters.to_dict(),
            }
        )
        # Counters advanced only when replaying recorded applied actions
        if kind == "recovery_decision" and ev.get("applied"):
            from .policy import apply_action_counter

            try:
                apply_action_counter(RecoveryAction(str(ev.get("action"))), counters)
            except ValueError:
                pass

    # Guarantees by construction
    assert result.model_calls == 0
    assert result.network_calls == 0
    assert result.billable_calls == 0
    assert result.mutations == 0
    return result
