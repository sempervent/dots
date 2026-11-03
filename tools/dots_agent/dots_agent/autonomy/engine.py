"""Recovery decision engine — structural inputs only."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .fingerprint import FailureFingerprint, classify_domain, make_fingerprint
from .policy import (
    AutonomyPolicy,
    RecoveryCounters,
    apply_action_counter,
    load_autonomy_policy,
    next_recovery_action,
)
from .progress import ProgressState, is_stuck, observe
from .types import AutonomyMode, FailureDomain, Outcome, RecoveryAction


@dataclass
class Decision:
    action: RecoveryAction
    domain: FailureDomain
    fingerprint: FailureFingerprint
    reason: str
    applied: bool
    outcome_hint: Outcome | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "action": self.action.value,
            "domain": self.domain.value,
            "fingerprint": self.fingerprint.to_dict(),
            "reason": self.reason,
            "applied": self.applied,
            "outcome_hint": self.outcome_hint.value if self.outcome_hint else None,
        }


def decide(
    *,
    exit_code: int | None = None,
    provider_error: bool = False,
    sandbox_violation: bool = False,
    verification_status: str = "",
    budget_blocked: bool = False,
    transient_network: bool = False,
    harness_error: bool = False,
    human_required: bool = False,
    tool: str = "",
    error_class: str = "",
    iteration: int = 0,
    files_changed_count: int | None = None,
    counters: RecoveryCounters | None = None,
    progress: ProgressState | None = None,
    policy: AutonomyPolicy | None = None,
    apply: bool = True,
) -> Decision:
    policy = policy or load_autonomy_policy()
    counters = counters or RecoveryCounters()
    progress = progress or ProgressState()

    verification_failed = verification_status in ("FAIL", "FAILED", "MODEL_FAIL")
    domain = classify_domain(
        exit_code=exit_code,
        provider_error=provider_error,
        sandbox_violation=sandbox_violation,
        verification_failed=verification_failed,
        budget_blocked=budget_blocked,
        transient_network=transient_network,
        harness_error=harness_error,
        human_required=human_required,
    )
    fp = make_fingerprint(
        domain=domain,
        exit_code=exit_code,
        tool=tool,
        error_class=error_class,
        verification_status=verification_status,
        iteration=iteration,
    )
    observe(
        progress,
        fingerprint_digest=fp.digest(),
        verification_status=verification_status,
        files_changed_count=files_changed_count,
    )
    if is_stuck(progress) and domain not in (
        FailureDomain.SANDBOX_VIOLATION,
        FailureDomain.BUDGET,
        FailureDomain.HUMAN_REQUIRED,
    ):
        domain = FailureDomain.NO_PROGRESS
        fp = make_fingerprint(
            domain=domain,
            exit_code=exit_code,
            tool=tool,
            error_class=error_class or "no_progress",
            verification_status=verification_status,
            iteration=iteration,
        )

    action = next_recovery_action(domain, counters, policy, fingerprint=fp)
    reason = f"{domain.value} → {action.value} (mode={policy.mode.value})"
    applied = False
    outcome_hint: Outcome | None = None

    if policy.mode is AutonomyMode.MANUAL and action not in (
        RecoveryAction.NONE,
        RecoveryAction.STOP,
        RecoveryAction.HUMAN_ATTENTION,
    ):
        action = RecoveryAction.HUMAN_ATTENTION
        reason = "manual mode — human attention required"
        outcome_hint = Outcome.NEEDS_ATTENTION

    if action is RecoveryAction.HUMAN_ATTENTION:
        outcome_hint = Outcome.NEEDS_ATTENTION
    elif action is RecoveryAction.STOP:
        outcome_hint = Outcome.FAILED if not budget_blocked else Outcome.BUDGET_BLOCKED

    # Forbidden ops never auto-applied
    if sandbox_violation or human_required:
        action = RecoveryAction.HUMAN_ATTENTION
        outcome_hint = Outcome.NEEDS_ATTENTION
        if sandbox_violation:
            outcome_hint = Outcome.SANDBOX_BLOCKED

    if apply and action not in (RecoveryAction.NONE, RecoveryAction.STOP, RecoveryAction.HUMAN_ATTENTION):
        if policy.allows_automatic(action):
            apply_action_counter(action, counters)
            applied = True
        else:
            action = RecoveryAction.HUMAN_ATTENTION
            outcome_hint = Outcome.NEEDS_ATTENTION
            reason += " (autonomy denied → attention)"

    if action is RecoveryAction.HUMAN_ATTENTION:
        applied = False

    return Decision(
        action=action,
        domain=domain,
        fingerprint=fp,
        reason=reason,
        applied=applied,
        outcome_hint=outcome_hint,
    )
