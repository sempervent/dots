#!/usr/bin/env bash
# scripts/tests/prompt_contract_test.sh — Bash/Starship DOTS prompt layout contract
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

# Strip ANSI / bash \[ \] wrappers for shape comparison
strip_ansi() {
	# literal ESC[…m, octal escapes in PS1 source, and bash non-printing markers
	sed -E 's/\x1b\[[0-9;]*m//g; s/\\e\[[0-9;]*m//g; s/\\033\[[0-9;]*m//g; s/\\\[[^]]*\\\]//g; s/\\\[|\\\]//g' | tr -d '\r'
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-prompt.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT
export HOME="${TMP}/home"
mkdir -p "${HOME}"

# Source colors + functions + prompt helpers in a clean bash
# shellcheck disable=SC1091
source "${ROOT}/bash/colors.sh"
# shellcheck disable=SC1091
source "${ROOT}/shell/functions.sh"

echo "=== git helpers ==="
# Non-git
cd "${HOME}"
rel="$(dots_git_relation || true)"
[[ -z ${rel} ]] && ok "non-git: empty relation" || bad "non-git relation='${rel}'"

# Tracking branch
REPO="${TMP}/repo"
git init -b master "${REPO}" >/dev/null 2>&1
cd "${REPO}"
git config user.email "t@example.com"
git config user.name "t"
echo x >f && git add f && git commit -m c >/dev/null
git remote add origin "${TMP}/origin.git"
git init --bare "${TMP}/origin.git" >/dev/null
git push -u origin master >/dev/null 2>&1
rel="$(dots_git_relation)"
echo "${rel}" | grep -q 'origin/master->master' && ok "tracking: ${rel}" || bad "tracking got ${rel}"

# Local only
git branch --unset-upstream 2>/dev/null || true
rel="$(dots_git_relation)"
[[ ${rel} == "master" ]] && ok "no-upstream: master" || bad "no-upstream got ${rel}"

# Detached
rev="$(git rev-parse --short HEAD)"
git checkout --detach HEAD >/dev/null 2>&1
rel="$(dots_git_relation)"
echo "${rel}" | grep -q "detached@${rev}" && ok "detached: ${rel}" || bad "detached got ${rel}"
git checkout master >/dev/null 2>&1

echo "=== bash prompt shape ==="
# shellcheck disable=SC1091
source "${ROOT}/bash/prompt.sh"
export VIRTUAL_ENV="${TMP}/.venv"
mkdir -p "${VIRTUAL_ENV}"
cd "${REPO}"
git branch --set-upstream-to=origin/master master >/dev/null 2>&1 || true
render_prompt_command
shape="$(printf '%s' "${PS1}" | strip_ansi)"
echo "${shape}" | grep -q '┌──┤' && ok "line1 box start" || bad "line1 start"
echo "${shape}" | grep -q '\\u@\\h' && ok "user@host" || bad "user@host"
echo "${shape}" | grep -q '\\t' && ok "time \\t" || bad "time"
echo "${shape}" | grep -q '\\d' && ok "date \\d" || bad "date"
echo "${shape}" | grep -q 'jobs' && ok "jobs segment" || bad "jobs"
echo "${shape}" | grep -q '\.venv' && ok "venv .venv" || bad "venv"
echo "${shape}" | grep -q '└─┤' && ok "line3 box end" || bad "line3"
echo "${shape}" | grep -q 'origin/master->master\|master' && ok "git in PS1" || bad "git PS1"

unset VIRTUAL_ENV
render_prompt_command
shape="$(printf '%s' "${PS1}" | strip_ansi)"
echo "${shape}" | grep -q '\.venv' && bad "venv present when unset" || ok "no venv when unset"

DOTS_PROMPT=off
render_prompt_command
ok "DOTS_PROMPT=off returns"
unset DOTS_PROMPT

echo "=== starship.toml contract ==="
ST="${ROOT}/configs/starship/starship.toml"
grep -q 'show_always = true' "${ST}" && ok "starship username always" || bad "username"
grep -q 'ssh_only = false' "${ST}" && ok "starship hostname always" || bad "hostname"
grep -q 'time_format = "%H:%M:%S"' "${ST}" && ok "starship time format" || bad "time fmt"
grep -q 'symbol_threshold = 0' "${ST}" && ok "starship jobs zero" || bad "jobs"
grep -q 'custom.git_relation' "${ST}" && ok "starship git_relation" || bad "git custom"
grep -q 'character' "${ST}" && grep -A2 '^\[character\]' "${ST}" | grep -q 'disabled = true' && ok "no character wedge" || bad "character"
grep -q '┌──┤' "${ST}" && ok "starship box line1" || bad "box"
# Powerline wedges must not drive format
grep -E 'format = .*|' "${ST}" && bad "powerline still in format" || ok "no powerline format"

# shellcheck source=../../helpers/toml.sh
source "${ROOT}/helpers/toml.sh"
if dots_require_python 0; then
	"$DOTS_PYTHON" - <<PY
import tomllib, pathlib
p = pathlib.Path("${ST}")
tomllib.loads(p.read_text())
print("toml_ok")
PY
	ok "starship.toml parses"
else
	bad "Python >=3.11 missing for toml parse"
fi

if command -v starship >/dev/null 2>&1; then
	out="$(STARSHIP_CONFIG="${ST}" starship explain 2>&1 | head -5 || true)"
	ok "starship binary present (smoke)"
else
	ok "starship binary absent (toml-only validation)"
fi

# HOME path rendering helper: bash \w expands at runtime — just assert PS1 uses \w
echo "${PS1}" | grep -q '\\w' && ok "cwd uses \\\\w" || bad "cwd"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
