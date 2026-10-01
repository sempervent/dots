#!/usr/bin/env bash
# scripts/tests/zsh_prompt_starship_test.sh — Zsh/OMZ/Starship prompt ownership
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

need_starship() {
	command -v starship >/dev/null 2>&1 || {
		echo "SKIP: starship not installed (hook tests require binary)"
		exit 0
	}
}

# Minimal Oh My Zsh stub: empty theme but default PROMPT like real OMZ.
bootstrap_test_home() {
	local home="$1"
	mkdir -p "${home}/.config/dots"
	ln -sfn "${ROOT}/syms/zshrc" "${home}/.zshrc"
	ln -sfn "${ROOT}/configs/starship/starship.toml" "${home}/.config/starship.toml"
	cat >"${home}/.config/dots/runtime.env" <<'EOF'
: "${DOTS_PROFILE:=base}"
: "${DOTS_MULTIPLEXER:=none}"
: "${DOTS_GREETING:=0}"
: "${DOTS_PROMPT_STATS:=0}"
: "${DOTS_AUTO_TMUX:=0}"
: "${DOTS_PACKAGE_GROUPS:=core}"
export DOTS_PROFILE DOTS_MULTIPLEXER DOTS_GREETING DOTS_PROMPT_STATS DOTS_AUTO_TMUX DOTS_PACKAGE_GROUPS
EOF
	mkdir -p "${home}/.oh-my-zsh"
	cat >"${home}/.oh-my-zsh/oh-my-zsh.sh" <<'EOF'
# Test stub — simulates OMZ with ZSH_THEME="" (no Starship).
PROMPT='%n@%m %1~ %# '
RPROMPT=''
EOF
}

# Run interactive zsh once; emit probe markers on stdout.
zsh_probe() {
	local home="$1"
	shift
	# shellcheck disable=SC2048
	env HOME="${home}" DOTS_DIR="${ROOT}" DOTS_GREETING=0 DOTS_AUTO_TMUX=0 TERM=xterm-256color \
		"$@" zsh -ic '
typeset -f prompt_starship_precmd >/dev/null 2>&1 && echo HOOK_FN=1 || echo HOOK_FN=0
(( ${precmd_functions[(Ie)prompt_starship_precmd]:-0} )) && echo HOOK_ARR=1 || echo HOOK_ARR=0
[[ -n ${STARSHIP_SHELL:-} ]] && echo STARSHIP_SHELL=${STARSHIP_SHELL}
[[ -z "${ZSH_THEME:-}" ]] && echo OMZ_THEME_EMPTY=1 || echo OMZ_THEME=${ZSH_THEME}
print -r -- "$PROMPT" | grep -q starship && echo PROMPT_HAS_STARSHIP=1 || echo PROMPT_HAS_STARSHIP=0
[[ -n ${DOTS_STARSHIP_ZSH_INITIALIZED:-} ]] && echo DOTS_INIT=1 || echo DOTS_INIT=0
' 2>/dev/null | tr '\n' ' '
}

starship_active_in_probe() {
	local out="$1"
	echo "${out}" | grep -q 'HOOK_ARR=1' && echo "${out}" | grep -q 'PROMPT_HAS_STARSHIP=1'
}

echo "=== zsh starship ownership ==="
need_zsh
need_starship

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-zsh-prompt.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

HOME="${TMP}/home"
bootstrap_test_home "${HOME}"

echo "=== inherited STARSHIP_SHELL=bash ==="
out="$(zsh_probe "${HOME}" STARSHIP_SHELL=bash)"
if starship_active_in_probe "${out}"; then
	ok "STARSHIP_SHELL=bash: Starship Zsh hooks active"
else
	bad "STARSHIP_SHELL=bash: Starship not active (${out})"
fi

echo "=== unset STARSHIP_SHELL ==="
out="$(zsh_probe "${HOME}" env -u STARSHIP_SHELL)"
if starship_active_in_probe "${out}"; then
	ok "unset STARSHIP_SHELL: Starship initializes"
else
	bad "unset STARSHIP_SHELL: failed (${out})"
fi

echo "=== STARSHIP_SHELL=zsh without hooks ==="
out="$(zsh_probe "${HOME}" STARSHIP_SHELL=zsh)"
if starship_active_in_probe "${out}"; then
	ok "STARSHIP_SHELL=zsh without hooks: re-initializes"
else
	bad "STARSHIP_SHELL=zsh without hooks: failed (${out})"
fi

echo "=== reload idempotence ==="
reload_out="$(env HOME="${HOME}" DOTS_DIR="${ROOT}" DOTS_GREETING=0 DOTS_AUTO_TMUX=0 TERM=xterm-256color zsh -ic '
source ~/.zshrc 2>/dev/null
source ~/.zshrc 2>/dev/null
source ~/.zshrc 2>/dev/null
typeset -pm precmd_functions 2>/dev/null | grep -o prompt_starship_precmd | wc -l | tr -d " "
' 2>/dev/null)"
[[ "${reload_out}" == "1" ]] && ok "three reloads: one prompt_starship_precmd" || bad "reload precmd count=${reload_out} (want 1)"

echo "=== Oh My Zsh stub with empty theme ==="
out="$(zsh_probe "${HOME}" STARSHIP_SHELL=bash)"
echo "${out}" | grep -q 'OMZ_THEME_EMPTY=1' && ok "ZSH_THEME empty under OMZ" || bad "ZSH_THEME not empty (${out})"

echo "=== without Oh My Zsh ==="
HOME_NO_OMZ="${TMP}/home-no-omz"
bootstrap_test_home "${HOME_NO_OMZ}"
rm -rf "${HOME_NO_OMZ}/.oh-my-zsh"
out="$(zsh_probe "${HOME_NO_OMZ}" STARSHIP_SHELL=bash)"
if starship_active_in_probe "${out}"; then
	ok "no OMZ: Starship still initializes"
else
	bad "no OMZ: Starship missing (${out})"
fi

echo "=== Starship missing fallback ==="
fallback="$(PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -f -c "
  source '${ROOT}/zsh/prompt.zsh'
  print -r -- \"\$PROMPT\"
" 2>/dev/null || true)"
echo "${fallback}" | grep -q '%F{green}%n%f' && ok "no starship: minimal fallback PROMPT" || bad "no starship: bad fallback (${fallback})"

echo "=== local PROMPT override ==="
HOME_LOCAL="${TMP}/home-local"
bootstrap_test_home "${HOME_LOCAL}"
cat >>"${HOME_LOCAL}/.zshrc.local" <<'EOF'
PROMPT='LOCAL_OVERRIDE> '
EOF
local_out="$(env HOME="${HOME_LOCAL}" DOTS_DIR="${ROOT}" DOTS_GREETING=0 DOTS_AUTO_TMUX=0 TERM=xterm-256color zsh -ic '
print -r -- "$PROMPT"
' 2>/dev/null || true)"
echo "${local_out}" | grep -q 'LOCAL_OVERRIDE>' && ok '${HOME}/.zshrc.local may override PROMPT' || bad "local override failed (${local_out})"

echo "=== old guard regression (would skip init) ==="
# Legacy guard only: inherited STARSHIP_SHELL must not prove Zsh initialization.
legacy="$(STARSHIP_SHELL=bash TERM=xterm-256color zsh -f -c '
PROMPT="%n@%m %1~ %# "
if [[ -z "${STARSHIP_SHELL:-}" ]]; then
  command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
fi
(( ${precmd_functions[(Ie)prompt_starship_precmd]:-0} )) && echo LEGACY_HOOK=1 || echo LEGACY_HOOK=0
print -r -- "$PROMPT"
' 2>/dev/null | tr '\n' ' ')"
echo "${legacy}" | grep -q 'LEGACY_HOOK=0' && ok "legacy STARSHIP_SHELL guard fails as expected" || bad "legacy guard unexpectedly initialized (${legacy})"
echo "${legacy}" | grep -q '%n@%m %1~' && ok "legacy guard leaves OMZ-style PROMPT" || bad "legacy guard PROMPT unexpected (${legacy})"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
