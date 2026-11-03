"""Structured autonomy events appended to the run ledger."""

from __future__ import annotations

from typing import Any

from dots_agent.ledger import RunLedger

from .fingerprint import FailureFingerprint
from .types import RecoveryAction


def emit_failure(
    ledger: RunLedger,
    *,
    fingerprint: FailureFingerprint,
    detail: str = "",
) -> None:
    ledger.event(
        "failure",
        domain=fingerprint.domain,
        exit_code=fingerprint.exit_code,
        tool=fingerprint.tool,
        error_class=fingerprint.error_class,
        verification_status=fingerprint.verification_status,
        iteration=fingerprint.iteration,
        fingerprint=fingerprint.digest(),
        detail=detail[:500] if detail else "",
    )


def emit_recovery(
    ledger: RunLedger,
    *,
    action: RecoveryAction,
    applied: bool,
    reason: str = "",
    counters: dict[str, Any] | None = None,
) -> None:
    ledger.event(
        "recovery_decision",
        action=action.value,
        applied=applied,
        reason=reason[:500],
        counters=counters or {},
    )


def emit_attention(ledger: RunLedger, *, reason: str, blocking: bool = True) -> None:
    ledger.event("attention", reason=reason[:500], blocking=blocking)


def emit_checkpoint(ledger: RunLedger, *, path: str) -> None:
    ledger.event("checkpoint", path=path)
