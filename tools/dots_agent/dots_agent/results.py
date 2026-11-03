"""Canonical Phase 1 agent run result states."""

from __future__ import annotations

# Only VERIFIED means an explicit verification proof succeeded.
COMPLETED = "COMPLETED"
VERIFIED = "VERIFIED"
FAILED = "FAILED"
BUDGET_BLOCKED = "BUDGET_BLOCKED"
TIMED_OUT = "TIMED_OUT"
CANCELLED = "CANCELLED"
DRY_RUN = "DRY_RUN"

ALL = (COMPLETED, VERIFIED, FAILED, BUDGET_BLOCKED, TIMED_OUT, CANCELLED, DRY_RUN)
