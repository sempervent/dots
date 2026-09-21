#!/usr/bin/env bash
# Profile resolution tests — no installs, no provider mutation.
set -euo pipefail

DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${DOTS_DIR}"
# shellcheck source=../helpers/toml.sh
source "${DOTS_DIR}/helpers/toml.sh"
# shellcheck source=../helpers/components.sh
source "${DOTS_DIR}/helpers/components.sh"
# shellcheck source=../helpers/profiles.sh
source "${DOTS_DIR}/helpers/profiles.sh"
# shellcheck source=../helpers/packages.sh
source "${DOTS_DIR}/helpers/packages.sh"

pass=0
fail=0

ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

resolve_named() {
  PROFILE_NAME=""
  PROFILE_DESC=""
  PROFILE_WITH=()
  PROFILE_OPEN_APPS=()
  PROFILE_PACKAGES=()
  PROFILE_RUNTIME_MULTIPLEXER=""
  PROFILE_RUNTIME_GREETING=""
  PROFILE_RUNTIME_PROMPT_STATS=""
  PROFILE_RUNTIME_AUTO_TMUX=""
  CLI_WITH=()
  CLI_WITHOUT=()
  EFFECTIVE_WITH=()
  local file
  file="$(dots_resolve_profile_path "$1")"
  dots_load_profile_file "${file}" >/dev/null
  shift || true
  dots_compute_effective_with
}

echo "=== profile resolution tests ==="

# BASE
resolve_named base
if [[ ${#EFFECTIVE_WITH[@]} -eq 0 ]]; then ok "base → []"; else bad "base expected [] got ${EFFECTIVE_WITH[*]}"; fi

# WORK
resolve_named work
if [[ ${#EFFECTIVE_WITH[@]} -eq 0 ]]; then ok "work → []"; else bad "work expected [] got ${EFFECTIVE_WITH[*]}"; fi

# HOME set (order-independent; Darwin 15+ equivalence via ai − fluidvoice)
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
resolve_named home
home_got="$(printf '%s\n' "${EFFECTIVE_WITH[@]}" | sort | tr '\n' ' ')"
home_want="$(printf '%s\n' hermes herdr ollama llamacpp skills ai-skills drawthings opencode codex cursor images tex | sort | tr '\n' ' ')"
if [[ "${home_got}" == "${home_want}" ]]; then ok "home Darwin set"; else bad "home want='${home_want}' got='${home_got}'"; fi
unset DOTS_FORCE_OS DOTS_FORCE_DARWIN_MAJOR || true

# ALL from registry (platform-filtered; no archify, no dupes)
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
resolve_named all
all_count=${#EFFECTIVE_WITH[@]}
# Count supported registry members for this forced platform
reg_count=0
while IFS= read -r _cid; do
  dots_component_supported_here "${_cid}" && reg_count=$((reg_count + 1))
done < <(dots_component_ids_for_all)
if [[ "${all_count}" -eq "${reg_count}" ]]; then ok "all count=${all_count} matches platform registry"; else bad "all count ${all_count} != registry ${reg_count}"; fi
if dots_array_contains archify "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
  bad "all should omit archify"
else
  ok "all omits archify"
fi
# uniqueness
uniq="$(printf '%s\n' "${EFFECTIVE_WITH[@]}" | sort -u | wc -l | tr -d ' ')"
if [[ "${uniq}" -eq "${all_count}" ]]; then ok "all has no duplicates"; else bad "all has duplicates"; fi
if ! dots_array_contains cursor "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
  bad "all should include cursor on Darwin"
else
  ok "all includes cursor"
fi
if ! dots_array_contains fluidvoice "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
  bad "all should include fluidvoice on Darwin 15+"
else
  ok "all includes fluidvoice"
fi
unset DOTS_FORCE_OS DOTS_FORCE_DARWIN_MAJOR || true

# Linux all omits fluidvoice/cursor/codex
export DOTS_FORCE_OS=linux
resolve_named all
if dots_array_contains fluidvoice "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
  bad "linux all should omit fluidvoice"
else
  ok "linux all omits fluidvoice"
fi
if dots_array_contains cursor "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
  bad "linux all should omit cursor"
else
  ok "linux all omits cursor"
fi
unset DOTS_FORCE_OS || true

# Linux home: AI apps from group that are portable + extras (no cursor/codex)
export DOTS_FORCE_OS=linux
resolve_named home
if dots_array_contains cursor "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
  bad "linux home should omit cursor"
else
  ok "linux home omits cursor"
fi
if dots_array_contains herdr "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "linux home keeps herdr"; else bad "linux home lost herdr"; fi
if dots_array_contains hermes "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "linux home keeps hermes"; else bad "linux home lost hermes"; fi
unset DOTS_FORCE_OS || true

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
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
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
unset DOTS_FORCE_OS DOTS_FORCE_DARWIN_MAJOR || true

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

# SERVER — Herdr first-class; no AI providers; tmux automatic
resolve_named server
if [[ "${EFFECTIVE_WITH[*]}" == "herdr" ]]; then ok "server → [herdr]"; else bad "server expected [herdr] got ${EFFECTIVE_WITH[*]:-}"
fi
if [[ "${PROFILE_PACKAGES[*]}" == "core modern server" ]]; then ok "server packages"; else bad "server packages=${PROFILE_PACKAGES[*]}"; fi
if [[ "${PROFILE_RUNTIME_MULTIPLEXER}" == "tmux" ]]; then ok "server multiplexer=tmux"; else bad "server mux=${PROFILE_RUNTIME_MULTIPLEXER}"; fi

# HOME packages + runtime
resolve_named home
if dots_array_contains gui "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; then ok "home has gui group"; else bad "home missing gui"; fi
for g in dev network data geo security; do
  if dots_array_contains "${g}" "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; then
    ok "home has ${g} group"
  else
    bad "home missing ${g}"
  fi
done
if [[ "${PROFILE_RUNTIME_MULTIPLEXER}" == "herdr" ]]; then ok "home multiplexer=herdr"; else bad "home mux=${PROFILE_RUNTIME_MULTIPLEXER}"; fi

# WORK has no AI; has lean workstation tool groups (no geo/network)
resolve_named work
if [[ ${#EFFECTIVE_WITH[@]} -eq 0 ]]; then ok "work AI empty"; else bad "work leaked AI"; fi
for g in dev data security; do
  if dots_array_contains "${g}" "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; then
    ok "work has ${g} group"
  else
    bad "work missing ${g}"
  fi
done
if dots_array_contains geo "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; then
  bad "work should omit geo"
else
  ok "work omits geo"
fi
if dots_array_contains network "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; then
  bad "work should omit network"
else
  ok "work omits network"
fi

# BASE stays lean (no new workstation tool groups)
resolve_named base
if dots_array_contains dev "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; then
  bad "base should omit dev"
else
  ok "base omits new tool groups"
fi

# ALL includes new groups; SERVER stays lean
resolve_named all
for g in dev security network data geo; do
  if dots_array_contains "${g}" "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; then
    ok "all has ${g} group"
  else
    bad "all missing ${g}"
  fi
done
resolve_named server
if dots_array_contains security "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; then
  bad "server should omit security"
else
  ok "server omits workstation tool groups"
fi

# Unknown package group
if dots_validate_package_groups "not-a-group" 2>/dev/null; then
  bad "unknown package group should fail"
else
  ok "unknown package group rejected"
fi

# bootstrap --show smoke (avoid pipefail+rg -q SIGPIPE flakiness)
_show_work="$("${DOTS_DIR}/bootstrap.sh" --profile work --show 2>/dev/null || true)"
if echo "${_show_work}" | rg -q 'components:'; then
  ok "bootstrap --show work"
else
  bad "bootstrap --show work"
fi
_show_server="$("${DOTS_DIR}/bootstrap.sh" --profile server --show 2>/dev/null || true)"
if echo "${_show_server}" | rg -q 'package groups:'; then
  ok "bootstrap --show server"
else
  bad "bootstrap --show server"
fi

rm -f "${tmp}" "${badtoml}"

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ "${fail}" -eq 0 ]]
