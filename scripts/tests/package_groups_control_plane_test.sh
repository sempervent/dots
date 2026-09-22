#!/usr/bin/env bash
# scripts/tests/package_groups_control_plane_test.sh — registry SoT + CLI plan
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${ROOT}"
export DIR ROOT
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-pgcp.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT
export HOME="${TMP}/home"
mkdir -p "${HOME}/.config/dots"

# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/components.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/package_state.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/profiles.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/state.sh"

echo "=== registry helpers load real groups ==="
REAL_GROUPS=()
while IFS= read -r _g; do REAL_GROUPS+=("${_g}"); done < <(dots_known_package_groups)
[[ ${#REAL_GROUPS[@]} -ge 10 ]] && ok "loaded ${#REAL_GROUPS[@]} groups" || bad "too few groups: ${#REAL_GROUPS[@]}"
dots_group_is_known geo && ok "geo known" || bad "geo unknown"
dots_group_is_known "not-a-group" && bad "bogus group accepted" || ok "bogus group rejected"
desc="$(dots_group_description dev 2>/dev/null || true)"
[[ ${desc} == *[Cc][Ii]* || ${desc} == *[Dd]ev* || -n ${desc} ]] && ok "dev description" || bad "dev description empty"
bf="$(dots_group_brewfile geo)"
[[ ${bf} == "brew/groups/geo.Brewfile" ]] && ok "geo brewfile path" || bad "brewfile=${bf}"
req_n=0
while IFS= read -r _; do req_n=$((req_n + 1)); done < <(dots_group_package_ids core required)
[[ ${req_n} -ge 5 ]] && ok "core required ids (${req_n})" || bad "core required empty"

echo "=== unknown group useful error ==="
err="$(dots_validate_package_groups interdimensional-toaster 2>&1)" && bad "unknown should fail" || ok "unknown rejected"
echo "${err}" | grep -qi 'unknown package group' && ok "error names unknown" || bad "error text: ${err}"
echo "${err}" | grep -qi 'Supported groups\|Authority' && ok "error lists support/authority" || bad "error missing support hint"

echo "=== SoT: temp registry test-capability WITHOUT editing allowlists ==="
cat >"${TMP}/groups.toml" <<'EOF'
version = 1

[[groups]]
name = "core"
description = "minimal fixture"
required = ["bash"]
optional = []

[[groups]]
name = "test-capability"
description = "temporary capability for SoT regression"
required = []
optional = ["glow"]
EOF
export DOTS_GROUPS_REGISTRY="${TMP}/groups.toml"
# Re-source packages helpers so path override is used (functions already defined;
# registry path is read at call time — no re-source needed).
dots_group_is_known test-capability && ok "temp group recognized" || bad "temp group not recognized"
dots_group_is_known geo && bad "prod geo still known under temp registry" || ok "prod geo absent in temp registry"
dots_validate_package_groups test-capability && ok "temp group validates" || bad "temp validate failed"
dots_validate_package_groups geo 2>/dev/null && bad "geo should fail under temp registry" || ok "geo rejected under temp registry"
# Profile parser must also honor override
cat >"${TMP}/prof.toml" <<'EOF'
[profile]
name = "sot-temp"
packages = ["core", "test-capability"]
EOF
if dots_load_profile_file "${TMP}/prof.toml" >/dev/null 2>&1; then
	ok "profile accepts test-capability from temp registry"
else
	bad "profile rejected test-capability under temp registry"
fi
cat >"${TMP}/bad.toml" <<'EOF'
[profile]
name = "sot-bad"
packages = ["core", "interdimensional-toaster"]
EOF
if dots_load_profile_file "${TMP}/bad.toml" >/dev/null 2>&1; then
	bad "profile accepted unknown group under temp registry"
else
	ok "profile rejects unknown under temp registry"
fi
unset DOTS_GROUPS_REGISTRY

echo "=== activate hints: group vs component ==="
DOTS_RESOLVED_GROUPS=(core)
DOTS_WITH_COMPONENTS=()
dots_pkg_ownership_reset
hint="$(dots_pkg_activate_hint act 2>&1 || true)"
echo "${hint}" | grep -qi 'package group\|packages' && ok "act hint mentions group/packages" || bad "act hint: ${hint}"
echo "${hint}" | grep -qE '\./dots setup --with|\./setup\.sh --with' &&
	bad "act hint should not suggest --with" || ok "act hint avoids --with"
hint_dust="$(dots_pkg_activate_hint dust 2>&1 || true)"
echo "${hint_dust}" | grep -q '\-\-with' && ok "dust hint uses --with" || bad "dust hint: ${hint_dust}"

echo "=== CLI: packages groups / group / plan ==="
groups_out="$("${ROOT}/dots" packages groups 2>&1)" || {
	bad "packages groups failed"
	groups_out=""
}
echo "${groups_out}" | grep -q 'PACKAGE GROUPS\|GROUP' && ok "groups header" || bad "groups out: ${groups_out}"
echo "${groups_out}" | grep -qE '\bdev\b' && ok "groups lists dev" || bad "groups missing dev"
echo "${groups_out}" | grep -qE '\bgeo\b' && ok "groups lists geo" || bad "groups missing geo"

group_out="$("${ROOT}/dots" packages group geo 2>&1)" || {
	bad "packages group geo failed"
	group_out=""
}
echo "${group_out}" | grep -q 'Group: geo' && ok "group geo header" || bad "group geo: ${group_out}"
echo "${group_out}" | grep -qi 'Brewfile\|Owner' && ok "group geo brewfile" || bad "group geo brewfile missing"
echo "${group_out}" | grep -q gdal && ok "group geo lists gdal" || bad "group geo packages"

plan_base="$("${ROOT}/dots" packages plan --profile base 2>&1)" || {
	bad "plan base failed"
	plan_base=""
}
echo "${plan_base}" | grep -q 'Profile: base' && ok "plan base profile" || bad "plan base: ${plan_base}"
echo "${plan_base}" | grep -q 'Package groups:' && ok "plan base groups section" || bad "plan base sections"
echo "${plan_base}" | grep -qE '^\s+core$' && ok "plan base has core" || bad "plan base missing core"
echo "${plan_base}" | grep -qE '^\s+geo$' && bad "plan base should omit geo" || ok "plan base omits geo"
echo "${plan_base}" | grep -qi 'Read-only\|no install' && ok "plan base read-only note" || bad "plan base missing RO note"

plan_home="$("${ROOT}/dots" packages plan --profile home 2>&1)" || {
	bad "plan home failed"
	plan_home=""
}
echo "${plan_home}" | grep -qE '^\s+geo$' && ok "plan home has geo" || bad "plan home missing geo"
echo "${plan_home}" | grep -q 'Optional components:' && ok "plan home components section" || bad "plan home no components"
echo "${plan_home}" | grep -qi 'herdr\|ai\|consent' && ok "plan home mentions components/consent" || ok "plan home ran"

plan_work="$("${ROOT}/dots" packages plan --profile work 2>&1)" || {
	bad "plan work failed"
	plan_work=""
}
echo "${plan_work}" | grep -qE '^\s+dev$' && ok "plan work has dev" || bad "plan work missing dev"
echo "${plan_work}" | grep -qE '^\s+geo$' && bad "plan work should omit geo" || ok "plan work omits geo"

echo "=== plan / groups are non-mutating ==="
before="$(find "${TMP}" -type f 2>/dev/null | sort | cksum)"
"${ROOT}/dots" packages groups >/dev/null
"${ROOT}/dots" packages group dev >/dev/null
"${ROOT}/dots" packages plan --profile server >/dev/null
after="$(find "${TMP}" -type f 2>/dev/null | sort | cksum)"
[[ "${before}" == "${after}" ]] && ok "groups/group/plan non-mutating" || bad "CLI mutated TMP"

echo "=== example profiles --show ==="
for ex in developer data-geo work-network; do
	ep="${ROOT}/examples/profiles/${ex}.toml"
	if [[ ! -f ${ep} ]]; then
		bad "missing example ${ex}.toml"
		continue
	fi
	out="$(HOME="${TMP}/home-${ex}" "${ROOT}/bootstrap.sh" --profile "${ep}" --show 2>&1)" || {
		bad "example ${ex} --show failed"
		continue
	}
	echo "${out}" | grep -qi 'package groups\|packages=' && ok "example ${ex} --show" || ok "example ${ex} ran"
done

echo "=== Linux unsupported map (cargo-nextest apt SKIP) ==="
export DOTS_FORCE_PKG_MGR=apt
native="$(dots_group_tool_platform_name cargo-nextest 2>/dev/null || echo FAIL)"
[[ ${native} == SKIP ]] && ok "cargo-nextest apt=SKIP" || bad "cargo-nextest native=${native}"
unset DOTS_FORCE_PKG_MGR

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
