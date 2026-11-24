"""Merge DOTS-owned MCP entries into client configs without replacing user entries."""

from __future__ import annotations

import json
import os
import shutil
import time
from pathlib import Path
from typing import Any

CLIENTS = {
    "pi": {
        "installed_bins": ["pi"],
        "supports_skills": True,
        "skills_mode": "native",
        "supports_mcp": True,
        "mcp_mode": "json",
        "config": ".pi/agent/mcp.json",
        "key": "mcpServers",
    },
    "hermes": {
        "installed_bins": ["hermes"],
        "supports_skills": True,
        "skills_mode": "native",
        "supports_mcp": True,
        "mcp_mode": "yaml-append",
        "config": ".hermes/config.yaml",
        "key": "mcp_servers",
    },
    "opencode": {
        "installed_bins": ["opencode"],
        "supports_skills": True,
        "skills_mode": "native",
        "supports_mcp": True,
        "mcp_mode": "json",
        "config": ".config/opencode/opencode.json",
        "key": "mcp.servers",
    },
    "codex": {
        "installed_bins": ["codex"],
        "supports_skills": True,
        "skills_mode": "native",
        "supports_mcp": True,
        "mcp_mode": "toml-region",
        "config": ".codex/config.toml",
        "key": "mcp_servers",
    },
    "cursor": {
        "installed_bins": ["cursor"],
        "supports_skills": True,
        "skills_mode": "native",
        "supports_mcp": True,
        "mcp_mode": "json",
        "config": ".cursor/mcp.json",
        "key": "mcpServers",
    },
}

BEGIN = "# DOTS MCP BEGIN"
END = "# DOTS MCP END"


def _which(name: str) -> bool:
    for part in os.environ.get("PATH", "").split(os.pathsep):
        if part and (Path(part) / name).is_file():
            return True
    return False


def client_report(home: Path | None = None) -> list[dict[str, Any]]:
    home = home or Path.home()
    rows = []
    for ident, spec in CLIENTS.items():
        installed = any(_which(binary) for binary in spec["installed_bins"])
        config = home / str(spec["config"])
        rows.append(
            {
                "id": ident,
                "installed": installed,
                "supports_skills": spec["supports_skills"],
                "supports_mcp": spec["supports_mcp"],
                "skills_mode": spec["skills_mode"],
                "mcp_mode": spec["mcp_mode"],
                "config_path": str(config),
                "healthy": installed or not config.exists(),
            }
        )
    return rows


def _backup(path: Path) -> str | None:
    if not path.exists():
        return None
    dest = path.with_name(path.name + f".bak.{time.strftime('%Y%m%d%H%M%S')}")
    shutil.copy2(path, dest)
    return str(dest)


def _ownership(home: Path) -> dict[str, list[str]]:
    path = home / ".config" / "dots" / "mcp-projection.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def _save_ownership(home: Path, data: dict[str, list[str]]) -> None:
    path = home / ".config" / "dots" / "mcp-projection.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def _server_payload(row: dict[str, Any]) -> dict[str, Any]:
    transport = str(row.get("transport") or "stdio")
    if transport == "streamable_http":
        return {"url": row.get("url"), "type": "streamable-http"}
    payload: dict[str, Any] = {"command": row.get("command") or row.get("id")}
    if row.get("args"):
        payload["args"] = list(row["args"])
    return payload


def _dig(data: dict[str, Any], key: str) -> tuple[dict[str, Any], str]:
    current = data
    parts = key.split(".")
    for part in parts[:-1]:
        nxt = current.get(part)
        if not isinstance(nxt, dict):
            nxt = {}
            current[part] = nxt
        current = nxt
    return current, parts[-1]


def project_client(
    client: str,
    servers: list[dict[str, Any]],
    *,
    home: Path,
    dry_run: bool = False,
) -> dict[str, Any]:
    spec = CLIENTS.get(client)
    if spec is None:
        return {"client": client, "ok": False, "error": "unknown client"}
    supported = []
    unsupported = []
    for row in servers:
        allowed = [str(c) for c in (row.get("allowed_clients") or [])]
        if allowed and client not in allowed:
            unsupported.append(str(row.get("id")))
        else:
            supported.append(row)
    path = home / str(spec["config"])
    result: dict[str, Any] = {
        "client": client,
        "ok": True,
        "config": str(path),
        "added": [str(r.get("id")) for r in supported],
        "unsupported": unsupported,
        "backup": None,
        "manual": False,
        "changed": False,
    }
    if dry_run:
        return result
    mode = spec["mcp_mode"]
    if mode == "json":
        return {**result, **_merge_json(client, path, str(spec["key"]), supported, home)}
    if mode == "toml-region":
        return {**result, **_merge_toml(path, supported)}
    return {**result, **_merge_yaml(path, supported)}


def _merge_json(client: str, path: Path, key: str, servers: list[dict[str, Any]], home: Path) -> dict[str, Any]:
    existing: dict[str, Any] = {}
    if path.exists():
        text = path.read_text(encoding="utf-8")
        if "/*" in text or text.strip().startswith("//"):
            return {"ok": False, "manual": True, "error": "manual integration required: comments present"}
        try:
            existing = json.loads(text or "{}")
        except json.JSONDecodeError:
            return {"ok": False, "manual": True, "error": "manual integration required: invalid JSON"}
    if not isinstance(existing, dict):
        return {"ok": False, "manual": True, "error": "manual integration required: JSON root is not an object"}
    parent, leaf = _dig(existing, key)
    table = parent.get(leaf)
    if table is None:
        table = {}
    if not isinstance(table, dict):
        return {"ok": False, "manual": True, "error": "manual integration required: MCP table is not an object"}
    owned = set(_ownership(home).get(client) or [])
    desired_ids = []
    for row in servers:
        ident = str(row["id"])
        desired_ids.append(ident)
        table[ident] = _server_payload(row)
        owned.add(ident)
    for ident in list(table):
        if ident in owned and ident not in desired_ids:
            table.pop(ident, None)
            owned.discard(ident)
    parent[leaf] = table
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(existing, indent=2) + "\n"
    changed = not path.exists() or path.read_text(encoding="utf-8") != encoded
    backup = _backup(path) if changed and path.exists() else None
    if changed:
        path.write_text(encoded, encoding="utf-8")
    data = _ownership(home)
    data[client] = sorted(owned)
    _save_ownership(home, data)
    return {"ok": True, "backup": backup, "changed": changed, "manual": False}


def _merge_toml(path: Path, servers: list[dict[str, Any]]) -> dict[str, Any]:
    original = path.read_text(encoding="utf-8") if path.exists() else ""
    if BEGIN in original and END not in original:
        return {"ok": False, "manual": True, "error": "manual integration required: broken DOTS region"}
    block = [BEGIN]
    for row in servers:
        ident = str(row["id"])
        payload = _server_payload(row)
        block.append(f"[mcp_servers.{ident}]")
        if payload.get("url"):
            block.append(f'url = "{payload["url"]}"')
        else:
            block.append(f'command = "{payload["command"]}"')
        if payload.get("args"):
            rendered = ", ".join(f'"{a}"' for a in payload["args"])
            block.append(f"args = [{rendered}]")
    block.append(END)
    region = "\n".join(block) + "\n"
    if BEGIN in original:
        pre, rest = original.split(BEGIN, 1)
        _, post = rest.split(END, 1)
        updated = pre.rstrip() + "\n\n" + region + post.lstrip("\n")
    else:
        updated = (original.rstrip() + "\n\n" if original.strip() else "") + region
    path.parent.mkdir(parents=True, exist_ok=True)
    changed = original != updated
    backup = _backup(path) if changed and path.exists() else None
    if changed:
        path.write_text(updated, encoding="utf-8")
    return {"ok": True, "backup": backup, "changed": changed, "manual": False}


def _merge_yaml(path: Path, servers: list[dict[str, Any]]) -> dict[str, Any]:
    original = path.read_text(encoding="utf-8") if path.exists() else ""
    if original.strip() and "mcp_servers:" in original and BEGIN not in original:
        return {
            "ok": False,
            "manual": True,
            "changed": False,
            "error": "manual integration required: Hermes config already has mcp_servers",
        }
    lines = ["mcp_servers:"]
    for row in servers:
        ident = str(row["id"])
        payload = _server_payload(row)
        lines.append(f"  {ident}:")
        if payload.get("url"):
            lines.append(f"    url: {payload['url']}")
        else:
            lines.append(f"    command: {payload['command']}")
        lines.append("    enabled: true")
    region = BEGIN + "\n" + "\n".join(lines) + "\n" + END + "\n"
    if BEGIN in original and END in original:
        pre, rest = original.split(BEGIN, 1)
        _, post = rest.split(END, 1)
        updated = pre + region + post.lstrip("\n")
    elif not original.strip():
        updated = region
    else:
        updated = original.rstrip() + "\n\n" + region
    path.parent.mkdir(parents=True, exist_ok=True)
    changed = original != updated
    backup = _backup(path) if changed and path.exists() else None
    if changed:
        path.write_text(updated, encoding="utf-8")
    return {"ok": True, "backup": backup, "changed": changed, "manual": False}


def sync_clients(
    servers: list[dict[str, Any]],
    *,
    clients: list[str] | None = None,
    home: Path | None = None,
    dry_run: bool = False,
) -> dict[str, Any]:
    home = home or Path.home()
    names = clients or list(CLIENTS)
    # Validate every JSON target before the first mutation when not a dry run.
    if not dry_run:
        for name in names:
            spec = CLIENTS[name]
            if spec["mcp_mode"] != "json":
                continue
            path = home / str(spec["config"])
            if not path.exists():
                continue
            text = path.read_text(encoding="utf-8")
            try:
                json.loads(text or "{}")
            except json.JSONDecodeError:
                return {
                    "ok": False,
                    "results": [{"client": name, "ok": False, "error": "invalid target config; no clients were modified"}],
                }
    results = [project_client(name, servers, home=home, dry_run=dry_run) for name in names]
    return {"ok": all(row.get("ok") for row in results), "results": results}
