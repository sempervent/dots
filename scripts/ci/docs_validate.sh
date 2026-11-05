#!/usr/bin/env bash
# scripts/ci/docs_validate.sh — documentation / publishing diagnostics (Phase 8)
#
# Non-mutating / offline-safe by default:
#   - never rewrite Markdown / README / diagram sources
#   - never publish, deploy, or upload documentation
#   - never download Chromium / Puppeteer browsers
#   - never call mermaid.ink or other remote renderers
#   - never modify ~/.config/vale, ~/.pandoc, or user Typst config
#   - temporary outputs only (unless --output PATH is explicit)
#
# Usage:
#   ./scripts/ci/docs_validate.sh              # status (default)
#   ./scripts/ci/docs_validate.sh status
#   ./scripts/ci/docs_validate.sh gate [--offline]
#   ./scripts/ci/docs_validate.sh render [--format svg|html|pdf] [--output DIR]
#   ./scripts/ci/docs_validate.sh examples
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

MODE="${1:-status}"
shift || true

FIXTURES="${ROOT}/scripts/tests/fixtures/docs"
# Controlled temp / ignored artifact root for renders (never pollute repo root).
ARTIFACT_ROOT="${DOTS_DOCS_ARTIFACT_DIR:-${TMPDIR:-/tmp}/dots-docs-$$}"

usage() {
	cat <<'EOF'
Usage: ./scripts/ci/docs_validate.sh [status|gate|render|examples] [args]

  status   Report documentation tooling presence + capabilities
  gate     Graphviz / Mermaid / Typst / Pandoc / Vale stages (non-mutating)
  render   Non-mutating preview renders to temp (or --output DIR)
  examples Print example commands (stdout only; not executed)

Never rewrites sources, publishes docs, downloads browsers, or uses remote renderers.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

pass() { echo "${GREEN}PASS${NC} $1"; }
fail() {
	echo "${RED}FAIL${NC} $1"
	return 1
}
skip() { echo "${YELLOW}SKIP${NC} $1"; }

tool_line() {
	local label="$1"
	local bin="$2"
	local note="${3:-}"
	if have "${bin}"; then
		local ver=""
		case "${bin}" in
		dot) ver="$(dot -V 2>&1 | head -n1 || true)" ;;
		pandoc) ver="$(pandoc --version 2>/dev/null | head -n1 || true)" ;;
		vale) ver="$(vale --version 2>/dev/null | head -n1 || true)" ;;
		mmdc) ver="$(mmdc --version 2>/dev/null | head -n1 || true)" ;;
		typst) ver="$(typst --version 2>/dev/null | head -n1 || true)" ;;
		markdownlint-cli2) ver="present" ;;
		cspell) ver="$(cspell --version 2>/dev/null | head -n1 || true)" ;;
		lychee) ver="$(lychee --version 2>/dev/null | head -n1 || true)" ;;
		mkdocs) ver="$(mkdocs --version 2>/dev/null | head -n1 || true)" ;;
		*) ver="present" ;;
		esac
		printf '  %-22s %s%s%s\n' "${label}" "${GREEN}OK${NC}" "${ver:+ (${ver})}" "${note:+ — ${note}}"
	else
		printf '  %-22s %s\n' "${label}" "${YELLOW}missing${NC}"
	fi
}

# Mermaid CLI often needs Chromium/Chrome via Puppeteer. Never download it here.
mermaid_runtime_available() {
	if [[ -n ${DOTS_MERMAID_EXECUTABLE:-} && -x ${DOTS_MERMAID_EXECUTABLE} ]]; then
		return 0
	fi
	if [[ -n ${PUPPETEER_EXECUTABLE_PATH:-} && -x ${PUPPETEER_EXECUTABLE_PATH} ]]; then
		return 0
	fi
	local c
	for c in chromium chromium-browser google-chrome google-chrome-stable; do
		if have "${c}"; then
			return 0
		fi
	done
	return 1
}

pandoc_pdf_backend() {
	have pandoc || {
		echo "NOT CONFIGURED"
		return
	}
	local engines=(pdflatex xelatex lualatex typst weasyprint wkhtmltopdf prince context)
	local e
	for e in "${engines[@]}"; do
		if have "${e}"; then
			echo "AVAILABLE (${e})"
			return
		fi
	done
	echo "NOT CONFIGURED"
}

find_graphviz_sources() {
	local dir="${1:-${ROOT}}"
	find "${dir}" \( -name '*.dot' -o -name '*.gv' \) \
		! -path '*/.git/*' ! -path '*/vendor/*' ! -path '*/node_modules/*' \
		! -path '*/.tools/*' ! -path '*/site/*' \
		! -path '*/scripts/tests/fixtures/*' \
		2>/dev/null | sort -u
}

find_mermaid_sources() {
	local dir="${1:-${ROOT}}"
	find "${dir}" \( -name '*.mmd' -o -name '*.mermaid' \) \
		! -path '*/.git/*' ! -path '*/vendor/*' ! -path '*/node_modules/*' \
		! -path '*/.tools/*' ! -path '*/site/*' \
		! -path '*/scripts/tests/fixtures/*' \
		2>/dev/null | sort -u
}

find_typst_sources() {
	local dir="${1:-${ROOT}}"
	find "${dir}" -name '*.typ' \
		! -path '*/.git/*' ! -path '*/vendor/*' ! -path '*/node_modules/*' \
		! -path '*/.tools/*' ! -path '*/site/*' \
		! -path '*/scripts/tests/fixtures/*' \
		2>/dev/null | sort -u
}

run_status() {
	echo "${BLUE}Documentation Tooling${NC}"
	echo "──────────────────────────────────"
	echo ""
	echo "Validation"
	tool_line "markdownlint-cli2" markdownlint-cli2 "owned by package group dev"
	tool_line "cspell" cspell "owned by package group dev"
	tool_line "Vale" vale "package group docs"
	tool_line "Lychee" lychee "owned by package group dev"
	echo ""
	echo "Rendering"
	tool_line "Graphviz / dot" dot "package group docs"
	tool_line "Mermaid / mmdc" mmdc "package group docs (Homebrew → node)"
	if have mmdc; then
		if mermaid_runtime_available; then
			printf '  %-22s %s\n' "Mermaid runtime" "${GREEN}AVAILABLE${NC}"
		else
			printf '  %-22s %s\n' "Mermaid runtime" "NOT CONFIGURED (no Chromium/Chrome; check will SKIP render)"
		fi
	else
		printf '  %-22s %s\n' "Mermaid runtime" "n/a (mmdc missing)"
	fi
	tool_line "Typst" typst "package group docs"
	echo ""
	echo "Conversion"
	tool_line "Pandoc" pandoc "package group docs"
	printf '  %-22s %s\n' "Pandoc PDF backend" "$(pandoc_pdf_backend)"
	echo ""
	echo "Site / TeX"
	tool_line "MkDocs" mkdocs "Python site generator (authoritative for docs site)"
	if have xelatex || have pdflatex || have lualatex; then
		printf '  %-22s %s\n' "TeX (--with tex)" "${GREEN}OK${NC} (engine present; separate from docs group)"
	else
		printf '  %-22s %s\n' "TeX (--with tex)" "OPTIONAL / not installed"
	fi
	echo ""
	echo "Safety"
	echo "  source rewrite during check:     NO"
	echo "  diagram overwrite during check:  NO"
	echo "  browser download during check:   NO"
	echo "  remote render / publish:         NO"
	echo "  YubiKey required:                NO"
}

run_vale() {
	if ! have vale; then
		skip "vale (not installed — select package group docs)"
		return 0
	fi
	if [[ ! -f ${ROOT}/.vale.ini ]]; then
		skip "vale (no .vale.ini)"
		return 0
	fi
	# Project-local config only; never hit Packages sync / remote styles.
	# Restrict to docs + root guides (same surface as cspell, minus help TOML).
	vale --config="${ROOT}/.vale.ini" \
		"${ROOT}/README.md" \
		"${ROOT}/AGENTS.md" \
		"${ROOT}/CONTRIBUTING.md" \
		"${ROOT}/docs"
}

run_graphviz() {
	if ! have dot; then
		skip "graphviz (dot not installed)"
		return 0
	fi
	local files=()
	local f
	while IFS= read -r f; do
		[[ -n ${f} ]] && files+=("${f}")
	done < <(find_graphviz_sources)
	if [[ ${#files[@]} -eq 0 ]]; then
		skip "no Graphviz diagrams"
		return 0
	fi
	local tmp rc=0
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/dots-gv.XXXXXX")"
	for f in "${files[@]}"; do
		local out
		out="${tmp}/$(basename "${f}").svg"
		if ! dot -Tsvg "${f}" -o "${out}" 2>/dev/null; then
			echo "  invalid: ${f}" >&2
			rc=1
		fi
	done
	rm -rf "${tmp}"
	[[ ${rc} -eq 0 ]] || return 1
	return 0
}

# Validate a single Graphviz file to temp (used by tests / gate).
validate_graphviz_file() {
	local src="$1"
	have dot || return 2
	local tmp out
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/dots-gv-one.XXXXXX")"
	out="${tmp}/out.svg"
	if dot -Tsvg "${src}" -o "${out}" 2>/dev/null && [[ -s ${out} ]]; then
		rm -rf "${tmp}"
		return 0
	fi
	rm -rf "${tmp}"
	return 1
}

# Validate a single Mermaid file; never downloads a browser.
validate_mermaid_file() {
	local src="$1"
	have mmdc || return 2
	if ! mermaid_runtime_available; then
		skip "MERMAID RENDER: SKIP_RUNTIME_UNAVAILABLE (install Chromium/Chrome or set PUPPETEER_EXECUTABLE_PATH; check will not download a browser)"
		return 0
	fi
	local tmp out
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/dots-mmd-one.XXXXXX")"
	out="${tmp}/out.svg"
	local chrome_args=()
	if [[ -n ${PUPPETEER_EXECUTABLE_PATH:-} ]]; then
		chrome_args+=(-p "{\"executablePath\":\"${PUPPETEER_EXECUTABLE_PATH}\"}")
	elif [[ -n ${DOTS_MERMAID_EXECUTABLE:-} ]]; then
		chrome_args+=(-p "{\"executablePath\":\"${DOTS_MERMAID_EXECUTABLE}\"}")
	fi
	if mmdc -i "${src}" -o "${out}" "${chrome_args[@]}" 2>/dev/null && [[ -s ${out} ]]; then
		rm -rf "${tmp}"
		return 0
	fi
	rm -rf "${tmp}"
	return 1
}

run_mermaid() {
	if ! have mmdc; then
		skip "mermaid-cli (mmdc not installed)"
		return 0
	fi
	local files=()
	local f
	while IFS= read -r f; do
		[[ -n ${f} ]] && files+=("${f}")
	done < <(find_mermaid_sources)
	if [[ ${#files[@]} -eq 0 ]]; then
		skip "no Mermaid diagrams"
		return 0
	fi
	if ! mermaid_runtime_available; then
		skip "MERMAID RENDER: SKIP_RUNTIME_UNAVAILABLE (install Chromium/Chrome or set PUPPETEER_EXECUTABLE_PATH; check will not download a browser)"
		return 0
	fi
	local tmp rc=0
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/dots-mmd.XXXXXX")"
	local chrome_args=()
	if [[ -n ${PUPPETEER_EXECUTABLE_PATH:-} ]]; then
		chrome_args+=(-p "{\"executablePath\":\"${PUPPETEER_EXECUTABLE_PATH}\"}")
	elif [[ -n ${DOTS_MERMAID_EXECUTABLE:-} ]]; then
		chrome_args+=(-p "{\"executablePath\":\"${DOTS_MERMAID_EXECUTABLE}\"}")
	fi
	for f in "${files[@]}"; do
		local out
		out="${tmp}/$(basename "${f}").svg"
		# Intentionally local-only; never pass remote URL inputs.
		if ! mmdc -i "${f}" -o "${out}" "${chrome_args[@]}" 2>/dev/null; then
			echo "  render failed: ${f}" >&2
			rc=1
		fi
	done
	rm -rf "${tmp}"
	[[ ${rc} -eq 0 ]] || return 1
	return 0
}

run_typst() {
	if ! have typst; then
		skip "typst (not installed)"
		return 0
	fi
	local files=()
	local f
	while IFS= read -r f; do
		[[ -n ${f} ]] && files+=("${f}")
	done < <(find_typst_sources)
	if [[ ${#files[@]} -eq 0 ]]; then
		skip "no Typst sources"
		return 0
	fi
	local tmp rc=0
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/dots-typ.XXXXXX")"
	# Point package path at an empty dir so missing @preview deps cannot
	# surprise-download during ordinary checks.
	export TYPST_PACKAGE_PATH="${tmp}/no-packages"
	mkdir -p "${TYPST_PACKAGE_PATH}"
	for f in "${files[@]}"; do
		local out
		out="${tmp}/$(basename "${f}" .typ).pdf"
		if ! typst compile "${f}" "${out}" 2>/dev/null; then
			echo "  typst compile failed (local-only; external packages need explicit network): ${f}" >&2
			rc=1
		fi
	done
	rm -rf "${tmp}"
	[[ ${rc} -eq 0 ]] || return 1
	return 0
}

run_pandoc_capability() {
	if ! have pandoc; then
		skip "pandoc (not installed)"
		return 0
	fi
	echo "  Pandoc: $(pandoc --version | head -n1)"
	echo "  Pandoc PDF backend: $(pandoc_pdf_backend)"
	# Tiny deterministic Markdown → HTML (no remote assets).
	local tmp in out
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/dots-pandoc.XXXXXX")"
	in="${tmp}/sample.md"
	out="${tmp}/sample.html"
	printf '%s\n' '# DOTS Pandoc fixture' '' 'Hello from local validation.' >"${in}"
	if ! pandoc "${in}" -o "${out}" -t html 2>/dev/null || [[ ! -s ${out} ]]; then
		rm -rf "${tmp}"
		return 1
	fi
	rm -rf "${tmp}"
	return 0
}

# Diagram / conversion stages only (Vale is a separate step in check docs).
run_diagrams() {
	local rc=0
	echo "${BLUE}=== Graphviz ===${NC}"
	if run_graphviz; then
		pass "graphviz"
	else
		fail "graphviz" || rc=1
	fi
	echo "${BLUE}=== Mermaid ===${NC}"
	if run_mermaid; then
		pass "mermaid"
	else
		fail "mermaid" || rc=1
	fi
	echo "${BLUE}=== Typst ===${NC}"
	if run_typst; then
		pass "typst"
	else
		fail "typst" || rc=1
	fi
	echo "${BLUE}=== Pandoc capability ===${NC}"
	if run_pandoc_capability; then
		pass "pandoc"
	else
		fail "pandoc" || rc=1
	fi
	return "${rc}"
}

run_gate() {
	local rc=0
	echo "${BLUE}=== docs publishing gate ===${NC}"
	run_status
	echo ""
	echo "${BLUE}=== Vale ===${NC}"
	if run_vale; then
		pass "vale"
	else
		fail "vale" || rc=1
	fi
	run_diagrams || rc=1
	return "${rc}"
}

run_render() {
	local format="svg"
	local outdir=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--format)
			format="${2:-}"
			shift 2 || true
			;;
		--output)
			outdir="${2:-}"
			shift 2 || true
			;;
		*)
			echo "Unknown render arg: $1" >&2
			usage >&2
			return 1
			;;
		esac
	done
	if [[ -z ${outdir} ]]; then
		outdir="${ARTIFACT_ROOT}/render"
		mkdir -p "${outdir}"
		echo "Using temporary output: ${outdir}"
	else
		# Explicit persistent path required by caller — still never overwrite sources.
		mkdir -p "${outdir}"
		echo "Using explicit output: ${outdir}"
	fi
	local meta="${outdir}/render-meta.txt"
	{
		echo "tool_versions:"
		have dot && echo "  graphviz: $(dot -V 2>&1 | head -n1)"
		have mmdc && echo "  mermaid-cli: $(mmdc --version 2>/dev/null | head -n1)"
		have typst && echo "  typst: $(typst --version 2>/dev/null | head -n1)"
		have pandoc && echo "  pandoc: $(pandoc --version 2>/dev/null | head -n1)"
		echo "format: ${format}"
		echo "source_mutation: NO"
		echo "publish: NO"
	} >"${meta}"

	local n=0
	local f
	if have dot; then
		while IFS= read -r f; do
			[[ -z ${f} ]] && continue
			local base
			base="$(basename "${f}" | sed 's/\.[^.]*$//')"
			dot -T"${format}" "${f}" -o "${outdir}/${base}.gv.${format}" 2>/dev/null && n=$((n + 1)) || true
		done < <(find_graphviz_sources)
	fi
	if have mmdc && mermaid_runtime_available; then
		while IFS= read -r f; do
			[[ -z ${f} ]] && continue
			local base
			base="$(basename "${f}" | sed 's/\.[^.]*$//')"
			mmdc -i "${f}" -o "${outdir}/${base}.mmd.svg" 2>/dev/null && n=$((n + 1)) || true
		done < <(find_mermaid_sources)
	elif have mmdc; then
		skip "MERMAID RENDER: SKIP_RUNTIME_UNAVAILABLE"
	fi
	if have typst; then
		while IFS= read -r f; do
			[[ -z ${f} ]] && continue
			local base
			base="$(basename "${f}" .typ)"
			typst compile "${f}" "${outdir}/${base}.pdf" 2>/dev/null && n=$((n + 1)) || true
		done < <(find_typst_sources)
	fi
	echo "Rendered ${n} artifact(s) → ${outdir}"
	echo "Sources unchanged. No publish performed."
	return 0
}

run_examples() {
	cat <<'EOF'
# Documentation tooling examples (not executed by this command)

# Install docs group (plus Phase 1 validators via dev):
./setup.sh --packages core,modern,dev,docs

# Full docs gate (offline-safe when --offline):
./dots check docs --offline

# Tooling inventory:
./dots check docs status

# Non-mutating render preview (temp dir):
./dots check docs render

# Explicit output path only (never guessed):
./dots check docs render --output /tmp/dots-docs-preview

# Pandoc baseline (Markdown → HTML; no remote assets):
pandoc README.md -o /tmp/readme.html -t html

# Graphviz to temp:
dot -Tsvg path/to/diagram.dot -o /tmp/diagram.svg

# Typst local compile:
typst compile doc.typ /tmp/doc.pdf

# MkDocs site (separate from docs package group):
# mkdocs build   # only when intentionally generating the site
EOF
}

case "${MODE}" in
"" | -h | --help)
	usage
	exit 0
	;;
status)
	run_status
	exit 0
	;;
vale)
	# Exit status only — caller (local_validate run_step) prints PASS/FAIL.
	run_vale
	exit $?
	;;
diagrams)
	run_diagrams "$@"
	exit $?
	;;
gate)
	run_gate "$@"
	exit $?
	;;
render)
	run_render "$@"
	exit $?
	;;
examples)
	run_examples
	exit 0
	;;
# Internal helpers for tests (stable entrypoints).
validate-graphviz-file)
	validate_graphviz_file "${1:-}"
	exit $?
	;;
validate-mermaid-file)
	validate_mermaid_file "${1:-}"
	exit $?
	;;
*)
	echo "Unknown mode: ${MODE}" >&2
	usage >&2
	exit 1
	;;
esac
