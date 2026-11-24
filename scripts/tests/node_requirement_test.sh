#!/usr/bin/env bash
# Semantic Node constraints for capability runtimes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/helpers/fnm.sh"
DIR="${ROOT}"

pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

dots_node_version_satisfies "22.20.0" ">=22.20.0" && ok "22.20 satisfies skills floor" || bad "22.20 should satisfy"
dots_node_version_satisfies "22.19.0" ">=22.20.0" && bad "22.19 must not satisfy skills floor" || ok "22.19 rejected"
dots_node_version_satisfies "24.11.0" ">=22.19.0" && ok "24 satisfies pi floor" || bad "24 should satisfy pi"
dots_node_version_satisfies "v22.20.1" ">=22.20.0" && ok "v prefix accepted" || bad "v prefix rejected"

constraint="$(dots_runtime_node_constraint skills-cli)"
[[ ${constraint} == ">=22.20.0" ]] && ok "skills-cli constraint from registry" || bad "skills-cli constraint is ${constraint}"

echo "passed=${pass} failed=${fail}"
[[ ${fail} -eq 0 ]]
