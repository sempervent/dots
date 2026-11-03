"""Typed outcomes, failure domains, and autonomy modes (no NL parsing)."""

from __future__ import annotations

from enum import Enum


class AutonomyMode(str, Enum):
    MANUAL = "manual"
    GUARDED = "guarded"
    AUTO = "auto"


class Outcome(str, Enum):
    """Structural run outcomes — VERIFIED requires proof, not model prose."""

    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    VERIFIED = "VERIFIED"
    FAILED = "FAILED"
    BUDGET_BLOCKED = "BUDGET_BLOCKED"
    TIMED_OUT = "TIMED_OUT"
    CANCELLED = "CANCELLED"
    DRY_RUN = "DRY_RUN"
    NEEDS_ATTENTION = "NEEDS_ATTENTION"
    RECONCILIATION_REQUIRED = "RECONCILIATION_REQUIRED"
    SANDBOX_BLOCKED = "SANDBOX_BLOCKED"
    POLICY_BLOCKED = "POLICY_BLOCKED"


class FailureDomain(str, Enum):
    TRANSIENT_NETWORK = "transient_network"
    PROVIDER_ERROR = "provider_error"
    TOOL_ERROR = "tool_error"
    SANDBOX_VIOLATION = "sandbox_violation"
    VERIFICATION_FAIL = "verification_fail"
    NO_PROGRESS = "no_progress"
    BUDGET = "budget"
    HARNESS = "harness"
    HUMAN_REQUIRED = "human_required"
    UNKNOWN = "unknown"


class RecoveryAction(str, Enum):
    TRANSIENT_RETRY = "transient_retry"
    LOCAL_REPLAN = "local_replan"
    REMOTE_EXPERT = "remote_expert"
    TEAM_REROUTE = "team_reroute"
    HUMAN_ATTENTION = "human_attention"
    STOP = "stop"
    NONE = "none"
