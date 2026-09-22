#!/usr/bin/env bash
# scripts/tests/component_discovery_test.sh — active components, INACTIVE vs UNDECLARED
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-comp-disc.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

export DIR="${ROOT}"
export HOME="${TMP}/home"
mkdir -p "${HOME}/.config/dots"

# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/state.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/components.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/package_state.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/profiles.sh"

echo "=== state: home activation persists + load_active restores components ==="
DRY_RUN=0
EFFECTIVE_WITH=(herdr ollama)
PROFILE_NAME=home
PROFILE_PACKAGES=(core modern)
PROFILE_RUNTIME_MULTIPLEXER=herdr
PROFILE_RUNTIME_GREETING=1
PROFILE_RUNTIME_PROMPT_STATS=0
PROFILE_RUNTIME_AUTO_TMUX=1
dots_write_runtime_policy "${ROOT}/configs/bootstrap/profiles/home.toml"
# shellcheck disable=SC1090
source "${HOME}/.config/dots/active-profile"
[[ -n ${DOTS_LAST_WITH_INFO:-} ]] && ok "wrote DOTS_LAST_WITH_INFO" || bad "missing LAST_WITH_INFO"
[[ -n ${DOTS_ACTIVE_COMPONENTS:-} ]] && ok "wrote DOTS_ACTIVE_COMPONENTS" || bad "missing ACTIVE_COMPONENTS"
[[ ${DOTS_LAST_WITH_INFO} == *herdr* ]] && ok "LAST_WITH has herdr" || bad "LAST_WITH=${DOTS_LAST_WITH_INFO}"

unset DOTS_ACTIVE_COMPONENTS DOTS_LAST_WITH_INFO DOTS_PROFILE DOTS_PACKAGE_GROUPS
dots_state_load_active || bad "load_active failed"
[[ ${DOTS_ACTIVE_COMPONENTS} == *herdr* ]] && ok "load_active restores ACTIVE_COMPONENTS" || bad "active=${DOTS_ACTIVE_COMPONENTS:-empty}"
[[ ${DOTS_ACTIVE_COMPONENTS} == *ollama* ]] && ok "load_active has ollama" || bad "missing ollama in active"

echo "=== BC: LAST_WITH_INFO-only active-profile still loads ==="
cat >"${HOME}/.config/dots/active-profile" <<EOF
DOTS_PROFILE='home'
DOTS_PROFILE_FILE='${ROOT}/configs/bootstrap/profiles/home.toml'
DOTS_PACKAGE_GROUPS='core modern'
DOTS_LAST_WITH_INFO='herdr skills'
EOF
unset DOTS_ACTIVE_COMPONENTS DOTS_LAST_WITH_INFO
dots_state_load_active || bad "BC load failed"
[[ ${DOTS_ACTIVE_COMPONENTS} == "herdr skills" ]] && ok "BC maps LAST_WITH → ACTIVE_COMPONENTS" || bad "BC active=${DOTS_ACTIVE_COMPONENTS:-}"

echo "=== persistence ≠ AI consent ==="
# shellcheck disable=SC1091
source "${ROOT}/helpers/ai_consent.sh"
has_component() { dots_array_contains "$1" "${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}"; }
# Simulate packages reader using ACTIVE_COMPONENTS without selecting for consent
DOTS_WITH_COMPONENTS=()
if dots_client_selected hermes 2>/dev/null; then
	bad "empty WITH still consents hermes"
else
	ok "ACTIVE_COMPONENTS alone does not consent AI clients"
fi
# Even if we seed WITH from active for read-only packages, consent helpers
# must remain invocation-scoped in setup — document via comment + no auto config.
DOTS_WITH_COMPONENTS=(herdr ollama)
if dots_may_configure_cursor 2>/dev/null; then
	bad "cursor consented without selection"
else
	ok "cursor not consented from herdr/ollama inventory"
fi

echo "=== mocked brew: git MANAGED, herdr MANAGED, dust INACTIVE, glow UNDECLARED ==="
dots_pkg_ownership_reset
export DOTS_PACKAGE_GROUPS="core"
DOTS_RESOLVED_GROUPS=(core)
DOTS_WITH_COMPONENTS=(herdr)
export DOTS_PKG_MOCK_LEAVES=$'git\nherdr\ndust\nglow'
export DOTS_PKG_MOCK_FORMULAE=$'git\nherdr\ndust\nglow'
export DOTS_PKG_MOCK_CASKS=''
export DOTS_PKG_MOCK_OUTDATED_FORMULAE=''
export DOTS_PKG_MOCK_OUTDATED_CASKS=''

dots_desired_packages_resolve
dots_pkg_classify_resolved 1
dots_pkg_status_print >"${TMP}/status.out"

# git from core → MANAGED; herdr from component → MANAGED
# dust from mactools (not selected) → INACTIVE; glow → UNDECLARED
# (act is owned by group:dev once that Brewfile exists — use glow for undeclared)
printf '%s\n' "${DOTS_DESIRED_FORMULAE[@]}" | grep -qx git && ok "git in desired" || bad "git not desired"
printf '%s\n' "${DOTS_DESIRED_FORMULAE[@]}" | grep -qx herdr && ok "herdr in desired" || bad "herdr not desired"
printf '%s\n' "${DOTS_DESIRED_FORMULAE[@]}" | grep -qx dust && bad "dust should not be desired" || ok "dust not in desired"
[[ ${DOTS_PKG_COUNT_MANAGED} -ge 2 ]] && ok "managed>=2 (git+herdr)" || bad "managed=${DOTS_PKG_COUNT_MANAGED}"
printf '%s\n' "${DOTS_PKG_INACTIVE_FORMULAE[@]+"${DOTS_PKG_INACTIVE_FORMULAE[@]}"}" | grep -qx dust && ok "dust INACTIVE" || bad "dust not inactive"
printf '%s\n' "${DOTS_PKG_UNDECLARED_FORMULAE[@]+"${DOTS_PKG_UNDECLARED_FORMULAE[@]}"}" | grep -qx glow && ok "glow UNDECLARED" || bad "glow not undeclared"
printf '%s\n' "${DOTS_PKG_UNDECLARED_FORMULAE[@]+"${DOTS_PKG_UNDECLARED_FORMULAE[@]}"}" | grep -qx dust && bad "dust wrongly undeclared" || ok "dust not undeclared"
printf '%s\n' "${DOTS_PKG_INACTIVE_FORMULAE[@]+"${DOTS_PKG_INACTIVE_FORMULAE[@]}"}" | grep -qx glow && bad "glow wrongly inactive" || ok "glow not inactive"

grep -q 'inactive:' "${TMP}/status.out" && ok "status prints inactive" || bad "no inactive line"
grep -qi 'Inactive' "${TMP}/status.out" && ok "status has Inactive section" || bad "no Inactive section"

echo "=== overlapping ownership: any active owner → not INACTIVE ==="
# dust owned by mactools; activate mactools → MANAGED
DOTS_WITH_COMPONENTS=(herdr mactools)
dots_pkg_ownership_reset
dots_desired_packages_resolve
dots_pkg_classify_resolved 1
printf '%s\n' "${DOTS_DESIRED_FORMULAE[@]}" | grep -qx dust && ok "dust desired with mactools" || bad "dust not desired"
printf '%s\n' "${DOTS_PKG_INACTIVE_FORMULAE[@]+"${DOTS_PKG_INACTIVE_FORMULAE[@]}"}" | grep -qx dust && bad "dust still inactive" || ok "dust not inactive when mactools active"
# herdr still managed (active component owner)
[[ ${DOTS_PKG_COUNT_MANAGED} -ge 3 ]] && ok "managed includes herdr+dust+git" || bad "managed=${DOTS_PKG_COUNT_MANAGED}"

echo "=== packages explain ==="
exp="$(dots_pkg_explain dust 2>&1)" || true
echo "${exp}" | grep -q 'state:.*INACTIVE\|state:.*MANAGED' && ok "explain has state" || bad "explain state"
echo "${exp}" | grep -q 'component:mactools' && ok "explain known owner mactools" || bad "explain owners: ${exp}"
echo "${exp}" | grep -q '\-\-with' && ok "explain activate hint" || bad "no activate hint"

exp_glow="$(dots_pkg_explain glow 2>&1)" || true
echo "${exp_glow}" | grep -q 'UNDECLARED' && ok "explain glow UNDECLARED" || bad "glow explain: ${exp_glow}"

# act is known via group:dev but INACTIVE when core-only is selected
DOTS_WITH_COMPONENTS=(herdr)
dots_pkg_ownership_reset
export DOTS_PKG_MOCK_LEAVES=$'git\nherdr\nact'
export DOTS_PKG_MOCK_FORMULAE=$'git\nherdr\nact'
dots_desired_packages_resolve
dots_pkg_classify_resolved 1
printf '%s\n' "${DOTS_PKG_INACTIVE_FORMULAE[@]+"${DOTS_PKG_INACTIVE_FORMULAE[@]}"}" | grep -qx act && ok "act INACTIVE when dev unselected" || bad "act not inactive"
exp_act="$(dots_pkg_explain act 2>&1)" || true
echo "${exp_act}" | grep -q 'INACTIVE\|group:dev' && ok "explain act known owner" || bad "act explain: ${exp_act}"

adopt_out="$(dots_pkg_suggest_declare brew dust 2>&1)" || true
echo "${adopt_out}" | grep -qi 'do not adopt\|already has DOTS ownership\|--with' && ok "adopt redirects for owned pkg" || bad "adopt: ${adopt_out}"

echo "=== components list / active / show ==="
list_out="$(dots_components_list 2>&1)" || {
	bad "components list failed"
	list_out=""
}
echo "${list_out}" | grep -q mactools && ok "list has mactools" || bad "list mactools"
echo "${list_out}" | grep -q skills && ok "list has skills" || bad "list skills"

# Restore LAST_WITH for active view
cat >"${HOME}/.config/dots/active-profile" <<EOF
DOTS_PROFILE='home'
DOTS_PROFILE_FILE='${ROOT}/configs/bootstrap/profiles/home.toml'
DOTS_PACKAGE_GROUPS='core modern'
DOTS_LAST_WITH_INFO='herdr'
EOF
act_out="$(dots_components_active 2>&1)" || true
echo "${act_out}" | grep -q herdr && ok "active shows herdr" || bad "active: ${act_out}"
echo "${act_out}" | grep -qi 'informational\|consent\|NOT authorize' && ok "active consent disclaimer" || bad "no disclaimer"

show_m="$(dots_components_show mactools 2>&1)" || true
echo "${show_m}" | grep -q dust && ok "show mactools lists dust" || bad "show mactools: ${show_m}"
show_sk="$(dots_components_show skills 2>&1)" || true
echo "${show_sk}" | grep -qi skill && ok "show skills mentions skills" || bad "show skills"
show_ai="$(dots_components_show ai 2>&1)" || true
echo "${show_ai}" | grep -qi member && ok "show ai has members" || bad "show ai"
if dots_components_show nonexistent >/dev/null 2>&1; then
	bad "show nonexistent succeeded"
else
	ok "show nonexistent fails"
fi

echo "=== CLI help discoverability ==="
help_out="$("${ROOT}/dots" help 2>&1)" || true
echo "${help_out}" | grep -q components && ok "help mentions components" || bad "help components"
echo "${help_out}" | grep -q '\-\-with\|with=' && ok "help mentions --with" || bad "help --with"
setup_help="$("${ROOT}/dots" setup --help 2>&1)" || true
echo "${setup_help}" | grep -q '\-\-with' && ok "setup --help --with" || bad "setup help with"
echo "${setup_help}" | grep -q '\-\-without' && ok "setup --help --without" || bad "setup help without"
pkg_help="$("${ROOT}/dots" packages help 2>&1)" || true
echo "${pkg_help}" | grep -qi inactive && ok "packages help inactive" || bad "pkg help inactive"
echo "${pkg_help}" | grep -q explain && ok "packages help explain" || bad "pkg help explain"

echo "=== docs generate --check (with-options) ==="
# shellcheck source=../../helpers/python_runtime.sh
source "${ROOT}/helpers/python_runtime.sh"
DOC_PY="$(dots_find_python311)" || DOC_PY=""
if [[ -n ${DOC_PY} ]] && "${DOC_PY}" "${ROOT}/scripts/docs/generate_reference.py" >/dev/null 2>&1; then
	ok "docs generate wrote outputs"
else
	bad "docs generate failed"
fi
if [[ -n ${DOC_PY} ]] && "${DOC_PY}" "${ROOT}/scripts/docs/generate_reference.py" --check >/dev/null 2>&1; then
	ok "docs generate --check clean"
else
	bad "docs generate --check drift"
fi
[[ -f ${ROOT}/docs/reference/generated/with-options.md ]] && ok "with-options.md exists" || bad "missing with-options.md"
grep -q 'dust' "${ROOT}/docs/reference/generated/with-options.md" && ok "with-options lists dust" || bad "with-options dust"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
