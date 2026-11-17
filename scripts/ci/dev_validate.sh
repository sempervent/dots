#!/usr/bin/env bash
# scripts/ci/dev_validate.sh — developer workflow diagnostics (Phase 4)
#
# Read-only: never runs jj init, git-town, git-filter-repo, ast-grep -U,
# mitmproxy, Bruno, or Proxyman. Never mutates Git config or trust stores.
#
# Usage:
#   ./scripts/ci/dev_validate.sh           # status (default)
#   ./scripts/ci/dev_validate.sh status
#   ./scripts/ci/dev_validate.sh repo      # optional read-only git-sizer
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

MODE="${1:-status}"

usage() {
	cat <<'EOF'
Usage: ./scripts/ci/dev_validate.sh [status|repo]

  status  Report developer tooling presence (non-mutating)
  repo    Optional read-only git-sizer on the DOTS repository

Never converts repos to jj, rewrites history, starts proxies, or launches GUIs.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

tool_line() {
	local label="$1"
	local bin="$2"
	local alt="${3:-}"
	if have "${bin}" || { [[ -n ${alt} ]] && have "${alt}"; }; then
		local ver=""
		case "${bin}" in
		jj) ver="$(jj --version 2>/dev/null | head -n1 || true)" ;;
		git-town) ver="$(git-town version 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | head -n1 || true)" ;;
		ast-grep | sg)
			if have ast-grep; then
				ver="$(ast-grep --version 2>/dev/null | head -n1 || true)"
			elif have sg; then ver="$(sg --version 2>/dev/null | head -n1 || true)"; fi
			;;
		lnav) ver="$(lnav -V 2>/dev/null | head -n1 || true)" ;;
		mitmproxy) ver="$(mitmproxy --version 2>/dev/null | head -n1 || true)" ;;
		git-sizer) ver="$(git-sizer --version 2>/dev/null | head -n1 || true)" ;;
		git-filter-repo) ver="present" ;;
		watchexec) ver="$(watchexec --version 2>/dev/null | head -n1 || true)" ;;
		hyperfine) ver="$(hyperfine --version 2>/dev/null | head -n1 || true)" ;;
		mprocs|dekit)
			if have dekit; then ver="$(dekit --version 2>/dev/null | head -n1 || true)"
			elif have mprocs; then ver="$(mprocs --version 2>/dev/null | head -n1 || true)"; fi
			;;
		xh) ver="$(xh --version 2>/dev/null | head -n1 || true)" ;;
		hexyl) ver="$(hexyl --version 2>/dev/null | head -n1 || true)" ;;
		tokei) ver="$(tokei --version 2>/dev/null | head -n1 || true)" ;;
		jc) ver="$(jc --version 2>/dev/null | head -n1 || true)" ;;
		navi) ver="$(navi --version 2>/dev/null | head -n1 || true)" ;;
		sd) ver="$(sd --version 2>/dev/null | head -n1 || true)" ;;
		procs) ver="$(procs --version 2>/dev/null | head -n1 || true)" ;;
		ouch) ver="$(ouch --version 2>/dev/null | head -n1 || true)" ;;
		mise) ver="$(mise --version 2>/dev/null | head -n1 || true)" ;;
		dust) ver="$(dust --version 2>/dev/null | head -n1 || true)" ;;
		duf) ver="$(duf --version 2>/dev/null | head -n1 || true)" ;;
		yazi) ver="$(yazi --version 2>/dev/null | head -n1 || true)" ;;
		*) ver="present" ;;
		esac
		printf '  %-20s %s%s\n' "${label}" "${GREEN}OK${NC}" "${ver:+ (${ver})}"
	else
		printf '  %-20s %s\n' "${label}" "${YELLOW}missing${NC}"
	fi
}

gui_line() {
	local label="$1"
	local app="$2"
	local cask="$3"
	if [[ "$(uname -s)" != Darwin ]]; then
		printf '  %-20s %s\n' "${label}" "unsupported (non-Darwin)"
		return
	fi
	if [[ -d "/Applications/${app}.app" ]] || brew list --cask "${cask}" >/dev/null 2>&1; then
		printf '  %-20s %s\n' "${label}" "${GREEN}INSTALLED${NC} (optional)"
	else
		printf '  %-20s %s\n' "${label}" "OPTIONAL / not installed"
	fi
}

run_status() {
	echo "${BLUE}Developer Tooling${NC}"
	echo "────────────────────────────────"
	echo ""
	echo "Version control"
	tool_line "git" git
	tool_line "gh" gh
	tool_line "lazygit" lazygit
	tool_line "jj" jj
	tool_line "git-town" git-town
	tool_line "git-filter-repo" git-filter-repo
	tool_line "git-sizer" git-sizer
	echo ""
	echo "Code inspection"
	if have ast-grep; then
		tool_line "ast-grep" ast-grep
	else
		tool_line "ast-grep (sg)" sg
	fi
	echo ""
	echo "Logs"
	tool_line "lnav" lnav
	echo ""
	echo "Watch / benchmark / processes"
	tool_line "watchexec" watchexec
	tool_line "hyperfine" hyperfine
	if have dekit; then tool_line "mprocs (dekit)" dekit
	else tool_line "mprocs" mprocs; fi
	tool_line "hexyl" hexyl
	tool_line "tokei" tokei
	echo ""
	echo "HTTP / API"
	tool_line "curl" curl "(baseline; xh is optional)"
	tool_line "mitmproxy" mitmproxy
	tool_line "mitmdump" mitmdump
	tool_line "xh" xh
	gui_line "Bruno" "Bruno" bruno
	gui_line "Proxyman" "Proxyman" proxyman
	echo ""
	echo "Modern ergonomics (inventory)"
	tool_line "mise" mise "(fnm remains DOTS Node authority)"
	tool_line "jc" jc
	tool_line "navi" navi
	tool_line "sd" sd
	tool_line "procs" procs
	tool_line "ouch" ouch
	tool_line "dust" dust
	tool_line "duf" duf
	tool_line "yazi" yazi "(additive; ranger default)"
	echo ""
	echo "Invariants"
	echo "  Git remains default VCS"
	echo "  No jj init / git-town config / history rewrite by this command"
	echo "  No proxy start / CA trust / GUI launch"
	echo "  No mise activate, watchexec runs, hyperfine benchmarks, or xh requests"
	echo "  navi does not alter Tab/Ctrl-R; sd does not replace sed"
	# Safety: ensure we did not create .jj in this repo as a side effect of version checks
	if [[ -d ${ROOT}/.jj ]]; then
		echo "  ${YELLOW}NOTE${NC}: .jj directory present (not created by this check)" >&2
	fi
	return 0
}

run_repo() {
	if ! have git-sizer; then
		echo "git-sizer not installed (package group modern)." >&2
		return 1
	fi
	echo "${BLUE}Repository size (read-only git-sizer)${NC}"
	echo "────────────────────────────────"
	# --no-progress keeps output stable; never mutates.
	git-sizer --no-progress --verbose
}

case "${MODE}" in
"" | -h | --help)
	usage
	exit 0
	;;
status)
	run_status
	exit $?
	;;
repo)
	run_repo
	exit $?
	;;
*)
	echo "Unknown mode: ${MODE}" >&2
	usage >&2
	exit 1
	;;
esac
