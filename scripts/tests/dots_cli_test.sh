#!/usr/bin/env bash
# scripts/tests/dots_cli_test.sh — ./dots command surface (non-mutating)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() {
	echo "OK: $1"
	pass=$((pass + 1))
}
bad() {
	echo "FAIL: $1" >&2
	fail=$((fail + 1))
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-cli.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT
export HOME="${TMP}/home"
mkdir -p "${HOME}"

echo "=== dots CLI surface ==="

out="$("${ROOT}/dots" help 2>&1)" || {
	bad "help failed"
	out=""
}
echo "${out}" | grep -q 'interactive setup' && ok "help mentions interactive setup" || bad "help text"
echo "${out}" | grep -q './dots status' && ok "help lists status" || bad "help status"
echo "${out}" | grep -q 'bootstrap.sh' && ok "help mentions expert scripts" || bad "help experts"

ver="$("${ROOT}/dots" --version 2>&1)" || {
	bad "version failed"
	ver=""
}
echo "${ver}" | grep -Eq 'dots 1\.2\.0' && ok "version 1.2.0" || bad "version got: ${ver}"
[[ -f ${ROOT}/VERSION ]] && [[ $(tr -d '[:space:]' <"${ROOT}/VERSION") == 1.2.0 ]] && ok "VERSION file" || bad "VERSION file"

# status on fresh HOME (no active profile)
st="$("${ROOT}/dots" status 2>&1)" || true
echo "${st}" | grep -q 'DOTS Status' && ok "status header" || bad "status header"
echo "${st}" | grep -q '1.2.0' && ok "status shows version" || bad "status version"
echo "${st}" | grep -qi 'profile' && ok "status mentions profile" || bad "status profile"

# setup --help
sh="$("${ROOT}/dots" setup --help 2>&1)" || {
	bad "setup --help"
	sh=""
}
echo "${sh}" | grep -q -- '--dry-run' && ok "setup --help dry-run" || bad "setup help"

# Noninteractive bootstrap delegation
if "${ROOT}/dots" setup --profile base --yes --dry-run >"${TMP}/passthru.out" 2>&1; then
	ok "setup --profile base --yes --dry-run delegates"
	grep -qiE 'dry.run|Would|profile|base|Stage' "${TMP}/passthru.out" && ok "passthru dry-run output" || bad "passthru empty"
else
	bad "setup --profile --yes --dry-run failed"
	tail -20 "${TMP}/passthru.out" || true
fi

# Orchestration markers: dots must not be a second installer — it execs bootstrap
if grep -q 'exec.*bootstrap.sh' "${ROOT}/dots" || grep -q 'bootstrap.sh' "${ROOT}/helpers/wizard.sh"; then
	ok "dots delegates to bootstrap.sh"
else
	bad "dots missing bootstrap delegation"
fi
if grep -q 'pull_models.sh' "${ROOT}/dots" && grep -q 'pull_models.sh' "${ROOT}/helpers/wizard.sh"; then
	ok "dots delegates to pull_models.sh"
else
	bad "dots missing pull_models delegation"
fi
if grep -q 'check.sh' "${ROOT}/dots"; then
	ok "dots delegates to check.sh"
else
	bad "dots missing check delegation"
fi
# Must not embed package install loops (heuristic)
if grep -ERq 'brew install|apt-get install|pacman -S' "${ROOT}/dots" "${ROOT}/helpers/wizard.sh" "${ROOT}/helpers/ui.sh" "${ROOT}/helpers/state.sh"; then
	bad "dots embeds package install logic"
else
	ok "dots has no package-install duplication"
fi

# No required TUI deps
for dep in gum dialog fzf whiptail; do
	if grep -ERq "command -v ${dep}|require.*${dep}" "${ROOT}/dots" "${ROOT}/helpers/ui.sh" "${ROOT}/helpers/wizard.sh"; then
		bad "hard-requires ${dep}"
	else
		ok "no hard ${dep} dependency"
	fi
done

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
