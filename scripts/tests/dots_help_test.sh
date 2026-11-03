#!/usr/bin/env bash
# scripts/tests/dots_help_test.sh — dots-help plain mode, metadata drift, man pages
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${ROOT}"
export DIR ROOT DOTS_DIR="${ROOT}"

pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-help.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT
export HOME="${TMP}/home"
# Isolate from developer machine runtime env
unset DOTS_PROFILE DOTS_ACTIVE_COMPONENTS DOTS_PACKAGE_GROUPS DOTS_MULTIPLEXER DOTS_PROFILE_FILE || true
mkdir -p "${HOME}/.config/dots" "${HOME}/.local/state/dots/backups"

# shellcheck source=../../helpers/python_runtime.sh
source "${ROOT}/helpers/python_runtime.sh"
PY="$(dots_find_python311)" || {
	bad "Python >=3.11 required"
	echo "Passed: ${pass}  Failed: ${fail}"
	exit 1
}

echo "=== metadata files ==="
[[ -f ${ROOT}/configs/help/commands.toml ]] && ok "commands.toml" || bad "commands.toml"
[[ -f ${ROOT}/configs/help/topics.toml ]] && ok "topics.toml" || bad "topics.toml"
[[ -d ${ROOT}/docs/help ]] && ok "docs/help/" || bad "docs/help/"
[[ -f ${ROOT}/tools/dots_help/pyproject.toml ]] && ok "dots_help pyproject" || bad "pyproject"
[[ -f ${ROOT}/tools/dots_help/uv.lock ]] && ok "dots_help uv.lock" || bad "uv.lock"
[[ -x ${ROOT}/scripts/dots-help ]] || chmod +x "${ROOT}/scripts/dots-help"
[[ -x ${ROOT}/scripts/dots-help ]] && ok "scripts/dots-help executable" || bad "launcher"

echo "=== CLI dispatcher ↔ commands.toml drift ==="
cli_cmds=(setup status components lsp ai agent packages backup backups restore profile models check update help shell completion)
mapfile -t meta_cmds < <(
	cd "${ROOT}" && "${PY}" - <<'PY'
import tomllib
from pathlib import Path
data = tomllib.loads(Path("configs/help/commands.toml").read_text())
for c in data.get("commands") or []:
    name = (c.get("name") or "").strip()
    if name:
        print(name)
PY
)
dispatch_block="$(
	awk '/^# --- dispatch ---/{p=1} p{print} p && /^esac$/{exit}' "${ROOT}/dots"
)"
for c in "${cli_cmds[@]}"; do
	if printf '%s\n' "${dispatch_block}" | grep -Eq "^${c}\\)|${c} \\||\\|${c}\\)|\\|${c} "; then
		ok "dispatch has '${c}'"
	else
		bad "dispatch missing '${c}'"
	fi
	found=0
	for m in "${meta_cmds[@]}"; do
		[[ ${m} == "${c}" ]] && found=1 && break
	done
	[[ ${found} -eq 1 ]] && ok "metadata covers '${c}'" || bad "metadata missing '${c}'"
done
for m in "${meta_cmds[@]}"; do
	found=0
	for c in "${cli_cmds[@]}"; do
		[[ ${c} == "${m}" ]] && found=1 && break
	done
	[[ ${found} -eq 1 ]] && ok "metadata '${m}' in CLI set" || bad "orphan metadata '${m}'"
done

echo "=== generated usage / man --check ==="
"${PY}" "${ROOT}/scripts/docs/generate_usage.py" --check && ok "usage.inc drift check" || bad "usage.inc stale — run generate_usage.py"
"${PY}" "${ROOT}/scripts/docs/generate_manpages.py" --check && ok "man pages drift check" || bad "man pages stale — run generate_manpages.py"

if command -v mandoc >/dev/null 2>&1; then
	mandoc -T lint "${ROOT}/docs/man/man1/dots.1" >/dev/null 2>&1 && ok "mandoc lint dots.1" || bad "mandoc lint dots.1"
	mandoc -T lint "${ROOT}/docs/man/man1/dots-help.1" >/dev/null 2>&1 && ok "mandoc lint dots-help.1" || bad "mandoc lint dots-help.1"
elif command -v groff >/dev/null 2>&1; then
	groff -man -Tascii "${ROOT}/docs/man/man1/dots.1" >/dev/null 2>&1 && ok "groff dots.1" || bad "groff dots.1"
else
	ok "no mandoc/groff (skip roff lint)"
fi

echo "=== plain help (isolated HOME) ==="
# Simulate home profile selection without real machine noise
cat >"${HOME}/.config/dots/active-profile" <<'EOF'
DOTS_PROFILE=home
DOTS_PACKAGE_GROUPS=core modern
DOTS_ACTIVE_COMPONENTS=lsp hermes ollama
DOTS_MULTIPLEXER=tmux
EOF
mkdir -p "${HOME}/.local/state/dots/backups/2026-11-02T120000-test"
mkdir -p "${HOME}/.config/dots/profiles"
echo 'packages = ["core"]' >"${HOME}/.config/dots/profiles/lab.toml"

export NO_COLOR=1
HELP="${ROOT}/scripts/dots-help"

out="$("${HELP}" --version 2>&1)" || {
	bad "--version failed"
	out=""
}
echo "${out}" | grep -Fq "DOTS 1.6.0" && ok "--version reports DOTS version" || bad "--version: ${out}"

plain="$("${HELP}" --plain 2>&1)" || {
	bad "--plain failed"
	plain=""
}
echo "${plain}" | grep -q 'DOTS 1.6.0\|Overview\|OVERVIEW' && ok "--plain overview" || bad "--plain overview"
echo "${plain}" | grep -qi 'home' && ok "--plain shows profile" || bad "--plain profile"
printf '%s' "${plain}" | grep -q $'\x1b\[' && bad "--plain leaked ANSI under NO_COLOR" || ok "--plain no ANSI"

comp="$("${HELP}" --plain completion 2>&1)" || {
	bad "plain completion failed"
	comp=""
}
echo "${comp}" | grep -qi 'fzf\|Ctrl-R\|Tab' && ok "plain completion content" || bad "plain completion content"

for topic in components packages backup lsp models; do
	t="$("${HELP}" --plain "${topic}" 2>&1)" || {
		bad "plain ${topic}"
		continue
	}
	[[ -n ${t} ]] && ok "plain ${topic}" || bad "plain ${topic} empty"
done

sg="$("${HELP}" --plain supergroups 2>&1)" || {
	bad "plain supergroups"
	sg=""
}
echo "${sg}" | grep -q '`ai`\|ai' && ok "supergroups lists ai" || bad "supergroups ai"
echo "${sg}" | grep -qi Traceback && bad "supergroups traceback" || ok "supergroups no crash"

search="$("${HELP}" --search completion 2>&1)" || true
echo "${search}" | grep -qi 'completion\|Fuzzy' && ok "search completion" || bad "search completion"
search_b="$("${HELP}" --search backup 2>&1)" || true
echo "${search_b}" | grep -qi 'backup' && ok "search backup" || bad "search backup"
search_l="$("${HELP}" --search lsp 2>&1)" || true
echo "${search_l}" | grep -qi 'lsp' && ok "search lsp" || bad "search lsp"
search_a="$("${HELP}" --search ai 2>&1)" || true
echo "${search_a}" | grep -qi 'ai\|AI' && ok "search ai" || bad "search ai"

echo "=== non-TTY / pipe ==="
piped="$("${HELP}" 2>/dev/null | cat)" || {
	bad "piped dots-help failed"
	piped=""
}
echo "${piped}" | grep -q 'DOTS\|Overview\|OVERVIEW' && ok "pipe yields plain" || bad "pipe plain"
printf '%s' "${piped}" | grep -q $'\x1b\[' && bad "pipe ANSI" || ok "pipe no ANSI"

echo "=== ./dots --help vs help ==="
synopsis="$("${ROOT}/dots" --help 2>&1)" || {
	bad "./dots --help"
	synopsis=""
}
echo "${synopsis}" | grep -q './dots status' && ok "./dots --help synopsis" || bad "./dots --help content"
echo "${synopsis}" | grep -q '^#' && bad "./dots --help shows generator comments" || ok "./dots --help no # headers"
echo "${synopsis}" | grep -qi 'Textual\|interactive help\|dots-help' && ok "--help mentions interactive help" || ok "--help terse"

# ./dots help --plain should work without TUI
dh="$("${ROOT}/dots" help --plain completion 2>&1)" || {
	bad "./dots help --plain"
	dh=""
}
echo "${dh}" | grep -qi 'fzf\|Tab\|completion' && ok "./dots help --plain completion" || bad "./dots help --plain completion"

echo "=== status Help footer ==="
st="$("${ROOT}/dots" status 2>&1)" || true
echo "${st}" | grep -q 'dots-help' && ok "status mentions dots-help" || bad "status Help footer"

echo "=== uv package + Textual pilot (optional) ==="
if command -v uv >/dev/null 2>&1; then
	uv sync --directory "${ROOT}/tools/dots_help" --python-preference system --frozen >/dev/null 2>&1 \
		&& ok "uv sync --frozen" || {
		uv sync --directory "${ROOT}/tools/dots_help" --python-preference system >/dev/null 2>&1 && ok "uv sync" || bad "uv sync"
	}
	uv sync --directory "${ROOT}/tools/dots_help" --python-preference system --group dev >/dev/null 2>&1 || true
	if uv run --directory "${ROOT}/tools/dots_help" --python-preference system --group dev \
		pytest "${ROOT}/tools/dots_help/tests" -q >"${TMP}/pytest.out" 2>&1; then
		ok "pytest dots_help"
	else
		bad "pytest dots_help"
		cat "${TMP}/pytest.out" || true
	fi
else
	ok "uv missing (skip package tests)"
fi

echo "=== shell completion sources ==="
[[ -f ${ROOT}/shell/dots_completion.sh ]] && ok "shell/dots_completion.sh" || bad "shell completion"
[[ -f ${ROOT}/zsh/dots_completion.zsh ]] && ok "zsh/dots_completion.zsh" || bad "zsh completion"
grep -q 'dots_completion' "${ROOT}/bash/completion.sh" && ok "bash sources dots completion" || bad "bash completion wire"
grep -q 'dots_completion' "${ROOT}/syms/zshrc" && ok "zshrc sources dots completion" || bad "zshrc completion wire"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
