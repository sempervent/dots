#!/usr/bin/env bash
# scripts/tests/leaf_packages_test.sh — v1.13 explicit leaf package desired state
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

# shellcheck source=../ci/helpers.sh
source "${ROOT}/scripts/ci/helpers.sh" 2>/dev/null || true

pass() { echo "OK: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
ok=0
bad() { ok=$((ok + 1)); fail "$*"; }

CUST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/dots-leaf-test.XXXXXX")"
export HOME="${CUST_HOME}"
export DOTS_FORCE_OS=darwin
export DOTS_FORCE_PKG_MGR=brew
export DOTS_PKG_DISABLE_HOST_WHICH=1
export DOTS_UI_NONINTERACTIVE=1
export DOTS_UI_ANSWERS=$'y\n'

# --- leaf metadata ---
meta="$("${ROOT}/dots" profile resolve raycast --json 2>/dev/null)"
echo "${meta}" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("leaf_selectable") is True, d
assert d.get("via_package") == "raycast"
' && pass "raycast leaf_selectable on Darwin" || bad "raycast leaf metadata"

meta="$("${ROOT}/dots" profile resolve component:openrig --json 2>/dev/null)"
echo "${meta}" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("owner") == "component:openrig"
' && pass "openrig resolves as component" || bad "openrig resolve"

# --- install --only dry-run (fresh profile, before explicit include) ---
dry="$("${ROOT}/dots" install raycast --only --dry-run --yes --profile base 2>&1)" || true
echo "${dry}" | grep -q '+ package:raycast' && pass "install --only dry-run adds package only" || bad "dry-run: ${dry}"
echo "${dry}" | grep -qv '+ component:mactools' && pass "install --only does not add mactools" || bad "dry-run added mactools"

# --- profile include persistence ---
"${ROOT}/dots" profile add-package raycast --profile base --yes >/dev/null
overlay="${HOME}/.config/dots/profiles/base-local.toml"
[[ -f ${overlay} ]] && grep -q 'raycast' "${overlay}" && pass "add-package writes packages.include" || bad "overlay missing raycast include"

show="$("${ROOT}/dots" profile show --json --profile base-local 2>/dev/null)"
echo "${show}" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("explicit_packages",{}).get("raycast",{}).get("state")=="local", d
' && pass "profile show --json explicit_packages.local" || bad "show json explicit_packages"

hyper="$("${ROOT}/dots" profile resolve hyperfine --json 2>/dev/null)"
echo "${hyper}" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("leaf_selectable") is True, d
' && pass "hyperfine group-owned leaf-selectable" || bad "hyperfine leaf"

rm -rf "${CUST_HOME}"
echo ""
echo "Passed: ${ok}"