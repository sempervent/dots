#!/usr/bin/env python3
"""DOTS Codex MCP bridge — stdio tools over ``codex exec``.

Replaces the removed ``codex mcp-server`` subcommand for Hermes MCP clients.
Tools mirror the old surface names: ``codex``, ``codex-reply``, plus ``status``.
"""

from __future__ import annotations

import json

from mcp.server.fastmcp import FastMCP

from adapter import reply_codex, run_codex, status_info

mcp = FastMCP("codex")


@mcp.tool()
def status() -> str:
    """Codex CLI / DOTS bridge status (no secrets)."""
    return json.dumps(status_info(), indent=2)


@mcp.tool(name="codex")
def codex(
    prompt: str,
    cwd: str,
    model: str | None = None,
    sandbox: str = "workspace-write",
    timeout_seconds: int | None = None,
    skip_git_repo_check: bool = False,
) -> str:
    """Run a Codex coding session via ``codex exec`` (requires existing cwd)."""
    try:
        result = run_codex(
            prompt=prompt,
            cwd=cwd,
            model=model,
            sandbox=sandbox,
            timeout_seconds=timeout_seconds,
            skip_git_repo_check=skip_git_repo_check,
        )
    except (ValueError, RuntimeError) as exc:
        return json.dumps({"success": False, "error": str(exc)}, indent=2)
    return json.dumps(result.to_dict(), indent=2)


@mcp.tool(name="codex-reply")
def codex_reply(
    prompt: str,
    thread_id: str,
    cwd: str,
    timeout_seconds: int | None = None,
) -> str:
    """Continue a Codex thread via ``codex exec resume``."""
    try:
        result = reply_codex(
            prompt=prompt,
            thread_id=thread_id,
            cwd=cwd,
            timeout_seconds=timeout_seconds,
        )
    except (ValueError, RuntimeError) as exc:
        return json.dumps({"success": False, "error": str(exc)}, indent=2)
    return json.dumps(result.to_dict(), indent=2)


if __name__ == "__main__":
    mcp.run(transport="stdio")
