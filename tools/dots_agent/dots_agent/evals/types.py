"""Eval attempt classifications and shared types."""

from __future__ import annotations

from enum import Enum


class AttemptStatus(str, Enum):
    PASS = "PASS"
    MODEL_FAIL = "MODEL_FAIL"
    TIMEOUT = "TIMEOUT"
    TOOL_FAIL = "TOOL_FAIL"
    HARNESS_ERROR = "HARNESS_ERROR"
    PROVIDER_ERROR = "PROVIDER_ERROR"
    BUDGET_BLOCKED = "BUDGET_BLOCKED"
    SKIPPED_PREREQUISITE = "SKIPPED_PREREQUISITE"


# Contribute to empirical success statistics
STAT_STATUSES = frozenset(
    {
        AttemptStatus.PASS,
        AttemptStatus.MODEL_FAIL,
        AttemptStatus.TIMEOUT,
    }
)


def counts_toward_success(status: AttemptStatus | str) -> bool:
    s = AttemptStatus(status) if isinstance(status, str) else status
    return s in STAT_STATUSES


def is_success(status: AttemptStatus | str) -> bool:
    s = AttemptStatus(status) if isinstance(status, str) else status
    return s is AttemptStatus.PASS
