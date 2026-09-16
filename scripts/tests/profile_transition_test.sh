#!/usr/bin/env bash
# scripts/tests/profile_transition_test.sh — profile switches rewrite runtime; AI not consented
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

echo "=== profile transition ==="
TMP="$(mktemp -d)"
export HOME="$TMP"
export DIR="$ROOT"
# shellcheck source=../../helpers/toml.sh
source "$ROOT/helpers/toml.sh"
# shellcheck source=../../helpers/components.sh
source "$ROOT/helpers/components.sh"
# shellcheck source=../../helpers/profiles.sh
source "$ROOT/helpers/profiles.sh"

DRY_RUN=0
EFFECTIVE_WITH=()

write_profile() {
	local name="$1"
	shift
	EFFECTIVE_WITH=("$@")
	PROFILE_NAME=""
	PROFILE_PACKAGES=()
	PROFILE_RUNTIME_MULTIPLEXER=""
	PROFILE_RUNTIME_GREETING=""
	PROFILE_RUNTIME_PROMPT_STATS=""
	PROFILE_RUNTIME_AUTO_TMUX=""
	dots_load_profile_file "$ROOT/configs/bootstrap/profiles/${name}.toml"
	dots_write_runtime_policy "$ROOT/configs/bootstrap/profiles/${name}.toml"
}

mux_from_runtime() {
	# shellcheck disable=SC1090
	unset DOTS_MULTIPLEXER DOTS_PROFILE
	# shellcheck source=/dev/null
	source "$HOME/.config/dots/runtime.env"
	printf '%s\n' "${DOTS_MULTIPLEXER}"
}

profile_from_active() {
	# shellcheck disable=SC1090
	unset DOTS_PROFILE DOTS_EFFECTIVE_WITH
	# shellcheck source=/dev/null
	source "$HOME/.config/dots/active-profile"
	printf '%s\n' "${DOTS_PROFILE}"
}

# base -> home
write_profile base
[[ "$(mux_from_runtime)" == "tmux" ]] && ok "base → tmux" || bad "base mux=$(mux_from_runtime)"
write_profile home hermes herdr ollama cursor
[[ "$(mux_from_runtime)" == "herdr" ]] && ok "home → herdr" || bad "home mux=$(mux_from_runtime)"
[[ "$(profile_from_active)" == "home" ]] && ok "active=home" || bad "active=$(profile_from_active)"

# home -> work: multiplexer + profile rewrite; effective-with must not authorize AI
write_profile work
[[ "$(mux_from_runtime)" == "tmux" ]] && ok "work → tmux (not herdr)" || bad "work mux=$(mux_from_runtime)"
[[ "$(profile_from_active)" == "work" ]] && ok "active=work" || bad "active=$(profile_from_active)"
# shellcheck disable=SC1090
source "$HOME/.config/dots/active-profile"
if [[ "${DOTS_LAST_WITH_INFO:-}" == *hermes* ]] || [[ "${DOTS_LAST_WITH_INFO:-}" == *cursor* ]]; then
	bad "work active-profile still lists home AI components (${DOTS_LAST_WITH_INFO})"
else
	ok "work active-profile has no home AI with-list"
fi

# work -> server
write_profile server
[[ "$(mux_from_runtime)" == "tmux" ]] && ok "server → tmux" || bad "server mux=$(mux_from_runtime)"
[[ "$(profile_from_active)" == "server" ]] && ok "active=server" || bad "active=$(profile_from_active)"

# server -> home
write_profile home herdr
[[ "$(mux_from_runtime)" == "herdr" ]] && ok "server→home → herdr" || bad "home2 mux=$(mux_from_runtime)"

# Consent: presence of binaries must not appear as runtime consent flags
mkdir -p "$HOME/bin"
ln -sfn /usr/bin/true "$HOME/bin/hermes"
ln -sfn /usr/bin/true "$HOME/bin/cursor"
export PATH="$HOME/bin:$PATH"
write_profile work
# shellcheck disable=SC1090
source "$HOME/.config/dots/runtime.env"
if [[ "${DOTS_MULTIPLEXER}" == "herdr" ]]; then
	bad "work kept herdr because binary existed"
else
	ok "binary presence does not keep herdr on work"
fi
if grep -E 'CONSENT|hermes|cursor|ollama' "$HOME/.config/dots/runtime.env" >/dev/null 2>&1; then
	bad "runtime.env mentions AI consent/providers"
else
	ok "runtime.env has no AI consent markers"
fi

rm -rf "$TMP"
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
