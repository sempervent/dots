#!/usr/bin/env bash
# scripts/tests/idempotence_test.sh — second setup run must not churn backups/runtime
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

echo "=== idempotence (links + runtime; fake brew) ==="
TMP="$(mktemp -d)"
export HOME="$TMP"
export DIR="$ROOT"
OLD_DOTS="$TMP/.old_dots"

# Fake brew so package provisioning is a no-op success without touching real Homebrew state.
mkdir -p "$TMP/fakebin"
cat >"$TMP/fakebin/brew" <<'EOF'
#!/bin/sh
# no-op brew for idempotence tests
case "$1" in
bundle) exit 0 ;;
*) exit 0 ;;
esac
EOF
chmod +x "$TMP/fakebin/brew"
export PATH="$TMP/fakebin:$PATH"

# Minimal setup helpers expected by links
ensure_dir() { mkdir -p "$1"; }
backup_stamp() { date +%Y%m%d%H%M%S; }
move_sym() {
	local name="$1" dest="$2" source="${3:-}"
	mkdir -p "$(dirname "$dest")"
	if [[ -L $dest ]] && [[ $(readlink "$dest") == "$source" ]]; then
		echo "OK: $name (present)"
		return 0
	fi
	if [[ -e $dest || -L $dest ]]; then
		mkdir -p "$OLD_DOTS"
		mv "$dest" "$OLD_DOTS/${name}_$(backup_stamp)"
	fi
	ln -sfn "$source" "$dest"
}

# shellcheck source=../../helpers/toml.sh
source "$ROOT/helpers/toml.sh"
# shellcheck source=../../helpers/links.sh
source "$ROOT/helpers/links.sh"
# shellcheck source=../../helpers/components.sh
source "$ROOT/helpers/components.sh"
# shellcheck source=../../helpers/profiles.sh
source "$ROOT/helpers/profiles.sh"

DRY_RUN=0
PROFILE_NAME=base
PROFILE_PACKAGES=(core)
PROFILE_RUNTIME_MULTIPLEXER=tmux
PROFILE_RUNTIME_GREETING=1
PROFILE_RUNTIME_PROMPT_STATS=0
PROFILE_RUNTIME_AUTO_TMUX=1
EFFECTIVE_WITH=()

run_once() {
	dots_write_runtime_policy "$ROOT/configs/bootstrap/profiles/base.toml"
	dots_deploy_links >/dev/null
}

run_once
mkdir -p "$OLD_DOTS"
snap1=$(find "$HOME" \( -type f -o -type l \) | sort | cksum)
rt1=$(cksum <"$HOME/.config/dots/runtime.env")
ap1=$(cksum <"$HOME/.config/dots/active-profile")
backups1=$(find "$OLD_DOTS" -type f 2>/dev/null | wc -l | tr -d ' ')

sleep 1 # ensure backup stamps would differ if churn occurred
run_once
snap2=$(find "$HOME" \( -type f -o -type l \) | sort | cksum)
rt2=$(cksum <"$HOME/.config/dots/runtime.env")
ap2=$(cksum <"$HOME/.config/dots/active-profile")
backups2=$(find "$OLD_DOTS" -type f 2>/dev/null | wc -l | tr -d ' ')

[[ $snap1 == "$snap2" ]] && ok "filesystem inventory unchanged" || bad "filesystem changed between runs"
[[ $rt1 == "$rt2" ]] && ok "runtime.env identical" || bad "runtime.env rewritten"
[[ $ap1 == "$ap2" ]] && ok "active-profile identical" || bad "active-profile rewritten"
[[ $backups1 == "$backups2" ]] && ok "no backup churn ($backups1)" || bad "backups $backups1→$backups2"

rm -rf "$TMP"
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
