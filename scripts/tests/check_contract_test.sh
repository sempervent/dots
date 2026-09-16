#!/usr/bin/env bash
# scripts/tests/check_contract_test.sh — missing required state must fail check.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

echo "=== check.sh contract ==="
TMP="$(mktemp -d)"
export HOME="$TMP"
export DOTS_DIR="$ROOT"
ORIG_PATH="${PATH}"

mkdir -p "$HOME/.config/dots"
cat >"$HOME/.config/dots/runtime.env" <<'EOF'
: "${DOTS_PROFILE:=server}"
: "${DOTS_MULTIPLEXER:=tmux}"
: "${DOTS_GREETING:=1}"
: "${DOTS_PROMPT_STATS:=0}"
: "${DOTS_AUTO_TMUX:=1}"
: "${DOTS_PACKAGE_GROUPS:=core,modern,server}"
export DOTS_PROFILE DOTS_MULTIPLEXER DOTS_GREETING DOTS_PROMPT_STATS DOTS_AUTO_TMUX DOTS_PACKAGE_GROUPS
EOF
cat >"$HOME/.config/dots/active-profile" <<EOF
DOTS_PROFILE='server'
DOTS_PROFILE_FILE='$ROOT/configs/bootstrap/profiles/server.toml'
DOTS_PACKAGE_GROUPS='core modern server'
DOTS_LAST_WITH_INFO='herdr'
EOF

# Restricted PATH: enough to run check/profile parse, but omit tmux/herdr/nvim/etc.
mkdir -p "$TMP/bin"
keep='bash sh mkdir cat printf echo awk sed grep tr find ls date uname dirname basename pwd true false rm mv cp ln head tail cut sort uniq wc tee xargs python3 python3.11 python3.12 python3.13 python3.14 env git zsh realpath readlink mktemp cksum'
for c in $keep; do
	p=$(command -v "$c" 2>/dev/null || true)
	[[ -n $p && -x $p ]] && ln -sfn "$p" "$TMP/bin/$c"
done
# Ensure tomllib-capable interpreter is available as python3 for profile load
if ! "$TMP/bin/python3" -c 'import tomllib' 2>/dev/null; then
	for cand in python3.14 python3.13 python3.12 python3.11; do
		if [[ -x $TMP/bin/$cand ]] && "$TMP/bin/$cand" -c 'import tomllib' 2>/dev/null; then
			ln -sfn "$TMP/bin/$cand" "$TMP/bin/python3"
			break
		fi
	done
fi

set +e
PATH="$TMP/bin" /bin/bash "$ROOT/scripts/check.sh" --profile server >"$TMP/check.out" 2>&1
rc=$?
set -e
export PATH="${ORIG_PATH}"

if [[ $rc -ne 0 ]]; then
	ok "check.sh exits nonzero when required state missing (rc=$rc)"
else
	bad "check.sh exited 0 despite missing required tools/links"
fi
if grep -q 'Bootstrap contract satisfied' "$TMP/check.out"; then
	bad "claimed contract satisfied with missing required state"
else
	ok "did not claim contract satisfied"
fi
if grep -E 'required tool missing|missing .*bashrc|tmux missing|herdr missing' "$TMP/check.out" >/dev/null; then
	ok "emits ERROR for required absence"
else
	bad "no ERROR line for required absence"
	grep -nE 'Required tools|✗|tmux|herdr|Health check' "$TMP/check.out" | head -40 >&2 || true
fi

rm -rf "$TMP"
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
