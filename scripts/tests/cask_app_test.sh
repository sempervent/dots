#!/usr/bin/env bash
# scripts/tests/cask_app_test.sh — GUI cask satisfaction without --force / overwrite
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-cask.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

export DIR="${ROOT}"
export DRY_RUN=0
export NO_INSTALL=0
export DOTS_APPLICATIONS_DIR="${TMP}/Applications"
mkdir -p "${DOTS_APPLICATIONS_DIR}"

MOCK_BREW="${TMP}/mock-brew"
cat >"${MOCK_BREW}" <<'EOF'
#!/usr/bin/env bash
# Mock brew controlled by DOTS_MOCK_BREW_* env files/flags
set -euo pipefail
cmd="${1:-}"
shift || true
case "${cmd}" in
list)
	# brew list --cask <token>
	if [[ ${1:-} == --cask ]]; then
		token="${2:-}"
		if [[ -f ${DOTS_MOCK_MANAGED:-/dev/null} ]] && grep -qx "${token}" "${DOTS_MOCK_MANAGED}"; then
			exit 0
		fi
		exit 1
	fi
	exit 1
	;;
install)
	# brew install [--adopt] --cask <token>
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
			echo "ERROR: mock brew refused --force" >&2
			exit 99
			;;
		*)
			# trailing token if not using --cask form
			[[ -z ${cask} && $1 != --* ]] && cask="$1"
			;;
		esac
		shift || true
	done
	mkdir -p "${DOTS_MOCK_LOG%/*}"
	echo "install adopt=${adopt} cask=${cask}" >>"${DOTS_MOCK_LOG}"
	if [[ ${adopt} -eq 1 ]]; then
		if [[ ${DOTS_MOCK_ADOPT_OK:-0} -eq 1 ]]; then
			echo "${cask}" >>"${DOTS_MOCK_MANAGED}"
			exit 0
		fi
		echo "Error: adopt failed for ${cask}" >&2
		exit 1
	fi
	if [[ ${DOTS_MOCK_INSTALL_OK:-0} -eq 1 ]]; then
		app_name=""
		case "${cask}" in
		hermes-desktop) app_name="Hermes.app" ;;
		fluidvoice) app_name="FluidVoice.app" ;;
		*) app_name="${cask}.app" ;;
		esac
		mkdir -p "${DOTS_APPLICATIONS_DIR}/${app_name}"
		echo "${cask}" >>"${DOTS_MOCK_MANAGED}"
		exit 0
	fi
	if [[ -d ${DOTS_APPLICATIONS_DIR}/Hermes.app && ${cask} == hermes-desktop ]]; then
		echo "Error: hermes-desktop: It seems there is already an App at '${DOTS_APPLICATIONS_DIR}/Hermes.app'." >&2
		exit 1
	fi
	if [[ -d ${DOTS_APPLICATIONS_DIR}/FluidVoice.app && ${cask} == fluidvoice ]]; then
		echo "Error: fluidvoice: It seems there is already an App at '${DOTS_APPLICATIONS_DIR}/FluidVoice.app'." >&2
		exit 1
	fi
	echo "Error: Installation of ${cask} failed" >&2
	exit 1
	;;
*)
	exit 0
	;;
esac
EOF
chmod +x "${MOCK_BREW}"

export DOTS_BREW_BIN="${MOCK_BREW}"
export DOTS_MOCK_MANAGED="${TMP}/managed.casks"
export DOTS_MOCK_LOG="${TMP}/brew.log"
export DOTS_MOCK_INSTALL_OK=0
export DOTS_MOCK_ADOPT_OK=0
: >"${DOTS_MOCK_MANAGED}"
: >"${DOTS_MOCK_LOG}"

# shellcheck disable=SC1091
source "${ROOT}/helpers/cask_apps.sh"

echo "=== A: cask installed and app exists ==="
mkdir -p "${DOTS_APPLICATIONS_DIR}/Hermes.app"
echo hermes-desktop >"${DOTS_MOCK_MANAGED}"
: >"${DOTS_MOCK_LOG}"
if dots_ensure_cask_app hermes-desktop /Applications/Hermes.app "Hermes.app" >/tmp/cask-a.out 2>&1; then
	[[ ${DOTS_CASK_LAST_STATUS} == managed ]] && ok "A managed success" || bad "A status=${DOTS_CASK_LAST_STATUS}"
	grep -q 'install' "${DOTS_MOCK_LOG}" && bad "A should not reinstall" || ok "A no reinstall"
else
	bad "A should succeed"
fi

echo "=== B: cask installed, app artifact missing ==="
: >"${DOTS_MOCK_MANAGED}"
echo hermes-desktop >"${DOTS_MOCK_MANAGED}"
rm -rf "${DOTS_APPLICATIONS_DIR}/Hermes.app"
: >"${DOTS_MOCK_LOG}"
if dots_ensure_cask_app hermes-desktop /Applications/Hermes.app "Hermes.app" >/tmp/cask-b.out 2>&1; then
	[[ ${DOTS_CASK_LAST_STATUS} == managed ]] && ok "B managed still OK (brew owns cask)" || bad "B status"
else
	bad "B should succeed when brew-managed"
fi

echo "=== C: app exists, cask not managed (Hermes regression) ==="
mkdir -p "${DOTS_APPLICATIONS_DIR}/Hermes.app"
echo "sentinel" >"${DOTS_APPLICATIONS_DIR}/Hermes.app/Contents"
: >"${DOTS_MOCK_MANAGED}"
: >"${DOTS_MOCK_LOG}"
DOTS_MOCK_INSTALL_OK=0
if dots_ensure_cask_app hermes-desktop /Applications/Hermes.app "Hermes.app" >/tmp/cask-c.out 2>&1; then
	[[ ${DOTS_CASK_LAST_STATUS} == external ]] && ok "C external success" || bad "C status=${DOTS_CASK_LAST_STATUS}"
	grep -q 'install' "${DOTS_MOCK_LOG}" && bad "C must not brew install" || ok "C no brew install"
	[[ -f ${DOTS_APPLICATIONS_DIR}/Hermes.app/Contents ]] && ok "C app untouched" || bad "C app mutated"
	grep -q 'leaving it untouched' /tmp/cask-c.out && ok "C message" || bad "C message"
else
	bad "C Hermes external should succeed"
	cat /tmp/cask-c.out
fi

echo "=== D: neither exists, install succeeds ==="
rm -rf "${DOTS_APPLICATIONS_DIR}/Hermes.app"
: >"${DOTS_MOCK_MANAGED}"
: >"${DOTS_MOCK_LOG}"
export DOTS_MOCK_INSTALL_OK=1
if dots_ensure_cask_app hermes-desktop /Applications/Hermes.app "Hermes.app" >/tmp/cask-d.out 2>&1; then
	[[ ${DOTS_CASK_LAST_STATUS} == installed ]] && ok "D installed" || bad "D status=${DOTS_CASK_LAST_STATUS}"
	[[ -d ${DOTS_APPLICATIONS_DIR}/Hermes.app ]] && ok "D app created" || bad "D no app"
else
	bad "D should succeed"
	cat /tmp/cask-d.out || true
fi

echo "=== E: neither exists, install fails ==="
rm -rf "${DOTS_APPLICATIONS_DIR}/Hermes.app"
: >"${DOTS_MOCK_MANAGED}"
: >"${DOTS_MOCK_LOG}"
export DOTS_MOCK_INSTALL_OK=0
if dots_ensure_cask_app hermes-desktop /Applications/Hermes.app "Hermes.app" >/tmp/cask-e.out 2>&1; then
	bad "E should fail"
else
	[[ ${DOTS_CASK_LAST_STATUS} == failed ]] && ok "E failed status" || bad "E status=${DOTS_CASK_LAST_STATUS}"
fi

echo "=== F: app exists after conflict; adopt fails → external OK ==="
# Simulate: missing at check time is hard; instead invoke post-fail path by
# having app present but forcing install attempt via temporarily hiding it...
# Direct path: app present → C. For adopt-after-fail: remove from early path by
# calling install failure when app appears mid-flight — create app then call with
# a wrapper. Simpler: create app, empty managed, ensure returns external (C).
# Separate adopt-after-fail: manually exercise by missing app, install mock that
# fails AND creates app, then ensure's post-fail branch runs adopt.
rm -rf "${DOTS_APPLICATIONS_DIR}/Hermes.app"
: >"${DOTS_MOCK_MANAGED}"
: >"${DOTS_MOCK_LOG}"
# Custom brew: install fails but leaves app; adopt fails
cat >"${MOCK_BREW}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"; shift || true
case "${cmd}" in
list)
	[[ ${1:-} == --cask ]] || exit 1
	[[ -f ${DOTS_MOCK_MANAGED} ]] && grep -qx "${2:-}" "${DOTS_MOCK_MANAGED}" && exit 0
	exit 1
	;;
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
			echo "refused --force" >&2
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
		echo "adopt failed" >&2
		exit 1
	fi
	mkdir -p "${DOTS_APPLICATIONS_DIR}/Hermes.app"
	echo "conflict" >&2
	exit 1
	;;
esac
exit 0
EOF
chmod +x "${MOCK_BREW}"
if dots_ensure_cask_app hermes-desktop /Applications/Hermes.app "Hermes.app" >/tmp/cask-f.out 2>&1; then
	[[ ${DOTS_CASK_LAST_STATUS} == external ]] && ok "F external after adopt fail" || bad "F status=${DOTS_CASK_LAST_STATUS}"
	[[ -d ${DOTS_APPLICATIONS_DIR}/Hermes.app ]] && ok "F app preserved" || bad "F app missing"
	grep -q 'adopt=1' "${DOTS_MOCK_LOG}" && ok "F tried adopt" || bad "F no adopt attempt"
else
	bad "F should succeed as external"
	cat /tmp/cask-f.out
fi

echo "=== FluidVoice equivalent (external app) ==="
# Restore standard mock
cat >"${MOCK_BREW}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"; shift || true
case "${cmd}" in
list)
	[[ ${1:-} == --cask ]] || exit 1
	[[ -f ${DOTS_MOCK_MANAGED} ]] && grep -qx "${2:-}" "${DOTS_MOCK_MANAGED}" && exit 0
	exit 1
	;;
install)
	echo "install $*" >>"${DOTS_MOCK_LOG}"
	exit 1
	;;
esac
exit 0
EOF
chmod +x "${MOCK_BREW}"
mkdir -p "${DOTS_APPLICATIONS_DIR}/FluidVoice.app"
: >"${DOTS_MOCK_MANAGED}"
: >"${DOTS_MOCK_LOG}"
if dots_ensure_cask_app fluidvoice /Applications/FluidVoice.app "FluidVoice.app" >/tmp/cask-fv.out 2>&1; then
	[[ ${DOTS_CASK_LAST_STATUS} == external ]] && ok "FluidVoice external OK" || bad "FV status"
	grep -q 'install' "${DOTS_MOCK_LOG}" && bad "FV must not install" || ok "FV no install"
else
	bad "FluidVoice external should succeed"
fi

echo "=== no --force ever ==="
if grep -r -- '--force' "${DOTS_MOCK_LOG}" 2>/dev/null; then
	bad "force was used"
else
	ok "no --force in brew log"
fi
# Source policy: helper must not mention install --cask --force as a strategy
if grep -E 'install --cask --force|brew install --cask --force' "${ROOT}/helpers/cask_apps.sh"; then
	bad "cask_apps.sh contains --force install"
else
	ok "cask_apps.sh has no --force install"
fi

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
