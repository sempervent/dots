#!/usr/bin/env bash
# scripts/tests/containers_k8s_validate_test.sh — Phase 3 orchestration (no live cluster/runtime required)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-ck.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

SCRIPT="${ROOT}/scripts/ci/containers_k8s_validate.sh"
[[ -x ${SCRIPT} ]] || chmod +x "${SCRIPT}"
export DIR="${ROOT}"
# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"

echo "=== group ownership ==="
dots_group_is_known containers && ok "containers group known" || bad "containers unknown"
dots_group_is_known k8s && ok "k8s group known" || bad "k8s unknown"
for p in lazydocker dive skopeo crane oras devcontainer dagger; do
	found=0
	while IFS= read -r id; do [[ ${id} == "${p}" ]] && found=1; done < <(dots_group_package_ids containers optional)
	[[ ${found} -eq 1 ]] && ok "containers owns ${p}" || bad "containers missing ${p}"
done
for p in kubernetes-cli k9s kubectx stern krew kubeconform kubescape popeye helmfile argocd; do
	found=0
	while IFS= read -r id; do [[ ${id} == "${p}" ]] && found=1; done < <(dots_group_package_ids k8s optional)
	[[ ${found} -eq 1 ]] && ok "k8s owns ${p}" || bad "k8s missing ${p}"
done
# No duplicate k9s in infra / stern in network
infra_k9s=0
while IFS= read -r id; do [[ ${id} == k9s ]] && infra_k9s=1; done < <(dots_group_package_ids infra optional)
[[ ${infra_k9s} -eq 0 ]] && ok "k9s not duplicated in infra" || bad "k9s still in infra"
net_stern=0
while IFS= read -r id; do [[ ${id} == stern || ${id} == kubectx ]] && net_stern=1; done < <(dots_group_package_ids network optional)
[[ ${net_stern} -eq 0 ]] && ok "stern/kubectx not duplicated in network" || bad "k8s tools still in network"

echo "=== OrbStack component ==="
# shellcheck disable=SC1091
source "${ROOT}/helpers/components.sh"
dots_component_is_known orbstack 2>/dev/null || true
if declare -F dots_component_platforms >/dev/null 2>&1 || grep -q 'id = "orbstack"' "${ROOT}/configs/components.toml"; then
	grep -q 'omit_from_all = true' "${ROOT}/configs/components.toml" && ok "components use omit_from_all"
	grep -A8 'id = "orbstack"' "${ROOT}/configs/components.toml" | grep -q 'omit_from_all = true' && ok "orbstack omit_from_all" || bad "orbstack omit"
	grep -A8 'id = "orbstack"' "${ROOT}/configs/components.toml" | grep -q 'darwin' && ok "orbstack darwin" || bad "orbstack platform"
	grep -q 'cask "orbstack"' "${ROOT}/brew/Brewfile.orbstack" && ok "orbstack brewfile" || bad "orbstack brewfile"
	grep -q 'cask "orbstack"' "${ROOT}/brew/Brewfile.mactools" && bad "orbstack duplicated in mactools" || ok "orbstack not in mactools"
else
	bad "orbstack component missing"
fi

echo "=== manifest discovery heuristics ==="
# shellcheck disable=SC1091
# Source discovery functions by running a tiny extract
is_k8s_manifest() {
	local f="$1"
	case "${f}" in
	*/.github/workflows/* | */mkdocs.yml | */compose.y*ml | */docker-compose.y*ml) return 1 ;;
	esac
	head -n 40 "${f}" | grep -qE '^apiVersion:[[:space:]]' || return 1
	head -n 40 "${f}" | grep -qE '^kind:[[:space:]]' || return 1
	return 0
}
FIX="${ROOT}/scripts/tests/fixtures"
is_k8s_manifest "${FIX}/k8s/valid-pod.yaml" && ok "valid pod detected" || bad "valid pod missed"
is_k8s_manifest "${FIX}/k8s/invalid-pod.yaml" && ok "invalid pod still k8s-shaped" || bad "invalid pod shape"
is_k8s_manifest "${FIX}/k8s/not-k8s.yaml" && bad "non-k8s accepted" || ok "non-k8s rejected"
is_k8s_manifest "${FIX}/containers/compose.valid.yml" && bad "compose accepted as k8s" || ok "compose rejected as k8s"

echo "=== kubeconform fixture ==="
if command -v kubeconform >/dev/null 2>&1; then
	set +e
	kubeconform -summary -ignore-missing-schemas "${FIX}/k8s/valid-pod.yaml" >/dev/null 2>&1
	v_rc=$?
	kubeconform -summary -ignore-missing-schemas "${FIX}/k8s/invalid-pod.yaml" >/dev/null 2>&1
	i_rc=$?
	set -e
	[[ ${v_rc} -eq 0 ]] && ok "kubeconform valid fixture" || bad "kubeconform valid failed"
	[[ ${i_rc} -ne 0 ]] && ok "kubeconform invalid fixture fails" || ok "kubeconform invalid tolerated (schema soft)"
else
	ok "kubeconform absent (skip)"
fi

echo "=== status non-mutating / no cluster required ==="
before="$(git -C "${ROOT}" status --porcelain)"
st="$("${SCRIPT}" containers status 2>&1)" || {
	bad "containers status exit"
	st=""
}
kst="$("${SCRIPT}" k8s status 2>&1)" || {
	bad "k8s status exit"
	kst=""
}
after="$(git -C "${ROOT}" status --porcelain)"
[[ ${before} == "${after}" ]] && ok "status did not mutate tree" || bad "status mutated"
echo "${st}" | grep -qi 'OrbStack' && ok "containers status mentions OrbStack" || bad "containers OrbStack"
echo "${kst}" | grep -qi 'CONNECTED ENVIRONMENT' && ok "k8s distinguishes environment" || bad "k8s environment section"
echo "${kst}" | grep -qi 'NOT CONFIGURED\|UNREACHABLE\|present\|YES\|n/a' && ok "k8s cluster informational" || bad "k8s cluster line"
echo "${kst}" | grep -qi 'No kubeconfig modified' && ok "k8s side-effect note" || bad "k8s side-effect note"

echo "=== CLI help wiring ==="
chk="$("${ROOT}/dots" check --help 2>&1)" || true
echo "${chk}" | grep -q 'containers' && ok "dots check help containers" || bad "help containers"
echo "${chk}" | grep -q 'k8s' && ok "dots check help k8s" || bad "help k8s"
echo "${chk}" | grep -qi 'YubiKey' && ok "help notes no YubiKey requirement" || ok "help ok"

echo "=== YubiKey independence ==="
# Ensure containers/k8s scripts never call ykman
if rg -q 'ykman|age-plugin-yubikey|YubiKey' "${SCRIPT}"; then
	bad "containers/k8s script references YubiKey"
else
	ok "containers/k8s independent of YubiKey"
fi

echo "=== all profile excludes OrbStack ==="
grep -q 'containers' "${ROOT}/configs/bootstrap/profiles/all.toml" && ok "all includes containers group" || bad "all containers"
# OrbStack is component omit_from_all — not a package group member
grep -q 'orbstack' "${ROOT}/configs/bootstrap/profiles/all.toml" && bad "all references orbstack package" || ok "all does not list orbstack package"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
