#!/usr/bin/env bash
# scripts/tests/shell_startup_test.sh — interactive shell must not provision config
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

echo "=== shell startup side effects ==="
TMP="$(mktemp -d)"
export HOME="$TMP"
mkdir -p "$HOME/.config/dots"

# Install only shell entrypoints + runtime (what setup would link)
ln -sfn "$ROOT/syms/bashrc" "$HOME/.bashrc"
ln -sfn "$ROOT/syms/zshrc" "$HOME/.zshrc"
ln -sfn "$ROOT/syms/zshenv" "$HOME/.zshenv" 2>/dev/null || true
cat >"$HOME/.config/dots/runtime.env" <<'EOF'
: "${DOTS_PROFILE:=base}"
: "${DOTS_MULTIPLEXER:=tmux}"
: "${DOTS_GREETING:=0}"
: "${DOTS_PROMPT_STATS:=0}"
: "${DOTS_AUTO_TMUX:=0}"
: "${DOTS_PACKAGE_GROUPS:=core}"
export DOTS_PROFILE DOTS_MULTIPLEXER DOTS_GREETING DOTS_PROMPT_STATS DOTS_AUTO_TMUX DOTS_PACKAGE_GROUPS
EOF

before=$(find "$HOME" \( -type f -o -type l -o -type d \) | sort)

# Non-interactive startup paths used by scripts; also force interactive-ish rc source.
DOTS_GREETING=0 DOTS_AUTO_TMUX=0 bash --noprofile --rcfile "$HOME/.bashrc" -c 'true' >/dev/null 2>&1 || true
DOTS_GREETING=0 DOTS_AUTO_TMUX=0 zsh -f -c 'source ~/.zshrc; true' >/dev/null 2>&1 || true

after=$(find "$HOME" \( -type f -o -type l -o -type d \) | sort)
new=$(comm -13 <(echo "$before") <(echo "$after") || true)

# Allow only well-known shell history/runtime scratch — not provisioning.
allow_re='/\.(bash_history|zsh_history|zsh_sessions|zcompdump|local/state|cache)/|/\.zsh_history$|/\.bash_history$|/\.zcompdump'
bad_new=""
while IFS= read -r p; do
	[[ -z $p ]] && continue
	if echo "$p" | grep -Eq 'local\.sh$|runtime\.env$|active-profile$|atuin|/fnm|starship\.toml|herdr|hermes|ollama|codex|cursor|drawthings|\.config/git'; then
		bad_new="${bad_new}${p}"$'\n'
	fi
done <<<"$new"

if [[ -z $bad_new ]]; then
	ok "no provisioning files created on shell startup"
else
	bad "unexpected provisioning on startup:"$'\n'"$bad_new"
fi

# Explicitly ensure local.sh was not created
[[ ! -e $HOME/.config/dots/local.sh ]] && ok "local.sh not auto-created" || bad "local.sh created at startup"

rm -rf "$TMP"
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
