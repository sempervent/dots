#!/usr/bin/env python3
"""DOTS OpenCode MCP bridge — thin stdio tools over the execution adapter.

Tools: status, list_models, list_agents, run.
Does not expose arbitrary shell execution.
"""

from __future__ import annotations

import json

from mcp.server.fastmcp import FastMCP

from adapter import (
    list_agents as adapter_list_agents,
    list_models as adapter_list_models,
    run_opencode,
    status_info,
)

mcp = FastMCP("opencode")


@mcp.tool()
def status() -> str:
    """OpenCode adapter status (binary, defaults, mutation policy)."""
    return json.dumps(status_info(), indent=2)


@mcp.tool()
def list_models() -> str:
    """List models known to the OpenCode CLI."""
    return json.dumps(adapter_list_models(), indent=2)


@mcp.tool()
def list_agents() -> str:
    """List agents known to the OpenCode CLI."""
    return json.dumps(adapter_list_agents(), indent=2)


@mcp.tool()
def run(
    prompt: str,
    cwd: str,
    model: str | None = None,
    agent: str | None = None,
    auto_approve: bool | None = None,
    timeout_seconds: int | None = None,
) -> str:
    """Run an OpenCode coding task.

    Requires an existing working directory (cwd). Default agent/model come from
    DOTS execution.toml. Implementation agents may modify files in cwd.
    """
    try:
        result = run_opencode(
            prompt=prompt,
            cwd=cwd,
            model=model,
            agent=agent,
            timeout_seconds=timeout_seconds,
            auto_approve=auto_approve,
        )
    except (ValueError, RuntimeError) as exc:
        return json.dumps({"success": False, "error": str(exc)}, indent=2)
    payload = result.to_dict()
    events = payload.get("raw_events") or []
    if isinstance(events, list) and len(events) > 50:
        payload["raw_events"] = events[-50:]
        payload["raw_events_truncated"] = True
    return json.dumps(payload, indent=2)


if __name__ == "__main__":
    mcp.run(transport="stdio")
