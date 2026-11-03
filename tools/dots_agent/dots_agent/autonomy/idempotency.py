"""Billable-call crash safety — never blindly re-issue paid calls."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from enum import Enum
from typing import Any

from .types import Outcome


class BillableState(str, Enum):
    NONE = "none"
    RESERVED = "reserved"
    SENT_UNKNOWN = "sent_unknown"  # may have reached provider; response not persisted
    SETTLED = "settled"
    RELEASED = "released"


@dataclass
class PendingBillable:
    reservation_id: str
    estimated_usd: float
    model: str
    packet_hash: str
    state: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "reservation_id": self.reservation_id,
            "estimated_usd": self.estimated_usd,
            "model": self.model,
            "packet_hash": self.packet_hash,
            "state": self.state,
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> PendingBillable:
        return cls(
            reservation_id=str(d.get("reservation_id") or ""),
            estimated_usd=float(d.get("estimated_usd") or 0),
            model=str(d.get("model") or ""),
            packet_hash=str(d.get("packet_hash") or ""),
            state=str(d.get("state") or BillableState.NONE.value),
        )


def packet_hash(packet: dict[str, Any] | str) -> str:
    if isinstance(packet, str):
        raw = packet.encode("utf-8")
    else:
        raw = json.dumps(packet, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def mark_sent_unknown(pending: PendingBillable) -> PendingBillable:
    pending.state = BillableState.SENT_UNKNOWN.value
    return pending


def on_resume_pending(pending: dict[str, Any] | None) -> Outcome | None:
    """If a billable call may have been sent without settlement → reconcile."""
    if not pending:
        return None
    state = str(pending.get("state") or "")
    if state == BillableState.SENT_UNKNOWN.value:
        return Outcome.RECONCILIATION_REQUIRED
    if state == BillableState.RESERVED.value:
        # Safe to release reservation without re-calling
        return None
    return None


def should_skip_duplicate_expert(
    packet_hash_value: str, prior_hashes: list[str]
) -> bool:
    """Deduplicate identical expert packets within a run."""
    return packet_hash_value in prior_hashes
