#!/usr/bin/env bash
# scripts/tests/local_validate_test.sh — Phase 1 local CI orchestration (no third-party internals)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-lv.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

SCRIPT="${ROOT}/scripts/ci/local_validate.sh"
[[ -x ${SCRIPT} ]] || chmod +x "${SCRIPT}"

echo "=== usage / mode discovery ==="
out="$("${SCRIPT}" --help 2>&1)" || {
	bad "help exit"
	out=""
}
echo "${out}" | grep -q 'fast' && ok "help lists fast" || bad "help fast"
echo "${out}" | grep -q 'workflows' && ok "help lists workflows" || bad "help workflows"
echo "${out}" | grep -q 'docs' && ok "help lists docs" || bad "help docs"
echo "${out}" | grep -q 'all-local' && ok "help lists all-local" || bad "help all-local"
echo "${out}" | grep -q 'release-notes' && ok "help lists release-notes" || bad "help release-notes"
echo "${out}" | grep -q 'setup.sh --packages' && ok "help hints package group" || bad "help package hint"

set +e
bad_mode="$("${SCRIPT}" not-a-mode 2>&1)"
bad_rc=$?
set -e
[[ ${bad_rc} -ne 0 ]] && ok "unknown mode nonzero" || bad "unknown mode zero"
echo "${bad_mode}" | grep -qi 'Unknown mode' && ok "unknown mode message" || bad "unknown mode text"

echo "=== dots check dispatcher ==="
chk="$("${ROOT}/dots" check --help 2>&1)" || true
echo "${chk}" | grep -q 'check fast' && ok "dots check --help fast" || bad "dots check help"
echo "${chk}" | grep -q 'release-notes' && ok "dots check --help release-notes" || bad "dots check release-notes"

echo "=== missing tool actionable error ==="
mkdir -p "${TMP}/emptybin"
# Provide only bash/coreutils; omit validators.
for c in bash sh mkdir cat printf echo awk sed grep tr find ls sort uniq head tail cut env true false mktemp; do
	p=$(command -v "$c" 2>/dev/null || true)
	[[ -n ${p} && -x ${p} ]] && ln -sfn "${p}" "${TMP}/emptybin/${c}"
done
set +e
miss_out="$(PATH="${TMP}/emptybin" "${SCRIPT}" workflows 2>&1)"
miss_rc=$?
set -e
[[ ${miss_rc} -ne 0 ]] && ok "missing tool exits nonzero" || bad "missing tool exit 0"
echo "${miss_out}" | grep -qi 'missing required tool' && ok "missing tool named" || bad "missing tool text"
echo "${miss_out}" | grep -qi "package group 'dev'\|--packages.*dev\|--profile work" && ok "missing tool hints setup" || bad "missing tool hint: ${miss_out}"

echo "=== fixture: actionlint syntax failure ==="
FIX="${TMP}/repo"
mkdir -p "${FIX}/.github/workflows"
cat >"${FIX}/.github/workflows/bad.yml" <<'YAML'
name: bad
on: push
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: echo ${{ github.event.invalid
YAML
# local_validate.sh derives ROOT from its path; invoke tools directly for fixtures.
if command -v actionlint >/dev/null 2>&1; then
	set +e
	actionlint -shellcheck= "${FIX}/.github/workflows/bad.yml" >/dev/null 2>&1
	al_rc=$?
	set -e
	[[ ${al_rc} -ne 0 ]] && ok "actionlint fails invalid workflow" || bad "actionlint accepted invalid workflow"
else
	ok "actionlint absent (skip fixture assert)"
fi

echo "=== fixture: zizmor security finding ==="
cat >"${FIX}/.github/workflows/danger.yml" <<'YAML'
name: danger
on: push
permissions: write-all
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
YAML
if command -v zizmor >/dev/null 2>&1; then
	set +e
	zizmor --offline --min-severity=low "${FIX}/.github/workflows/danger.yml" >/dev/null 2>&1
	zz_rc=$?
	set -e
	[[ ${zz_rc} -ne 0 ]] && ok "zizmor fails dangerous workflow" || bad "zizmor accepted dangerous workflow"
else
	ok "zizmor absent (skip fixture assert)"
fi

echo "=== fixture: markdownlint / cspell / broken link offline ==="
mkdir -p "${FIX}/docs"
printf '# Title\n\nHello\n' >"${FIX}/ok.md"
printf '# Title\n###### skipped level\n' >"${FIX}/bad.md"
printf '# Spell\n\nThis has zzqxwordtypo\n' >"${FIX}/spell.md"
printf '# Links\n\nSee [missing](./no-such-file.md).\n' >"${FIX}/link.md"

if command -v markdownlint-cli2 >/dev/null 2>&1; then
	set +e
	(
		cd "${FIX}"
		markdownlint-cli2 --config "${ROOT}/.markdownlint-cli2.jsonc" "bad.md" >/dev/null 2>&1
	)
	md_rc=$?
	set -e
	[[ ${md_rc} -ne 0 ]] && ok "markdownlint fails invalid md" || bad "markdownlint accepted invalid md"
else
	ok "markdownlint absent (skip)"
fi

if command -v cspell >/dev/null 2>&1; then
	set +e
	cspell --no-progress --config "${ROOT}/cspell.json" "${FIX}/spell.md" >/dev/null 2>&1
	cs_rc=$?
	set -e
	[[ ${cs_rc} -ne 0 ]] && ok "cspell fails misspelling" || bad "cspell accepted typo"
else
	ok "cspell absent (skip)"
fi

if command -v lychee >/dev/null 2>&1; then
	set +e
	lychee --config "${ROOT}/.lychee.toml" --no-progress --exclude '^https?://' "${FIX}/link.md" >/dev/null 2>&1
	ly_rc=$?
	set -e
	[[ ${ly_rc} -ne 0 ]] && ok "lychee fails broken internal link" || bad "lychee accepted broken link"
else
	ok "lychee absent (skip)"
fi

echo "=== package ownership: Phase 1 ADD tools in dev only ==="
export DIR="${ROOT}"
# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"
for pkg in zizmor git-cliff lychee markdownlint-cli2 cspell; do
	found=0
	while IFS= read -r id; do
		[[ ${id} == "${pkg}" ]] && found=1
	done < <(dots_group_package_ids dev required; dots_group_package_ids dev optional)
	[[ ${found} -eq 1 ]] && ok "dev owns ${pkg}" || bad "dev missing ${pkg}"
done
for pkg in act actionlint pre-commit hadolint; do
	found=0
	while IFS= read -r id; do
		[[ ${id} == "${pkg}" ]] && found=1
	done < <(dots_group_package_ids dev required; dots_group_package_ids dev optional)
	[[ ${found} -eq 1 ]] && ok "dev still owns ${pkg}" || bad "lost ownership ${pkg}"
done
# Ensure security group did not gain zizmor duplicate ownership
sec_has=0
while IFS= read -r id; do
	[[ ${id} == zizmor ]] && sec_has=1
done < <(dots_group_package_ids security required; dots_group_package_ids security optional)
[[ ${sec_has} -eq 0 ]] && ok "zizmor not duplicated in security" || bad "zizmor duplicated in security"

echo "=== release-notes non-mutating ==="
if command -v git-cliff >/dev/null 2>&1; then
	before="$(git -C "${ROOT}" status --porcelain)"
	set +e
	rn_out="$("${SCRIPT}" release-notes 2>/dev/null)"
	rn_rc=$?
	set -e
	after="$(git -C "${ROOT}" status --porcelain)"
	[[ ${rn_rc} -eq 0 ]] && ok "release-notes exits 0" || bad "release-notes rc=${rn_rc}"
	[[ ${before} == "${after}" ]] && ok "release-notes did not mutate tree" || bad "release-notes mutated tree"
	[[ -n ${rn_out} || ${rn_rc} -eq 0 ]] && ok "release-notes produced stdout or empty history ok" || bad "release-notes empty unexpected"
else
	ok "git-cliff absent (skip release-notes)"
fi

echo "=== act helper does not auto-forward secrets ==="
# Inspect script source contract (ignore comments mentioning -s).
rg -q 'Never forward host secrets' "${SCRIPT}" && ok "act secrets comment present" || bad "act secrets comment"
if rg -n '^\s*act\b' "${SCRIPT}" | rg -q -- '--secret|\s-s\s|\s-s='; then
	bad "act passes -s/--secret"
else
	ok "act does not pass secrets flags"
fi
rg -q 'Docker Desktop|OrbStack' "${SCRIPT}" && ok "act documents no auto-start runtime" || bad "act runtime docs"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
