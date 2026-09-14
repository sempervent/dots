#!/usr/bin/env bash
# Lightweight Draw Things MCP connectivity probe (no image generation).
# Exercises: initialize, tool discovery, status, list_models.
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v realpath >/dev/null 2>&1; then
  SCRIPT_PATH="$(realpath "${SCRIPT_PATH}")"
fi
DOTS_DIR="$(cd "$(dirname "${SCRIPT_PATH}")/.." && pwd)"
LAUNCHER="${DRAWTHINGS_MCP_LAUNCHER:-${HOME}/.local/bin/drawthings-mcp}"
export DOTS_DIR
export DOTS_DRAWTHINGS_CONFIG="${DOTS_DRAWTHINGS_CONFIG:-${HOME}/.config/drawthings-mcp/config.toml}"

if [[ ! -e "${LAUNCHER}" ]]; then
  LAUNCHER="${DOTS_DIR}/scripts/drawthings-mcp"
fi
if [[ ! -e "${LAUNCHER}" ]]; then
  echo "Error: drawthings-mcp launcher not found" >&2
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "Error: uv required for MCP probe" >&2
  exit 1
fi

uv run --directory "${DOTS_DIR}/tools/drawthings_mcp" --python-preference system python - "${LAUNCHER}" <<'PY'
import asyncio
import sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

launcher = sys.argv[1]
expected = {"status", "list_models", "generate", "img2img"}

async def main() -> None:
    params = StdioServerParameters(command=launcher, args=[], env=None)
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            names = {t.name for t in tools.tools}
            missing = expected - names
            if missing:
                raise SystemExit(f"missing tools: {sorted(missing)}; got {sorted(names)}")
            print("OK: tools", ", ".join(sorted(names)))

            status = await session.call_tool("status", {})
            text = status.content[0].text if status.content else ""
            print(text)
            if "cli:" not in text:
                raise SystemExit("status tool did not report cli")

            models = await session.call_tool("list_models", {"downloaded_only": True})
            mtext = models.content[0].text if models.content else ""
            print("--- list_models ---")
            print(mtext[:800] if mtext else "(empty)")
            # Empty inventory is a soft condition (no models); bridge still works.
            if "not found" in mtext.lower() and "draw-things-cli" in mtext.lower():
                raise SystemExit("list_models indicates CLI failure")

asyncio.run(main())
print("OK: Draw Things MCP probe passed (no generation)")
PY
