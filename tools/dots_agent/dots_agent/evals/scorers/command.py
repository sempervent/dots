"""Command-exit scorers (pytest, bash verify, etc.)."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import Any


def score_command(
    work_dir: Path,
    scorer: dict[str, Any],
    expected: dict[str, Any],
    *,
    hidden_dir: Path | None = None,
) -> dict[str, Any]:
    cmd = scorer.get("command")
    if not isinstance(cmd, list) or not cmd:
        return {
            "passed": False,
            "status": "HARNESS_ERROR",
            "summary": "scorer.command missing",
        }
    exe = str(cmd[0])
    if shutil.which(exe) is None and not Path(exe).is_file():
        return {
            "passed": False,
            "status": "SKIPPED_PREREQUISITE",
            "summary": f"missing executable: {exe}",
        }
    env = os.environ.copy()
    if hidden_dir is not None:
        env["DOTS_EVAL_HIDDEN"] = str(hidden_dir)
    try:
        proc = subprocess.run(
            [str(c) for c in cmd],
            cwd=str(work_dir),
            capture_output=True,
            text=True,
            timeout=int(scorer.get("timeout_seconds") or 60),
            env=env,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return {
            "passed": False,
            "status": "TIMEOUT",
            "summary": "scorer command timed out",
            "exit_code": None,
        }
    except OSError as exc:
        return {
            "passed": False,
            "status": "HARNESS_ERROR",
            "summary": f"scorer spawn failed: {exc}",
        }
    want = int(expected.get("exit_code", 0))
    passed = proc.returncode == want
    out = (proc.stdout or "")[-800:]
    err = (proc.stderr or "")[-800:]
    return {
        "passed": passed,
        "status": "PASS" if passed else "MODEL_FAIL",
        "summary": f"exit={proc.returncode} want={want}",
        "exit_code": proc.returncode,
        "stdout_tail": out,
        "stderr_tail": err,
    }
