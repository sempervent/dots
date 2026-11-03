#!/usr/bin/env bash
# scripts/tests/fuzzy_completion_test.sh — fzf / fzf-tab ownership, order, fallback
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

need_zsh() {
	command -v zsh >/dev/null 2>&1 || {
		echo "SKIP: zsh not installed"
		exit 0
	}
}

need_fzf() {
	command -v fzf >/dev/null 2>&1 || {
		echo "SKIP: fzf not installed"
		exit 0
	}
}

_DOTS_REAL_HOME="${HOME}"

provision_fzf_tab() {
	local dest="$1"
	mkdir -p "$(dirname "${dest}")"
	local host_tab=""
	for cand in \
		"${_DOTS_REAL_HOME}/.oh-my-zsh/custom/plugins/fzf-tab" \
		"${HOME}/.oh-my-zsh/custom/plugins/fzf-tab"; do
		if [[ -f "${cand}/fzf-tab.plugin.zsh" ]]; then
			host_tab="${cand}"
			break
		fi
	done
	if [[ -n "${host_tab}" ]]; then
		# Copy tree (not symlink) so tests stay isolated from the host checkout
		rm -rf "${dest}"
		mkdir -p "${dest}"
		# Prefer cp -a; fall back to git clone
		if cp -a "${host_tab}/." "${dest}/" 2>/dev/null; then
			return 0
		fi
	fi
	if command -v git >/dev/null 2>&1; then
		rm -rf "${dest}"
		git clone --depth 1 https://github.com/Aloxaf/fzf-tab.git "${dest}" >/dev/null 2>&1
		return $?
	fi
	return 1
}

bootstrap_home() {
	local home="$1"
	local with_fzf_tab="${2:-1}"
	mkdir -p "${home}/.config/dots" "${home}/bin" \
		"${home}/.oh-my-zsh/plugins" "${home}/.oh-my-zsh/custom/plugins"
	ln -sfn "${ROOT}/syms/zshrc" "${home}/.zshrc"
	ln -sfn "${ROOT}/syms/bashrc" "${home}/.bashrc"
	cat >"${home}/.config/dots/runtime.env" <<'EOF'
: "${DOTS_PROFILE:=base}"
: "${DOTS_MULTIPLEXER:=none}"
: "${DOTS_GREETING:=0}"
: "${DOTS_PROMPT_STATS:=0}"
: "${DOTS_AUTO_TMUX:=0}"
: "${DOTS_PACKAGE_GROUPS:=core}"
export DOTS_PROFILE DOTS_MULTIPLEXER DOTS_GREETING DOTS_PROMPT_STATS DOTS_AUTO_TMUX DOTS_PACKAGE_GROUPS
EOF

	# Minimal OMZ: compinit + fzf --zsh + custom plugins in declared order
	cat >"${home}/.oh-my-zsh/oh-my-zsh.sh" <<'EOF'
autoload -Uz compinit
compinit -u 2>/dev/null || true

if command -v fzf >/dev/null 2>&1 && fzf --zsh >/dev/null 2>&1; then
  source <(fzf --zsh)
fi

for _p in ${plugins[@]}; do
  if [[ -f "${ZSH_CUSTOM}/plugins/${_p}/${_p}.plugin.zsh" ]]; then
    source "${ZSH_CUSTOM}/plugins/${_p}/${_p}.plugin.zsh"
  elif [[ -f "${ZSH_CUSTOM}/plugins/${_p}/${_p}.zsh" ]]; then
    source "${ZSH_CUSTOM}/plugins/${_p}/${_p}.zsh"
  fi
done
unset _p
EOF

	mkdir -p "${home}/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
	cat >"${home}/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh" <<'EOF'
autosuggest-accept() { }
zle -N autosuggest-accept
# Plugin stub intentionally does NOT bind Ctrl-Space (reserved for tmux).
EOF

	mkdir -p "${home}/.oh-my-zsh/custom/plugins/zsh-history-substring-search"
	cat >"${home}/.oh-my-zsh/custom/plugins/zsh-history-substring-search/zsh-history-substring-search.plugin.zsh" <<'EOF'
history-substring-search-up() { }
history-substring-search-down() { }
zle -N history-substring-search-up
zle -N history-substring-search-down
EOF

	mkdir -p "${home}/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
	echo '# stub' >"${home}/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh"

	if [[ "${with_fzf_tab}" == "1" ]]; then
		if ! provision_fzf_tab "${home}/.oh-my-zsh/custom/plugins/fzf-tab"; then
			echo "WARN: could not provision fzf-tab" >&2
		fi
	fi
}

zsh_probe() {
	local home="$1"
	# Unset ZSH/ZSH_CUSTOM so host exports cannot leak into the isolated HOME
	env -u ZSH -u ZSH_CUSTOM \
		HOME="${home}" DOTS_DIR="${ROOT}" DOTS_GREETING=0 DOTS_AUTO_TMUX=0 TERM=xterm-256color \
		PATH="${home}/bin:${PATH}" zsh -ic '
bindkey "^I" | head -1 | sed "s/^/TAB_DEFAULT=/"
bindkey -M viins "^I" | head -1 | sed "s/^/TAB_VIINS=/"
bindkey "^R" | head -1 | sed "s/^/CTRL_R=/"
bindkey "^T" | head -1 | sed "s/^/CTRL_T=/"
bindkey -M viins "^]" | head -1 | sed "s/^/CTRL_BRACKET=/"
bindkey "^ " | head -1 | sed "s/^/CTRL_SPACE=/"
bindkey "^@" | head -1 | sed "s/^/CTRL_AT=/"
typeset -f fzf-file-widget >/dev/null && echo FZF_FILE=1 || echo FZF_FILE=0
typeset -f _fzf_compgen_path >/dev/null && echo FZF_COMPGEN=1 || echo FZF_COMPGEN=0
print -r -- "PLUGINS=${(j:,:)plugins}"
' 2>/dev/null
}

echo "=== fuzzy completion ==="
need_zsh
need_fzf

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-fuzzy.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

# --- Static: plugin order in oh-my-zsh.zsh ---
omz_src="${ROOT}/zsh/oh-my-zsh.zsh"
ftb_line="$(rg -n '^\s*fzf-tab\s*$' "${omz_src}" | head -1 | cut -d: -f1 || true)"
as_line="$(rg -n '^\s*zsh-autosuggestions\s*$' "${omz_src}" | head -1 | cut -d: -f1 || true)"
hss_line="$(rg -n '^\s*zsh-history-substring-search\s*$' "${omz_src}" | head -1 | cut -d: -f1 || true)"
syh_line="$(rg -n '^\s*zsh-syntax-highlighting\s*$' "${omz_src}" | head -1 | cut -d: -f1 || true)"
fzf_line="$(rg -n '^\s*fzf\s*$' "${omz_src}" | head -1 | cut -d: -f1 || true)"

if [[ -n "${fzf_line}" && -n "${ftb_line}" && "${fzf_line}" -lt "${ftb_line}" ]]; then
	ok "plugin list: fzf before fzf-tab"
else
	bad "plugin list: fzf must precede fzf-tab (fzf=${fzf_line} fzf-tab=${ftb_line})"
fi
if [[ -n "${ftb_line}" && -n "${as_line}" && -n "${hss_line}" && -n "${syh_line}" ]] \
	&& [[ "${ftb_line}" -lt "${as_line}" && "${as_line}" -lt "${hss_line}" && "${hss_line}" -lt "${syh_line}" ]]; then
	ok "plugin list: fzf-tab → autosuggestions → history-substring → syntax-highlighting"
else
	bad "plugin order wrong (fzf-tab=${ftb_line} as=${as_line} hss=${hss_line} syh=${syh_line})"
fi

rg -q 'Aloxaf/fzf-tab' "${ROOT}/setup.sh" && ok "setup.sh installs Aloxaf/fzf-tab" || bad "setup.sh missing fzf-tab"

for f in shell/fzf.sh zsh/fzf.zsh bash/fzf.sh; do
	[[ -f "${ROOT}/${f}" ]] && ok "present ${f}" || bad "missing ${f}"
done

zshrc="${ROOT}/syms/zshrc"
fzf_src_line="$(rg -n 'zsh/fzf\.zsh' "${zshrc}" | head -1 | cut -d: -f1 || true)"
tools_line="$(rg -n 'shell/tools\.sh' "${zshrc}" | head -1 | cut -d: -f1 || true)"
if [[ -n "${fzf_src_line}" && -n "${tools_line}" && "${fzf_src_line}" -lt "${tools_line}" ]]; then
	ok "zshrc: zsh/fzf.zsh before shell/tools.sh"
else
	bad "zshrc order: fzf.zsh must precede tools.sh"
fi

bashrc="${ROOT}/syms/bashrc"
bash_fzf_line="$(rg -n 'bash/fzf\.sh' "${bashrc}" | head -1 | cut -d: -f1 || true)"
bash_tools_line="$(rg -n 'shell/tools\.sh' "${bashrc}" | head -1 | cut -d: -f1 || true)"
if [[ -n "${bash_fzf_line}" && -n "${bash_tools_line}" && "${bash_fzf_line}" -lt "${bash_tools_line}" ]]; then
	ok "bashrc: bash/fzf.sh before shell/tools.sh"
else
	bad "bashrc order: bash/fzf.sh must precede tools.sh"
fi

if rg -q "autosuggest-accept" "${ROOT}/zsh/keybindings.zsh" \
	&& rg -q "\^\]" "${ROOT}/zsh/keybindings.zsh"; then
	ok "Ctrl-] autosuggest-accept owned by keybindings.zsh"
else
	bad "Ctrl-] autosuggest-accept missing from keybindings.zsh"
fi
if rg -q "bindkey '\^ ' autosuggest-accept" "${ROOT}/zsh/fzf.zsh" \
	|| rg -q "bindkey '\^ ' autosuggest-accept" "${ROOT}/zsh/oh-my-zsh.zsh"; then
	bad "Ctrl-Space still bound to autosuggest-accept (conflicts with tmux)"
else
	ok "Ctrl-Space not bound for autosuggest in fzf/OMZ modules"
fi
rg -q 'dots_bind_keybindings' "${ROOT}/syms/zshrc" && ok "zshrc calls dots_bind_keybindings" || bad "zshrc missing dots_bind_keybindings"
rg -q 'ctrl-y:toggle' "${ROOT}/zsh/fzf.zsh" && ok "fzf-tab multi-select uses ctrl-y" || bad "multi-select should use ctrl-y"
rg -q 'Fuzzy completion' "${ROOT}/scripts/check.sh" && ok "check.sh Fuzzy completion section" || bad "check.sh missing section"

# --- Interactive with fzf-tab ---
HOME_WITH="${TMP}/home-with"
bootstrap_home "${HOME_WITH}" 1

if [[ ! -f "${HOME_WITH}/.oh-my-zsh/custom/plugins/fzf-tab/fzf-tab.plugin.zsh" ]]; then
	bad "fzf-tab plugin not provisioned for interactive tests"
else
	ok "fzf-tab plugin provisioned for tests"
	out="$(zsh_probe "${HOME_WITH}")"
	echo "probe: ${out}"

	if echo "${out}" | rg -q 'fzf-tab-complete'; then
		ok "Tab / viins ^I owned by fzf-tab-complete"
	else
		bad "Tab not owned by fzf-tab (${out})"
	fi
	if echo "${out}" | rg -q 'CTRL_T=.*"fzf-file-widget"|FZF_FILE=1'; then
		ok "Ctrl-T fzf-file-widget present"
	else
		bad "Ctrl-T / fzf-file-widget missing (${out})"
	fi
	if echo "${out}" | rg -q 'CTRL_BRACKET=.*autosuggest-accept'; then
		ok "Ctrl-] autosuggest-accept after startup"
	else
		bad "Ctrl-] not autosuggest-accept (${out})"
	fi
	if echo "${out}" | rg -q 'CTRL_SPACE=.*autosuggest-accept|CTRL_AT=.*autosuggest-accept'; then
		bad "Ctrl-Space still autosuggest-accept (${out})"
	else
		ok "Ctrl-Space not claimed by autosuggest after startup"
	fi
	if echo "${out}" | rg -q 'CTRL_R=.*"fzf-tab'; then
		bad "fzf-tab stole Ctrl-R"
	else
		ok "Ctrl-R not owned by fzf-tab"
	fi
	if echo "${out}" | rg -q 'PLUGINS=.*fzf-tab'; then
		ok "effective plugins include fzf-tab"
	else
		bad "fzf-tab not in effective plugins (${out})"
	fi
	# plugins array order: fzf-tab before autosuggestions
	if echo "${out}" | rg -q 'PLUGINS=.*fzf-tab.*zsh-autosuggestions.*zsh-syntax-highlighting'; then
		ok "effective plugin order places fzf-tab before wrappers"
	else
		bad "effective plugin order unexpected (${out})"
	fi

	reload_out="$(env -u ZSH -u ZSH_CUSTOM HOME="${HOME_WITH}" DOTS_DIR="${ROOT}" DOTS_GREETING=0 DOTS_AUTO_TMUX=0 TERM=xterm-256color \
		zsh -ic 'source ~/.zshrc; source ~/.zshrc; source ~/.zshrc; bindkey -M viins "^I"' 2>/dev/null || true)"
	if echo "${reload_out}" | rg -q 'fzf-tab-complete'; then
		ok "reload idempotence: Tab still fzf-tab-complete"
	else
		bad "reload broke Tab ownership (${reload_out})"
	fi

	if echo "${out}" | rg -q 'FZF_COMPGEN=1'; then
		ok "fd path generator wired"
	else
		bad "fd path generator missing"
	fi
fi

# --- Fallback without fzf-tab ---
HOME_FALLBACK="${TMP}/home-fallback"
bootstrap_home "${HOME_FALLBACK}" 0
rm -rf "${HOME_FALLBACK}/.oh-my-zsh/custom/plugins/fzf-tab"
fallback_out="$(zsh_probe "${HOME_FALLBACK}")"
if echo "${fallback_out}" | rg -q 'fzf-tab-complete'; then
	bad "fallback unexpectedly bound fzf-tab"
else
	ok "fallback without fzf-tab: Tab is normal completion"
fi
if echo "${fallback_out}" | rg -q 'FZF_FILE=1|fzf-file-widget'; then
	ok "fallback: fzf Ctrl-T still available"
else
	bad "fallback: fzf file widget missing (${fallback_out})"
fi

# --- File candidate generation ---
FILE_DIR="${TMP}/files"
mkdir -p "${FILE_DIR}/nested" "${FILE_DIR}/.git/objects" "${FILE_DIR}/node_modules/pkg"
touch "${FILE_DIR}/alpha.txt" "${FILE_DIR}/beta.md" "${FILE_DIR}/.hidden.toml" \
	"${FILE_DIR}/nested/gamma.rs" "${FILE_DIR}/.git/objects/pack" \
	"${FILE_DIR}/node_modules/pkg/index.js"
gen_out="$(env HOME="${HOME_WITH}" DOTS_DIR="${ROOT}" TERM=xterm-256color zsh -c '
source "'"${ROOT}"'/shell/fzf.sh"
if _dots_fd_bin="$(_dots_fzf_fd_bin 2>/dev/null)"; then
  _fzf_compgen_path() {
    local fd="${_dots_fd_bin}"
    "${fd}" --hidden --follow \
      --exclude .git --exclude node_modules --exclude target \
      --exclude .venv --exclude __pycache__ --exclude dist --exclude build \
      . "$1"
  }
  cd "'"${FILE_DIR}"'"
  _fzf_compgen_path . | sort
fi
' 2>/dev/null)"
echo "${gen_out}" | rg -q 'alpha\.txt' && ok "file gen includes alpha.txt" || bad "file gen missing alpha.txt"
echo "${gen_out}" | rg -q 'beta\.md' && ok "file gen includes beta.md" || bad "file gen missing beta.md"
echo "${gen_out}" | rg -q '\.hidden\.toml' && ok "file gen includes .hidden.toml" || bad "file gen missing hidden"
echo "${gen_out}" | rg -q 'nested/gamma\.rs|nested/gamma.rs' && ok "file gen includes nested/gamma.rs" || bad "file gen missing nested"
if echo "${gen_out}" | rg -q '\.git/objects|node_modules/pkg'; then
	bad "file gen leaked excluded paths"
else
	ok "file gen excludes .git and node_modules"
fi

# --- Fake commands discoverable ---
for _fake in dots-fuzzy-alpha dots-fuzzy-beta dots-fuzzy-gamma; do
	printf '#!/bin/sh\nexit 0\n' >"${HOME_WITH}/bin/${_fake}"
	chmod +x "${HOME_WITH}/bin/${_fake}"
done
unset _fake
cmd_out="$(env -u ZSH -u ZSH_CUSTOM HOME="${HOME_WITH}" DOTS_DIR="${ROOT}" DOTS_GREETING=0 DOTS_AUTO_TMUX=0 TERM=xterm-256color \
	PATH="${HOME_WITH}/bin:${PATH}" zsh -ic '
whence -p dots-fuzzy-alpha >/dev/null && echo CMD_ALPHA=1
whence -p dots-fuzzy-beta >/dev/null && echo CMD_BETA=1
whence -p dots-fuzzy-gamma >/dev/null && echo CMD_GAMMA=1
' 2>/dev/null || true)"
echo "${cmd_out}" | rg -q 'CMD_ALPHA=1' && ok "fake command dots-fuzzy-alpha discoverable" || bad "alpha not discoverable (${cmd_out})"
echo "${cmd_out}" | rg -q 'CMD_BETA=1' && ok "fake command dots-fuzzy-beta discoverable" || bad "beta not discoverable (${cmd_out})"
echo "${cmd_out}" | rg -q 'CMD_GAMMA=1' && ok "fake command dots-fuzzy-gamma discoverable" || bad "gamma not discoverable (${cmd_out})"

# --- Bash smoke (interactive: bashrc returns early when non-interactive) ---
bash_out="$(env HOME="${HOME_WITH}" DOTS_DIR="${ROOT}" DOTS_GREETING=0 DOTS_AUTO_TMUX=0 \
	bash --noprofile --rcfile "${HOME_WITH}/.bashrc" -ic '
command -v fzf >/dev/null && echo FZF_BIN=1
declare -F _fzf_compgen_path >/dev/null 2>&1 && echo BASH_COMPGEN=1
declare -F __fzf_select__ >/dev/null 2>&1 && echo BASH_SELECT=1
' 2>/dev/null | tr "\n" " " || true)"
echo "${bash_out}" | rg -q 'FZF_BIN=1' && ok "Bash: fzf on PATH" || bad "Bash: fzf missing (${bash_out})"
if echo "${bash_out}" | rg -q 'BASH_COMPGEN=1|BASH_SELECT=1'; then
	ok "Bash: fzf integration functions present"
else
	bad "Bash: fzf integration not loaded (${bash_out})"
fi

echo "Passed: ${pass}  Failed: ${fail}"
[[ "${fail}" -eq 0 ]]
