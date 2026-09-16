#!/usr/bin/env bash
# scripts/tests/multiplexer_nesting_test.sh — auto-start vs manual availability
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

# shellcheck source=../../shell/tmux.sh
source "${ROOT}/shell/tmux.sh"

echo "=== multiplexer nesting / auto vs manual ==="

# Auto-start helpers must be skippable inside multiplexers
TMUX="/tmp/fake-tmux-socket"
unset HERDR_SOCKET_PATH HERDR_ACTIVE_PANE_ID HERDR_ACTIVE_TAB_ID HERDR_ACTIVE_WORKSPACE_ID || true
if dots_maybe_start_herdr 2>/dev/null; then
	ok "auto herdr suppressed inside tmux (\$TMUX)"
else
	bad "auto herdr should no-op inside tmux"
fi
unset TMUX

HERDR_SOCKET_PATH="/tmp/fake-herdr"
export HERDR_SOCKET_PATH
if dots_maybe_start_tmux 2>/dev/null; then
	ok "auto tmux suppressed inside herdr"
else
	bad "auto tmux should no-op inside herdr"
fi
unset HERDR_SOCKET_PATH

# Manual commands are not wrapped/blocked — herdr and tmux remain plain commands
if ! type herdr 2>/dev/null | rg -q 'function|alias'; then
	ok "herdr is not a DOTS function/alias (manual invoke OK inside tmux)"
else
	if type herdr 2>/dev/null | rg -q 'dots_maybe_start'; then
		bad "herdr wraps auto-start (would block nesting)"
	else
		ok "herdr not auto-start wrapper"
	fi
fi

if ! type tmux 2>/dev/null | rg -q 'dots_maybe_start'; then
	ok "tmux not wrapped by dots_maybe_start (manual invoke OK inside herdr)"
else
	bad "tmux wraps auto-start"
fi

DOTS_MULTIPLEXER=none
unset TMUX HERDR_SOCKET_PATH || true
dots_maybe_start_multiplexer
ok "multiplexer=none is a no-op"

if declare -F dots_maybe_start_herdr >/dev/null && declare -F dots_maybe_start_tmux >/dev/null; then
	ok "both auto-start entrypoints exist"
else
	bad "missing auto-start functions"
fi

# Recursion guard: already in herdr + DOTS_MULTIPLEXER=tmux must not start tmux
HERDR_SOCKET_PATH="/tmp/fake-herdr"
export HERDR_SOCKET_PATH DOTS_MULTIPLEXER=tmux DOTS_AUTO_TMUX=1
dots_maybe_start_multiplexer
ok "no recursive auto-tmux when already in herdr"
unset HERDR_SOCKET_PATH

TMUX="/tmp/fake"
export TMUX DOTS_MULTIPLEXER=herdr
dots_maybe_start_multiplexer
ok "no recursive auto-herdr when already in tmux"
unset TMUX

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ "${fail}" -eq 0 ]]
