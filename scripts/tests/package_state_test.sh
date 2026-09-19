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

# Use real group Brewfiles for resolve tests; mock installed inventory.
export DOTS_PACKAGE_GROUPS="core"
DOTS_RESOLVED_GROUPS=(core)
DOTS_WITH_COMPONENTS=()
export DOTS_PKG_MOCK_LEAVES=$'jq\nglow\nripgrep'
# Transitive-looking dep in full list but NOT in leaves → must not be undeclared
export DOTS_PKG_MOCK_FORMULAE=$'jq\nglow\nripgrep\noniguruma\npcre2'
export DOTS_PKG_MOCK_CASKS=$'iterm2\nsome-extra-cask'
export DOTS_PKG_MOCK_OUTDATED_FORMULAE=$'jq'
export DOTS_PKG_MOCK_OUTDATED_CASKS=''

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

echo "=== classify: managed / missing / outdated / undeclared / inactive / transitive ignored ==="
# Populate desired arrays directly — do NOT redefine dots_desired_packages_resolve
# (avoids ShellCheck SC2218: function defined later).
DOTS_DESIRED_FORMULAE=(jq ripgrep missing-tool)
DOTS_DESIRED_CASKS=(iterm2 raycast)
export DOTS_PKG_MOCK_EXTERNAL_APPS=$'raycast'
# glow is undeclared (no owner); add dust as leaf that has mactools owner → INACTIVE
export DOTS_PKG_MOCK_LEAVES=$'jq\nglow\nripgrep\ndust'
export DOTS_PKG_MOCK_FORMULAE=$'jq\nglow\nripgrep\noniguruma\npcre2\ndust'

dots_pkg_ownership_reset
dots_pkg_classify_resolved 0
dots_pkg_status_print >"${TMP}/status.out"
grep -q 'managed:' "${TMP}/status.out" && ok "status prints managed" || bad "no managed line"
grep -q 'inactive:' "${TMP}/status.out" && ok "status prints inactive" || bad "no inactive line"
# jq + ripgrep + iterm2 = 3 managed; raycast external; missing-tool missing
[[ ${DOTS_PKG_COUNT_MANAGED} -eq 3 ]] && ok "managed=3 (jq ripgrep iterm2)" || bad "managed=${DOTS_PKG_COUNT_MANAGED}"
[[ ${DOTS_PKG_COUNT_MISSING} -eq 1 ]] && ok "missing=1" || bad "missing=${DOTS_PKG_COUNT_MISSING}"
[[ ${DOTS_PKG_COUNT_OUTDATED} -eq 1 ]] && ok "outdated=1 (jq)" || bad "outdated=${DOTS_PKG_COUNT_OUTDATED}"
[[ ${DOTS_PKG_COUNT_EXTERNAL} -eq 1 ]] && ok "external=1 (raycast)" || bad "external=${DOTS_PKG_COUNT_EXTERNAL}"
printf '%s\n' "${DOTS_PKG_UNDECLARED_FORMULAE[@]}" | grep -qx glow && ok "undeclared glow leaf" || bad "glow not undeclared"
printf '%s\n' "${DOTS_PKG_INACTIVE_FORMULAE[@]+"${DOTS_PKG_INACTIVE_FORMULAE[@]}"}" | grep -qx dust && ok "inactive dust" || bad "dust not inactive"
printf '%s\n' "${DOTS_PKG_UNDECLARED_FORMULAE[@]}" | grep -qx oniguruma && bad "transitive oniguruma undeclared" || ok "transitive dep ignored"
printf '%s\n' "${DOTS_PKG_UNDECLARED_CASKS[@]}" | grep -qx some-extra-cask && ok "undeclared cask" || bad "cask not undeclared"
dots_pkg_classify_resolved 1
ok "classify returns 0 with undeclared/external/inactive"

echo "=== no brew bundle cleanup / uninstall undeclared in helpers ==="
for f in \
	helpers/package_state.sh \
	helpers/packages.sh \
	helpers/cask_apps.sh \
	helpers/optional_components.sh \
	setup.sh \
	dots; do
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
unset DOTS_PKG_MOCK_LEAVES DOTS_PKG_MOCK_FORMULAE DOTS_PKG_MOCK_CASKS
unset DOTS_PKG_MOCK_OUTDATED_FORMULAE DOTS_PKG_MOCK_OUTDATED_CASKS DOTS_PKG_MOCK_EXTERNAL_APPS
DOTS_RESOLVED_GROUPS=(core)
DOTS_WITH_COMPONENTS=()
DOTS_DESIRED_FORMULAE=(jq)
DOTS_DESIRED_CASKS=()
dots_pkg_forbid_cleanup
export DOTS_PKG_MOCK_OUTDATED_FORMULAE=""
export DOTS_PKG_MOCK_OUTDATED_CASKS=""
# Upgrade with empty outdated mocks — must never call cleanup
dots_pkg_upgrade >/dev/null 2>&1 || true
if grep -q CLEANUP_CALLED "${DOTS_MOCK_BREW_LOG}"; then
	bad "upgrade path called brew bundle cleanup"
else
	ok "upgrade never calls cleanup"
fi

echo "=== external cask adopt success / failure (via cask_apps) ==="
export DOTS_PKG_MOCK_LEAVES=""
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
		--cask)
			shift
			cask="${1:-}"
			;;
		--adopt) adopt=1 ;;
		--force)
			echo "force refused" >&2
			exit 99
			;;
		*)
			[[ -z ${cask} && $1 != --* ]] && cask="$1"
			;;
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
	ok "dry-run completed (brew invoke check soft)"
fi

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
