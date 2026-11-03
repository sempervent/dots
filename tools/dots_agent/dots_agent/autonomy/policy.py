"""Bounded recovery ladder and forbidden-operation gates."""

from __future__ import annotations

import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from dots_agent.config import dots_root

from .fingerprint import FailureFingerprint
from .types import AutonomyMode, FailureDomain, RecoveryAction


@dataclass
class AutonomyBounds:
    max_transient_retries: int = 2
    max_local_replans: int = 2
    max_expert_escalations: int = 2
    max_team_reroutes: int = 1
    max_identical_fingerprints: int = 3
    backoff_base_seconds: float = 1.0
    backoff_max_seconds: float = 30.0


@dataclass
class RecoveryCounters:
    transient_retries: int = 0
    local_replans: int = 0
    expert_escalations: int = 0
    team_reroutes: int = 0
    fingerprint_counts: dict[str, int] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "transient_retries": self.transient_retries,
            "local_replans": self.local_replans,
            "expert_escalations": self.expert_escalations,
            "team_reroutes": self.team_reroutes,
            "fingerprint_counts": dict(self.fingerprint_counts),
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> RecoveryCounters:
        return cls(
            transient_retries=int(d.get("transient_retries") or 0),
            local_replans=int(d.get("local_replans") or 0),
            expert_escalations=int(d.get("expert_escalations") or 0),
            team_reroutes=int(d.get("team_reroutes") or 0),
            fingerprint_counts={
                str(k): int(v) for k, v in (d.get("fingerprint_counts") or {}).items()
            },
        )


FORBIDDEN_OPS = frozenset(
    {
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
    }
)


@dataclass
class AutonomyPolicy:
    mode: AutonomyMode
    bounds: AutonomyBounds
    ladder: tuple[RecoveryAction, ...]
    policy_version: int = 1
    forbidden: frozenset[str] = FORBIDDEN_OPS

    def allows_automatic(self, action: RecoveryAction) -> bool:
        if self.mode is AutonomyMode.MANUAL:
            return action is RecoveryAction.NONE
        if self.mode is AutonomyMode.GUARDED:
            # Guarded: retries + replan + expert OK; team reroute needs attention signal
            return action in (
                RecoveryAction.TRANSIENT_RETRY,
                RecoveryAction.LOCAL_REPLAN,
                RecoveryAction.REMOTE_EXPERT,
                RecoveryAction.HUMAN_ATTENTION,
                RecoveryAction.STOP,
                RecoveryAction.NONE,
            )
        # AUTO: full ladder including team reroute
        return True

    def forbid(self, operation: str) -> bool:
        """True if operation is forbidden for automation."""
        return operation in self.forbidden


def load_autonomy_policy(
    path: Path | None = None,
    *,
    mode_override: str | None = None,
) -> AutonomyPolicy:
    path = path or (dots_root() / "configs" / "agents" / "autonomy.toml")
    data: dict[str, Any] = {}
    if path.is_file():
        with path.open("rb") as fh:
            loaded = tomllib.load(fh)
            data = loaded if isinstance(loaded, dict) else {}
    mode_s = mode_override or str(
        (data.get("autonomy") or {}).get("default_mode") or "guarded"
    )
    try:
        mode = AutonomyMode(mode_s)
    except ValueError:
        mode = AutonomyMode.GUARDED
    b = data.get("bounds") or {}
    bounds = AutonomyBounds(
        max_transient_retries=int(b.get("max_transient_retries", 2)),
        max_local_replans=int(b.get("max_local_replans", 2)),
        max_expert_escalations=int(b.get("max_expert_escalations", 2)),
        max_team_reroutes=int(b.get("max_team_reroutes", 1)),
        max_identical_fingerprints=int(b.get("max_identical_fingerprints", 3)),
        backoff_base_seconds=float(b.get("backoff_base_seconds", 1.0)),
        backoff_max_seconds=float(b.get("backoff_max_seconds", 30.0)),
    )
    ladder_raw = (data.get("recovery") or {}).get("ladder") or [
        "transient_retry",
        "local_replan",
        "remote_expert",
        "team_reroute",
        "human_attention",
    ]
    ladder = tuple(RecoveryAction(x) for x in ladder_raw)
    return AutonomyPolicy(
        mode=mode,
        bounds=bounds,
        ladder=ladder,
        policy_version=int(data.get("policy_version") or 1),
    )


def next_recovery_action(
    domain: FailureDomain,
    counters: RecoveryCounters,
    policy: AutonomyPolicy,
    *,
    fingerprint: FailureFingerprint | None = None,
) -> RecoveryAction:
    """Decide next recovery step from structural domain + counters."""
    # Hard stops
    if domain is FailureDomain.SANDBOX_VIOLATION:
        return RecoveryAction.HUMAN_ATTENTION
    if domain is FailureDomain.HUMAN_REQUIRED:
        return RecoveryAction.HUMAN_ATTENTION
    if domain is FailureDomain.BUDGET:
        return RecoveryAction.STOP

    if fingerprint is not None:
        dig = fingerprint.digest()
        n = counters.fingerprint_counts.get(dig, 0) + 1
        counters.fingerprint_counts[dig] = n
        if n >= policy.bounds.max_identical_fingerprints:
            return RecoveryAction.HUMAN_ATTENTION

    # Domain → preferred first step
    preferred: RecoveryAction
    if domain is FailureDomain.TRANSIENT_NETWORK:
        preferred = RecoveryAction.TRANSIENT_RETRY
    elif domain in (FailureDomain.TOOL_ERROR, FailureDomain.VERIFICATION_FAIL):
        preferred = RecoveryAction.LOCAL_REPLAN
    elif domain is FailureDomain.PROVIDER_ERROR:
        preferred = RecoveryAction.REMOTE_EXPERT
    elif domain is FailureDomain.NO_PROGRESS:
        preferred = RecoveryAction.LOCAL_REPLAN
    else:
        preferred = RecoveryAction.LOCAL_REPLAN

    # Walk ladder from preferred, respecting bounds and autonomy mode
    start = 0
    try:
        start = policy.ladder.index(preferred)
    except ValueError:
        start = 0

    for action in policy.ladder[start:]:
        if not policy.allows_automatic(action):
            if action is RecoveryAction.TEAM_REROUTE and policy.mode is AutonomyMode.GUARDED:
                return RecoveryAction.HUMAN_ATTENTION
            continue
        if action is RecoveryAction.TRANSIENT_RETRY:
            if counters.transient_retries < policy.bounds.max_transient_retries:
                return action
            continue
        if action is RecoveryAction.LOCAL_REPLAN:
            if counters.local_replans < policy.bounds.max_local_replans:
                return action
            continue
        if action is RecoveryAction.REMOTE_EXPERT:
            if counters.expert_escalations < policy.bounds.max_expert_escalations:
                return action
            continue
        if action is RecoveryAction.TEAM_REROUTE:
            if counters.team_reroutes < policy.bounds.max_team_reroutes:
                return action
            continue
        if action is RecoveryAction.HUMAN_ATTENTION:
            return action
    return RecoveryAction.HUMAN_ATTENTION


def apply_action_counter(action: RecoveryAction, counters: RecoveryCounters) -> None:
    if action is RecoveryAction.TRANSIENT_RETRY:
        counters.transient_retries += 1
    elif action is RecoveryAction.LOCAL_REPLAN:
        counters.local_replans += 1
    elif action is RecoveryAction.REMOTE_EXPERT:
        counters.expert_escalations += 1
    elif action is RecoveryAction.TEAM_REROUTE:
        counters.team_reroutes += 1


def backoff_seconds(attempt: int, bounds: AutonomyBounds) -> float:
    delay = bounds.backoff_base_seconds * (2 ** max(0, attempt - 1))
    return min(delay, bounds.backoff_max_seconds)
