#!/usr/bin/env bash
# Opt-in Codex MCP smoke: connection/tool discovery only (no cloud coding task).
set -euo pipefail

if ! command -v hermes >/dev/null 2>&1; then
  echo "Error: hermes required for Codex MCP smoke" >&2
  exit 1
fi

echo "=== hermes mcp list (codex) ==="
hermes mcp list 2>&1 | rg -i 'codex|Name|Transport' || hermes mcp list

echo "=== hermes mcp test codex ==="
hermes mcp test codex

# Report which backend is registered
if command -v codex >/dev/null 2>&1; then
  help_out="$(codex mcp-server -h 2>&1 || true)"
  if printf '%s\n' "${help_out}" | rg -qi 'unrecognized subcommand[[:space:]]+.mcp-server'; then
    echo "Note: using DOTS codex-mcp bridge (codex exec) — native mcp-server removed in Codex ≥0.154."
  elif printf '%s\n' "${help_out}" | rg -qi 'Start Codex as an MCP server|mcp server \(stdio\)'; then
    echo "Note: native codex mcp-server appears available on this Codex build."
  else
    echo "Note: Codex MCP mode inconclusive; Hermes registration is authoritative (see hermes mcp list)."
  fi
fi

echo "OK: Codex MCP smoke (connection/discovery) passed"
echo "Note: expensive Codex cloud coding tasks are intentionally not part of this smoke."
