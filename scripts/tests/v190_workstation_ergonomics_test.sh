#!/usr/bin/env bash
# scripts/tests/v190_workstation_ergonomics_test.sh — v1.9 ownership + safety
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${ROOT}"
export DIR ROOT
unset DOTS_GROUPS_REGISTRY 2>/dev/null || true
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

MT="${ROOT}/brew/Brewfile.mactools"
# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/components.sh"

group_owns() {
	local grp="$1" pkg="$2"
	local found=0
	while IFS= read -r id; do [[ ${id} == "${pkg}" ]] && found=1; done < <(dots_group_package_ids "${grp}" optional)
	[[ ${found} -eq 1 ]]
}

echo "=== portable CLI promotion ==="
for pkg in mise yazi watchexec hyperfine mprocs xh dust duf; do
	if [[ ${pkg} == mprocs ]]; then
		grep -qE 'brew "dekit"|brew "mprocs"' "${MT}" && bad "${pkg} still in mactools" || ok "${pkg} not in mactools"
	else
		grep -q "brew \"${pkg}\"" "${MT}" && bad "${pkg} still in mactools" || ok "${pkg} not in mactools"
	fi
done
for pkg in mise dust duf jc navi sd procs ouch; do
	group_owns modern "${pkg}" && ok "modern owns ${pkg}" || bad "modern missing ${pkg}"
done
for pkg in yazi; do
	group_owns workstation "${pkg}" && ok "workstation owns ${pkg}" || bad "workstation missing ${pkg}"
done
for pkg in watchexec hyperfine mprocs xh hexyl tokei; do
	group_owns dev "${pkg}" && ok "dev owns ${pkg}" || bad "dev missing ${pkg}"
done
for pkg in kustomize kyverno; do
	group_owns k8s "${pkg}" && ok "k8s owns ${pkg}" || bad "k8s missing ${pkg}"
done
group_owns infra conftest && ok "infra owns conftest" || bad "infra missing conftest"

echo "=== brewfile ownership (no duplicates) ==="
for pkg in mise dust duf jc navi sd procs ouch; do
	count="$(rg -l "brew \"${pkg}\"" "${ROOT}/brew/groups" 2>/dev/null | wc -l | tr -d ' ')"
	[[ ${count} -eq 1 ]] && ok "single modern owner ${pkg}" || bad "dup ${pkg} (${count})"
done
grep -q 'brew "yazi"' "${ROOT}/brew/groups/workstation.Brewfile" && ok "yazi workstation brew" || bad "yazi brew"
grep -qE 'brew "dekit"|brew "mprocs"' "${ROOT}/brew/groups/dev.Brewfile" && ok "mprocs/dekit dev brew" || bad "dekit dev brew"
grep -q 'brew "kustomize"' "${ROOT}/brew/groups/k8s.Brewfile" && ok "kustomize k8s" || bad "kustomize"
grep -q 'brew "conftest"' "${ROOT}/brew/groups/infra.Brewfile" && ok "conftest infra" || bad "conftest"

echo "=== macOS casks in mactools only ==="
for cask in hammerspoon swiftbar betterdisplay pearcleaner keka iina; do
	grep -qi "cask \"${cask}\"" "${MT}" && ok "mactools ${cask}" || bad "missing ${cask}"
	count="$(rg -l "cask \"${cask}\"" "${ROOT}/brew" 2>/dev/null | wc -l | tr -d ' ')"
	[[ ${count} -eq 1 ]] && ok "single cask owner ${cask}" || bad "dup cask ${cask}"
done

echo "=== Karabiner component ==="
grep -A12 'id = "karabiner-elements"' "${ROOT}/configs/components.toml" | grep -q 'omit_from_all = true' && ok "karabiner omit_from_all" || bad "karabiner omit"
grep -A12 'id = "karabiner-elements"' "${ROOT}/configs/components.toml" | grep -q 'darwin' && ok "karabiner darwin" || bad "karabiner platform"
grep -q 'cask "karabiner-elements"' "${ROOT}/brew/Brewfile.karabiner-elements" && ok "karabiner brewfile" || bad "karabiner brewfile"
grep -q 'karabiner' "${MT}" && bad "karabiner in mactools" || ok "karabiner not in mactools"
dots_component_ids_for_all | grep -qx karabiner-elements && bad "karabiner in all" || ok "karabiner not in all"
export DOTS_FORCE_OS=linux
dots_require_explicit_component_supported karabiner-elements 2>/dev/null && bad "linux karabiner ok" || ok "linux karabiner blocked"
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
dots_require_explicit_component_supported karabiner-elements 2>/dev/null && ok "darwin karabiner ok" || bad "darwin karabiner"

echo "=== fnm / Pi / OpenRig / nvm ==="
grep -q 'brew "fnm"' "${ROOT}/brew/groups/core.Brewfile" && ok "fnm in core" || bad "fnm"
rg -q 'brew "nvm"' "${ROOT}/brew" 2>/dev/null && bad "nvm brew" || ok "no nvm"
rg -qi 'never nvm|Do NOT use nvm' "${ROOT}/helpers/fnm.sh" "${ROOT}/helpers/openrig.sh" && ok "nvm policy" || bad "nvm policy"
grep -q 'id = "pi"' "${ROOT}/configs/components.toml" && ok "pi component" || bad "pi"
rg -q 'mise activate|eval "\$\(mise' "${ROOT}/setup.sh" "${ROOT}/helpers" 2>/dev/null | rg -v 'mactools.sh|migration|\.md' && bad "mise auto-activate" || ok "no mise activate in setup"

echo "=== no GUI launch / permission mutation in setup helpers ==="
for pat in 'open -a.*Hammerspoon' 'open -a.*SwiftBar' 'open -a.*Karabiner' 'tccutil' 'systemextensionsctl' 'defaults write.*karabiner'; do
	rg -q "${pat}" "${ROOT}/setup.sh" "${ROOT}/helpers/mactools.sh" 2>/dev/null && bad "forbidden: ${pat}" || ok "absent ${pat}"
done

echo "=== shell keybinding docs unchanged (navi install-only) ==="
[[ -f ${ROOT}/scripts/tests/keybinding_collision_test.sh ]] && ok "keybinding test exists" || bad "keybinding test"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]