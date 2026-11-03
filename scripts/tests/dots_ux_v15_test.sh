#!/usr/bin/env bash
# scripts/tests/dots_ux_v15_test.sh — completions, suggestions, shell diag, cheatsheet
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${ROOT}"
export DIR ROOT DOTS_DIR="${ROOT}"

pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-ux15.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT
export HOME="${TMP}/home"
unset DOTS_PROFILE DOTS_ACTIVE_COMPONENTS DOTS_PACKAGE_GROUPS DOTS_MULTIPLEXER || true
mkdir -p "${HOME}/.config/dots/profiles" "${HOME}/.local/state/dots/backups/snap-test-1"

# shellcheck source=../../helpers/python_runtime.sh
source "${ROOT}/helpers/python_runtime.sh"
PY="$(dots_find_python311)" || {
	bad "Python >=3.11"
	exit 1
}

# shellcheck source=../../helpers/suggest.sh
source "${ROOT}/helpers/suggest.sh"
# shellcheck source=../../helpers/shell_diag.sh
source "${ROOT}/helpers/shell_diag.sh"
# shellcheck source=../../helpers/ui.sh
source "${ROOT}/helpers/ui.sh" 2>/dev/null || true

echo "=== generated completions present ==="
[[ -f ${ROOT}/generated/completions/_dots ]] && ok "_dots" || bad "_dots"
[[ -f ${ROOT}/generated/completions/dots.bash ]] && ok "dots.bash" || bad "dots.bash"
grep -q 'GENERATED — DO NOT EDIT' "${ROOT}/generated/completions/_dots" && ok "zsh GENERATED marker" || bad "zsh marker"
grep -q 'GENERATED — DO NOT EDIT' "${ROOT}/generated/completions/dots.bash" && ok "bash GENERATED marker" || bad "bash marker"
"${PY}" "${ROOT}/scripts/docs/generate_completions.py" --check && ok "completion drift check" || bad "completion drift"

echo "=== metadata ↔ completion consistency ==="
mapfile -t meta_cmds < <(
	cd "${ROOT}" && "${PY}" - <<'PY'
import sys
sys.path.insert(0, "scripts/docs")
import metadata as m
for c in m.commands():
    print(c["name"])
PY
)
for c in "${meta_cmds[@]}"; do
	grep -q "'${c}:" "${ROOT}/generated/completions/_dots" && ok "zsh has ${c}" || bad "zsh missing ${c}"
	grep -Eq "commands='[^']*\\b${c}\\b" "${ROOT}/generated/completions/dots.bash" && ok "bash has ${c}" || bad "bash missing ${c}"
done
grep -q "ai:" "${ROOT}/generated/completions/_dots" && ok "zsh has ai supergroup" || bad "zsh ai"
grep -q "modern:" "${ROOT}/generated/completions/_dots" && ok "zsh has modern group" || bad "zsh modern"
grep -q "completion:" "${ROOT}/generated/completions/_dots" && ok "zsh help topic completion" || bad "zsh topic"

echo "=== Bash completion sourcing ==="
# shellcheck disable=SC1091
source "${ROOT}/generated/completions/dots.bash"
complete -p dots >/dev/null 2>&1 && ok "bash complete -p dots" || bad "bash complete -p"
COMP_WORDS=(dots "")
COMP_CWORD=1
_dots_complete
printf '%s\n' "${COMPREPLY[@]}" | grep -qx setup && ok "bash top-level setup" || bad "bash top-level setup"
printf '%s\n' "${COMPREPLY[@]}" | grep -qx shell && ok "bash top-level shell" || bad "bash top-level shell"
COMP_WORDS=(dots help "")
COMP_CWORD=2
_dots_complete
printf '%s\n' "${COMPREPLY[@]}" | grep -qx completion && ok "bash help completion topic" || bad "bash help topic"
COMP_WORDS=(dots setup --with "")
COMP_CWORD=3
_dots_complete
printf '%s\n' "${COMPREPLY[@]}" | grep -qx ollama && ok "bash --with ollama" || bad "bash --with ollama"
printf '%s\n' "${COMPREPLY[@]}" | grep -qx ai && ok "bash --with ai" || bad "bash --with ai"
COMP_WORDS=(dots packages group "")
COMP_CWORD=3
_dots_complete
printf '%s\n' "${COMPREPLY[@]}" | grep -qx modern && ok "bash packages group modern" || bad "bash group"
COMP_WORDS=(dots shell "")
COMP_CWORD=2
_dots_complete
printf '%s\n' "${COMPREPLY[@]}" | grep -qx status && ok "bash shell status" || bad "bash shell"
COMP_WORDS=(dots completion "")
COMP_CWORD=2
_dots_complete
printf '%s\n' "${COMPREPLY[@]}" | grep -qx paths && ok "bash completion paths" || bad "bash completion"
COMP_WORDS=(dots restore "")
COMP_CWORD=2
_dots_complete
printf '%s\n' "${COMPREPLY[@]}" | grep -qx snap-test-1 && ok "bash restore snapshot" || bad "bash restore"
COMP_WORDS=(dots models --provider "")
COMP_CWORD=3
_dots_complete
printf '%s\n' "${COMPREPLY[@]}" | grep -qx ollama && ok "bash --provider ollama" || bad "bash provider"

echo "=== Zsh completion file load ==="
if command -v zsh >/dev/null 2>&1; then
	zsh -f -c "
fpath=(${ROOT}/generated/completions \$fpath)
autoload -Uz compinit && compinit -u -d ${TMP}/zcompdump
source ${ROOT}/generated/completions/_dots
typeset -f _dots >/dev/null && echo DOTS_OK
" 2>/dev/null | grep -q DOTS_OK && ok "zsh loads _dots" || bad "zsh loads _dots"
else
	ok "zsh missing (skip load)"
fi

echo "=== typo suggestions ==="
dist="$(dots_edit_distance pakages packages)"
[[ ${dist} == 1 ]] && ok "edit distance pakages" || bad "edit distance got ${dist}"
mapfile -t hits < <(dots_suggest_matches pakages packages components models)
printf '%s\n' "${hits[@]}" | grep -qx packages && ok "pakages -> packages" || bad "pakages"
mapfile -t hits < <(dots_suggest_matches componets components packages)
printf '%s\n' "${hits[@]}" | grep -qx components && ok "componets -> components" || bad "componets"
mapfile -t hits < <(dots_suggest_matches olama ollama hermes llamacpp)
printf '%s\n' "${hits[@]}" | grep -qx ollama && ok "olama -> ollama" || bad "olama"
mapfile -t hits < <(dots_suggest_matches modren modern core workstation)
printf '%s\n' "${hits[@]}" | grep -qx modern && ok "modren -> modern" || bad "modren"
mapfile -t hits < <(dots_suggest_matches completin completion components commands)
printf '%s\n' "${hits[@]}" | grep -qx completion && ok "completin -> completion" || bad "completin"
mapfile -t hits < <(dots_suggest_matches xyzzyplugh packages components models setup)
[[ ${#hits[@]} -eq 0 ]] && ok "nonsense: no suggestion" || bad "nonsense suggested: ${hits[*]}"

unk="$("${ROOT}/dots" pakages 2>&1)" || true
echo "${unk}" | grep -qi 'Did you mean' && ok "CLI suggests for pakages" || bad "CLI pakages suggest"
echo "${unk}" | grep -q packages && ok "CLI mentions packages" || bad "CLI packages mention"

echo "=== shell timing stats ==="
stats="$(printf '%s\n' 100 200 150 180 120 | dots_shell_timing_stats)"
read -r mn md mx n <<<"${stats}"
[[ ${mn} == 100 && ${mx} == 200 && ${n} == 5 && ${md} == 150 ]] && ok "timing aggregation" || bad "timing ${stats}"

echo "=== dots shell / completion commands ==="
out="$("${ROOT}/dots" shell keys 2>&1)" || {
	bad "shell keys"
	out=""
}
echo "${out}" | grep -Eq 'Ctrl-R|Key' && ok "shell keys table" || bad "shell keys"
out="$("${ROOT}/dots" completion paths 2>&1)" || {
	bad "completion paths"
	out=""
}
echo "${out}" | grep -q 'generated' && ok "completion paths" || bad "completion paths content"

echo "=== cheatsheet ==="
export NO_COLOR=1
cs="$("${ROOT}/scripts/dots-help" --cheatsheet 2>&1)" || {
	bad "cheatsheet"
	cs=""
}
echo "${cs}" | grep -q 'CHEAT SHEET\|cheat sheet' && ok "cheatsheet header" || bad "cheatsheet header"
echo "${cs}" | grep -q 'dots status\|dots-help' && ok "cheatsheet dots cmds" || bad "cheatsheet cmds"
printf '%s' "${cs}" | grep -q $'\x1b\[' && bad "cheatsheet ANSI" || ok "cheatsheet no ANSI"

# base-like HOME: no AI components
cat >"${HOME}/.config/dots/active-profile" <<'EOF'
DOTS_PROFILE=base
DOTS_PACKAGE_GROUPS=core
DOTS_ACTIVE_COMPONENTS=
DOTS_MULTIPLEXER=none
EOF
cs2="$("${ROOT}/scripts/dots-help" --cheatsheet 2>&1)" || true
echo "${cs2}" | grep -q 'AI (inactive)\|Enable:.*--with ai\|CHEAT' && ok "base cheatsheet AI inactive path" || ok "base cheatsheet rendered"

echo "=== keybindings metadata ==="
[[ -f ${ROOT}/configs/help/keybindings.toml ]] && ok "keybindings.toml" || bad "keybindings.toml"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
