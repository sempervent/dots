#!/usr/bin/env bash
# Provider-isolation dry-run matrix — no live credential mutation.
set -euo pipefail

DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="${DOTS_DIR}/setup.sh"
BOOT="${DOTS_DIR}/bootstrap.sh"

pass=0
fail=0

run_capture() {
  # shellcheck disable=SC2086
  eval "$@" 2>&1
}

must() {
  local name="$1" out="$2" pat="$3"
  if printf '%s\n' "${out}" | rg -q -- "${pat}"; then
    return 0
  fi
  echo "FAIL: ${name}: missing /${pat}/" >&2
  return 1
}

must_not() {
  local name="$1" out="$2" pat="$3"
  if printf '%s\n' "${out}" | rg -q -- "${pat}"; then
    echo "FAIL: ${name}: forbidden /${pat}/" >&2
    return 1
  fi
  return 0
}

check_case() {
  local name="$1"
  shift
  local out rc=0
  out="$(run_capture "$@")" || {
    echo "FAIL: ${name}: command failed" >&2
    printf '%s\n' "${out}" | head -40 >&2
    fail=$((fail + 1))
    return
  }
  # Remaining args after -- are must / must_not specs processed by caller via globals
  LAST_OUT="${out}"
  LAST_NAME="${name}"
}

finish_case() {
  local ok=1
  if [[ "${ok}" -eq 1 ]]; then
    echo "OK: ${LAST_NAME}"
    pass=$((pass + 1))
  fi
}

echo "=== provider isolation tests (dry-run) ==="

# A
out="$(run_capture "\"${SETUP}\" --dry-run --with herdr")" || true
ok=1
must "A" "${out}" "no AI-client integrations" || ok=0
must_not "A" "${out}" 'herdr integration install hermes' || ok=0
must_not "A" "${out}" 'herdr integration install cursor' || ok=0
must_not "A" "${out}" 'herdr integration install opencode' || ok=0
must_not "A" "${out}" 'herdr integration install codex' || ok=0
must_not "A" "${out}" 'Cursor Agent CLI' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: A herdr alone"; pass=$((pass+1)); } || fail=$((fail+1))

# B
out="$(run_capture "\"${SETUP}\" --dry-run --with herdr,hermes")"
ok=1
must "B" "${out}" 'herdr integration install hermes' || ok=0
must_not "B" "${out}" 'herdr integration install cursor' || ok=0
must_not "B" "${out}" 'herdr integration install opencode' || ok=0
must_not "B" "${out}" 'herdr integration install codex' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: B herdr,hermes"; pass=$((pass+1)); } || fail=$((fail+1))

# C
out="$(run_capture "\"${SETUP}\" --dry-run --with herdr,cursor")"
ok=1
must "C" "${out}" 'herdr integration install cursor' || ok=0
must "C" "${out}" 'Cursor Agent CLI' || ok=0
must_not "C" "${out}" 'herdr integration install hermes' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: C herdr,cursor"; pass=$((pass+1)); } || fail=$((fail+1))

# D
out="$(run_capture "\"${SETUP}\" --dry-run --with drawthings")"
ok=1
must "D" "${out}" 'skip Hermes MCP for drawthings' || ok=0
must "D" "${out}" 'skip Cursor MCP for drawthings' || ok=0
must_not "D" "${out}" 'register Hermes MCP .drawthings' || ok=0
must_not "D" "${out}" 'merge Cursor MCP' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: D drawthings alone"; pass=$((pass+1)); } || fail=$((fail+1))

# E
out="$(run_capture "\"${SETUP}\" --dry-run --with hermes,drawthings")"
ok=1
must "E" "${out}" 'register Hermes MCP .drawthings' || ok=0
must_not "E" "${out}" 'skip Hermes MCP for drawthings' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: E hermes,drawthings"; pass=$((pass+1)); } || fail=$((fail+1))

# F
out="$(run_capture "\"${SETUP}\" --dry-run --with cursor,drawthings")"
ok=1
must "F" "${out}" 'Cursor Agent CLI' || ok=0
must "F" "${out}" 'merge Cursor MCP' || ok=0
must_not "F" "${out}" 'register Hermes MCP .drawthings' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: F cursor,drawthings"; pass=$((pass+1)); } || fail=$((fail+1))

# G — Cursor may exist on PATH; still no Cursor config
out="$(run_capture "\"${SETUP}\" --dry-run --with hermes,ollama")"
ok=1
must_not "G" "${out}" 'Cursor Agent CLI' || ok=0
must_not "G" "${out}" 'merge Cursor' || ok=0
must_not "G" "${out}" '~/.cursor' || ok=0
must_not "G" "${out}" 'herdr integration install cursor' || ok=0
must_not "G" "${out}" 'Brewfile.cursor' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: G no cursor consent"; pass=$((pass+1)); } || fail=$((fail+1))

# Profiles
out="$(run_capture "\"${BOOT}\" --profile base --dry-run")"
ok=1
must "base" "${out}" 'no optional components' || ok=0
must "base" "${out}" 'none — base/core only' || ok=0
must_not "base" "${out}" 'Cursor Agent CLI' || ok=0
must_not "base" "${out}" 'Brewfile.hermes' || ok=0
must_not "base" "${out}" 'Brewfile.cursor' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: base profile"; pass=$((pass+1)); } || fail=$((fail+1))

out="$(run_capture "\"${BOOT}\" --profile work --dry-run")"
ok=1
must_not "work" "${out}" 'Cursor Agent CLI' || ok=0
must_not "work" "${out}" 'Brewfile.cursor' || ok=0
must "work" "${out}" 'none — base/core only' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: work profile"; pass=$((pass+1)); } || fail=$((fail+1))

out="$(run_capture "\"${BOOT}\" --profile home --dry-run")"
ok=1
must "home" "${out}" 'cursor' || ok=0
must "home" "${out}" 'ai-skills' || ok=0
must "home" "${out}" 'Cursor Agent CLI' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: home profile"; pass=$((pass+1)); } || fail=$((fail+1))

out="$(run_capture "\"${SETUP}\" --dry-run --with cursor")"
ok=1
must "cursor" "${out}" 'Cursor Agent CLI' || ok=0
must "cursor" "${out}" 'Brewfile.cursor' || ok=0
must_not "cursor" "${out}" 'register Hermes MCP' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: cursor only"; pass=$((pass+1)); } || fail=$((fail+1))

out="$(run_capture "\"${SETUP}\" --dry-run --with cursor,herdr")"
ok=1
must "ch" "${out}" 'herdr integration install cursor' || ok=0
must_not "ch" "${out}" 'herdr integration install hermes' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: cursor+herdr"; pass=$((pass+1)); } || fail=$((fail+1))

# --- ai-skills isolation ---
# Skill manifests need tomllib; on hosts without Python ≥3.11, dry-run must
# announce managed provisioning rather than fail or ask for manual install.
if ! python3 -c 'import tomllib' 2>/dev/null && ! command -v python3.12 >/dev/null 2>&1 && ! command -v python3.11 >/dev/null 2>&1; then
  echo "NOTE: no Python ≥3.11 on PATH — expecting dry-run provisioning message"
  out="$(run_capture "\"${SETUP}\" --dry-run --with ai-skills" || true)"
  ok=1
  must "ai-prov" "${out}" 'Skill packs: ai-skills' || ok=0
  must "ai-prov" "${out}" 'Would provision Python >=3.11 for:' || ok=0
  must_not "ai-prov" "${out}" 'Brewfile.cursor' || ok=0
  [[ "${ok}" -eq 1 ]] && { echo "OK: ai-skills alone (provision announce)"; pass=$((pass+1)); } || fail=$((fail+1))
  out="$(run_capture "\"${SETUP}\" --dry-run --with hermes,skills,ai-skills" || true)"
  ok=1
  must "hs-prov" "${out}" 'Hermes skill exposure: enabled' || ok=0
  must "hs-prov" "${out}" 'Would provision Python >=3.11 for:' || ok=0
  must_not "hs-prov" "${out}" 'Brewfile.cursor' || ok=0
  [[ "${ok}" -eq 1 ]] && { echo "OK: hermes+skills+ai-skills (provision announce)"; pass=$((pass+1)); } || fail=$((fail+1))
  out="$(run_capture "\"${SETUP}\" --dry-run --with cursor,ai-skills" || true)"
  ok=1
  must "ca-prov" "${out}" 'Cursor Agent CLI' || ok=0
  must "ca-prov" "${out}" 'Would provision Python >=3.11 for:' || ok=0
  must_not "ca-prov" "${out}" 'Brewfile.hermes' || ok=0
  [[ "${ok}" -eq 1 ]] && { echo "OK: cursor+ai-skills (provision announce)"; pass=$((pass+1)); } || fail=$((fail+1))
  out="$(run_capture "\"${BOOT}\" --profile home --dry-run" || true)"
  ok=1
  must "home-prov" "${out}" 'Would provision Python >=3.11 for:' || ok=0
  must_not "home-prov" "${out}" 'Install python3.11+ or omit' || ok=0
  [[ "${ok}" -eq 1 ]] && { echo "OK: home dry-run announces Python provisioning"; pass=$((pass+1)); } || fail=$((fail+1))
  out="$(run_capture "\"${BOOT}\" --profile work --dry-run" || true)"
  ok=1
  must_not "work-noprov" "${out}" 'Would provision Python >=3.11' || ok=0
  [[ "${ok}" -eq 1 ]] && { echo "OK: work dry-run does not provision Python 3.11"; pass=$((pass+1)); } || fail=$((fail+1))
  out="$(run_capture "\"${BOOT}\" --profile server --dry-run" || true)"
  ok=1
  must_not "server-noprov" "${out}" 'Would provision Python >=3.11' || ok=0
  [[ "${ok}" -eq 1 ]] && { echo "OK: server dry-run does not provision Python 3.11"; pass=$((pass+1)); } || fail=$((fail+1))
else
out="$(run_capture "\"${SETUP}\" --dry-run --with ai-skills")"
ok=1
must "ai" "${out}" 'Skill packs: ai-skills' || ok=0
must "ai" "${out}" 'agent-evals-and-observability' || ok=0
must "ai" "${out}" 'Hermes skill exposure: disabled' || ok=0
must_not "ai" "${out}" 'Cursor Agent CLI' || ok=0
must_not "ai" "${out}" 'Brewfile.cursor' || ok=0
must_not "ai" "${out}" 'Brewfile.hermes' || ok=0
must_not "ai" "${out}" 'register Hermes MCP' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: ai-skills alone"; pass=$((pass+1)); } || fail=$((fail+1))

out="$(run_capture "\"${SETUP}\" --dry-run --with skills,ai-skills")"
ok=1
must "union" "${out}" 'Skill packs: skills ai-skills' || ok=0
must "union" "${out}" 'Planned unique skills' || ok=0
must "union" "${out}" 'systematic-debugging' || ok=0
must "union" "${out}" 'litellm' || ok=0
must "union" "${out}" 'Hermes skill exposure: disabled' || ok=0
# security-review install header once
sec_count="$(printf '%s\n' "${out}" | rg -c 'Skill: skill-security-review' || true)"
[[ -z "${sec_count}" ]] && sec_count=0
if [[ "${sec_count}" -le 1 ]]; then
  :
else
  echo "FAIL: union: skill-security-review install section repeated (${sec_count})" >&2
  ok=0
fi
[[ "${ok}" -eq 1 ]] && { echo "OK: skills+ai-skills union"; pass=$((pass+1)); } || fail=$((fail+1))

out="$(run_capture "\"${SETUP}\" --dry-run --with hermes,skills,ai-skills")"
ok=1
must "hs" "${out}" 'Skill packs: skills ai-skills' || ok=0
must "hs" "${out}" 'Hermes skill exposure: enabled' || ok=0
must_not "hs" "${out}" 'Cursor Agent CLI' || ok=0
must_not "hs" "${out}" 'Brewfile.cursor' || ok=0
must_not "hs" "${out}" 'Brewfile.opencode' || ok=0
must_not "hs" "${out}" 'Brewfile.codex' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: hermes+skills+ai-skills"; pass=$((pass+1)); } || fail=$((fail+1))

out="$(run_capture "\"${SETUP}\" --dry-run --with cursor,ai-skills")"
ok=1
must "ca" "${out}" 'Cursor Agent CLI' || ok=0
must "ca" "${out}" 'Skill packs: ai-skills' || ok=0
must "ca" "${out}" 'Hermes skill exposure: disabled' || ok=0
must_not "ca" "${out}" 'Brewfile.hermes' || ok=0
must_not "ca" "${out}" 'register Hermes MCP' || ok=0
[[ "${ok}" -eq 1 ]] && { echo "OK: cursor+ai-skills"; pass=$((pass+1)); } || fail=$((fail+1))
fi

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ "${fail}" -eq 0 ]]
