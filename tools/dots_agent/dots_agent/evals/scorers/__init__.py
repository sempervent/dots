"""Deterministic scorers — no LLM-as-judge."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .command import score_command
from .filesystem import score_filesystem
from .json_schema import score_json_exact, score_json_schema


def score_task(
    work_dir: Path,
    scorer: dict[str, Any],
    expected: dict[str, Any],
    *,
    hidden_dir: Path | None = None,
) -> dict[str, Any]:
    stype = str(scorer.get("type") or "").lower()
    if stype == "command":
        return score_command(work_dir, scorer, expected, hidden_dir=hidden_dir)
    if stype == "filesystem":
        return score_filesystem(work_dir, expected)
    if stype == "json_exact":
        return score_json_exact(work_dir, scorer, expected)
    if stype == "json_schema":
        return score_json_schema(work_dir, scorer, expected)
    return {
        "passed": False,
        "status": "HARNESS_ERROR",
        "summary": f"unknown scorer type: {stype}",
    }
