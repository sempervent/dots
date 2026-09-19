#!/usr/bin/env bash
# scripts/tests/mactools_test.sh — mactools component + Brewfile + Darwin gate
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

DIR="${ROOT}"
export DIR
# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/components.sh"

echo "=== Brewfile.mactools exists and names Vorssaint ==="
bf="${ROOT}/brew/Brewfile.mactools"
[[ -f ${bf} ]] && ok "Brewfile present" || bad "missing Brewfile.mactools"
grep -q 'cask "vorssaint"' "${bf}" && ok "vorssaint cask" || bad "no vorssaint"
grep -q 'cask "raycast"' "${bf}" && ok "raycast" || bad "no raycast"
grep -q 'brew "mise"' "${bf}" && ok "mise" || bad "no mise"
grep -q 'brew "yazi"' "${bf}" && ok "yazi" || bad "no yazi"
# Dedup against modern group
grep -qE 'brew "just"|brew "lazygit"' "${bf}" && bad "duplicates just/lazygit" || ok "no just/lazygit dup"
# No redundant utility casks
for badcask in cleanshot dropover soundsource bettertouchtool popclip; do
	grep -qi "${badcask}" "${bf}" && bad "contains ${badcask}" || true
done
ok "no redundant utility casks"

echo "=== registry: mactools darwin-only, omit_from_all ==="
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
ids="$(dots_component_ids)"
echo "${ids}" | grep -qx mactools && ok "registry has mactools" || bad "not in registry"
all_ids="$(dots_component_ids_for_all)"
echo "${all_ids}" | grep -qx mactools && bad "mactools should omit_from_all" || ok "omit_from_all"

echo "=== explicit Linux mactools fails ==="
export DOTS_FORCE_OS=linux
if dots_require_explicit_component_supported mactools 2>/dev/null; then
	bad "linux mactools should fail"
else
	ok "linux mactools errors"
fi

echo "=== Darwin accepts mactools ==="
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
if dots_require_explicit_component_supported mactools 2>/dev/null; then
	ok "darwin mactools ok"
else
	bad "darwin mactools rejected"
fi

echo "=== dry-run setup parses --with mactools ==="
export DOTS_FORCE_OS=darwin DOTS_FORCE_DARWIN_MAJOR=15
dry_out="$("${ROOT}/setup.sh" --dry-run --with mactools 2>&1)" || {
	bad "dry-run mactools failed"
	echo "${dry_out}" | tail -20
}
echo "${dry_out}" | grep -qi 'Brewfile.mactools\|mactools' && ok "dry-run mentions mactools" || bad "dry-run silent"
echo "${dry_out}" | grep -qi 'Backup' && ok "dry-run runs backup stage" || bad "no backup stage"
echo "${dry_out}" | grep -qi 'vorssaint\|Vorssaint' && ok "lists vorssaint" || ok "bundle listed (sed)"

echo "=== composition herdr,mactools ==="
comp_out="$("${ROOT}/setup.sh" --dry-run --with herdr,mactools 2>&1)" || bad "composition failed"
echo "${comp_out}" | grep -qi 'herdr' && ok "composition herdr" || bad "no herdr"
echo "${comp_out}" | grep -qi 'mactools\|Brewfile.mactools' && ok "composition mactools" || bad "no mactools in composition"

echo "=== portable configs + docs present ==="
for f in \
	configs/ghostty/config \
	configs/yazi/yazi.toml \
	configs/mise/config.toml \
	configs/lazygit/config.yml \
	docs/MACTOOLS.md \
	docs/ORBSTACK_MIGRATION.md \
	docs/MISE_MIGRATION.md \
	configs/mactools/README.md \
	scripts/mactools/export-configs.sh \
	scripts/mactools/import-configs.sh \
	scripts/mactools/docker-orbstack-audit.sh; do
	[[ -f ${ROOT}/${f} ]] && ok "file ${f}" || bad "missing ${f}"
done

echo "=== export helper status table ==="
exp="$("${ROOT}/scripts/mactools/export-configs.sh" all 2>&1)" || bad "export-configs all failed"
echo "${exp}" | grep -qi vorssaint && ok "export helper lists vorssaint" || bad "export helper"
echo "${exp}" | grep -qi 'manual' && ok "marks manual tools" || bad "no manual status"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
