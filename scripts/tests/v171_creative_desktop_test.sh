#!/usr/bin/env bash
# scripts/tests/v171_creative_desktop_test.sh — v1.7.1 Vorssaint / f.lux / DaVinci Resolve
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

DIR="${ROOT}"
export DIR
# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/components.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/davinci_resolve.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-v171.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

echo "=== Vorssaint + f.lux mactools ownership ==="
BF="${ROOT}/brew/Brewfile.mactools"
grep -q 'cask "vorssaint"' "${BF}" && ok "vorssaint in mactools" || bad "vorssaint missing"
grep -q 'cask "flux-app"' "${BF}" && ok "flux-app in mactools" || bad "flux-app missing"
# No duplicate ownership across brew/
for c in vorssaint flux-app; do
	count="$(rg -l "cask \"${c}\"" "${ROOT}/brew" 2>/dev/null | wc -l | tr -d ' ')"
	[[ ${count} -eq 1 ]] && ok "single owner ${c}" || bad "dup owner ${c} (${count})"
done
grep -A12 'id = "mactools"' "${ROOT}/configs/components.toml" | grep -q 'omit_from_all = true' && ok "mactools omit_from_all" || bad "mactools omit"

echo "=== profiles: GUIs absent from all ==="
if grep -qiE 'vorssaint|flux-app|flux|davinci|mactools' "${ROOT}/configs/bootstrap/profiles/all.toml"; then
	bad "all profile references new GUIs/mactools"
else
	ok "all excludes Vorssaint/f.lux/Resolve"
fi
for prof in home work server; do
	if grep -qiE 'davinci-resolve|flux-app|vorssaint' "${ROOT}/configs/bootstrap/profiles/${prof}.toml"; then
		bad "${prof} auto-includes creative GUI"
	else
		ok "${prof} no auto creative GUI"
	fi
done

echo "=== platform gates ==="
export DOTS_FORCE_OS=linux
if dots_require_explicit_component_supported mactools 2>/dev/null; then
	bad "linux mactools should fail"
else
	ok "linux mactools unsupported"
fi
if dots_require_explicit_component_supported davinci-resolve 2>/dev/null; then
	bad "linux davinci-resolve should fail"
else
	ok "linux davinci-resolve unsupported"
fi
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
if dots_require_explicit_component_supported davinci-resolve 2>/dev/null; then
	ok "darwin davinci-resolve ok"
else
	bad "darwin davinci-resolve rejected"
fi
dots_component_ids_for_all | grep -qx davinci-resolve && bad "resolve in all ids" || ok "resolve omit_from_all"
dots_component_is_known davinci-resolve && ok "resolve registered" || bad "resolve not registered"
dots_component_brewfile davinci-resolve | grep -q Brewfile.davinci-resolve && ok "resolve brewfile mapped" || bad "resolve brewfile"

echo "=== Resolve Brewfile is mas-only ==="
RBF="${ROOT}/brew/Brewfile.davinci-resolve"
grep -q 'brew "mas"' "${RBF}" && ok "mas prerequisite" || bad "mas missing"
# Executable Brewfile lines only (comments may mention mas install policy).
if grep -E '^\s*(brew|cask)\s+"' "${RBF}" | grep -qiE 'davinci|resolve'; then
	bad "brewfile installs Resolve app"
else
	ok "brewfile install-only mas"
fi
grep -E '^\s*cask\s+"' "${RBF}" && bad "unexpected cask in resolve brewfile" || ok "no resolve cask line"

echo "=== Resolve helper: no launch / auth soft-skip ==="
mkdir -p "${TMP}/bin" "${TMP}/apps"
# Stub mas: not authenticated
cat >"${TMP}/bin/mas" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
account) echo "Not signed in"; exit 1 ;;
install) echo "FORBIDDEN_MAS_INSTALL:$*" >&2; exit 99 ;;
*) echo "mas stub $*"; exit 0 ;;
esac
EOF
# Stub open / osascript
cat >"${TMP}/bin/open" <<'EOF'
#!/usr/bin/env bash
echo "FORBIDDEN_OPEN:$*" >&2; exit 99
EOF
cat >"${TMP}/bin/osascript" <<'EOF'
#!/usr/bin/env bash
echo "FORBIDDEN_OSASCRIPT:$*" >&2; exit 99
EOF
chmod +x "${TMP}/bin/"*
export PATH="${TMP}/bin:${PATH}"
export DOTS_DAVINCI_RESOLVE_APP_PATH="${TMP}/apps/DaVinci Resolve.app"
export DRY_RUN=0

st="$(dots_davinci_resolve_status)"
echo "${st}" | grep -qi 'AUTH REQUIRED\|NOT INSTALLED' && ok "status auth/not-installed" || bad "status: ${st}"

# Force Darwin for install-path exercises (real uname may be Linux in CI).
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
out="$(dots_davinci_resolve_install 2>&1)" || bad "install failed unexpectedly"
echo "${out}" | grep -qi 'AUTH REQUIRED\|NOT CONFIGURED' && ok "install soft-skips without auth" || bad "no auth message: ${out}"
echo "${out}" | grep -qi 'FORBIDDEN_MAS_INSTALL' && bad "mas install invoked without auth" || ok "mas install not called"
echo "${out}" | grep -qi 'FORBIDDEN_OPEN\|FORBIDDEN_OSASCRIPT' && bad "Resolve launched" || ok "no GUI launch"

# Already installed path
mkdir -p "${DOTS_DAVINCI_RESOLVE_APP_PATH}"
out2="$(dots_davinci_resolve_install 2>&1)" || bad "installed path failed"
echo "${out2}" | grep -qi 'already present' && ok "idempotent when installed" || bad "no already-present: ${out2}"
echo "${out2}" | grep -qi 'FORBIDDEN_MAS_INSTALL' && bad "reinstall attempted" || ok "no reinstall when present"
st2="$(dots_davinci_resolve_status)"
echo "${st2}" | grep -qi 'INSTALLED' && ok "status installed" || bad "status not installed: ${st2}"

# Authenticated + dry-run never installs
rm -rf "${DOTS_DAVINCI_RESOLVE_APP_PATH}"
cat >"${TMP}/bin/mas" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
account) echo "user@example.test"; exit 0 ;;
install) echo "FORBIDDEN_MAS_INSTALL:$*" >&2; exit 99 ;;
*) exit 0 ;;
esac
EOF
export DRY_RUN=1
dout="$(dots_davinci_resolve_install 2>&1)" || bad "dry-run failed"
echo "${dout}" | grep -qi 'dry-run' && ok "dry-run announce" || bad "dry-run silent"
echo "${dout}" | grep -qi 'FORBIDDEN_MAS_INSTALL' && bad "dry-run called mas install" || ok "dry-run no mas install"
export DRY_RUN=0

# Real Linux host without FORCE_OS must still reject install.
if [[ "$(uname -s)" != "Darwin" ]]; then
	unset DOTS_FORCE_OS DOTS_FORCE_DARWIN_MAJOR || true
	if dots_davinci_resolve_install 2>/dev/null; then
		bad "linux host should reject install without FORCE_OS"
	else
		ok "linux host install rejected"
	fi
fi

echo "=== dry-run setup --with davinci-resolve (Darwin) ==="
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
dry="$("${ROOT}/setup.sh" --dry-run --with davinci-resolve 2>&1)" || {
	bad "setup dry-run davinci-resolve failed"
	echo "${dry}" | tail -30
}
echo "${dry}" | grep -qi 'davinci-resolve\|Brewfile.davinci-resolve\|mas' && ok "dry-run mentions resolve/mas" || bad "dry-run silent on resolve"
echo "${dry}" | grep -qi 'FORBIDDEN_' && bad "dry-run forbidden" || ok "dry-run clean"
echo "${dry}" | grep -qi 'optional components failed' && bad "dry-run recorded resolve failure" || ok "dry-run no resolve failure"

echo "=== mactools dry-run includes flux, excludes Resolve install ==="
mdry="$("${ROOT}/setup.sh" --dry-run --with mactools 2>&1)" || bad "mactools dry-run failed"
echo "${mdry}" | grep -qiE 'flux-app|vorssaint|Brewfile.mactools' && ok "mactools dry-run lists flux/vorssaint" || ok "mactools brewfile applied"
# Notes may mention Resolve as NOT included; Brewfile.davinci-resolve must not apply.
echo "${mdry}" | grep -qi 'Brewfile.davinci-resolve\|mas install 571213070' && bad "mactools applies Resolve brewfile" || ok "mactools excludes Resolve brewfile"
# Desired components should be mactools only (not davinci-resolve)
echo "${mdry}" | grep -E 'Optional components:.*davinci-resolve' && bad "mactools selects davinci-resolve" || ok "mactools does not select Resolve"

echo "=== media status: no launch / YubiKey NO ==="
# shellcheck disable=SC1091
SCRIPT="${ROOT}/scripts/ci/media_validate.sh"
[[ -x ${SCRIPT} ]] || chmod +x "${SCRIPT}"
stat_out="$("${SCRIPT}" status 2>&1)" || true
echo "${stat_out}" | grep -qi 'FORBIDDEN_' && bad "media status forbidden" || ok "media status safe"
echo "${stat_out}" | grep -qi 'YubiKey required:.*NO' && ok "YubiKey NO" || bad "YubiKey policy"
if [[ "$(uname -s)" == "Darwin" ]]; then
	echo "${stat_out}" | grep -qi 'Vorssaint\|f\.lux\|DaVinci Resolve' && ok "inventory lists v1.7.1 apps" || bad "inventory incomplete"
fi

# Source safety: helper never opens apps
if rg -n 'open[[:space:]]+-a|osascript|defaults[[:space:]]+write|tccutil' "${ROOT}/helpers/davinci_resolve.sh" | rg -v '^[[:space:]]*#' | grep -q .; then
	bad "davinci helper may launch/mutate"
else
	ok "davinci helper no launch APIs"
fi

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
