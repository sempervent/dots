#!/usr/bin/env bash
# scripts/tests/openrig_install_smoke.sh — optional real-machine OpenRig converge smoke
# Not run in ordinary CI (needs network + fnm). Safe to re-run; idempotent.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

echo "=== OpenRig install smoke (live) ==="
export DIR="${ROOT}"
export DRY_RUN=0
# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/fnm.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/openrig.sh"

dots_fnm_available && ok "fnm present" || bad "fnm missing"
dots_openrig_ensure_node && ok "Node converged" || bad "Node converge"
dots_npm_belongs_to_active_node && ok "npm↔node" || bad "npm↔node"
dots_npm_prefix_user_owned && ok "prefix writable" || bad "prefix"
dots_openrig_install_cli && ok "OpenRig CLI+ABI" || bad "OpenRig CLI+ABI"
command -v "$(dots_openrig_rig_bin)" >/dev/null && ok "rig resolves" || bad "rig"
dots_openrig_check_abi && ok "ABI recheck" || bad "ABI recheck"

# Second pass idempotence
before="$(dots_openrig_version || true)"
dots_openrig_install_cli >/tmp/dots-openrig-idem.out 2>&1 || bad "second install"
echo "$(cat /tmp/dots-openrig-idem.out)" | grep -q 'already installed\|ABI check passed' && ok "idempotent" || bad "idempotent"
after="$(dots_openrig_version || true)"
[[ ${before} == "${after}" ]] && ok "version stable" || bad "version changed"

dots_openrig_doctor && ok "doctor converged" || bad "doctor"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
