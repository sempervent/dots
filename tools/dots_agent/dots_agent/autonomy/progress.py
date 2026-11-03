"""Structural progress / no-progress detection (verification deltas, not NL)."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class ProgressState:
    last_fingerprint: str | None = None
    last_verification: str = ""
    verification_history: list[str] = field(default_factory=list)
    iterations_without_delta: int = 0
    files_changed_count: int = 0
    last_files_changed_count: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "last_fingerprint": self.last_fingerprint,
            "last_verification": self.last_verification,
            "verification_history": list(self.verification_history)[-20:],
            "iterations_without_delta": self.iterations_without_delta,
            "files_changed_count": self.files_changed_count,
            "last_files_changed_count": self.last_files_changed_count,
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> ProgressState:
        return cls(
            last_fingerprint=d.get("last_fingerprint"),
            last_verification=str(d.get("last_verification") or ""),
            verification_history=list(d.get("verification_history") or []),
            iterations_without_delta=int(d.get("iterations_without_delta") or 0),
            files_changed_count=int(d.get("files_changed_count") or 0),
            last_files_changed_count=int(d.get("last_files_changed_count") or 0),
        )


def observe(
    state: ProgressState,
    *,
    fingerprint_digest: str | None,
    verification_status: str,
    files_changed_count: int | None = None,
) -> bool:
    """Update progress state. Returns True if structural progress occurred."""
    progressed = False
    if verification_status and verification_status != state.last_verification:
        if verification_status in ("PASS", "VERIFIED") or (
            state.last_verification and verification_status != state.last_verification
        ):
            progressed = True
        state.last_verification = verification_status
        state.verification_history.append(verification_status)

    if files_changed_count is not None:
        if files_changed_count != state.last_files_changed_count:
            progressed = True
        state.last_files_changed_count = state.files_changed_count
        state.files_changed_count = files_changed_count

    if fingerprint_digest:
        if fingerprint_digest == state.last_fingerprint and not progressed:
            state.iterations_without_delta += 1
        else:
            if fingerprint_digest != state.last_fingerprint and progressed:
                state.iterations_without_delta = 0
            elif fingerprint_digest != state.last_fingerprint:
                # New failure shape without verification delta — still no progress
                state.iterations_without_delta += 1
            state.last_fingerprint = fingerprint_digest
    elif progressed:
        state.iterations_without_delta = 0

    if progressed:
        state.iterations_without_delta = 0
    return progressed


def is_stuck(state: ProgressState, *, min_iterations: int = 2) -> bool:
    return state.iterations_without_delta >= min_iterations
