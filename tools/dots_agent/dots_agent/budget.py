"""DOTS-side hard session budget (authoritative for Phase 1)."""

from __future__ import annotations

import threading
from dataclasses import dataclass, field


@dataclass
class Budget:
    session_budget_usd: float
    spent_usd: float = 0.0
    reserved_usd: float = 0.0
    remote_call_count: int = 0
    max_remote_calls: int = 3
    _lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    @property
    def remaining_usd(self) -> float:
        return max(0.0, self.session_budget_usd - self.spent_usd - self.reserved_usd)

    def can_afford(self, estimated_usd: float) -> bool:
        with self._lock:
            if self.remote_call_count >= self.max_remote_calls:
                return False
            return estimated_usd <= self.remaining_usd + 1e-12

    def reserve(self, estimated_usd: float) -> None:
        with self._lock:
            if self.remote_call_count >= self.max_remote_calls:
                raise RuntimeError("max remote calls exhausted")
            if estimated_usd > self.remaining_usd + 1e-12:
                raise RuntimeError(
                    f"insufficient budget: need ${estimated_usd:.4f}, "
                    f"remaining ${self.remaining_usd:.4f}"
                )
            self.reserved_usd += estimated_usd
            self.remote_call_count += 1

    def settle(self, reserved_usd: float, actual_usd: float | None) -> float:
        """Replace reservation with actual (or keep reserved if actual unknown)."""
        with self._lock:
            self.reserved_usd = max(0.0, self.reserved_usd - reserved_usd)
            charge = actual_usd if actual_usd is not None else reserved_usd
            if charge < 0:
                charge = 0.0
            self.spent_usd += charge
            return charge

    def release_reservation(self, reserved_usd: float, *, count_against_max: bool = True) -> None:
        """Drop a reservation without charging spend.

        Used when the request definitely never reached the provider
        (connection refused, DNS failure before send, etc.).
        remote_call_count stays incremented when count_against_max is True
        so loops cannot hammer a dead gateway for free.
        """
        with self._lock:
            self.reserved_usd = max(0.0, self.reserved_usd - reserved_usd)
            if not count_against_max and self.remote_call_count > 0:
                self.remote_call_count -= 1

    def snapshot(self) -> dict[str, float | int]:
        with self._lock:
            return {
                "session_budget_usd": self.session_budget_usd,
                "spent_usd": round(self.spent_usd, 6),
                "reserved_usd": round(self.reserved_usd, 6),
                "remaining_usd": round(self.remaining_usd, 6),
                "remote_call_count": self.remote_call_count,
                "max_remote_calls": self.max_remote_calls,
            }
