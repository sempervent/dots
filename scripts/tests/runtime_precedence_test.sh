#!/usr/bin/env bash
# scripts/tests/runtime_precedence_test.sh — prove DOTS_* precedence for Bash and Zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0; fail=0
ok() { echo "OK: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail+1)); }

run_case() {
  local shell="$1" label="$2" expect="$3"
  shift 3
  local out
  out="$(
    env -i HOME="$HOME" USER="${USER:-dots}" TERM=dumb PATH="/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
      DOTS_DIR="$ROOT" "$@" \
      "$shell" -c '
        export DOTS_DIR="'"$ROOT"'"
        export DOTS_SHELL="'"$shell"'"
        # minimal init path matching runtime → exports
        . "$DOTS_DIR/shell/runtime.sh"
        . "$DOTS_DIR/shell/exports.sh"
        printf "%s\n" "${DOTS_MULTIPLEXER-}"
      ' 2>/dev/null | tail -1
  )"
  if [[ "$out" == "$expect" ]]; then
    ok "$label ($shell → $out)"
  else
    bad "$label ($shell got='$out' want='$expect')"
  fi
}

echo "=== runtime precedence ==="
TMP="$(mktemp -d)"
export HOME="$TMP"
mkdir -p "$HOME/.config/dots"

# Profile only: home → herdr
cat >"$HOME/.config/dots/runtime.env" <<'EOF'
: "${DOTS_MULTIPLEXER:=herdr}"
export DOTS_MULTIPLEXER
EOF
: >"$HOME/.config/dots/local.sh"
run_case bash "profile only herdr" herdr
run_case zsh "profile only herdr" herdr

# local.sh overrides profile
cat >"$HOME/.config/dots/local.sh" <<'EOF'
export DOTS_MULTIPLEXER=tmux
EOF
run_case bash "local overrides profile" tmux
run_case zsh "local overrides profile" tmux

# process env overrides both
run_case bash "env overrides local+profile" none DOTS_MULTIPLEXER=none
run_case zsh "env overrides local+profile" none DOTS_MULTIPLEXER=none

# server profile tmux
cat >"$HOME/.config/dots/runtime.env" <<'EOF'
: "${DOTS_MULTIPLEXER:=tmux}"
export DOTS_MULTIPLEXER
EOF
: >"$HOME/.config/dots/local.sh"
run_case bash "server profile tmux" tmux
run_case zsh "server profile tmux" tmux

rm -rf "$TMP"
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
