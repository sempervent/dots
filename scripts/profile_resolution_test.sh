#!/usr/bin/env bash
# Profile resolution tests — no installs, no provider mutation.
set -euo pipefail

DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${DOTS_DIR}"
# shellcheck source=../helpers/components.sh
source "${DOTS_DIR}/helpers/components.sh"
# shellcheck source=../helpers/profiles.sh
source "${DOTS_DIR}/helpers/profiles.sh"

pass=0
fail=0

ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

resolve_named() {
  PROFILE_NAME=""
  PROFILE_DESC=""
  PROFILE_WITH=()
  PROFILE_OPEN_APPS=()
  CLI_WITH=()
  CLI_WITHOUT=()
  EFFECTIVE_WITH=()
  local file
  file="$(dots_resolve_profile_path "$1")"
  dots_load_profile_file "${file}" >/dev/null
  shift || true
  # remaining: optional --with / --without simulated via globals set by caller
  dots_compute_effective_with
}

echo "=== profile resolution tests ==="

# BASE
resolve_named base
if [[ ${#EFFECTIVE_WITH[@]} -eq 0 ]]; then ok "base → []"; else bad "base expected [] got ${EFFECTIVE_WITH[*]}"; fi

# WORK
resolve_named work
if [[ ${#EFFECTIVE_WITH[@]} -eq 0 ]]; then ok "work → []"; else bad "work expected [] got ${EFFECTIVE_WITH[*]}"; fi

# HOME exact list
resolve_named home
home_got="${EFFECTIVE_WITH[*]}"
home_want="hermes herdr ollama skills ai-skills drawthings opencode codex cursor images tex"
if [[ "${home_got}" == "${home_want}" ]]; then ok "home exact list"; else bad "home want='${home_want}' got='${home_got}'"; fi

# ALL from registry (no archify, no dupes)
resolve_named all
all_count=${#EFFECTIVE_WITH[@]}
reg_count="$(dots_component_ids_for_all | wc -l | tr -d ' ')"
if [[ "${all_count}" -eq "${reg_count}" ]]; then ok "all count=${all_count} matches registry"; else bad "all count ${all_count} != registry ${reg_count}"; fi
if dots_array_contains archify "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
  bad "all should omit archify"
else
  ok "all omits archify"
fi
# uniqueness
uniq="$(printf '%s\n' "${EFFECTIVE_WITH[@]}" | sort -u | wc -l | tr -d ' ')"
if [[ "${uniq}" -eq "${all_count}" ]]; then ok "all has no duplicates"; else bad "all has duplicates"; fi
if ! dots_array_contains cursor "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
  bad "all should include cursor"
else
  ok "all includes cursor"
fi

# CUSTOM TOML
tmp="$(mktemp /tmp/dots-profile-XXXXXX.toml)"
cat >"${tmp}" <<'EOF'
[profile]
name = "studio"
description = "test custom"
with = ["hermes", "ollama", "images"]
open_apps = ["iTerm"]
EOF
resolve_named "${tmp}"
if [[ "${EFFECTIVE_WITH[*]}" == "hermes ollama images" ]]; then ok "custom TOML"; else bad "custom got ${EFFECTIVE_WITH[*]}"; fi

# ADDITIONS
PROFILE_NAME=""; PROFILE_DESC=""; PROFILE_WITH=(); PROFILE_OPEN_APPS=()
CLI_WITH=(tex); CLI_WITHOUT=(); EFFECTIVE_WITH=()
file="$(dots_resolve_profile_path home)"
dots_load_profile_file "${file}" >/dev/null
# tex already in home — add herdr already there; add archify
CLI_WITH=(archify)
dots_compute_effective_with
if dots_array_contains archify "${EFFECTIVE_WITH[@]}"; then ok "home + --with archify"; else bad "missing archify addition"; fi

# REMOVALS / PRECEDENCE
CLI_WITH=(); CLI_WITHOUT=(cursor)
file="$(dots_resolve_profile_path home)"
PROFILE_WITH=(); PROFILE_OPEN_APPS=(); PROFILE_NAME=""; PROFILE_DESC=""
dots_load_profile_file "${file}" >/dev/null
dots_compute_effective_with
if dots_array_contains cursor "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
  bad "home --without cursor should remove cursor"
else
  ok "home --without cursor"
fi
if dots_array_contains codex "${EFFECTIVE_WITH[@]}"; then ok "codex remains after removing cursor"; else bad "codex missing unexpectedly"; fi

# UNKNOWN component
if dots_validate_components "not-a-real-component" 2>/dev/null; then
  bad "unknown component should fail"
else
  ok "unknown component rejected"
fi

# MALFORMED TOML
badtoml="$(mktemp /tmp/dots-bad-XXXXXX.toml)"
echo 'this is not = valid toml [[' >"${badtoml}"
if dots_profile_parse "${badtoml}" >/dev/null 2>&1; then
  bad "malformed TOML should fail"
else
  ok "malformed TOML rejected"
fi

# bootstrap --show smoke
if "${DOTS_DIR}/bootstrap.sh" --profile work --show 2>/dev/null | rg -q 'components:'; then
  ok "bootstrap --show work"
else
  bad "bootstrap --show work"
fi

rm -f "${tmp}" "${badtoml}"

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ "${fail}" -eq 0 ]]
