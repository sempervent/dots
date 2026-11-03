"""Trusted MCP allowlist for safe DOTS agent runs."""

from __future__ import annotations

import json
import tomllib
from pathlib import Path
from typing import Any

from dots_agent.config import AgentConfig, dots_root, load_config


def load_mcp_trust(root: Path | None = None) -> list[dict[str, Any]]:
    root = root or dots_root()
    path = root / "configs" / "agents" / "mcp-trust.toml"
    if not path.is_file():
        return []
    with path.open("rb") as fh:
        data = tomllib.load(fh)
    rows = data.get("mcp_servers") or []
    return [r for r in rows if isinstance(r, dict)]


def safe_server_ids(cfg: AgentConfig | None = None) -> list[str]:
    cfg = cfg or load_config()
    raw = cfg.raw.get("mcp", {}).get("safe_servers")
    if isinstance(raw, list) and raw:
        return [str(x) for x in raw]
    return ["dots-model-scout", "dots-expert"]


def trust_row(server_id: str) -> dict[str, Any] | None:
    for row in load_mcp_trust():
        if row.get("id") == server_id:
            return row
    return None


def write_safe_mcp_json(
    dest: Path,
    *,
    scout_command: str,
    expert_command: str,
    scout_env: dict[str, str] | None = None,
    expert_env: dict[str, str] | None = None,
) -> Path:
    """Write a run-local mcp.json containing only the safe allowlist."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "mcpServers": {
            "dots-model-scout": {
                "command": scout_command,
                "args": [],
                "env": scout_env or {},
            },
            "dots-expert": {
                "command": expert_command,
                "args": [],
                "env": expert_env or {},
            },
        }
    }
    dest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    dest.chmod(0o600)
    return dest


def inspector_cli_cmd(server_command: str) -> list[str]:
    """Official MCP Inspector CLI invocation (no browser)."""
    return [
        "npx",
        "-y",
        "@modelcontextprotocol/inspector",
        "--cli",
        server_command,
        "--method",
        "tools/list",
    ]
