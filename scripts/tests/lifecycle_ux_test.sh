#!/usr/bin/env bash
# scripts/tests/lifecycle_ux_test.sh — v1.10 lifecycle UX, overlays, install, upgrade
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${ROOT}"
export DIR ROOT DOTS_DIR="${ROOT}"

# Isolate from user environment
unset DOTS_PROFILE DOTS_ACTIVE_COMPONENTS DOTS_PACKAGE_GROUPS DOTS_MULTIPLEXER DOTS_PROFILE_FILE || true
unset DOTS_UI_ANSWERS DOTS_UI_NONINTERACTIVE DOTS_BOOTSTRAP_SH || true

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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-lifecycle.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

export HOME="${TMP}/home"
mkdir -p "${HOME}"

# Mock brew that logs every call and forbids install/uninstall/cleanup unless allowed
MOCK_BREW="${TMP}/mock-brew"
MOCK_BREW_LOG="${TMP}/brew.log"
: >"${MOCK_BREW_LOG}"
cat >"${MOCK_BREW}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "brew $*" >>"${DOTS_MOCK_BREW_LOG}"
cmd="${1:-}"
shift || true
case "${cmd}" in
install)
	echo "FORBIDDEN_BREW_INSTALL:$*" >&2
	exit 99
	;;
uninstall | remove | cleanup | autoremove)
	echo "FORBIDDEN_BREW_DESTRUCTIVE:${cmd}:$*" >&2
	exit 99
	;;
bundle)
	if [[ ${1:-} == cleanup ]]; then
		echo "FORBIDDEN_BREW_CLEANUP" >&2
		exit 99
	fi
	exit 0
	;;
upgrade)
	pkg="${*: -1}"
	if [[ -n ${DOTS_MOCK_UPGRADE_FAIL:-} ]] && [[ ${pkg} == "${DOTS_MOCK_UPGRADE_FAIL}" ]]; then
		exit 1
	fi
	exit 0
	;;
esac
exit 0
EOF
chmod +x "${MOCK_BREW}"
export DOTS_BREW_BIN="${MOCK_BREW}"
export DOTS_MOCK_BREW_LOG="${MOCK_BREW_LOG}"

# Mock bootstrap that always succeeds unless configured to fail
MOCK_BOOT_OK="${TMP}/boot-ok.sh"
MOCK_BOOT_LOG="${TMP}/boot.log"
: >"${MOCK_BOOT_LOG}"
cat >"${MOCK_BOOT_OK}" <<'EOF'
#!/usr/bin/env bash
echo "bootstrap $*" >>"${DOTS_MOCK_BOOT_LOG}"
exit 0
EOF
chmod +x "${MOCK_BOOT_OK}"
export DOTS_MOCK_BOOT_LOG="${MOCK_BOOT_LOG}"

MOCK_BOOT_FAIL="${TMP}/boot-fail.sh"
cat >"${MOCK_BOOT_FAIL}" <<'EOF'
#!/usr/bin/env bash
echo "bootstrap-fail $*" >>"${DOTS_MOCK_BOOT_LOG}"
exit 1
EOF
chmod +x "${MOCK_BOOT_FAIL}"

# shellcheck source=../../helpers/ui.sh
source "${ROOT}/helpers/ui.sh"
# shellcheck source=../../helpers/state.sh
source "${ROOT}/helpers/state.sh"
# shellcheck source=../../helpers/packages.sh
source "${ROOT}/helpers/packages.sh"
# shellcheck source=../../helpers/components.sh
source "${ROOT}/helpers/components.sh"
# shellcheck source=../../helpers/profiles.sh
source "${ROOT}/helpers/profiles.sh"
# shellcheck source=../../helpers/package_state.sh
source "${ROOT}/helpers/package_state.sh"
# shellcheck source=../../helpers/profile_edit.sh
source "${ROOT}/helpers/profile_edit.sh"

echo "=== 1. Owner resolution (live metadata) ==="
assert_owner() {
	local sel="$1" want="$2"
	if dots_resolve_capability_selector "${sel}" 0 >/dev/null 2>&1 && [[ ${DOTS_SEL_OWNER} == "${want}" ]]; then
		ok "resolve ${sel} -> ${want}"
	else
		bad "resolve ${sel} got='${DOTS_SEL_OWNER:-}' status='${DOTS_SEL_STATUS:-}' want='${want}'"
	fi
}
assert_owner hyperfine group:dev
assert_owner yazi group:workstation
assert_owner sshuttle group:network
assert_owner ssh-audit group:security
assert_owner karabiner-elements component:karabiner-elements
assert_owner ai supergroup:ai
assert_owner group:dev group:dev
assert_owner component:karabiner-elements component:karabiner-elements
assert_owner supergroup:ai supergroup:ai
assert_owner package:hyperfine group:dev

echo "=== 2. Unknown and ambiguous selectors ==="
: >"${MOCK_BREW_LOG}"
set +e
unk_out="$("${ROOT}/dots" install totally-unknown-package --profile home --yes 2>&1)"
unk_rc=$?
set -e
[[ ${unk_rc} -ne 0 ]] && ok "unknown selector fails" || bad "unknown selector passed"
echo "${unk_out}" | grep -q 'not declared in DOTS' && ok "unknown selector error" || bad "unknown error text: ${unk_out}"
echo "${unk_out}" | grep -q 'dots packages adopt totally-unknown-package' && ok "unknown suggests adopt" || bad "unknown missing adopt hint"
grep -q 'FORBIDDEN_BREW_INSTALL' "${MOCK_BREW_LOG}" && bad "unknown called brew install" || ok "unknown did not call brew install"

# Ambiguous package (taplo is owned by both group:dev and component:lsp)
set +e
amb_nonint="$(DOTS_UI_NONINTERACTIVE=1 dots_resolve_capability_selector taplo 0 2>&1)"
amb_rc=$?
set -e
[[ ${amb_rc} -ne 0 ]] && ok "ambiguous noninteractive fails" || bad "ambiguous noninteractive succeeded"
echo "${amb_nonint}" | grep -q 'component:lsp' && echo "${amb_nonint}" | grep -q 'group:dev' &&
	ok "ambiguous lists choices" || bad "ambiguous missing choices: ${amb_nonint}"

# Ambiguous interactive choice (pick 2 -> group:dev)
DOTS_UI_ANSWERS=$'2\n'
if dots_resolve_capability_selector taplo 1 >/dev/null 2>&1 && [[ ${DOTS_SEL_OWNER} == "group:dev" ]]; then
	ok "ambiguous interactive choice selected group:dev"
else
	bad "ambiguous interactive choice got=${DOTS_SEL_OWNER:-}"
fi
unset DOTS_UI_ANSWERS

echo "=== 3. No active profile rules ==="
rm -rf "${HOME:?}/.config" "${HOME:?}/.local"
set +e
no_prof_err="$(DOTS_UI_NONINTERACTIVE=1 "${ROOT}/dots" install hyperfine --yes 2>&1)"
no_prof_rc=$?
set -e
[[ ${no_prof_rc} -ne 0 ]] && ok "noninteractive install without profile fails" || bad "noninteractive without profile passed"
echo "${no_prof_err}" | grep -qi '\-\-profile' && ok "error requires --profile" || bad "error text: ${no_prof_err}"

# Interactive choose base profile (4 = base, then y = proceed)
HOME_NOACT="${TMP}/home-noact"
mkdir -p "${HOME_NOACT}"
set +e
HOME="${HOME_NOACT}" DOTS_UI_ANSWERS=$'4\ny\n' \
	"${ROOT}/dots" install hyperfine --no-apply >"${TMP}/noact.out" 2>&1
noact_rc=$?
set -e
[[ ${noact_rc} -eq 0 ]] && ok "interactive no-active-profile chose base" || {
	bad "interactive no-active-profile rc=${noact_rc}"
	cat "${TMP}/noact.out" || true
}
[[ -f ${HOME_NOACT}/.config/dots/profiles/base-local.toml ]] && ok "base-local.toml created" || bad "base-local.toml missing"

echo "=== 4. Dry-run zero-mutation contract ==="
DRY_HOME="${TMP}/home-dry"
mkdir -p "${DRY_HOME}/.config/dots"
cat >"${DRY_HOME}/.config/dots/active-profile" <<EOF
DOTS_PROFILE='base'
DOTS_PROFILE_FILE='${ROOT}/configs/bootstrap/profiles/base.toml'
DOTS_PACKAGE_GROUPS='core modern'
EOF
snap_tree() { (cd "$1" && find . -print | LC_ALL=C sort | cksum); }
before_dry="$(snap_tree "${DRY_HOME}")"
: >"${MOCK_BREW_LOG}"
: >"${MOCK_BOOT_LOG}"

HOME="${DRY_HOME}" "${ROOT}/dots" install dev --dry-run >/dev/null 2>&1
HOME="${DRY_HOME}" "${ROOT}/dots" install hyperfine --dry-run >/dev/null 2>&1
HOME="${DRY_HOME}" "${ROOT}/dots" profile add dev --dry-run >/dev/null 2>&1
HOME="${DRY_HOME}" "${ROOT}/dots" profile remove core --dry-run >/dev/null 2>&1
HOME="${DRY_HOME}" DOTS_PKG_MOCK_OUTDATED_FORMULAE=$'jq' DOTS_PKG_MOCK_OUTDATED_CASKS='' \
	"${ROOT}/dots" upgrade --dry-run >/dev/null 2>&1

after_dry="$(snap_tree "${DRY_HOME}")"
[[ ${before_dry} == "${after_dry}" ]] && ok "dry-run zero HOME mutations" || bad "dry-run mutated HOME"
[[ ! -s ${MOCK_BREW_LOG} ]] && ok "dry-run zero brew calls" || bad "dry-run called brew: $(cat "${MOCK_BREW_LOG}")"
[[ ! -s ${MOCK_BOOT_LOG} ]] && ok "dry-run zero bootstrap calls" || bad "dry-run called bootstrap"

echo "=== 5. Abort contract ==="
ABORT_HOME="${TMP}/home-abort"
mkdir -p "${ABORT_HOME}/.config/dots"
cat >"${ABORT_HOME}/.config/dots/active-profile" <<EOF
DOTS_PROFILE='base'
DOTS_PROFILE_FILE='${ROOT}/configs/bootstrap/profiles/base.toml'
DOTS_PACKAGE_GROUPS='core modern'
EOF
before_ab="$(snap_tree "${ABORT_HOME}")"
: >"${MOCK_BREW_LOG}"
: >"${MOCK_BOOT_LOG}"
HOME="${ABORT_HOME}" DOTS_BOOTSTRAP_SH="${MOCK_BOOT_OK}" DOTS_UI_ANSWERS=$'n\n' \
	"${ROOT}/dots" install hyperfine >"${TMP}/abort.out" 2>&1
after_ab="$(snap_tree "${ABORT_HOME}")"
[[ ${before_ab} == "${after_ab}" ]] && ok "abort zero HOME/profile/active writes" || bad "abort mutated HOME"
[[ ! -s ${MOCK_BREW_LOG} ]] && ok "abort zero brew calls" || bad "abort called brew"
[[ ! -s ${MOCK_BOOT_LOG} ]] && ok "abort zero bootstrap calls" || bad "abort called bootstrap"

echo "=== 6. Builtin protection + overlay creation + reuse + idempotence ==="
home_toml_before="$(cksum <"${ROOT}/configs/bootstrap/profiles/home.toml")"
server_toml_before="$(cksum <"${ROOT}/configs/bootstrap/profiles/server.toml")"

export HOME="${TMP}/home-overlay"
mkdir -p "${HOME}/.config/dots"
cat >"${HOME}/.config/dots/active-profile" <<EOF
DOTS_PROFILE='server'
DOTS_PROFILE_FILE='${ROOT}/configs/bootstrap/profiles/server.toml'
DOTS_PACKAGE_GROUPS='core modern server'
EOF

DOTS_BOOTSTRAP_SH="${MOCK_BOOT_OK}" "${ROOT}/dots" install hyperfine --yes >"${TMP}/ov1.out" 2>&1
[[ -f ${HOME}/.config/dots/profiles/server-local.toml ]] && ok "created server-local.toml" || bad "missing server-local.toml"
grep -qF '# DOTS managed profile overlay' "${HOME}/.config/dots/profiles/server-local.toml" &&
	ok "overlay has DOTS managed marker" || bad "overlay missing marker"
grep -q 'extends = "server"' "${HOME}/.config/dots/profiles/server-local.toml" &&
	ok "overlay extends server" || bad "overlay extends missing"
grep -q '"dev"' "${HOME}/.config/dots/profiles/server-local.toml" &&
	ok "overlay adds dev" || bad "overlay missing dev"

# Check active-profile switched to server-local
# shellcheck disable=SC1091
source "${HOME}/.config/dots/active-profile"
[[ ${DOTS_PROFILE} == "server-local" ]] && ok "active-profile switched to server-local" || bad "active=${DOTS_PROFILE}"

# Second install reuses server-local (NO server-local-local)
DOTS_BOOTSTRAP_SH="${MOCK_BOOT_OK}" "${ROOT}/dots" install duckdb --no-apply --yes >/dev/null 2>&1
[[ ! -f ${HOME}/.config/dots/profiles/server-local-local.toml ]] &&
	ok "no server-local-local created" || bad "created server-local-local"
grep -q '"data"' "${HOME}/.config/dots/profiles/server-local.toml" &&
	ok "reused server-local for data" || bad "data not in server-local"

# Builtin home test
"${ROOT}/dots" install dev --profile home --no-apply --yes >/dev/null 2>&1 || true
home_toml_after="$(cksum <"${ROOT}/configs/bootstrap/profiles/home.toml")"
server_toml_after="$(cksum <"${ROOT}/configs/bootstrap/profiles/server.toml")"
[[ ${home_toml_before} == "${home_toml_after}" ]] && ok "builtin home.toml unchanged" || bad "home.toml modified"
[[ ${server_toml_before} == "${server_toml_after}" ]] && ok "builtin server.toml unchanged" || bad "server.toml modified"

# Idempotence: repeated install dev
idem_out="$("${ROOT}/dots" install dev --profile "${HOME}/.config/dots/profiles/server-local.toml" --no-apply --yes 2>&1)"
echo "${idem_out}" | grep -q 'group:dev is already desired' && ok "idempotent already desired msg" || bad "idem msg: ${idem_out}"
dev_count="$(grep -o '"dev"' "${HOME}/.config/dots/profiles/server-local.toml" | wc -l | tr -d ' ')"
[[ ${dev_count} -eq 1 ]] && ok "no duplicate dev entry" || bad "dev_count=${dev_count}"

echo "=== 7. Custom profile preservation ==="
CUST_HOME="${TMP}/home-custom"
mkdir -p "${CUST_HOME}/.config/dots/profiles"
BERTHA="${CUST_HOME}/.config/dots/profiles/bertha.toml"
cat >"${BERTHA}" <<'EOF'
# Hand-crafted server profile — preserve comments and layout!
[profile]
name = "bertha"
extends = "server"
description = "My custom box"

[packages]
add = ["infra"]

[components]
with = ["lsp"]

[runtime]
multiplexer = "tmux"
EOF
bertha_ck1="$(cksum <"${BERTHA}")"

HOME="${CUST_HOME}" "${ROOT}/dots" install dev --profile "${BERTHA}" --no-apply --yes >/dev/null 2>&1
bertha_ck2="$(cksum <"${BERTHA}")"
[[ ${bertha_ck1} == "${bertha_ck2}" ]] && ok "custom bertha.toml byte-for-byte unchanged" || bad "bertha.toml modified"
[[ -f ${CUST_HOME}/.config/dots/profiles/bertha-local.toml ]] && ok "created bertha-local.toml overlay" || bad "missing bertha-local"
show_b="$(HOME="${CUST_HOME}" "${ROOT}/bootstrap.sh" --profile "${CUST_HOME}/.config/dots/profiles/bertha-local.toml" --show 2>/dev/null)"
echo "${show_b}" | grep -q 'dev' && echo "${show_b}" | grep -q 'infra' && echo "${show_b}" | grep -q 'lsp' &&
	ok "bertha-local resolves base + bertha + dev" || bad "bertha-local resolution failed"

echo "=== 8. Symmetric remove (group & component) + no uninstall ==="
: >"${MOCK_BREW_LOG}"
# Remove locally added dev -> removed from add
HOME="${CUST_HOME}" "${ROOT}/dots" profile remove dev --yes >/dev/null 2>&1
grep -q '"dev"' "${CUST_HOME}/.config/dots/profiles/bertha-local.toml" && bad "dev still in add" || ok "removed local dev from add"
# Remove inherited infra -> added to remove
HOME="${CUST_HOME}" "${ROOT}/dots" profile remove infra --yes >/dev/null 2>&1
grep -q 'remove = \["infra"\]' "${CUST_HOME}/.config/dots/profiles/bertha-local.toml" && ok "inherited infra added to remove" || bad "infra not in remove"
# Re-add infra -> removes from remove
HOME="${CUST_HOME}" "${ROOT}/dots" profile add infra --yes >/dev/null 2>&1
grep -q 'remove =' "${CUST_HOME}/.config/dots/profiles/bertha-local.toml" && bad "infra still in remove" || ok "re-add cleared remove"
# Remove inherited component lsp -> added to components.without
HOME="${CUST_HOME}" "${ROOT}/dots" profile remove lsp --yes >/dev/null 2>&1
grep -q 'without = \["lsp"\]' "${CUST_HOME}/.config/dots/profiles/bertha-local.toml" && ok "inherited lsp added to without" || bad "lsp not in without"
# Re-add lsp -> removes from without
HOME="${CUST_HOME}" "${ROOT}/dots" profile add lsp --yes >/dev/null 2>&1
grep -q 'without =' "${CUST_HOME}/.config/dots/profiles/bertha-local.toml" && bad "lsp still in without" || ok "re-add cleared without"
grep -q 'FORBIDDEN_BREW_DESTRUCTIVE' "${MOCK_BREW_LOG}" && bad "remove called uninstall/cleanup" || ok "remove never uninstalls"

echo "=== 9. --no-apply, diff, switch, and convergence failure recovery ==="
noapp_out="$(HOME="${CUST_HOME}" "${ROOT}/dots" install geo --no-apply --yes 2>&1)"
echo "${noapp_out}" | grep -q 'Profile updated' && echo "${noapp_out}" | grep -q 'dots profile apply' &&
	ok "--no-apply reports apply-later hint" || bad "no-apply output: ${noapp_out}"

diff_out="$(HOME="${CUST_HOME}" "${ROOT}/dots" profile diff 2>&1)"
echo "${diff_out}" | grep -q '+ group:geo' && ok "profile diff shows + group:geo" || bad "diff: ${diff_out}"

HOME="${CUST_HOME}" "${ROOT}/dots" profile switch base >/dev/null 2>&1
# shellcheck disable=SC1091
source "${CUST_HOME}/.config/dots/active-profile"
[[ ${DOTS_PROFILE} == "base" ]] && ok "profile switch updated active-profile" || bad "switch active=${DOTS_PROFILE}"

# Apply failure preserves persisted desired profile
set +e
fail_out="$(HOME="${CUST_HOME}" DOTS_BOOTSTRAP_SH="${MOCK_BOOT_FAIL}" \
	"${ROOT}/dots" install dev --yes 2>&1)"
fail_rc=$?
set -e
[[ ${fail_rc} -ne 0 ]] && ok "failed apply exits nonzero" || bad "failed apply exited 0"
echo "${fail_out}" | grep -q 'Desired state updated successfully' &&
	echo "${fail_out}" | grep -q 'Machine convergence failed' &&
	ok "failed apply distinguishes desired state vs convergence" || bad "fail text: ${fail_out}"
grep -q '"dev"' "${CUST_HOME}/.config/dots/profiles/base-local.toml" &&
	ok "desired overlay preserved after apply failure" || bad "overlay lost on apply failure"

echo "=== 10. Upgrade workflow (scoped, dry-run, --profile, --all, partial failure) ==="
UPG_HOME="${TMP}/home-upgrade"
mkdir -p "${UPG_HOME}/.config/dots"
cat >"${UPG_HOME}/.config/dots/active-profile" <<EOF
DOTS_PROFILE='base'
DOTS_PROFILE_FILE='${ROOT}/configs/bootstrap/profiles/base.toml'
DOTS_PACKAGE_GROUPS='core modern'
EOF

# jq (desired core), iterm2 (desired core cask? wait: check cask in base: font-jetbrains-mono-nerd-font is gui; use mactools/herdr or server),
# hyperfine (owned by dev -> excluded from base), glow (undeclared)
export DOTS_PKG_MOCK_OUTDATED_FORMULAE=$'jq\nhyperfine\nglow'
export DOTS_PKG_MOCK_OUTDATED_CASKS=$'raycast'

: >"${MOCK_BREW_LOG}"
dry_upg="$(HOME="${UPG_HOME}" "${ROOT}/dots" upgrade --dry-run 2>&1)"
echo "${dry_upg}" | grep -q 'Would upgrade:' && echo "${dry_upg}" | grep -q 'jq' &&
	ok "upgrade dry-run lists managed jq" || bad "dry_upg: ${dry_upg}"
echo "${dry_upg}" | grep -q 'Outdated but excluded from this profile:' &&
	echo "${dry_upg}" | grep -q 'hyperfine' && echo "${dry_upg}" | grep -q 'raycast' &&
	ok "upgrade dry-run lists excluded hyperfine + raycast" || bad "dry_upg excluded: ${dry_upg}"
echo "${dry_upg}" | grep -q 'Undeclared:' && echo "${dry_upg}" | grep -q 'glow' &&
	ok "upgrade dry-run lists undeclared glow" || bad "dry_upg undeclared: ${dry_upg}"
[[ ! -s ${MOCK_BREW_LOG} ]] && ok "upgrade dry-run zero brew mutations" || bad "upgrade dry-run called brew"

# Scoped upgrade --yes upgrades ONLY jq (not hyperfine, raycast, glow)
: >"${MOCK_BREW_LOG}"
HOME="${UPG_HOME}" "${ROOT}/dots" upgrade --yes >"${TMP}/upg-scoped.out" 2>&1
grep -q 'upgrade --formula jq' "${MOCK_BREW_LOG}" && ok "scoped upgrade upgraded jq" || bad "scoped missing jq"
grep -q 'hyperfine\|raycast\|glow' "${MOCK_BREW_LOG}" && bad "scoped upgraded out-of-scope pkg" || ok "scoped ignored excluded/undeclared"

# --profile work scopes to work (includes hyperfine via dev) without changing active-profile
: >"${MOCK_BREW_LOG}"
ap_before="$(cksum <"${UPG_HOME}/.config/dots/active-profile")"
HOME="${UPG_HOME}" "${ROOT}/dots" upgrade --profile work --yes >"${TMP}/upg-prof.out" 2>&1
ap_after="$(cksum <"${UPG_HOME}/.config/dots/active-profile")"
[[ ${ap_before} == "${ap_after}" ]] && ok "--profile upgrade did not change active-profile" || bad "--profile mutated active"
grep -q 'upgrade --formula hyperfine' "${MOCK_BREW_LOG}" && ok "--profile work upgraded hyperfine" || bad "--profile work missed hyperfine"

# --all safety: noninteractive without --yes must refuse
set +e
all_refuse="$(HOME="${UPG_HOME}" DOTS_UI_NONINTERACTIVE=1 "${ROOT}/dots" upgrade --all 2>&1)"
all_refuse_rc=$?
set -e
[[ ${all_refuse_rc} -ne 0 ]] && ok "--all noninteractive without --yes refused" || bad "--all noninteractive allowed"
echo "${all_refuse}" | grep -qi '\-\-yes' && ok "--all error mentions --yes" || bad "--all error: ${all_refuse}"

# --all --yes upgrades managed + excluded + undeclared (including cask)
: >"${MOCK_BREW_LOG}"
HOME="${UPG_HOME}" "${ROOT}/dots" upgrade --all --yes >"${TMP}/upg-all.out" 2>&1
grep -q 'upgrade --formula jq' "${MOCK_BREW_LOG}" &&
	grep -q 'upgrade --formula hyperfine' "${MOCK_BREW_LOG}" &&
	grep -q 'upgrade --formula glow' "${MOCK_BREW_LOG}" &&
	grep -q 'upgrade --cask raycast' "${MOCK_BREW_LOG}" &&
	ok "--all --yes upgraded all outdated" || bad "--all --yes log: $(cat "${MOCK_BREW_LOG}")"
grep -q 'FORBIDDEN_BREW_CLEANUP\|FORBIDDEN_BREW_DESTRUCTIVE' "${MOCK_BREW_LOG}" &&
	bad "upgrade called cleanup/uninstall" || ok "upgrade never called cleanup"

# Nothing outdated
DOTS_PKG_MOCK_OUTDATED_FORMULAE="" DOTS_PKG_MOCK_OUTDATED_CASKS="" \
	HOME="${UPG_HOME}" "${ROOT}/dots" upgrade --yes >"${TMP}/upg-none.out" 2>&1
grep -qi 'nothing outdated in scope' "${TMP}/upg-none.out" && ok "nothing outdated handled" || bad "upg-none: $(cat "${TMP}/upg-none.out")"

# Partial upgrade failure reports successful, failed, remaining
set +e
part_out="$(DOTS_MOCK_UPGRADE_FAIL=bat DOTS_PKG_MOCK_OUTDATED_FORMULAE=$'jq\nbat\nfzf' DOTS_PKG_MOCK_OUTDATED_CASKS="" \
	HOME="${UPG_HOME}" "${ROOT}/dots" upgrade --yes 2>&1)"
part_rc=$?
set -e
[[ ${part_rc} -ne 0 ]] && ok "partial upgrade failure exits nonzero" || bad "partial failure exited 0"
echo "${part_out}" | grep -qi 'successful.*jq.*fzf\|successful.*jq' &&
	echo "${part_out}" | grep -qi 'failed.*bat' &&
	echo "${part_out}" | grep -qi 'remaining.*bat' &&
	ok "partial failure reports successful, failed, remaining" || bad "partial out: ${part_out}"

unset DOTS_PKG_MOCK_OUTDATED_FORMULAE DOTS_PKG_MOCK_OUTDATED_CASKS

echo "=== 11. Returning-user wizard, status, explain, components show, metadata ==="
wiz_ret="$(HOME="${UPG_HOME}" DOTS_UI_ANSWERS=$'q\n' "${ROOT}/dots" setup 2>&1)"
echo "${wiz_ret}" | grep -q 'Existing DOTS Machine' &&
	echo "${wiz_ret}" | grep -q 'Add software/capability' &&
	echo "${wiz_ret}" | grep -q 'Upgrade managed software' &&
	ok "returning-user wizard shows lifecycle menu" || bad "wiz_ret: ${wiz_ret}"

st_out="$(HOME="${UPG_HOME}" "${ROOT}/dots" status 2>&1 || true)"
echo "${st_out}" | grep -q './dots upgrade' && echo "${st_out}" | grep -q './dots install' &&
	ok "status surfaces upgrade & install hints" || bad "status hints: ${st_out}"

exp_h="$(HOME="${UPG_HOME}" "${ROOT}/dots" packages explain hyperfine 2>&1)"
echo "${exp_h}" | grep -q 'owner:.*group:dev' &&
	echo "${exp_h}" | grep -q 'desired:.*NO' &&
	echo "${exp_h}" | grep -q './dots install hyperfine' &&
	echo "${exp_h}" | grep -q './dots packages group dev' &&
	ok "explain hyperfine shows owner/desired/install/inspect" || bad "explain hyperfine: ${exp_h}"

comp_s="$(HOME="${UPG_HOME}" "${ROOT}/dots" components show lsp 2>&1)"
echo "${comp_s}" | grep -q './dots install lsp' &&
	echo "${comp_s}" | grep -q './dots setup --with lsp' &&
	ok "components show lsp advertises install + --with" || bad "components show: ${comp_s}"

# Mutation metadata check
python3 - "${ROOT}/configs/help/commands.toml" <<'PY' && ok "commands.toml mutating metadata valid" || bad "commands.toml mutating metadata"
import sys, tomllib
from pathlib import Path
data = tomllib.loads(Path(sys.argv[1]).read_text())
cmds = {c["name"]: c for c in data["commands"]}
for k in ("install", "upgrade", "packages", "setup", "profile", "update"):
    assert cmds[k]["mutating"] is True, f"{k} mutating != True"
PY

echo "=== 12. YubiKey independence ==="
if rg -q 'ykman|YubiKey|age-plugin' "${ROOT}/helpers/profile_edit.sh"; then
	bad "profile_edit.sh references YubiKey"
else
	ok "lifecycle helpers independent of YubiKey"
fi

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
