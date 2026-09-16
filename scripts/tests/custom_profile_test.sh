#!/usr/bin/env bash
# scripts/tests/custom_profile_test.sh — extends, merge, validation, dry-run
set -euo pipefail

DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${DOTS_DIR}"
# shellcheck source=../../helpers/toml.sh
source "${DOTS_DIR}/helpers/toml.sh"
# shellcheck source=../../helpers/components.sh
source "${DOTS_DIR}/helpers/components.sh"
# shellcheck source=../../helpers/profiles.sh
source "${DOTS_DIR}/helpers/profiles.sh"
# shellcheck source=../../helpers/packages.sh
source "${DOTS_DIR}/helpers/packages.sh"

pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

resolve_file() {
	PROFILE_NAME=""
	PROFILE_DESC=""
	PROFILE_EXTENDS=""
	PROFILE_CHAIN=()
	PROFILE_WITH=()
	PROFILE_WITHOUT=()
	PROFILE_OPEN_APPS=()
	PROFILE_PACKAGES=()
	PROFILE_RUNTIME_MULTIPLEXER=""
	PROFILE_RUNTIME_GREETING=""
	PROFILE_RUNTIME_PROMPT_STATS=""
	PROFILE_RUNTIME_AUTO_TMUX=""
	CLI_WITH=()
	CLI_WITHOUT=()
	EFFECTIVE_WITH=()
	dots_load_profile_file "$1" >/dev/null
	dots_compute_effective_with
}

echo "=== custom profile / inheritance ==="

# --- home-custom ---
HOME_CUSTOM="$TMP/home-custom.toml"
cat >"${HOME_CUSTOM}" <<'EOF'
[profile]
name = "home-custom"
extends = "home"
without = ["cursor"]

[runtime]
multiplexer = "tmux"
EOF

resolve_file "${HOME_CUSTOM}"
if [[ "${PROFILE_EXTENDS}" == "home" ]]; then ok "home-custom extends home"; else bad "extends=${PROFILE_EXTENDS}"; fi
if dots_array_contains herdr "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "home-custom retains herdr"; else bad "herdr missing"; fi
if dots_array_contains cursor "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then bad "cursor should be removed"; else ok "home-custom removes cursor"; fi
if [[ "${PROFILE_RUNTIME_MULTIPLEXER}" == "tmux" ]]; then ok "home-custom mux=tmux"; else bad "mux=${PROFILE_RUNTIME_MULTIPLEXER}"; fi
if dots_array_contains gui "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; then ok "home packages inherited"; else bad "packages=${PROFILE_PACKAGES[*]}"; fi

# --- work-custom ---
WORK_CUSTOM="$TMP/work-custom.toml"
cat >"${WORK_CUSTOM}" <<'EOF'
[profile]
name = "work-custom"
extends = "work"

[components]
with = ["images"]

[packages]
add = ["infra"]
EOF

resolve_file "${WORK_CUSTOM}"
if dots_array_contains images "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "work-custom adds images"; else bad "images missing"; fi
if dots_array_contains hermes "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then bad "work-custom must not add AI"; else ok "work-custom no AI providers"; fi
if dots_array_contains infra "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; then ok "work-custom adds infra"; else bad "pkgs=${PROFILE_PACKAGES[*]}"; fi
if [[ "${PROFILE_RUNTIME_MULTIPLEXER}" == "tmux" ]]; then ok "work-custom inherits tmux"; else bad "mux=${PROFILE_RUNTIME_MULTIPLEXER}"; fi

# --- server-custom / bertha ---
BERTHA="$TMP/bertha.toml"
cat >"${BERTHA}" <<'EOF'
[profile]
name = "bertha"
extends = "server"

[runtime]
multiplexer = "tmux"

[packages]
add = ["infra"]
EOF

resolve_file "${BERTHA}"
if [[ "${PROFILE_NAME}" == "bertha" ]]; then ok "bertha name"; else bad "name=${PROFILE_NAME}"; fi
if dots_array_contains herdr "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "bertha inherits herdr from server"; else bad "herdr missing on bertha"; fi
if dots_array_contains hermes "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then bad "bertha must not imply AI"; else ok "bertha no AI from herdr"; fi
if dots_array_contains infra "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; then ok "bertha adds infra"; else bad "pkgs=${PROFILE_PACKAGES[*]}"; fi
if dots_array_contains gui "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; then bad "bertha must not add gui"; else ok "bertha no gui"; fi
if [[ "${PROFILE_RUNTIME_MULTIPLEXER}" == "tmux" ]]; then ok "bertha mux=tmux"; else bad "mux=${PROFILE_RUNTIME_MULTIPLEXER}"; fi

# server-custom with herdr automatic
SERVER_CUSTOM="$TMP/server-custom.toml"
cat >"${SERVER_CUSTOM}" <<'EOF'
[profile]
name = "server-custom"
extends = "server"

[runtime]
multiplexer = "herdr"

[packages]
add = ["infra"]
EOF
resolve_file "${SERVER_CUSTOM}"
if [[ "${PROFILE_RUNTIME_MULTIPLEXER}" == "herdr" ]]; then ok "server-custom mux=herdr"; else bad "mux=${PROFILE_RUNTIME_MULTIPLEXER}"; fi
if dots_array_contains herdr "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "server-custom herdr present"; else bad "herdr missing"; fi

# CLI overrides on custom
CLI_WITH=(ollama)
CLI_WITHOUT=(herdr)
EFFECTIVE_WITH=()
dots_compute_effective_with
if dots_array_contains ollama "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then ok "CLI --with ollama on custom"; else bad "ollama missing"; fi
if dots_array_contains herdr "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then bad "CLI --without herdr failed"; else ok "CLI --without herdr on custom"; fi

# --- validation failures ---
BAD_BASE="$TMP/bad-base.toml"
cat >"${BAD_BASE}" <<'EOF'
[profile]
name = "x"
extends = "does-not-exist"
EOF
if dots_load_profile_file "${BAD_BASE}" >/dev/null 2>&1; then bad "unknown base should fail"; else ok "unknown base rejected"; fi

LOOP_A="$TMP/loop-a.toml"
LOOP_B="$TMP/loop-b.toml"
cat >"${LOOP_A}" <<EOF
[profile]
name = "loop-a"
extends = "${LOOP_B}"
EOF
cat >"${LOOP_B}" <<EOF
[profile]
name = "loop-b"
extends = "${LOOP_A}"
EOF
if dots_load_profile_file "${LOOP_A}" >/dev/null 2>&1; then bad "inheritance loop should fail"; else ok "inheritance loop rejected"; fi

BAD_PKG="$TMP/bad-pkg.toml"
cat >"${BAD_PKG}" <<'EOF'
[profile]
name = "x"
extends = "base"

[packages]
add = ["infrra"]
EOF
out="$(dots_load_profile_file "${BAD_PKG}" 2>&1 || true)"
if echo "${out}" | rg -q "Unknown package group 'infrra'"; then ok "unknown package group message"; else bad "pkg error: ${out}"; fi

BAD_COMP="$TMP/bad-comp.toml"
cat >"${BAD_COMP}" <<'EOF'
[profile]
name = "x"
extends = "base"
with = ["not-a-real-component"]
EOF
if dots_load_profile_file "${BAD_COMP}" >/dev/null 2>&1; then bad "unknown component should fail"; else ok "unknown component rejected"; fi

BAD_MUX="$TMP/bad-mux.toml"
cat >"${BAD_MUX}" <<'EOF'
[profile]
name = "x"
extends = "base"

[runtime]
multiplexer = "screen"
EOF
if dots_load_profile_file "${BAD_MUX}" >/dev/null 2>&1; then bad "invalid mux should fail"; else ok "invalid multiplexer rejected"; fi

CONTRA="$TMP/contra.toml"
cat >"${CONTRA}" <<'EOF'
[profile]
name = "x"
extends = "base"
with = ["herdr"]
without = ["herdr"]
EOF
if dots_load_profile_file "${CONTRA}" >/dev/null 2>&1; then bad "contradictory with/without should fail"; else ok "contradictory with/without rejected"; fi

BAD_KEY="$TMP/bad-key.toml"
cat >"${BAD_KEY}" <<'EOF'
[profile]
name = "x"
extends = "base"
typo_packages = ["core"]
EOF
if dots_load_profile_file "${BAD_KEY}" >/dev/null 2>&1; then bad "unknown key should fail"; else ok "unknown profile key rejected"; fi

if dots_resolve_profile_path "${TMP}/missing.toml" >/dev/null 2>&1; then bad "missing file should fail"; else ok "missing profile file rejected"; fi

# Builtin name not shadowed by user profile of same name
mkdir -p "$TMP/fakehome/.config/dots/profiles"
export HOME="$TMP/fakehome"
cat >"$HOME/.config/dots/profiles/home.toml" <<'EOF'
[profile]
name = "home"
extends = "base"
with = ["hermes"]
EOF
builtin_path="$(dots_resolve_profile_path home)"
if [[ "${builtin_path}" == *"configs/bootstrap/profiles/home.toml" ]]; then
	ok "builtin home not shadowed by user home.toml"
else
	bad "shadowed path=${builtin_path}"
fi
# restore TMP as HOME for dry-run isolation below
export HOME="$TMP"

# --- --show exposes resolved state ---
show_out="$("${DOTS_DIR}/bootstrap.sh" --profile "${BERTHA}" --show 2>/dev/null || true)"
if echo "${show_out}" | rg -q 'profile: bertha'; then ok "--show profile name"; else bad "show name"; fi
if echo "${show_out}" | rg -q 'extends: server'; then ok "--show extends"; else bad "show extends"; fi
if echo "${show_out}" | rg -q 'source chain:'; then ok "--show source chain"; else bad "show chain"; fi
if echo "${show_out}" | rg -q 'infra'; then ok "--show infra group"; else bad "show infra"; fi
if echo "${show_out}" | rg -q 'herdr'; then ok "--show herdr component"; else bad "show herdr"; fi
if echo "${show_out}" | rg -q 'multiplexer = tmux'; then ok "--show multiplexer"; else bad "show mux"; fi

# --- dry-run custom profiles ---
snap() { (cd "$1" && find . -print | LC_ALL=C sort | cksum); }
DRY_HOME="$TMP/dryhome"
mkdir -p "${DRY_HOME}"
export HOME="${DRY_HOME}"
before="$(snap "${DRY_HOME}")"
for p in "${HOME_CUSTOM}" "${WORK_CUSTOM}" "${SERVER_CUSTOM}" "${BERTHA}"; do
	/bin/bash "${DOTS_DIR}/bootstrap.sh" --profile "${p}" --dry-run >/dev/null 2>&1 || true
done
after="$(snap "${DRY_HOME}")"
if [[ "${before}" == "${after}" ]]; then ok "custom profile dry-runs non-mutating"; else bad "custom dry-run mutated HOME"; fi

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ "${fail}" -eq 0 ]]
