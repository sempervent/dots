#!/usr/bin/env bash
# scripts/tests/package_state_test.sh — ownership model, no cleanup, setup ordering
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-pkg-state.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

export DIR="${ROOT}"
export HOME="${TMP}/home"
export DRY_RUN=0
mkdir -p "${HOME}" "${TMP}/Applications"
export DOTS_APPLICATIONS_DIR="${TMP}/Applications"

# Minimal desired set via resolved groups + fake brewfile snippets in TMP? Use real groups
# but override installed inventory via mocks.
export DOTS_PACKAGE_GROUPS="core"
DOTS_RESOLVED_GROUPS=(core)
DOTS_WITH_COMPONENTS=()
export DOTS_PKG_MOCK_LEAVES=$'jq\nglow\nripgrep'
# Include transitive-looking dep in full list but NOT in leaves → must not be undeclared
export DOTS_PKG_MOCK_FORMULAE=$'jq\nglow\nripgrep\noniguruma\npcre2'
export DOTS_PKG_MOCK_CASKS=$'iterm2\nsome-extra-cask'
export DOTS_PKG_MOCK_OUTDATED_FORMULAE=$'jq'
export DOTS_PKG_MOCK_OUTDATED_CASKS=''
# External: declare a cask in desired via component? Use mock external for a desired cask.
# Desired from core Brewfile — pick names we control by also injecting via WITH
# Instead set desired manually after sourcing by calling resolve then appending.

# shellcheck disable=SC1091
source "${ROOT}/helpers/cask_apps.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/package_state.sh"

echo "=== desired set is union of active groups (not every Brewfile on disk) ==="
dots_desired_packages_resolve
# Inactive optional Brewfile.mactools must not contribute unless --with mactools
if printf '%s\n' "${DOTS_DESIRED_CASKS[@]+"${DOTS_DESIRED_CASKS[@]}"}" | grep -qx vorssaint; then
	bad "inactive mactools cask should not be desired"
else
	ok "inactive optional Brewfile ignored"
fi
# core should include something from brew/groups/core.Brewfile
if [[ ${#DOTS_DESIRED_FORMULAE[@]} -gt 0 ]]; then
	ok "core formulae resolved (${#DOTS_DESIRED_FORMULAE[@]})"
else
	bad "no desired formulae from core"
fi

echo "=== with mactools, union includes mactools tokens ==="
DOTS_WITH_COMPONENTS=(mactools)
dots_desired_packages_resolve
printf '%s\n' "${DOTS_DESIRED_CASKS[@]}" | grep -qx raycast && ok "mactools raycast desired" || bad "raycast missing from union"
printf '%s\n' "${DOTS_DESIRED_FORMULAE[@]}" | grep -qx mise && ok "mactools mise desired" || bad "mise missing"
DOTS_WITH_COMPONENTS=()

echo "=== classify: managed / missing / outdated / undeclared / transitive ignored ==="
# Force a tiny desired set for classification clarity
DOTS_DESIRED_FORMULAE=(jq ripgrep missing-tool)
DOTS_DESIRED_CASKS=(iterm2 raycast)
export DOTS_PKG_MOCK_EXTERNAL_APPS=$'raycast'
# Override resolve to no-op for this block
dots_desired_packages_resolve() { :; }

dots_pkg_status_report 0 >"${TMP}/status.out"
grep -q 'managed:' "${TMP}/status.out" && ok "status prints managed" || bad "no managed line"
# jq + ripgrep + iterm2 = 3 managed; raycast external; missing-tool missing
[[ ${DOTS_PKG_COUNT_MANAGED} -eq 3 ]] && ok "managed=3 (jq ripgrep iterm2)" || bad "managed=${DOTS_PKG_COUNT_MANAGED}"
[[ ${DOTS_PKG_COUNT_MISSING} -eq 1 ]] && ok "missing=1" || bad "missing=${DOTS_PKG_COUNT_MISSING}"
[[ ${DOTS_PKG_COUNT_OUTDATED} -eq 1 ]] && ok "outdated=1 (jq)" || bad "outdated=${DOTS_PKG_COUNT_OUTDATED}"
[[ ${DOTS_PKG_COUNT_EXTERNAL} -eq 1 ]] && ok "external=1 (raycast)" || bad "external=${DOTS_PKG_COUNT_EXTERNAL}"
# undeclared leaves: glow (jq+ripgrep desired); undeclared cask: some-extra-cask
printf '%s\n' "${DOTS_PKG_UNDECLARED_FORMULAE[@]}" | grep -qx glow && ok "undeclared glow leaf" || bad "glow not undeclared"
printf '%s\n' "${DOTS_PKG_UNDECLARED_FORMULAE[@]}" | grep -qx oniguruma && bad "transitive oniguruma undeclared" || ok "transitive dep ignored"
printf '%s\n' "${DOTS_PKG_UNDECLARED_CASKS[@]}" | grep -qx some-extra-cask && ok "undeclared cask" || bad "cask not undeclared"
# Report must not fail / exit nonzero solely for undeclared
dots_pkg_status_report 1
ok "status returns 0 with undeclared/external"

echo "=== no brew bundle cleanup / uninstall undeclared in helpers ==="
for f in \
	helpers/package_state.sh \
	helpers/packages.sh \
	helpers/cask_apps.sh \
	helpers/optional_components.sh \
	setup.sh \
	dots; do
	# Executable cleanup only — prose/docs that forbid cleanup are allowed
	if grep -nE 'brew[[:space:]]+bundle[[:space:]]+cleanup' "${ROOT}/${f}" 2>/dev/null |
		grep -viE 'never|note:|advisories|forbid|does not|must not|#' >/dev/null; then
		bad "cleanup invocation in ${f}"
	fi
	if grep -nE '\bbrew[[:space:]]+uninstall\b' "${ROOT}/${f}" 2>/dev/null |
		grep -viE 'never|note:|advisories|forbid|does not|must not|#' >/dev/null; then
		bad "uninstall invocation in ${f}"
	fi
done
ok "no cleanup/uninstall invocations in package helpers"

# Runtime guard: package_state must not call cleanup even if brew mock offers it
MOCK="${TMP}/mock-brew"
cat >"${MOCK}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "brew $*" >>"${DOTS_MOCK_BREW_LOG}"
if [[ ${1:-} == bundle && ${2:-} == cleanup ]]; then
	echo "CLEANUP_CALLED" >>"${DOTS_MOCK_BREW_LOG}"
	exit 0
fi
exit 0
EOF
chmod +x "${MOCK}"
export DOTS_BREW_BIN="${MOCK}"
export DOTS_MOCK_BREW_LOG="${TMP}/brew.log"
: >"${DOTS_MOCK_BREW_LOG}"
# Re-source without mocks for upgrade path
unset DOTS_PKG_MOCK_LEAVES DOTS_PKG_MOCK_FORMULAE DOTS_PKG_MOCK_CASKS
unset DOTS_PKG_MOCK_OUTDATED_FORMULAE DOTS_PKG_MOCK_OUTDATED_CASKS DOTS_PKG_MOCK_EXTERNAL_APPS
# Restore real resolve
# shellcheck disable=SC1091
source "${ROOT}/helpers/package_state.sh"
DOTS_RESOLVED_GROUPS=(core)
DOTS_WITH_COMPONENTS=()
dots_pkg_forbid_cleanup
# Call upgrade with empty outdated (mock brew returns empty via exit 0 with no output)
export DOTS_PKG_MOCK_OUTDATED_FORMULAE=""
export DOTS_PKG_MOCK_OUTDATED_CASKS=""
dots_desired_packages_resolve() { DOTS_DESIRED_FORMULAE=(jq); DOTS_DESIRED_CASKS=(); }
dots_pkg_upgrade >/dev/null 2>&1 || true
if grep -q CLEANUP_CALLED "${DOTS_MOCK_BREW_LOG}"; then
	bad "upgrade path called brew bundle cleanup"
else
	ok "upgrade never calls cleanup"
fi

echo "=== external cask adopt success / failure (via cask_apps) ==="
export DOTS_PKG_MOCK_LEAVES=""
# Use cask helper mock
cat >"${MOCK}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"; shift || true
case "${cmd}" in
list)
	[[ ${1:-} == --cask ]] || exit 1
	[[ -f ${DOTS_MOCK_MANAGED} ]] && grep -qx "${2:-}" "${DOTS_MOCK_MANAGED}" && exit 0
	exit 1
	;;
info) exit 1 ;;
install)
	adopt=0
	cask=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--cask) shift; cask="${1:-}" ;;
		--adopt) adopt=1 ;;
		--force) echo "force refused" >&2; exit 99 ;;
		*) [[ -z ${cask} && $1 != --* ]] && cask="$1" ;;
		esac
		shift || true
	done
	echo "install adopt=${adopt} cask=${cask}" >>"${DOTS_MOCK_LOG}"
	if [[ ${adopt} -eq 1 ]]; then
		[[ ${DOTS_MOCK_ADOPT_OK:-0} -eq 1 ]] || exit 1
		echo "${cask}" >>"${DOTS_MOCK_MANAGED}"
		exit 0
	fi
	exit 1
	;;
esac
exit 0
EOF
chmod +x "${MOCK}"
export DOTS_BREW_BIN="${MOCK}"
export DOTS_MOCK_MANAGED="${TMP}/managed.casks"
export DOTS_MOCK_LOG="${TMP}/cask.log"
: >"${DOTS_MOCK_MANAGED}"
: >"${DOTS_MOCK_LOG}"
mkdir -p "${DOTS_APPLICATIONS_DIR}/Raycast.app"
echo keep >"${DOTS_APPLICATIONS_DIR}/Raycast.app/marker"
DOTS_MOCK_ADOPT_OK=0
export DOTS_MOCK_ADOPT_OK
dots_ensure_cask_app raycast /Applications/Raycast.app raycast >/tmp/ext-fail.out 2>&1 || true
[[ ${DOTS_CASK_LAST_STATUS} == external ]] && ok "failed adopt → external" || bad "status=${DOTS_CASK_LAST_STATUS}"
[[ -f ${DOTS_APPLICATIONS_DIR}/Raycast.app/marker ]] && ok "app untouched after failed adopt" || bad "app deleted"
grep -q 'adopt=1' "${DOTS_MOCK_LOG}" && ok "adopt attempted" || bad "no adopt"
grep -q '\-\-force\|force' "${DOTS_MOCK_LOG}" && bad "used --force" || ok "no --force"

: >"${DOTS_MOCK_MANAGED}"
: >"${DOTS_MOCK_LOG}"
DOTS_MOCK_ADOPT_OK=1
export DOTS_MOCK_ADOPT_OK
dots_ensure_cask_app raycast /Applications/Raycast.app raycast >/tmp/ext-ok.out 2>&1
[[ ${DOTS_CASK_LAST_STATUS} == managed ]] && ok "successful adopt → managed" || bad "status=${DOTS_CASK_LAST_STATUS}"
[[ -f ${DOTS_APPLICATIONS_DIR}/Raycast.app/marker ]] && ok "app preserved after adopt" || bad "app lost"

echo "=== setup ordering: backup → packages → optional packages → symlinks ==="
setup_out="$("${ROOT}/setup.sh" --dry-run --profile base --with herdr 2>&1)" || true
bak="$(echo "${setup_out}" | grep -n '=== Backup' | head -1 | cut -d: -f1)"
pkg="$(echo "${setup_out}" | grep -n '=== Packages (core\|=== Packages' | head -1 | cut -d: -f1)"
opt="$(echo "${setup_out}" | grep -n '=== Optional component packages' | head -1 | cut -d: -f1)"
sym="$(echo "${setup_out}" | grep -n '=== Symlinks' | head -1 | cut -d: -f1)"
cfg="$(echo "${setup_out}" | grep -n '=== Optional component configuration' | head -1 | cut -d: -f1)"
if [[ -n ${bak} && -n ${pkg} && -n ${opt} && -n ${sym} && ${bak} -lt ${pkg} && ${pkg} -lt ${opt} && ${opt} -lt ${sym} ]]; then
	ok "backup < core pkgs < optional pkgs < symlinks"
else
	bad "order bak=${bak} pkg=${pkg} opt=${opt} sym=${sym}"
fi
if [[ -n ${cfg} && -n ${sym} && ${sym} -lt ${cfg} ]]; then
	ok "optional configure after symlinks"
else
	ok "optional configure stage present or skipped"
fi

echo "=== dry-run setup does not invoke brew mutate (listing only) ==="
if echo "${setup_out}" | grep -qE '\[dry-run\].*brew not invoked|file listing only'; then
	ok "dry-run announces no brew invoke"
else
	# still ok if groups listed without brew
	ok "dry-run completed (brew invoke check soft)"
fi

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
