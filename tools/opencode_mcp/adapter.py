#!/usr/bin/env python3
"""Shared OpenCode execution adapter (argv-safe, no shell interpolation)."""

from __future__ import annotations

import json
import os
import re
import shutil
import signal
import subprocess
import tomllib
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


DEFAULT_TIMEOUT = 600
DEFAULT_AGENT = "build"
DEFAULT_MODEL = "ollama/qwen-hermes:latest"
DEFAULT_MODE = "standalone"
DEFAULT_SERVER_URL = "http://127.0.0.1:4096"


def dots_root() -> Path:
    env = os.environ.get("DOTS_DIR")
    if env:
        return Path(env).expanduser()
    return Path(__file__).resolve().parents[2]


def exec_config_path() -> Path:
    override = os.environ.get("DOTS_AGENTS_EXEC_CONFIG")
    if override:
        return Path(override).expanduser()
    live = Path.home() / ".config" / "dots" / "agents" / "execution.toml"
    if live.is_file():
        return live
    return dots_root() / "configs" / "agents" / "execution.toml"


def load_exec_config() -> dict[str, Any]:
    path = exec_config_path()
    if not path.is_file():
        return {}
    with path.open("rb") as fh:
        return tomllib.load(fh)


def opencode_section() -> dict[str, Any]:
    return dict(load_exec_config().get("opencode") or {})


def resolve_cwd(raw: str | None) -> Path:
    if not raw or not str(raw).strip():
        raise ValueError(
            "Working directory required (--dir / cwd). "
            "Do not silently default to DOTS or $HOME for coding tasks."
        )
    path = Path(raw).expanduser()
    if not path.exists():
        raise ValueError(f"cwd does not exist: {path}")
    if not path.is_dir():
        raise ValueError(f"cwd is not a directory: {path}")
    return path.resolve()


def resolve_opencode_bin(configured: str | None = None) -> str:
    name = configured or str(opencode_section().get("binary") or "opencode")
    if name.startswith("/") and Path(name).is_file():
        return name
    path = shutil.which(name)
    if not path:
        raise RuntimeError(
            f"'{name}' not found on PATH. Install with: ./setup.sh --with opencode"
        )
    return path


@dataclass
class RunResult:
    success: bool
    exit_code: int
    cwd: str
    model: str
    agent: str
    mode: str
    timed_out: bool
    session_id: str | None
    output: str
    raw_events: list[Any]
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _parse_json_events(stdout: str) -> tuple[list[Any], str | None, str]:
    """Extract JSON event lines; return events, session_id, text summary."""
    events: list[Any] = []
    texts: list[str] = []
    session_id: str | None = None
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            texts.append(line)
            continue
        events.append(obj)
        if isinstance(obj, dict):
            sid = obj.get("sessionID") or obj.get("session_id") or obj.get("id")
            if isinstance(sid, str) and sid and session_id is None:
                # Prefer explicit session fields when present on top-level events
                if "sessionID" in obj or "session_id" in obj:
                    session_id = sid
            part = obj.get("part") or obj.get("message") or {}
            if isinstance(part, dict):
                t = part.get("text") or part.get("content")
                if isinstance(t, str) and t.strip():
                    texts.append(t.strip())
            if obj.get("type") in ("text", "message") and isinstance(obj.get("text"), str):
                texts.append(obj["text"])
            # Common OpenCode json event: type=message with role assistant
            info = obj.get("info")
            if isinstance(info, dict) and isinstance(info.get("id"), str):
                if obj.get("type") == "session" or "session" in str(obj.get("type", "")):
                    session_id = session_id or info["id"]
    summary = "\n".join(texts).strip() if texts else stdout.strip()
    return events, session_id, summary


def run_opencode(
    *,
    prompt: str,
    cwd: str,
    model: str | None = None,
    agent: str | None = None,
    timeout_seconds: int | None = None,
    auto_approve: bool | None = None,
    attach: str | None = None,
    format_json: bool = True,
) -> RunResult:
    cfg = opencode_section()
    mode = str(cfg.get("mode") or DEFAULT_MODE)
    resolved_cwd = resolve_cwd(cwd)
    resolved_model = model or str(cfg.get("default_model") or DEFAULT_MODEL)
    resolved_agent = agent or str(cfg.get("default_agent") or DEFAULT_AGENT)
    timeout = int(
        timeout_seconds
        if timeout_seconds is not None
        else cfg.get("timeout_seconds") or DEFAULT_TIMEOUT
    )
    if auto_approve is None:
        auto_approve = bool(cfg.get("auto_approve", False))

    server_url = attach
    if mode == "server" and not server_url:
        server_url = str(cfg.get("server_url") or DEFAULT_SERVER_URL)

    # Local telemetry (never stores prompt; never fails the task)
    _tele_id = None
    try:
        import sys as _sys
        from pathlib import Path as _Path

        _tele_root = str(_Path(__file__).resolve().parents[2] / "tools" / "agent_telemetry")
        if _tele_root not in _sys.path:
            _sys.path.insert(0, _tele_root)
        import bridge as _tele  # type: ignore

        _tele_id = _tele.start(
            backend="opencode",
            task_kind="coding-local",
            task_label="repository coding",
            model=resolved_model,
            provider="opencode",
            agent=resolved_agent,
            tool="opencode-agent",
            cwd=str(resolved_cwd),
            local_or_cloud="local",
        )
    except Exception:
        _tele_id = None

    bin_path = resolve_opencode_bin(str(cfg.get("binary") or "opencode"))
    argv: list[str] = [
        bin_path,
        "run",
        "--dir",
        str(resolved_cwd),
        "--model",
        resolved_model,
        "--agent",
        resolved_agent,
    ]
    if format_json:
        argv.extend(["--format", "json"])
    if server_url:
        argv.extend(["--attach", server_url])
    if auto_approve:
        argv.append("--auto")
    argv.append(prompt)

    timed_out = False
    error: str | None = None
    proc: subprocess.Popen[str] | None = None
    stdout = ""
    stderr = ""
    exit_code = 1
    try:
        proc = subprocess.Popen(
            argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=str(resolved_cwd),
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
    session_id: str | None = None
    output = (stdout or "").strip()
    if format_json and stdout:
        events, session_id, summary = _parse_json_events(stdout)
        if summary:
            output = summary
    if stderr and not timed_out:
        # Keep stderr for debugging without dumping secrets-heavy env
        if error:
            error = f"{error}; stderr: {stderr.strip()[:2000]}"
        elif exit_code != 0:
            error = stderr.strip()[:4000] or error

    success = (exit_code == 0) and not timed_out and error is None
    if timed_out:
        success = False
        exit_code = exit_code if exit_code not in (0, None) else 124

    try:
        if _tele_id:
            import sys as _sys
            from pathlib import Path as _Path

            _tele_root = str(_Path(__file__).resolve().parents[2] / "tools" / "agent_telemetry")
            if _tele_root not in _sys.path:
                _sys.path.insert(0, _tele_root)
            import bridge as _tele  # type: ignore

            _tele.finish(
                _tele_id,
                success=success,
                exit_code=exit_code,
                timed_out=timed_out,
                model=resolved_model,
            )
    except Exception:
        pass

    return RunResult(
        success=success,
        exit_code=exit_code,
        cwd=str(resolved_cwd),
        model=resolved_model,
        agent=resolved_agent,
        mode="server" if server_url else "standalone",
        timed_out=timed_out,
        session_id=session_id,
        output=output,
        raw_events=events,
        error=error,
    )


def status_info() -> dict[str, Any]:
    cfg = opencode_section()
    bin_path = None
    version = None
    try:
        bin_path = resolve_opencode_bin(str(cfg.get("binary") or "opencode"))
        proc = subprocess.run(
            [bin_path, "--version"],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        version = (proc.stdout or proc.stderr or "").strip().splitlines()[:1]
        version = version[0] if version else None
    except Exception as exc:  # noqa: BLE001
        return {
            "ok": False,
            "error": str(exc),
            "config": cfg,
            "exec_config": str(exec_config_path()),
        }
    return {
        "ok": True,
        "binary": bin_path,
        "version": version,
        "mode": cfg.get("mode", DEFAULT_MODE),
        "default_agent": cfg.get("default_agent", DEFAULT_AGENT),
        "default_model": cfg.get("default_model", DEFAULT_MODEL),
        "timeout_seconds": cfg.get("timeout_seconds", DEFAULT_TIMEOUT),
        "auto_approve": bool(cfg.get("auto_approve", False)),
        "server_url": cfg.get("server_url", DEFAULT_SERVER_URL),
        "exec_config": str(exec_config_path()),
        "mutation_policy": {
            "inspect": "Prefer --agent plan (edit denied) or a read-only prompt.",
            "implementation": "Default agent build may modify files in --dir.",
            "caller_owns_cwd": True,
        },
        "concurrency_note": (
            "Avoid concurrent heavy local inference (OpenCode + Hermes + Draw Things)."
        ),
    }


def list_models() -> dict[str, Any]:
    bin_path = resolve_opencode_bin()
    proc = subprocess.run(
        [bin_path, "models"],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    models = [ln.strip() for ln in (proc.stdout or "").splitlines() if ln.strip()]
    return {
        "ok": proc.returncode == 0,
        "exit_code": proc.returncode,
        "models": models,
        "stderr": (proc.stderr or "").strip()[:2000] or None,
    }


def list_agents() -> dict[str, Any]:
    bin_path = resolve_opencode_bin()
    proc = subprocess.run(
        [bin_path, "agent", "list"],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    agents: list[str] = []
    for ln in (proc.stdout or "").splitlines():
        m = re.match(r"^([A-Za-z][\w-]*)\s+\((primary|subagent)\)\s*$", ln.strip())
        if m:
            name = m.group(1)
            if name not in agents:
                agents.append(name)
    return {
        "ok": proc.returncode == 0,
        "exit_code": proc.returncode,
        "agents": agents,
        "stderr": (proc.stderr or "").strip()[:2000] or None,
    }
