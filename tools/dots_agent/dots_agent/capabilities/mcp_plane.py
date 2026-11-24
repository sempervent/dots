"""MCP trust, desired-state filtering, discovery, audit, and doctor.

Discovery never installs or enables a server. Registry search results stay
DISCOVERED until a maintainer adds them to configs/agents/mcp-trust.toml.
"""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from dots_agent.capabilities.load import known_mcp_ids, mcp_rows

SECRET_FIELD = re.compile(
    r"(?i)(api[_-]?key|token|secret|password)[\"']?\s*[:=]\s*[\"'][^\"']{8,}[\"']"
)
CLIENTS = {"pi", "hermes", "opencode", "codex", "cursor"}
TRANSPORTS = {"stdio", "streamable_http"}
AUTH_MODES = {"none", "env", "oauth", "client_credentials"}
MODES = {"safe", "in_place", "interactive"}
REGISTRY_URL = "https://registry.modelcontextprotocol.io/v0/servers"


def flag(row: dict[str, Any], key: str, legacy: str | None = None) -> bool:
    if key in row:
        return bool(row[key])
    if legacy and legacy in row:
        return bool(row[legacy])
    return False


def permissions(row: dict[str, Any]) -> dict[str, bool]:
    filesystem = flag(row, "filesystem")
    return {
        "filesystem_read": flag(row, "filesystem_read") or filesystem,
        "filesystem_write": flag(row, "filesystem_write") or filesystem,
        "shell": flag(row, "shell"),
        "network": flag(row, "network", None) or row.get("trust") in {"read_only_network", "billable_remote"},
        "remote_write": flag(row, "remote_write"),
        "billable": flag(row, "billable"),
        "credentials": bool(row.get("auth_mode") not in (None, "", "none")),
    }


def safe_decision(row: dict[str, Any]) -> tuple[bool, str]:
    """Fail closed. Desired state alone never admits a dangerous server."""
    perms = permissions(row)
    if perms["shell"]:
        return False, "shell is not allowed in safe mode"
    if perms["filesystem_write"]:
        return False, "filesystem write is not allowed in safe mode"
    if perms["remote_write"]:
        return False, "remote writes require explicit approval and stay out of safe mode"
    trust = str(row.get("trust") or "")
    if row.get("safe_default") is True or trust in {"read_only_network", "billable_remote"}:
        return True, "curated safe policy"
    return False, "not declared safe_default"


def auth_status(row: dict[str, Any]) -> dict[str, Any]:
    mode = str(row.get("auth_mode") or "none")
    required = [str(x) for x in (row.get("required_env") or [])]
    states = {name: "SET" if os.environ.get(name) else "UNSET" for name in required}
    return {"mode": mode, "required": required, "env": states}


def audit_registry(rows: list[dict[str, Any]] | None = None) -> dict[str, list[str]]:
    rows = mcp_rows() if rows is None else rows
    errors: list[str] = []
    warnings: list[str] = []
    seen: set[str] = set()
    for row in rows:
        ident = str(row.get("id") or "")
        if not ident:
            errors.append("mcp server missing id")
            continue
        if ident in seen:
            errors.append(f"duplicate mcp id: {ident}")
        seen.add(ident)
        transport = str(row.get("transport") or "")
        if transport and transport not in TRANSPORTS:
            errors.append(f"{ident}: invalid transport {transport}")
        if transport == "stdio" and not (row.get("command") or ident.startswith("dots-")):
            errors.append(f"{ident}: stdio without command")
        if transport == "streamable_http" and not row.get("url"):
            errors.append(f"{ident}: HTTP without URL")
        blob = json.dumps(row)
        if SECRET_FIELD.search(blob):
            errors.append(f"{ident}: secret value embedded in manifest")
        if row.get("safe_default") is True and (flag(row, "shell") or flag(row, "filesystem_write") or flag(row, "filesystem")):
            errors.append(f"{ident}: safe_default with unsafe shell or filesystem policy")
        for client in row.get("allowed_clients") or []:
            if str(client) not in CLIENTS:
                errors.append(f"{ident}: unknown client {client}")
        for mode in row.get("allowed_modes") or []:
            if str(mode) not in MODES:
                errors.append(f"{ident}: unsupported execution mode {mode}")
        if row.get("source") == "remote" and not row.get("url"):
            errors.append(f"{ident}: remote source is not identified")
        auth = str(row.get("auth_mode") or "none")
        if row.get("auth_mode") is not None and auth not in AUTH_MODES:
            errors.append(f"{ident}: unknown auth mode {auth}")
    return {"errors": errors, "warnings": warnings}


def filter_for_mode(
    desired: list[str],
    *,
    mode: str,
    client: str,
    rows: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    rows = mcp_rows() if rows is None else rows
    by_id = {str(r["id"]): r for r in rows}
    allowed: list[str] = []
    blocked: list[dict[str, str]] = []
    for ident in desired:
        row = by_id.get(ident)
        if row is None:
            blocked.append({"id": ident, "reason": "unknown server"})
            continue
        clients = [str(c) for c in (row.get("allowed_clients") or [])]
        if clients and client not in clients:
            blocked.append({"id": ident, "reason": f"client {client} is not allowed"})
            continue
        modes = [str(m) for m in (row.get("allowed_modes") or [])]
        if modes and mode not in modes:
            blocked.append({"id": ident, "reason": f"mode {mode} is not allowed"})
            continue
        if mode == "safe":
            ok, reason = safe_decision(row)
            if not ok:
                blocked.append({"id": ident, "reason": reason})
                continue
        allowed.append(ident)
    return {"allowed": allowed, "blocked": blocked}


def search_registry(query: str, *, timeout: float = 5.0) -> dict[str, Any]:
    """Metadata discovery only. Does not install, enable, or trust results."""
    fixture = os.environ.get("DOTS_MCP_REGISTRY_FIXTURE", "").strip()
    if fixture:
        data = json.loads(Path(fixture).read_text(encoding="utf-8"))
    elif os.environ.get("DOTS_MCP_REGISTRY_OFFLINE") == "1":
        return {
            "query": query,
            "servers": [],
            "error": "registry search is offline; set DOTS_MCP_REGISTRY_FIXTURE or run without DOTS_MCP_REGISTRY_OFFLINE",
        }
    else:
        url = f"{REGISTRY_URL}?search={urllib.parse.quote(query)}"
        req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "dots-mcp-search"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            return {"query": query, "servers": [], "error": f"registry unavailable: {exc.__class__.__name__}"}
    servers = data.get("servers") or data.get("results") or []
    curated = known_mcp_ids()
    out = []
    for row in servers:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or row.get("id") or "")
        blob = json.dumps(row).lower()
        if query and query.lower() not in blob and query.lower() not in name.lower():
            continue
        out.append(
            {
                "id": name,
                "description": row.get("description") or "",
                "state": "CURATED" if name in curated else "DISCOVERED",
                "trusted": name in curated,
            }
        )
    return {"query": query, "servers": out, "error": None}


def doctor_row(row: dict[str, Any]) -> dict[str, Any]:
    ident = str(row.get("id") or "")
    checks: list[dict[str, str]] = []
    transport = str(row.get("transport") or "stdio")
    checks.append({"check": "declaration", "status": "OK" if ident else "FAIL"})
    checks.append({"check": "transport", "status": "OK" if transport in TRANSPORTS or not row.get("transport") else "FAIL"})
    if transport == "streamable_http":
        url = str(row.get("url") or "")
        checks.append({"check": "url", "status": "OK" if url.startswith("https://") else "FAIL"})
    else:
        command = str(row.get("command") or "")
        checks.append({"check": "command", "status": "OK" if command or ident.startswith("dots-") else "FAIL"})
    auth = auth_status(row)
    missing = [name for name, state in auth["env"].items() if state == "UNSET"]
    checks.append({"check": "auth", "status": "AUTH REQUIRED" if missing else "OK"})
    ok, reason = safe_decision(row)
    checks.append({"check": "safe_policy", "status": "OK" if ok else "BLOCKED", "detail": reason})
    healthy = all(item["status"] in {"OK", "BLOCKED"} for item in checks if item["check"] != "safe_policy")
    if missing:
        healthy = False
    return {
        "id": ident,
        "healthy": healthy and not missing,
        "auth_required": bool(missing),
        "checks": checks,
        "permissions": permissions(row),
        "auth": auth,
    }
