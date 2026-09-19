#!/usr/bin/env bash
# scripts/tests/optional_failure_summary_test.sh — named optional-component failures
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

TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

export DIR="${ROOT}"
export DRY_RUN=0
brew_failed=0
OPTIONAL_COMPONENT_FAILURES=()

# Minimal stubs
has_component() { [[ $1 == opencode || $1 == ollama ]]; }
apply_brewfile() {
	local f="$1"
	if [[ ${f} == *opencode* ]]; then
		echo "Warn: brew bundle failed for ${f}"
		return 1
	fi
	echo "OK: applied ${f}"
	return 0
}

# shellcheck disable=SC1091
source "${ROOT}/helpers/optional_components.sh"

# Only exercise failure recording helpers + print
OPTIONAL_COMPONENT_FAILURES=()
brew_failed=0
dots_optional_record_failure "opencode" "brew bundle failed"
dots_optional_record_failure "hermes-desktop" "cask installation failed"

# Use summary_* names: helpers/components.sh (pulled in for brewfile lookup) uses local -a out.
summary_out="$(dots_optional_print_failures 2>&1)"
echo "${summary_out}" | grep -q 'Optional component failures:' && ok "summary header" || bad "header"
echo "${summary_out}" | grep -q 'opencode' && ok "lists opencode" || bad "opencode"
echo "${summary_out}" | grep -q 'hermes-desktop' && ok "lists hermes-desktop" || bad "hermes-desktop"
[[ ${brew_failed} -eq 1 ]] && ok "brew_failed set" || bad "brew_failed"

# Integration: apply_optional with stubs
OPTIONAL_COMPONENT_FAILURES=()
brew_failed=0
DOTS_WITH_COMPONENTS=(opencode ollama)
# Re-source not needed; has_component/apply_brewfile already stubbed in this shell
# But apply_optional_brewfiles was already defined — call it
apply_optional_brewfiles
summary_out2="$(dots_optional_print_failures 2>&1)"
echo "${summary_out2}" | grep -q 'opencode' && ok "apply path records opencode" || {
	bad "apply path opencode"
	echo "${summary_out2}"
	printf '%s\n' "${OPTIONAL_COMPONENT_FAILURES[@]+"${OPTIONAL_COMPONENT_FAILURES[@]}"}"
}
echo "${summary_out2}" | grep -q 'ollama' && bad "ollama should not be listed" || ok "ollama not failed"
[[ ${brew_failed} -eq 1 ]] && ok "aggregate brew_failed" || bad "aggregate"

# Ensure setup.sh no longer uses only generic message
if grep -q 'optional component Brewfile(s) failed' "${ROOT}/setup.sh"; then
	bad "old generic-only error still present"
else
	ok "generic-only error removed"
fi
grep -q 'dots_optional_print_failures' "${ROOT}/setup.sh" && ok "setup prints failures" || bad "setup missing print"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
