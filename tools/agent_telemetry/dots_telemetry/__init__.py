"""DOTS private local agent telemetry — stdlib only (sqlite3).

Never raises into callers. Never transmits off-machine.
Does not store prompts/responses by default.
Does not change routing decisions.
"""

from __future__ import annotations

from .config import load_config, telemetry_enabled
from .record import (
    finish_execution,
    record_escalation,
    record_route,
    start_execution,
)
from .stats import stats_summary

__all__ = [
    "load_config",
    "telemetry_enabled",
    "start_execution",
    "finish_execution",
    "record_route",
    "record_escalation",
    "stats_summary",
]
