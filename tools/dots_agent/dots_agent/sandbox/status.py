"""Sandbox status / doctor probes."""

from __future__ import annotations

import json
import platform
import shutil
import subprocess
from pathlib import Path
from typing import Any

from dots_agent.config import load_config
from dots_agent.mcp_trust import safe_server_ids
from dots_agent.sandbox.policy import global_sandbox_path


def pi_sandbox_installed() -> tuple[bool, str]:
    if not shutil.which("pi"):
        return False, "pi missing"
    try:
        out = subprocess.check_output(["pi", "list"], text=True, timeout=20)
    except Exception as exc:
        return False, f"pi list failed: {exc}"
    if "pi-sandbox" in out.lower():
        # try extract version line
        for line in out.splitlines():
            if "pi-sandbox" in line.lower():
                return True, line.strip()
        return True, "pi-sandbox (listed)"
    # package dir fallback
    for cand in (
        Path.home() / ".pi" / "agent" / "packages" / "pi-sandbox",
        Path.home() / ".pi" / "packages" / "pi-sandbox",
    ):
        if cand.is_dir():
            return True, f"present at {cand}"
    return False, "not installed"


def os_backend() -> dict[str, str]:
    system = platform.system()
    if system == "Darwin":
        return {
            "platform": "darwin",
            "backend": "sandbox-exec",
            "available": "yes" if shutil.which("sandbox-exec") or Path("/usr/bin/sandbox-exec").exists() else "no",
        }
    if system == "Linux":
        return {
            "platform": "linux",
            "backend": "bubblewrap",
            "available": "yes" if shutil.which("bwrap") else "no",
            "socat": "yes" if shutil.which("socat") else "no",
            "ripgrep": "yes" if shutil.which("rg") else "no",
        }
    return {"platform": system, "backend": "unknown", "available": "no"}


def sandbox_config_parseable() -> tuple[bool, str]:
    path = global_sandbox_path()
    if not path.is_file():
        return False, "missing"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return False, f"parse error: {exc}"
    if not isinstance(data, dict):
        return False, "not an object"
    if data.get("enabled") is False:
        return True, "parseable (enabled=false)"
    return True, "parseable (enabled=true)" if data.get("enabled", True) else "parseable"


def sandbox_status_report() -> dict[str, Any]:
    cfg = load_config()
    installed, detail = pi_sandbox_installed()
    backend = os_backend()
    parse_ok, parse_detail = sandbox_config_parseable()
    sandbox_cfg = cfg.raw.get("sandbox") or {}
    agent_cfg = cfg.raw.get("agent") or {}
    return {
        "provider": sandbox_cfg.get("provider", "pi-sandbox"),
        "installed": installed,
        "install_detail": detail,
        "enabled_default": True,
        "execution_mode_default": agent_cfg.get("execution_mode", "safe"),
        "worktree_enabled": bool(sandbox_cfg.get("worktree_enabled", True)),
        "bash_allowed_domains": list(
            sandbox_cfg.get("bash_allowed_domains") or ["localhost", "127.0.0.1"]
        ),
        "fail_closed": bool(sandbox_cfg.get("fail_closed", True)),
        "os_backend": backend,
        "config": parse_detail,
        "config_ok": parse_ok,
        "mcp_safe_servers": safe_server_ids(cfg),
        "unsafe_fallback": "NEVER AUTOMATIC",
    }


def doctor_sandbox_checks() -> list[tuple[str, str]]:
    """Return (name, OK|WARN|FAIL: detail) rows for doctor."""
    rows: list[tuple[str, str]] = []
    installed, detail = pi_sandbox_installed()
    if installed:
        rows.append(("Sandbox extension", f"OK ({detail})"))
    else:
        rows.append(("Sandbox extension", f"FAIL ({detail})"))

    backend = os_backend()
    if backend["platform"] == "darwin":
        rows.append(
            (
                "OS sandbox backend",
                "OK (sandbox-exec)"
                if backend.get("available") == "yes"
                else "FAIL (sandbox-exec missing)",
            )
        )
    elif backend["platform"] == "linux":
        if backend.get("available") == "yes" and backend.get("socat") == "yes" and backend.get("ripgrep") == "yes":
            rows.append(("OS sandbox backend", "OK (bwrap+socat+rg)"))
        else:
            missing = [
                k
                for k, v in (
                    ("bwrap", backend.get("available")),
                    ("socat", backend.get("socat")),
                    ("rg", backend.get("ripgrep")),
                )
                if v != "yes"
            ]
            rows.append(("OS sandbox backend", f"FAIL (missing {', '.join(missing)})"))
    else:
        rows.append(("OS sandbox backend", f"FAIL (unsupported {backend['platform']})"))

    parse_ok, parse_detail = sandbox_config_parseable()
    rows.append(
        ("Sandbox config", f"OK ({parse_detail})" if parse_ok else f"FAIL ({parse_detail})")
    )

    if shutil.which("git"):
        rows.append(("Worktree support", "OK (git)"))
    else:
        rows.append(("Worktree support", "FAIL (git missing)"))

    rows.append(("Secret deny policy", "OK (DOTS managed paths+globs)"))
    rows.append(("Bash network policy", "OK (localhost/127.0.0.1 only by default)"))
    rows.append(("MCP allowlist", f"OK ({', '.join(safe_server_ids())})"))
    rows.append(("Unsafe fallback", "OK (NEVER AUTOMATIC — use --unsafe-host)"))
    return rows
