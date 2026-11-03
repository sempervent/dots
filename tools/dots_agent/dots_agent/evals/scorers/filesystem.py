"""Filesystem outcome scorers."""

from __future__ import annotations

from pathlib import Path
from typing import Any


def score_filesystem(work_dir: Path, expected: dict[str, Any]) -> dict[str, Any]:
    reasons: list[str] = []
    for rel in expected.get("exists") or []:
        p = work_dir / str(rel)
        if not p.exists():
            reasons.append(f"missing:{rel}")
    for rel in expected.get("missing") or []:
        p = work_dir / str(rel)
        if p.exists():
            reasons.append(f"unexpected:{rel}")
    fe = expected.get("file_equals")
    if isinstance(fe, dict):
        path = fe.get("path")
        text = fe.get("text", "")
        if path:
            p = work_dir / str(path)
            if not p.is_file():
                reasons.append(f"missing:{path}")
            else:
                got = p.read_text(encoding="utf-8")
                # Allow missing final newline if expected has one
                if got != text and got.rstrip("\n") + "\n" != text:
                    if got.rstrip("\n") != str(text).rstrip("\n"):
                        reasons.append(f"content_mismatch:{path}")
    fc = expected.get("file_contains")
    if isinstance(fc, dict):
        path = fc.get("path")
        needle = str(fc.get("text") or "")
        if path:
            p = work_dir / str(path)
            if not p.is_file():
                reasons.append(f"missing:{path}")
            elif needle not in p.read_text(encoding="utf-8"):
                reasons.append(f"missing_text:{path}")
    passed = not reasons
    return {
        "passed": passed,
        "status": "PASS" if passed else "MODEL_FAIL",
        "summary": "ok" if passed else "; ".join(reasons),
    }
