#!/usr/bin/env bash
# scripts/tests/keybinding_collision_test.sh — reserved prefix invariants for v1.5.0
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

echo "=== keybinding collision audit (static) ==="

# tmux prefix must be Ctrl-Space
rg -q 'set -g prefix C-Space' "${ROOT}/syms/tmux.conf" && ok "tmux prefix C-Space" || bad "tmux prefix"
rg -q 'bind C-Space send-prefix' "${ROOT}/syms/tmux.conf" && ok "tmux send-prefix C-Space" || bad "tmux send-prefix"

# Herdr prefix must be Ctrl-A
rg -q 'prefix = "ctrl\+a"' "${ROOT}/configs/herdr/config.toml" && ok "Herdr prefix ctrl+a" || bad "Herdr prefix"

# Shell must NOT bind Ctrl-Space to autosuggest
if rg -n "bindkey ['\"]\^ ['\"] autosuggest-accept|bindkey ['\"]\^@['\"] autosuggest-accept" \
	"${ROOT}/zsh" "${ROOT}/syms/zshrc" 2>/dev/null | rg -v '^\s*#' >/dev/null; then
	bad "Zsh still binds Ctrl-Space/^@ to autosuggest-accept"
else
	ok "no Zsh Ctrl-Space → autosuggest-accept binding"
fi

# Shell MUST bind Ctrl-] for autosuggest in keybindings module
rg -q "bindkey -M viins '\^\]' autosuggest-accept|bindkey '\^\]' autosuggest-accept" \
	"${ROOT}/zsh/keybindings.zsh" && ok "keybindings.zsh binds Ctrl-]" || bad "Ctrl-] binding missing"

# fzf-tab multi-select must not use ctrl-space
if rg -q 'ctrl-space' "${ROOT}/zsh/fzf.zsh"; then
	bad "fzf-tab config mentions ctrl-space"
else
	ok "fzf-tab does not use ctrl-space"
fi
rg -q 'ctrl-y:toggle' "${ROOT}/zsh/fzf.zsh" && ok "fzf-tab multi-select ctrl-y" || bad "fzf-tab multi-select"

# Metadata registry invariants
kb="${ROOT}/configs/help/keybindings.toml"
[[ -f ${kb} ]] || bad "keybindings.toml missing"
rg -q 'key = "Ctrl-Space"' "${kb}" && rg -q 'context = "tmux"' "${kb}" && ok "metadata: Ctrl-Space → tmux" || bad "metadata Ctrl-Space"
rg -q 'key = "Ctrl-A"' "${kb}" && rg -q 'context = "herdr"' "${kb}" && ok "metadata: Ctrl-A → herdr" || bad "metadata Ctrl-A"
rg -q 'key = "Ctrl-]"' "${kb}" && rg -q 'autosuggest' "${kb}" && ok "metadata: Ctrl-] → autosuggest" || bad "metadata Ctrl-]"

# Docs must not advertise Ctrl-Space as autosuggest accept
if rg -n 'Ctrl-Space.*[Aa]ccept|[Aa]ccept.*Ctrl-Space|Control-Space.*autosuggest' \
	"${ROOT}/docs" "${ROOT}/README.md" "${ROOT}/docs/help" "${ROOT}/docs/using" 2>/dev/null \
	| rg -v 'tmux|prefix|reserved|never|RESERVED|conflict' >/dev/null; then
	# Allow lines that mention both if they say reserved/tmux; fail otherwise
	hits="$(rg -n 'Ctrl-Space' "${ROOT}/docs/help" "${ROOT}/docs/using" "${ROOT}/README.md" 2>/dev/null || true)"
	if echo "${hits}" | rg -i 'autosuggest' | rg -vi 'never|reserved|tmux prefix|not used' >/dev/null; then
		bad "docs still advertise Ctrl-Space for autosuggest"
		echo "${hits}" | rg -i 'autosuggest' || true
	else
		ok "docs Ctrl-Space references are tmux-safe"
	fi
else
	ok "docs do not advertise Ctrl-Space as autosuggest"
fi

rg -q 'Ctrl-\]' "${ROOT}/docs/help/keybindings.md" && ok "docs/help keybindings Ctrl-]" || bad "docs keybindings"
rg -q 'Ctrl-\]' "${ROOT}/docs/help/completion.md" && ok "docs/help completion Ctrl-]" || bad "docs completion"
rg -q 'Ctrl-\]' "${ROOT}/docs/using/fuzzy-completion.md" && ok "fuzzy-completion.md Ctrl-]" || bad "fuzzy docs"

# Runtime ownership (isolated HOME with stub autosuggestions)
if command -v zsh >/dev/null 2>&1; then
	TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-keys.XXXXXX")"
	trap 'rm -rf "${TMP}"' EXIT
	export HOME="${TMP}/home"
	mkdir -p "${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
	# Minimal OMZ + plugin stubs so keybindings.zsh can bind the widget
	mkdir -p "${HOME}/.oh-my-zsh"
	cat >"${HOME}/.oh-my-zsh/oh-my-zsh.sh" <<'EOF'
# minimal stub
EOF
	cat >"${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh" <<'EOF'
autosuggest-accept() { }
zle -N autosuggest-accept
EOF
	# Source keybindings directly after registering widget
	out="$(
		HOME="${HOME}" DOTS_DIR="${ROOT}" zsh -f -c '
source "'"${ROOT}"'/zsh/keybindings.zsh"
# simulate plugin widget already present
autosuggest-accept() { }
zle -N autosuggest-accept
dots_bind_keybindings
bindkey -M viins "^]" | head -1
bindkey "^ " | head -1
bindkey "^@" | head -1
' 2>/dev/null
	)"
	echo "${out}" | rg -q 'autosuggest-accept' && ok "runtime Ctrl-] → autosuggest-accept" || bad "runtime Ctrl-] (${out})"
	if echo "${out}" | rg -q '\^ |\^@.*autosuggest-accept'; then
		bad "runtime Ctrl-Space still autosuggest (${out})"
	else
		ok "runtime Ctrl-Space released from autosuggest"
	fi
else
	ok "zsh missing (skip runtime bind probe)"
fi

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
