#!/usr/bin/env python3
"""Shared Codex CLI execution helpers for the DOTS MCP bridge.

Codex Homebrew cask ≥0.154 removed ``codex mcp-server``. This adapter wraps
``codex exec`` (argv-safe) so Hermes can still invoke Codex as an MCP coding
specialist while auth stays in ``~/.codex/``.
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


DEFAULT_TIMEOUT = 900


def resolve_codex_bin() -> str:
    path = shutil.which("codex")
    if not path:
        raise RuntimeError("codex not found on PATH. Install: brew install --cask codex")
    return path


def native_mcp_server_available() -> bool:
    """True when ``codex mcp-server -h`` is a recognized subcommand."""
    try:
        proc = subprocess.run(
            [resolve_codex_bin(), "mcp-server", "-h"],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
    except (RuntimeError, OSError, subprocess.TimeoutExpired):
        return False
    combined = f"{proc.stdout}\n{proc.stderr}"
    if "unrecognized subcommand" in combined.lower():
        return False
    # Help text for the real subcommand mentions MCP server / stdio
    return proc.returncode == 0 or "mcp" in combined.lower()


def resolve_cwd(raw: str | None) -> Path:
    if not raw or not str(raw).strip():
        raise ValueError(
            "Working directory (cwd) required for Codex coding tasks. "
            "Do not silently default to DOTS or $HOME."
        )
    path = Path(raw).expanduser()
    if not path.exists():
        raise ValueError(f"cwd does not exist: {path}")
    if not path.is_dir():
        raise ValueError(f"cwd is not a directory: {path}")
    return path.resolve()


@dataclass
class ExecResult:
    success: bool
    exit_code: int
    cwd: str
    timed_out: bool
    output: str
    thread_id: str | None = None
    error: str | None = None
    raw_json_lines: list[Any] | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _extract_thread_id(events: list[Any], stdout: str) -> str | None:
    for obj in events:
        if not isinstance(obj, dict):
            continue
        for key in ("thread_id", "threadId", "session_id", "sessionId"):
            val = obj.get(key)
            if isinstance(val, str) and val:
                return val
        info = obj.get("thread") or obj.get("session") or {}
        if isinstance(info, dict):
            for key in ("id", "thread_id", "threadId"):
                val = info.get(key)
                if isinstance(val, str) and val:
                    return val
    # Fallback scan
    for line in stdout.splitlines():
        if "thread" in line.lower() and "id" in line.lower():
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict):
                tid = obj.get("thread_id") or obj.get("threadId")
                if isinstance(tid, str):
                    return tid
    return None


def _run_argv(argv: list[str], *, cwd: Path, timeout: int) -> ExecResult:
    timed_out = False
    error: str | None = None
    stdout = ""
    stderr = ""
    exit_code = 1
    proc: subprocess.Popen[str] | None = None
    try:
        proc = subprocess.Popen(
            argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=str(cwd),
            start_new_session=True,
        )
        try:
            stdout, stderr = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            error = f"timed out after {timeout}s"
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                stdout, stderr = proc.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                stdout, stderr = proc.communicate()
        exit_code = int(proc.returncode if proc.returncode is not None else 1)
    except OSError as exc:
        error = str(exc)
        exit_code = 127

    events: list[Any] = []
    for line in (stdout or "").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass

    if stderr and not timed_out and exit_code != 0:
        error = (error + "; " if error else "") + stderr.strip()[:4000]

    if timed_out and exit_code in (0, None):
        exit_code = 124

    return ExecResult(
        success=(exit_code == 0) and not timed_out and not error,
        exit_code=exit_code,
        cwd=str(cwd),
        timed_out=timed_out,
        output=(stdout or "").strip(),
        thread_id=_extract_thread_id(events, stdout or ""),
        error=error,
        raw_json_lines=events[-50:] if events else None,
    )


def run_codex(
    *,
    prompt: str,
    cwd: str,
    timeout_seconds: int | None = None,
    sandbox: str = "workspace-write",
    model: str | None = None,
    skip_git_repo_check: bool = False,
) -> ExecResult:
    resolved = resolve_cwd(cwd)
    timeout = int(timeout_seconds or DEFAULT_TIMEOUT)
    bin_path = resolve_codex_bin()
    argv: list[str] = [
        bin_path,
        "exec",
        "--cd",
        str(resolved),
        "--sandbox",
        sandbox,
        "--json",
    ]
    if model:
        argv.extend(["--model", model])
    if skip_git_repo_check:
        argv.append("--skip-git-repo-check")
    argv.append(prompt)
    return _run_argv(argv, cwd=resolved, timeout=timeout)


def reply_codex(
    *,
    prompt: str,
    thread_id: str,
    cwd: str,
    timeout_seconds: int | None = None,
) -> ExecResult:
    resolved = resolve_cwd(cwd)
    timeout = int(timeout_seconds or DEFAULT_TIMEOUT)
    bin_path = resolve_codex_bin()
    argv = [
        bin_path,
        "exec",
        "resume",
        thread_id,
        "--cd",
        str(resolved),
        "--json",
        prompt,
    ]
    return _run_argv(argv, cwd=resolved, timeout=timeout)


def status_info() -> dict[str, Any]:
    try:
        bin_path = resolve_codex_bin()
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc)}
    ver = subprocess.run(
        [bin_path, "--version"], capture_output=True, text=True, timeout=15, check=False
    )
    return {
        "ok": True,
        "binary": bin_path,
        "version": (ver.stdout or ver.stderr or "").strip().splitlines()[:1],
        "native_mcp_server": native_mcp_server_available(),
        "bridge": "dots-codex-mcp (codex exec)",
        "auth_note": "Credentials remain in ~/.codex/; never copied into DOTS",
        "mutation_policy": {
            "implementation": "codex exec may modify files under cwd",
            "caller_owns_cwd": True,
        },
    }
