#!/usr/bin/env bash
# scripts/tests/dev_validate_test.sh — Phase 4 developer tooling (non-mutating)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-dev.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

SCRIPT="${ROOT}/scripts/ci/dev_validate.sh"
[[ -x ${SCRIPT} ]] || chmod +x "${SCRIPT}"
export DIR="${ROOT}"
# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"

echo "=== modern package ownership ==="
for p in jj git-town git-filter-repo git-sizer ast-grep lnav; do
	found=0
	while IFS= read -r id; do [[ ${id} == "${p}" ]] && found=1; done < <(dots_group_package_ids modern optional)
	[[ ${found} -eq 1 ]] && ok "modern owns ${p}" || bad "modern missing ${p}"
done

echo "=== GUI / mitmproxy ownership ==="
grep -q 'cask "bruno"' "${ROOT}/brew/Brewfile.mactools" && ok "Bruno in mactools" || bad "Bruno missing"
grep -q 'cask "proxyman"' "${ROOT}/brew/Brewfile.mactools" && ok "Proxyman in mactools" || bad "Proxyman missing"
grep -q 'cask "mitmproxy"' "${ROOT}/brew/Brewfile.mitmproxy" && ok "mitmproxy brewfile" || bad "mitmproxy brewfile"
grep -A10 'id = "mitmproxy"' "${ROOT}/configs/components.toml" | grep -q 'omit_from_all = true' && ok "mitmproxy omit_from_all" || bad "mitmproxy omit"
# Not in network group default packages
net_mitm=0
while IFS= read -r id; do [[ ${id} == mitmproxy ]] && net_mitm=1; done < <(dots_group_package_ids network optional)
[[ ${net_mitm} -eq 0 ]] && ok "mitmproxy not in network group defaults" || bad "mitmproxy in network group"

echo "=== status non-mutating ==="
before_git="$(git -C "${ROOT}" rev-parse HEAD)"
before_cfg="$(cksum "${ROOT}/.git/config" | awk '{print $1}')"
before_tree="$(git -C "${ROOT}" status --porcelain)"
had_jj=0
[[ -d ${ROOT}/.jj ]] && had_jj=1
st="$("${SCRIPT}" status 2>&1)" || {
	bad "status exit"
	st=""
}
after_git="$(git -C "${ROOT}" rev-parse HEAD)"
after_cfg="$(cksum "${ROOT}/.git/config" | awk '{print $1}')"
after_tree="$(git -C "${ROOT}" status --porcelain)"
[[ ${before_git} == "${after_git}" ]] && ok "HEAD unchanged" || bad "HEAD changed"
[[ ${before_cfg} == "${after_cfg}" ]] && ok ".git/config unchanged" || bad ".git/config changed"
[[ ${before_tree} == "${after_tree}" ]] && ok "working tree porcelain unchanged" || bad "tree mutated"
if [[ ${had_jj} -eq 0 && -d ${ROOT}/.jj ]]; then
	bad ".jj created by status"
else
	ok "no .jj auto-created"
fi
echo "${st}" | grep -qi 'Git remains default' && ok "status states Git default" || bad "Git default note"
echo "${st}" | grep -qi 'No jj init\|history rewrite\|proxy start' && ok "status side-effect notes" || bad "side-effect notes"

echo "=== no destructive commands in check paths ==="
# Script must not invoke history rewrite / town sync / ast-grep -U as commands.
if rg -n '(^|[^[:alnum:]_-])(git filter-repo|jj git init|git town sync|git town hack|ast-grep -U)([[:space:]]|$)' \
	"${ROOT}/scripts/ci/dev_validate.sh" 2>/dev/null |
	rg -v '^\s*#|:' | grep -q .; then
	bad "destructive/mutating invocation in validate scripts"
else
	ok "no destructive invocations in validate scripts"
fi
# Version probes for mitmproxy are OK; bare proxy start is not.
if rg -n 'mitmproxy[[:space:]]+[^-]|mitmdump[[:space:]]+[^-]|mitmweb[[:space:]]+[^-]' \
	"${ROOT}/scripts/ci/dev_validate.sh" 2>/dev/null | grep -q .; then
	bad "mitmproxy start args present"
else
	ok "no mitmproxy start invocations"
fi

echo "=== ast-grep read-only fixture ==="
FIX="${TMP}/src"
mkdir -p "${FIX}"
cat >"${FIX}/sample.py" <<'EOF'
def greet(name):
    return f"hello {name}"
EOF
cksum_before="$(cksum "${FIX}/sample.py" | awk '{print $1}')"
if command -v ast-grep >/dev/null 2>&1 || command -v sg >/dev/null 2>&1; then
	bin=ast-grep
	command -v ast-grep >/dev/null 2>&1 || bin=sg
	set +e
	"${bin}" run -p 'def greet($$$ARGS): $$$BODY' -l python "${FIX}" >/dev/null 2>&1
	sg_rc=$?
	set -e
	cksum_after="$(cksum "${FIX}/sample.py" | awk '{print $1}')"
	[[ ${cksum_before} == "${cksum_after}" ]] && ok "ast-grep left source unchanged" || bad "ast-grep mutated source"
	# search may return 0/1 depending on match; either is fine if file unchanged
	ok "ast-grep search invoked (rc=${sg_rc})"
else
	ok "ast-grep absent (skip fixture)"
fi

echo "=== CLI help ==="
chk="$("${ROOT}/dots" check --help 2>&1)" || true
echo "${chk}" | grep -q 'check dev' && ok "dots check help mentions dev" || bad "help missing dev"

echo "=== YubiKey independence ==="
rg -q 'ykman|YubiKey|age-plugin' "${SCRIPT}" && bad "dev validate references YubiKey" || ok "dev validate independent of YubiKey"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
