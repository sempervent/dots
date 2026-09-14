#!/usr/bin/env bash
# Lightweight router policy tests — no model/API calls.
set -euo pipefail

DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTE="${DOTS_DIR}/skills/agent-router/route.py"

if [[ ! -f "${ROUTE}" ]]; then
  echo "Error: missing ${ROUTE}" >&2
  exit 1
fi

pass=0
fail=0

expect() {
  local prompt="$1" want="$2"
  local got
  got="$(python3 "${ROUTE}" --json "${prompt}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["destination"])')"
  if [[ "${got}" == "${want}" ]]; then
    echo "OK: [${want}] ${prompt}"
    pass=$((pass + 1))
  else
    echo "FAIL: want=${want} got=${got} :: ${prompt}" >&2
    fail=$((fail + 1))
  fi
}

echo "=== router policy tests ==="
expect "summarize this text" "local"
expect "inspect this repository for failing tests" "opencode"
expect "perform a difficult multi-package refactor" "codex"
expect "analyze the architecture of this repository" "archify"
expect "generate an image of a lunar synthesizer" "drawthings"
expect "resize foo.png to 512x512" "images"
expect "use Codex to inspect this" "codex"
expect "keep this local and inspect this repo" "opencode"

# Degradation: Codex missing → OpenCode
got="$(python3 "${ROUTE}" --json --available hermes_direct,local,opencode,archify,drawthings,images \
  "perform a difficult multi-package refactor" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["destination"], d.get("degraded"))')"
if [[ "${got}" == "opencode True" ]]; then
  echo "OK: [degrade codex→opencode] difficult refactor without Codex"
  pass=$((pass + 1))
else
  echo "FAIL: degrade expected 'opencode True' got '${got}'" >&2
  fail=$((fail + 1))
fi

echo "Passed: ${pass}  Failed: ${fail}"
[[ "${fail}" -eq 0 ]]
