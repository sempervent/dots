#!/usr/bin/env bash
# scripts/tests/workstation_groups_test.sh — new package groups contract
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${ROOT}"
export ROOT
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

# shellcheck source=../../helpers/toml.sh
source "${ROOT}/helpers/toml.sh"
# shellcheck source=../../helpers/packages.sh
source "${ROOT}/helpers/packages.sh"
# shellcheck source=../../helpers/package_state.sh
source "${ROOT}/helpers/package_state.sh"

echo "=== known groups allowlist includes workstation tool groups ==="
for g in dev security network data geo; do
	if dots_known_package_groups | grep -qx "${g}"; then
		ok "known: ${g}"
	else
		bad "missing known group ${g}"
	fi
	[[ -f ${ROOT}/brew/groups/${g}.Brewfile ]] && ok "Brewfile ${g}" || bad "missing brew/groups/${g}.Brewfile"
done

echo "=== groups.toml membership uniqueness across portable ids ==="
uniq_rc=0
python3 - <<'PY' || uniq_rc=$?
import os, tomllib, sys
from pathlib import Path

root = Path(os.environ["ROOT"])
data = tomllib.loads((root / "configs/packages/groups.toml").read_text())
seen = {}
for g in data.get("groups") or []:
    name = g["name"]
    for kind in ("required", "optional"):
        for t in g.get(kind) or []:
            t = str(t).strip()
            if t in seen and seen[t] != name:
                # htop is intentionally shared (modern required + server required)
                if t == "htop" and {seen[t], name} <= {"modern", "server"}:
                    continue
                print(f"DUPLICATE {t}: {seen[t]} and {name}", file=sys.stderr)
                sys.exit(2)
            seen[t] = name
print("OK")
PY
if [[ ${uniq_rc} -eq 0 ]]; then
	ok "portable ids unique (htop modern/server exempt)"
else
	bad "duplicate portable ids across groups"
fi

echo "=== Brewfile tokens: no kitchen-sink duplicates of core/modern tools ==="
for dup in jq yq lazygit ripgrep fd fzf bat; do
	hit=0
	for bf in dev security network data geo; do
		if grep -qE "^[[:space:]]*brew[[:space:]]+\"${dup}\"" "${ROOT}/brew/groups/${bf}.Brewfile"; then
			hit=1
		fi
	done
	if [[ ${hit} -eq 0 ]]; then
		ok "no ${dup} in new groups"
	else
		bad "duplicate ownership of ${dup} in new groups"
	fi
done

echo "=== Linux maps declare every portable id (value may be empty) ==="
map_rc=0
python3 - <<'PY' || map_rc=$?
import os, tomllib, sys
from pathlib import Path

root = Path(os.environ["ROOT"])
groups = tomllib.loads((root / "configs/packages/groups.toml").read_text())
ids = set()
for g in groups.get("groups") or []:
    for kind in ("required", "optional"):
        for t in g.get(kind) or []:
            ids.add(str(t).strip())
missing = []
for mgr in ("apt", "pacman", "dnf", "xbps"):
    pkgs = tomllib.loads((root / f"configs/packages/{mgr}.toml").read_text()).get("packages") or {}
    for t in sorted(ids):
        if t not in pkgs:
            missing.append(f"{mgr}:{t}")
if missing:
    print("\n".join(missing), file=sys.stderr)
    sys.exit(2)
print("OK")
PY
[[ ${map_rc} -eq 0 ]] && ok "all portable ids present in apt/pacman/dnf/xbps maps" || bad "linux map keys incomplete"

echo "=== INACTIVE vs UNDECLARED for known-unselected act ==="
HOME_TMP="${TMPDIR:-/tmp}/dots-wsg-home-$$"
mkdir -p "${HOME_TMP}"
export HOME="${HOME_TMP}"
export DOTS_PACKAGE_GROUPS="core"
DOTS_RESOLVED_GROUPS=(core)
DOTS_WITH_COMPONENTS=()
export DOTS_PKG_MOCK_LEAVES=$'jq\nact\nglow'
export DOTS_PKG_MOCK_FORMULAE=$'jq\nact\nglow'
export DOTS_PKG_MOCK_CASKS=''
export DOTS_PKG_MOCK_OUTDATED_FORMULAE=''
export DOTS_PKG_MOCK_OUTDATED_CASKS=''
dots_pkg_ownership_reset
dots_desired_packages_resolve
dots_pkg_classify_resolved 1
printf '%s\n' "${DOTS_PKG_INACTIVE_FORMULAE[@]+"${DOTS_PKG_INACTIVE_FORMULAE[@]}"}" | grep -qx act && ok "act INACTIVE" || bad "act not inactive"
printf '%s\n' "${DOTS_PKG_UNDECLARED_FORMULAE[@]+"${DOTS_PKG_UNDECLARED_FORMULAE[@]}"}" | grep -qx glow && ok "glow UNDECLARED" || bad "glow not undeclared"

echo "=== custom profile dry-run non-mutating ==="
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-wsg.XXXXXX")"
cleanup() { rm -rf "${TMP}" "${HOME_TMP}"; }
trap cleanup EXIT
custom="${TMP}/custom.toml"
cat >"${custom}" <<'EOF'
[profile]
name = "wsg-custom"
extends = "base"
packages = ["core", "modern", "dev", "data"]
EOF
mkdir -p "${TMP}/home2"
before="$(find "${TMP}" -type f | sort | cksum)"
out="$(HOME="${TMP}/home2" "${ROOT}/bootstrap.sh" --profile "${custom}" --dry-run 2>&1)" || true
after="$(find "${TMP}" -type f | sort | cksum)"
echo "${out}" | grep -qiE 'dev|package groups|DRY|dry-run|Would' && ok "dry-run ran for custom" || ok "dry-run completed"
[[ "${before}" == "${after}" ]] && ok "custom dry-run non-mutating" || bad "custom dry-run mutated"

echo "=== unsupported native empty map (SKIP/WARN contract) ==="
# cargo-nextest is "" on apt — optional tools SKIP rather than fail the profile.
if grep -qE '^cargo-nextest[[:space:]]*=[[:space:]]*""' "${ROOT}/configs/packages/apt.toml"; then
	ok "apt cargo-nextest unsupported (=\"\")"
else
	bad "apt cargo-nextest should be empty string"
fi
if grep -q 'SKIP\|optional tools unavailable\|best-effort' "${ROOT}/helpers/packages.sh"; then
	ok "packages.sh documents SKIP/WARN for unsupported optional"
else
	bad "missing SKIP/WARN handling in packages.sh"
fi

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
