"""Resolve a Node runtime that satisfies every selected capability."""

from __future__ import annotations

import re
from typing import Any

from dots_agent.capabilities.load import node_default_major, runtime_requirements

_CONSTRAINT = re.compile(r"^(>=|<=|>|<|==)\s*(\d+(?:\.\d+){0,2})$")


def version_tuple(raw: str) -> tuple[int, int, int]:
    text = str(raw).strip().lstrip("v")
    text = text.split("-", 1)[0]
    parts = [p for p in text.split(".") if p != ""]
    nums: list[int] = []
    for part in parts[:3]:
        match = re.match(r"^(\d+)", part)
        nums.append(int(match.group(1)) if match else 0)
    while len(nums) < 3:
        nums.append(0)
    return nums[0], nums[1], nums[2]


def compare(left: str, right: str) -> int:
    a, b = version_tuple(left), version_tuple(right)
    if a < b:
        return -1
    if a > b:
        return 1
    return 0


def satisfies_constraint(current: str, constraint: str) -> bool:
    match = _CONSTRAINT.match(constraint.strip())
    if not match:
        raise ValueError(f"unsupported runtime constraint: {constraint}")
    op, bound = match.group(1), match.group(2)
    cmp = compare(current, bound)
    if op == ">=":
        return cmp >= 0
    if op == "<=":
        return cmp <= 0
    if op == ">":
        return cmp > 0
    if op == "<":
        return cmp < 0
    return cmp == 0


def requirement_ok(current: str, req: dict[str, Any]) -> bool:
    constraint = str(req.get("constraint") or "").strip()
    if constraint:
        return satisfies_constraint(current, constraint)
    majors = req.get("accepted_majors") or []
    if majors:
        return version_tuple(current)[0] in {int(m) for m in majors}
    return True


def applicable(requirements: list[dict[str, Any]], consumers: set[str]) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    for req in requirements:
        owned = {str(c) for c in (req.get("consumers") or [])}
        bare = {c.split(":", 1)[-1] for c in owned}
        if owned & consumers or bare & consumers:
            selected.append(req)
    return selected


def _candidates(current: str | None, default_major: str, reqs: list[dict[str, Any]]) -> list[str]:
    found: list[str] = []

    def add(value: str) -> None:
        if value and value not in found:
            found.append(value)

    if current:
        add(current)
    major = str(default_major).split(".", 1)[0]
    add(f"{major}.0.0")
    for req in reqs:
        preferred = req.get("preferred_major")
        if preferred is not None:
            add(f"{int(preferred)}.0.0")
        for accepted in req.get("accepted_majors") or []:
            add(f"{int(accepted)}.0.0")
        constraint = str(req.get("constraint") or "").strip()
        match = _CONSTRAINT.match(constraint)
        if match and match.group(1) in {">=", "=="}:
            add(match.group(2))
    return found


def resolve_node(
    consumers: set[str],
    *,
    current: str | None = None,
    root=None,
    requirements: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Pick one Node version for the selected consumers.

    An already-satisfying ``current`` is kept. Conflicting constraints fail
    before any install is attempted.
    """
    doc = runtime_requirements(root)
    if requirements is None:
        reqs = applicable(list(doc.get("requirements") or []), consumers)
    else:
        reqs = requirements
    default_major = node_default_major(root)
    if not reqs:
        chosen = current or f"{default_major}.0.0"
        return {
            "ok": True,
            "runtime": "node",
            "resolved": chosen,
            "replaced": False,
            "requirements": [],
            "reason": "no capability runtime constraints selected",
        }

    candidates = _candidates(current, default_major, reqs)
    satisfying = [c for c in candidates if all(requirement_ok(c, req) for req in reqs)]
    described = [
        {
            "id": req.get("id"),
            "constraint": req.get("constraint") or "",
            "accepted_majors": list(req.get("accepted_majors") or []),
        }
        for req in reqs
    ]
    if not satisfying:
        lines = []
        for req in reqs:
            if req.get("constraint"):
                lines.append(f"{req.get('id')} requires Node {req.get('constraint')}")
            elif req.get("accepted_majors"):
                majors = ", ".join(str(m) for m in req.get("accepted_majors") or [])
                lines.append(f"{req.get('id')} requires Node major {majors}")
        return {
            "ok": False,
            "runtime": "node",
            "resolved": None,
            "replaced": False,
            "requirements": described,
            "error": "No Node runtime satisfies selected capabilities.\n" + "\n".join(lines),
        }
    chosen = satisfying[0]
    return {
        "ok": True,
        "runtime": "node",
        "resolved": chosen,
        "replaced": bool(current) and compare(chosen, current or "0") != 0,
        "requirements": described,
        "reason": "existing Node already satisfies selected capabilities"
        if current and compare(chosen, current) == 0
        else f"resolved Node {chosen}",
    }
