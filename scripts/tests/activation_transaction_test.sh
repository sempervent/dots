#!/usr/bin/env bash
# scripts/tests/activation_transaction_test.sh — profile activation after setup success only
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

echo "=== bootstrap writes runtime only after setup (source contract) ==="
write_line="$(grep -n 'dots_write_runtime_policy' "${ROOT}/bootstrap.sh" | head -1 | cut -d: -f1)"
setup_line="$(grep -n 'Invoking setup.sh' "${ROOT}/bootstrap.sh" | head -1 | cut -d: -f1)"
fail_line="$(grep -n 'Setup failed before profile activation' "${ROOT}/bootstrap.sh" | head -1 | cut -d: -f1)"
if [[ -n ${write_line} && -n ${setup_line} && ${write_line} -gt ${setup_line} ]]; then
	ok "runtime write after setup invoke (${setup_line}<${write_line})"
else
	bad "runtime write not after setup (setup=${setup_line} write=${write_line})"
fi
[[ -n ${fail_line} ]] && ok "setup-failure message present" || bad "missing setup-failure message"
grep -q 'DOTS_SETUP_SH' "${ROOT}/bootstrap.sh" && ok "DOTS_SETUP_SH override hook" || bad "missing DOTS_SETUP_SH"

echo "=== existing home preserved when mocked setup fails ==="
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-act.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT
export HOME="${TMP}"
mkdir -p "${HOME}/.config/dots"
cat >"${HOME}/.config/dots/runtime.env" <<'EOF'
: "${DOTS_PROFILE:=home}"
: "${DOTS_MULTIPLEXER:=herdr}"
export DOTS_PROFILE DOTS_MULTIPLEXER
EOF
cat >"${HOME}/.config/dots/active-profile" <<EOF
DOTS_PROFILE='home'
DOTS_PROFILE_FILE='${ROOT}/configs/bootstrap/profiles/home.toml'
DOTS_PACKAGE_GROUPS='core modern'
DOTS_LAST_WITH_INFO='herdr'
EOF
rt1="$(cksum <"${HOME}/.config/dots/runtime.env")"
ap1="$(cksum <"${HOME}/.config/dots/active-profile")"

cat >"${TMP}/setup-fail.sh" <<'EOF'
#!/usr/bin/env bash
echo "mock setup failure" >&2
exit 1
EOF
chmod +x "${TMP}/setup-fail.sh"

set +e
DOTS_SETUP_SH="${TMP}/setup-fail.sh" \
	"${ROOT}/bootstrap.sh" --profile all >/tmp/act-fail.out 2>&1
rc=$?
set -e
[[ ${rc} -ne 0 ]] && ok "bootstrap exits nonzero on setup failure" || bad "bootstrap rc=${rc}"
grep -q 'Setup failed before profile activation' /tmp/act-fail.out && ok "failure messaging" || {
	bad "missing activation failure text"
	tail -40 /tmp/act-fail.out || true
}
rt2="$(cksum <"${HOME}/.config/dots/runtime.env")"
ap2="$(cksum <"${HOME}/.config/dots/active-profile")"
[[ ${rt1} == "${rt2}" ]] && ok "runtime.env unchanged" || bad "runtime.env mutated"
[[ ${ap1} == "${ap2}" ]] && ok "active-profile unchanged" || bad "active-profile mutated"
# shellcheck disable=SC1090
source "${HOME}/.config/dots/active-profile"
[[ ${DOTS_PROFILE} == home ]] && ok "still home" || bad "profile=${DOTS_PROFILE}"

echo "=== fresh HOME: failure leaves no active-profile ==="
TMP2="$(mktemp -d)"
export HOME="${TMP2}"
set +e
DOTS_SETUP_SH="${TMP}/setup-fail.sh" \
	"${ROOT}/bootstrap.sh" --profile all >/tmp/act-fresh.out 2>&1
set -e
if [[ ! -f ${HOME}/.config/dots/active-profile ]]; then
	ok "fresh failure: no active-profile"
else
	bad "fresh failure wrote active-profile"
	cat "${HOME}/.config/dots/active-profile"
fi
if [[ ! -f ${HOME}/.config/dots/runtime.env ]]; then
	ok "fresh failure: no runtime.env"
else
	bad "fresh failure wrote runtime.env"
fi
rm -rf "${TMP2}"

echo "=== success path commits profile (mocked setup ok) ==="
export HOME="${TMP}"
cat >"${TMP}/setup-ok.sh" <<'EOF'
#!/usr/bin/env bash
echo "mock setup ok"
exit 0
EOF
chmod +x "${TMP}/setup-ok.sh"
# check.sh may fail on sparse HOME — allow bootstrap to write then possibly fail check.
# For activation commit we only need setup success; check failure is separate.
# Use --dry-run? dry-run still writes policy via dry-run echo only.
# Real write needs DRY_RUN=0 and setup ok. check may fail — that's OK for this assert
# if write happens before check.
set +e
DOTS_SETUP_SH="${TMP}/setup-ok.sh" \
	"${ROOT}/bootstrap.sh" --profile all >/tmp/act-ok.out 2>&1
set -e
if [[ -f ${HOME}/.config/dots/active-profile ]]; then
	# shellcheck disable=SC1090
	source "${HOME}/.config/dots/active-profile"
	[[ ${DOTS_PROFILE} == all ]] && ok "success activates all" || bad "active=${DOTS_PROFILE:-missing}"
else
	bad "success did not write active-profile"
	tail -40 /tmp/act-ok.out || true
fi

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
