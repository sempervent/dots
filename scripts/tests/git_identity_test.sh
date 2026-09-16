#!/usr/bin/env bash
# scripts/tests/git_identity_test.sh — Git identity must not be overwritten
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$ROOT"
pass=0; fail=0
ok() { echo "OK: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail+1)); }

source "$ROOT/helpers/git_config.sh"
ensure_dir() { mkdir -p "$1"; }

echo "=== git identity safety ==="
TMP="$(mktemp -d)"
export HOME="$TMP"
DRY_RUN=0

# Existing global identity
mkdir -p "$HOME"
cat >"$HOME/.gitconfig" <<'EOF'
[user]
	name = Existing User
	email = existing@example.com
EOF

dots_setup_git_config >/dev/null
if grep -q 'existing@example.com' "$HOME/.gitconfig"; then
  ok "existing ~/.gitconfig identity preserved"
else
  bad "existing identity rewritten"
fi
[[ -f "$HOME/.config/git/common" || -L "$HOME/.config/git/common" ]] && ok "common deployed" || bad "common missing"
[[ -f "$HOME/.config/git/personal" ]] && ok "personal seeded" || bad "personal missing"
# personal must still be template placeholders, not stolen from global
if grep -q 'YOUR_PERSONAL_EMAIL' "$HOME/.config/git/personal"; then
  ok "personal template not auto-filled from global"
else
  bad "personal unexpectedly filled"
fi

# Second run idempotent
cp "$HOME/.config/git/personal" /tmp/pers1
echo 'name = Kept' >>"$HOME/.config/git/personal"
dots_setup_git_config >/dev/null
grep -q 'Kept' "$HOME/.config/git/personal" && ok "personal not overwritten on re-run" || bad "personal overwritten"

# No identity case
TMP2="$(mktemp -d)"
export HOME="$TMP2"
dots_setup_git_config >/dev/null
[[ ! -f "$HOME/.gitconfig" ]] && ok "no invented ~/.gitconfig" || bad "invented gitconfig"
[[ -f "$HOME/.config/git/config" ]] && ok "xdg config created" || bad "xdg config missing"

rm -rf "$TMP" "$TMP2"
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
