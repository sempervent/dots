"""MCP trust allowlist tests."""

from __future__ import annotations

import json

from dots_agent.mcp_trust import load_mcp_trust, safe_server_ids, write_safe_mcp_json


def test_safe_servers_default():
    ids = safe_server_ids()
    assert ids == ["dots-model-scout", "dots-expert"]


def test_trust_metadata_no_filesystem():
    rows = {r["id"]: r for r in load_mcp_trust()}
    assert rows["dots-model-scout"]["filesystem"] is False
    assert rows["dots-expert"]["filesystem"] is False
    assert rows["dots-model-scout"]["shell"] is False
    assert rows["dots-expert"]["shell"] is False


def test_write_safe_mcp_json(tmp_path):
    path = write_safe_mcp_json(
        tmp_path / "mcp.json",
        scout_command="/bin/scout",
        expert_command="/bin/expert",
        scout_env={"OPENROUTER_API_KEY": "x"},
        expert_env={"LITELLM_MASTER_KEY": "y"},
    )
    data = json.loads(path.read_text())
    assert set(data["mcpServers"]) == {"dots-model-scout", "dots-expert"}
    assert data["mcpServers"]["dots-model-scout"]["env"]["OPENROUTER_API_KEY"] == "x"
    assert "OPENROUTER_API_KEY" not in data["mcpServers"]["dots-expert"]["env"]
