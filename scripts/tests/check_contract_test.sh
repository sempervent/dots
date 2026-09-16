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
DOTS_LAST_WITH_INFO=''
EOF

# Hide selected required CLIs while keeping a usable system PATH for the checker itself.
mkdir -p "$TMP/bin"
for tool in tmux nvim rg fd fzf bat zoxide direnv htop jq; do
	cat >"$TMP/bin/$tool" <<'EOF'
#!/bin/sh
echo "hidden-for-test" >&2
exit 127
EOF
	chmod +x "$TMP/bin/$tool"
done
# Prefer /bin /usr/bin for real utilities; put hide-dir AFTER so... wait, we need hide to win.
# Put hide first so command -v finds our stubs — but stubs exit 127; command -v still finds them!
# check.sh uses command -v which succeeds if stub exists. Remove stubs; use a filtered PATH instead.
rm -rf "$TMP/bin"
mkdir -p "$TMP/bin"
# Copy/symlink only "safe" commands needed to run check.sh, omitting required profile tools.
keep='bash sh mkdir cat printf echo awk sed grep tr cksum find ls date uname dirname basename pwd true false rm mv cp ln head tail cut sort uniq wc tee xargs python3 env git zsh realpath readlink cksum'
for c in $keep; do
	p=$(command -v "$c" 2>/dev/null || true)
	[[ -n $p && -x $p ]] && ln -sfn "$p" "$TMP/bin/$c"
done
# Also need common locations for dynamic linker helpers used by python
export PATH="$TMP/bin:/usr/bin:/bin"

set +e
PATH="$TMP/bin" /bin/bash "$ROOT/scripts/check.sh" --profile server >"$TMP/check.out" 2>&1
rc=$?
set -e

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
if grep -E 'required tool missing|missing .*bashrc|tmux missing \(required' "$TMP/check.out" >/dev/null; then
	ok "emits ERROR for required absence"
else
	bad "no ERROR line for required absence"
	rg -n 'Required tools|✗|fail|tmux|Health check' "$TMP/check.out" | head -40 >&2 || true
fi

rm -rf "$TMP"
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
