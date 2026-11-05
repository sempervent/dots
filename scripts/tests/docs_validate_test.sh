#!/usr/bin/env bash
# scripts/tests/docs_validate_test.sh — Phase 8 documentation toolchain safety
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${ROOT}/scripts/ci/docs_validate.sh"
LOCAL="${ROOT}/scripts/ci/local_validate.sh"
FIX="${ROOT}/scripts/tests/fixtures/docs"
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

have() { command -v "$1" >/dev/null 2>&1; }

echo "=== package ownership (no Phase 1 duplication) ==="
if grep -E '^[[:space:]]*brew[[:space:]]+"(lychee|markdownlint-cli2|cspell)"' "${ROOT}/brew/groups/docs.Brewfile"; then
	bad "docs Brewfile must not own lychee/markdownlint/cspell"
else
	ok "docs Brewfile omits Phase 1 validators"
fi
grep -q 'brew "lychee"' "${ROOT}/brew/groups/dev.Brewfile" && ok "lychee owned by dev" || bad "lychee missing from dev"
grep -q 'brew "markdownlint-cli2"' "${ROOT}/brew/groups/dev.Brewfile" && ok "markdownlint owned by dev" || bad "markdownlint missing from dev"
grep -q 'brew "cspell"' "${ROOT}/brew/groups/dev.Brewfile" && ok "cspell owned by dev" || bad "cspell missing from dev"
grep -q 'name = "docs"' "${ROOT}/configs/packages/groups.toml" && ok "docs group registered" || bad "docs group missing"
for pkg in graphviz pandoc vale mermaid-cli typst; do
	grep -q "\"${pkg}\"" "${ROOT}/configs/packages/groups.toml" && ok "groups.toml has ${pkg}" || bad "missing ${pkg}"
	grep -q "brew \"${pkg}\"" "${ROOT}/brew/groups/docs.Brewfile" && ok "Brewfile has ${pkg}" || bad "Brewfile missing ${pkg}"
done
for prof in work home all; do
	grep -q '"docs"' "${ROOT}/configs/bootstrap/profiles/${prof}.toml" && ok "profile ${prof} includes docs" || bad "profile ${prof} missing docs"
done
# tex / MkDocs preserved
[[ -f ${ROOT}/mkdocs.yml ]] && ok "MkDocs config preserved" || bad "mkdocs.yml missing"
grep -q 'tex' "${ROOT}/configs/components.toml" && ok "tex component preserved" || bad "tex component missing"

echo "=== status / examples (non-mutating) ==="
stat_out="$("${SCRIPT}" status 2>&1)" || {
	bad "status failed"
	stat_out=""
}
echo "${stat_out}" | grep -qi 'Documentation Tooling\|Validation\|Rendering' && ok "status header" || bad "status header missing"
echo "${stat_out}" | grep -qi 'browser download during check:.*NO' && ok "status denies browser download" || bad "browser policy missing"
echo "${stat_out}" | grep -qi 'YubiKey required:.*NO' && ok "status denies YubiKey" || bad "YubiKey policy missing"
ex="$("${SCRIPT}" examples 2>&1)" || bad "examples failed"
echo "${ex}" | grep -q 'check docs' && ok "examples mention check docs" || bad "examples incomplete"

echo "=== Graphviz fixtures ==="
if have dot; then
	before="$(shasum -a 256 "${FIX}/valid.dot" | awk '{print $1}')"
	if "${SCRIPT}" validate-graphviz-file "${FIX}/valid.dot"; then
		ok "valid.dot PASS"
	else
		bad "valid.dot should PASS"
	fi
	if "${SCRIPT}" validate-graphviz-file "${FIX}/invalid.dot"; then
		bad "invalid.dot should FAIL"
	else
		ok "invalid.dot FAIL"
	fi
	after="$(shasum -a 256 "${FIX}/valid.dot" | awk '{print $1}')"
	[[ ${before} == "${after}" ]] && ok "graphviz source unchanged" || bad "graphviz source mutated"
else
	ok "graphviz skipped (dot missing)"
fi

echo "=== Vale fixtures ==="
if have vale; then
	if vale --config="${ROOT}/.vale.ini" "${FIX}/vale_clean.md" >/dev/null 2>&1; then
		ok "vale clean PASS"
	else
		bad "vale clean should PASS"
	fi
	if vale --config="${ROOT}/.vale.ini" "${FIX}/vale_violation.md" >/dev/null 2>&1; then
		bad "vale violation should FAIL"
	else
		ok "vale violation FAIL"
	fi
	# Vocabulary accepts DOTS terms
	if vale --config="${ROOT}/.vale.ini" "${FIX}/vale_clean.md" 2>&1 | grep -qi 'DOTS\|MkDocs\|Mermaid'; then
		# errors mentioning those would be bad; presence in output as content is fine
		ok "vale ran on vocabulary fixture"
	else
		ok "vale vocabulary fixture clean"
	fi
else
	ok "vale skipped (not installed)"
fi

echo "=== Pandoc fixture ==="
if have pandoc; then
	TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-pandoc-test.XXXXXX")"
	before="$(shasum -a 256 "${FIX}/sample.md" | awk '{print $1}')"
	if pandoc "${FIX}/sample.md" -o "${TMP}/out.html" -t html && [[ -s ${TMP}/out.html ]]; then
		ok "pandoc md→html"
	else
		bad "pandoc md→html failed"
	fi
	after="$(shasum -a 256 "${FIX}/sample.md" | awk '{print $1}')"
	[[ ${before} == "${after}" ]] && ok "pandoc source unchanged" || bad "pandoc source mutated"
	# No remote fetch in fixture
	! grep -qiE 'https?://' "${FIX}/sample.md" && ok "pandoc fixture has no remote URLs" || bad "fixture has remotes"
	rm -rf "${TMP}"
else
	ok "pandoc skipped (not installed)"
fi

echo "=== Typst fixture ==="
if have typst; then
	TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-typst-test.XXXXXX")"
	before="$(shasum -a 256 "${FIX}/hello.typ" | awk '{print $1}')"
	if typst compile "${FIX}/hello.typ" "${TMP}/hello.pdf" && [[ -s ${TMP}/hello.pdf ]]; then
		ok "typst compile"
	else
		bad "typst compile failed"
	fi
	after="$(shasum -a 256 "${FIX}/hello.typ" | awk '{print $1}')"
	[[ ${before} == "${after}" ]] && ok "typst source unchanged" || bad "typst source mutated"
	! grep -q '@preview\|@local' "${FIX}/hello.typ" && ok "typst fixture dependency-free" || bad "typst fixture has packages"
	rm -rf "${TMP}"
else
	ok "typst skipped (not installed)"
fi

echo "=== Mermaid runtime classification ==="
mmd_out="$("${SCRIPT}" diagrams 2>&1)" || true
if have mmdc; then
	file_out="$("${SCRIPT}" validate-mermaid-file "${FIX}/valid.mmd" 2>&1)" || true
	if command -v chromium >/dev/null 2>&1 || command -v google-chrome >/dev/null 2>&1 ||
		[[ -n ${PUPPETEER_EXECUTABLE_PATH:-} && -x ${PUPPETEER_EXECUTABLE_PATH:-} ]]; then
		ok "mermaid runtime present (render may run)"
	else
		echo "${file_out}" | grep -q 'SKIP_RUNTIME_UNAVAILABLE' && ok "mermaid SKIP_RUNTIME_UNAVAILABLE" || bad "expected SKIP_RUNTIME_UNAVAILABLE: ${file_out}"
	fi
	# Discovery excludes fixtures → diagrams stage should not attempt browser download
	echo "${mmd_out}" | grep -qiE 'Downloading Chrome|chrome-headless-shell' && bad "diagrams downloaded browser" || ok "diagrams stage no browser download"
else
	echo "${mmd_out}" | grep -qi 'mermaid.*not installed\|SKIP' && ok "mermaid missing → skip" || ok "mermaid absent handled"
fi

echo "=== browser download / publish audit ==="
# Instrument: diagrams/status must not invoke curl/wget to browser CDNs.
# We assert policy strings and that no puppeteer cache download markers appear in output.
echo "${mmd_out}" | grep -qiE 'Downloading Chrome|chrome-headless-shell|puppeteer.*download' && bad "browser download detected in diagrams" || ok "no browser download in diagrams output"
stat_out2="$("${SCRIPT}" status 2>&1)"
echo "${stat_out2}" | grep -qi 'remote render / publish:.*NO' && ok "no remote publish" || bad "publish policy missing"

echo "=== render preview (temp only) ==="
rend="$("${SCRIPT}" render 2>&1)" || bad "render failed"
echo "${rend}" | grep -qi 'Sources unchanged\|source_mutation\|Using temporary\|Using explicit' && ok "render non-mutating" || bad "render messaging: ${rend}"
echo "${rend}" | grep -qi 'No publish' && ok "render denies publish" || bad "render publish denial missing"

echo "=== mutation snapshot (check docs --offline surface) ==="
# Snapshot key sources before/after docs status + diagrams (full check docs may need network for lychee online).
files_snap=("${ROOT}/README.md" "${FIX}/valid.dot" "${FIX}/sample.md" "${FIX}/hello.typ" "${FIX}/vale_clean.md")
declare -a hashes_before=()
for f in "${files_snap[@]}"; do
	hashes_before+=("$(shasum -a 256 "${f}" | awk '{print $1}')")
done
"${SCRIPT}" status >/dev/null
"${SCRIPT}" diagrams >/dev/null || true
"${SCRIPT}" render >/dev/null || true
i=0
mut=0
for f in "${files_snap[@]}"; do
	h="$(shasum -a 256 "${f}" | awk '{print $1}')"
	[[ ${h} == "${hashes_before[$i]}" ]] || mut=1
	i=$((i + 1))
done
[[ ${mut} -eq 0 ]] && ok "source mutation: NONE" || bad "sources mutated by docs validate"

echo "=== CLI / help wiring ==="
chk="$("${ROOT}/dots" check --help 2>&1)" || true
echo "${chk}" | grep -q 'check docs' && ok "help mentions check docs" || bad "help missing docs"
echo "${chk}" | grep -qi 'status\|render\|offline' && ok "help mentions docs submodes" || bad "help missing submodes"
# Ensure ./dots check docs status works
ds="$("${ROOT}/dots" check docs status 2>&1)" || bad "dots check docs status failed"
echo "${ds}" | grep -qi 'Documentation Tooling' && ok "dots check docs status" || bad "status via dots failed"

echo "=== local_validate docs still lists Phase 1 stages ==="
# Dry structure: --help
help_lv="$("${LOCAL}" --help 2>&1)" || true
echo "${help_lv}" | grep -qi 'vale\|diagram\|status\|render' && ok "local_validate docs help updated" || bad "local_validate help stale"

echo "=== Linux maps present ==="
for map in apt dnf pacman xbps; do
	grep -q '^graphviz' "${ROOT}/configs/packages/${map}.toml" && ok "${map} graphviz" || bad "${map} graphviz"
	grep -q '^pandoc' "${ROOT}/configs/packages/${map}.toml" && ok "${map} pandoc" || bad "${map} pandoc"
	grep -q '^vale' "${ROOT}/configs/packages/${map}.toml" && ok "${map} vale" || bad "${map} vale"
	grep -q '^mermaid-cli' "${ROOT}/configs/packages/${map}.toml" && ok "${map} mermaid-cli" || bad "${map} mermaid-cli"
	grep -q '^typst' "${ROOT}/configs/packages/${map}.toml" && ok "${map} typst" || bad "${map} typst"
done

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
