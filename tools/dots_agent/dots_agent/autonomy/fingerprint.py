"""Deterministic failure fingerprints — structural signals only (no NL)."""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass
from typing import Any

from .types import FailureDomain


@dataclass(frozen=True)
class FailureFingerprint:
    domain: str
    exit_code: int | None
    tool: str
    error_class: str
    verification_status: str
    iteration: int

    def digest(self) -> str:
        payload = json.dumps(asdict(self), sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["digest"] = self.digest()
        return d


def classify_domain(
    *,
    exit_code: int | None = None,
    provider_error: bool = False,
    sandbox_violation: bool = False,
    verification_failed: bool = False,
    budget_blocked: bool = False,
    transient_network: bool = False,
    no_progress: bool = False,
    human_required: bool = False,
    harness_error: bool = False,
) -> FailureDomain:
    """Map structural flags → domain. Order is intentional."""
    if human_required:
        return FailureDomain.HUMAN_REQUIRED
    if sandbox_violation:
        return FailureDomain.SANDBOX_VIOLATION
    if budget_blocked:
        return FailureDomain.BUDGET
    if transient_network:
        return FailureDomain.TRANSIENT_NETWORK
    if provider_error:
        return FailureDomain.PROVIDER_ERROR
    if verification_failed:
        return FailureDomain.VERIFICATION_FAIL
    if no_progress:
        return FailureDomain.NO_PROGRESS
    if harness_error:
        return FailureDomain.HARNESS
    if exit_code not in (None, 0):
        return FailureDomain.TOOL_ERROR
    return FailureDomain.UNKNOWN


def make_fingerprint(
    *,
    domain: FailureDomain | str,
    exit_code: int | None = None,
    tool: str = "",
    error_class: str = "",
    verification_status: str = "",
    iteration: int = 0,
) -> FailureFingerprint:
    return FailureFingerprint(
        domain=str(domain.value if isinstance(domain, FailureDomain) else domain),
        exit_code=exit_code,
        tool=tool or "",
        error_class=error_class or "",
        verification_status=verification_status or "",
        iteration=int(iteration),
    )
