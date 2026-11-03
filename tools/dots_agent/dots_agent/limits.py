"""Hard runtime limits enforced outside model instructions."""

from __future__ import annotations

import time
from dataclasses import dataclass, field

from .results import BUDGET_BLOCKED, CANCELLED, TIMED_OUT


@dataclass
class RunLimits:
    max_iterations: int = 25
    max_remote_calls: int = 3
    timeout_seconds: int = 1800
    session_budget_usd: float = 1.0
    iterations: int = 0
    remote_calls: int = 0
    started_at: float = field(default_factory=time.monotonic)
    cancelled: bool = False

    def tick_iteration(self) -> str | None:
        self.iterations += 1
        if self.cancelled:
            return CANCELLED
        if self.iterations > self.max_iterations:
            return TIMED_OUT  # iteration exhaustion treated as hard stop
        if self.elapsed() > self.timeout_seconds:
            return TIMED_OUT
        return None

    def allow_remote_call(self) -> str | None:
        if self.remote_calls >= self.max_remote_calls:
            return BUDGET_BLOCKED
        if self.elapsed() > self.timeout_seconds:
            return TIMED_OUT
        if self.cancelled:
            return CANCELLED
        return None

    def note_remote_call(self) -> None:
        self.remote_calls += 1

    def elapsed(self) -> float:
        return time.monotonic() - self.started_at

    def cancel(self) -> None:
        self.cancelled = True
