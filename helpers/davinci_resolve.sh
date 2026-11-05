# shellcheck shell=bash
# helpers/davinci_resolve.sh — explicit --with davinci-resolve (Darwin / App Store)
#
# Verified install path (2026-11):
#   Homebrew formula: mas
#   Mac App Store app id: 571213070 (DaVinci Resolve; bundle com.blackmagic-design.DaVinciResolveLite)
#   No Homebrew cask for davinci-resolve exists.
#
# App Store authentication is required only for this explicit component.
# Missing auth → NOT CONFIGURED / AUTH REQUIRED (non-fatal; setup continues).
# Never launches Resolve or mutates projects/media/permissions.

# Official App Store numeric id (verified via iTunes lookup; do not invent).
DOTS_DAVINCI_RESOLVE_MAS_ID="${DOTS_DAVINCI_RESOLVE_MAS_ID:-571213070}"
DOTS_DAVINCI_RESOLVE_APP_PATH="${DOTS_DAVINCI_RESOLVE_APP_PATH:-/Applications/DaVinci Resolve.app}"

dots_davinci_resolve_app_installed() {
	[[ -d ${DOTS_DAVINCI_RESOLVE_APP_PATH} ]]
}

# Return 0 when mas reports a signed-in App Store account.
dots_davinci_resolve_mas_authenticated() {
	local out
	command -v mas >/dev/null 2>&1 || return 1
	out="$(mas account 2>/dev/null || true)"
	[[ -n ${out} ]] || return 1
	# mas prints an error-ish line when not signed in on some versions
	case "${out}" in
	*[Nn]ot\ signed* | *[Ee]rror* | *[Nn]ot\ logged*) return 1 ;;
	esac
	return 0
}

# Non-launching status string for diagnostics / check media.
dots_davinci_resolve_status() {
	if [[ "$(dots_davinci_resolve_os)" != "darwin" ]]; then
		echo "PLATFORM_UNSUPPORTED"
		return 0
	fi
	if dots_davinci_resolve_app_installed; then
		echo "OPTIONAL / INSTALLED"
		return 0
	fi
	if ! command -v mas >/dev/null 2>&1; then
		echo "OPTIONAL / NOT INSTALLED (mas missing)"
		return 0
	fi
	if ! dots_davinci_resolve_mas_authenticated; then
		echo "OPTIONAL / NOT INSTALLED (App Store AUTH REQUIRED for --with davinci-resolve)"
		return 0
	fi
	echo "OPTIONAL / NOT INSTALLED"
}

# Effective OS for install gates (honors DOTS_FORCE_OS used by component tests/CI).
dots_davinci_resolve_os() {
	if [[ -n ${DOTS_FORCE_OS:-} ]]; then
		printf '%s\n' "${DOTS_FORCE_OS}"
		return 0
	fi
	case "$(uname -s)" in
	Darwin) printf 'darwin\n' ;;
	Linux) printf 'linux\n' ;;
	*) printf 'unknown\n' ;;
	esac
}

# Package + App Store install for explicit --with davinci-resolve.
# Returns 0 on success, already-installed, dry-run, or auth-not-configured.
# Hard-fails (nonzero) only when authenticated install actually fails.
dots_davinci_resolve_install() {
	local os
	os="$(dots_davinci_resolve_os)"
	if [[ ${os} != "darwin" ]]; then
		echo "Error: davinci-resolve is supported only on macOS (Darwin)." >&2
		return 1
	fi

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] ensure Homebrew formula mas (Brewfile.davinci-resolve)"
		echo "[dry-run] if App Store authenticated: mas install ${DOTS_DAVINCI_RESOLVE_MAS_ID}"
		echo "[dry-run] never launch Resolve / create projects / scan media / Blackmagic login"
		return 0
	fi

	if dots_davinci_resolve_app_installed; then
		echo "OK: DaVinci Resolve already present at ${DOTS_DAVINCI_RESOLVE_APP_PATH}"
		return 0
	fi

	if ! command -v mas >/dev/null 2>&1; then
		echo "Error: mas CLI missing after Brewfile.davinci-resolve (needed for App Store install)." >&2
		return 1
	fi

	if ! dots_davinci_resolve_mas_authenticated; then
		echo "DaVinci Resolve: NOT CONFIGURED / AUTH REQUIRED"
		echo "  Sign in to the Mac App Store, then re-run:"
		echo "    ./setup.sh --with davinci-resolve"
		echo "  DOTS does not require an App Store account for other profiles or CI."
		echo "  Manual alternative (Blackmagic direct installer): see docs/using/media-tooling.md"
		# Soft skip — do not fail the whole setup / other components.
		return 0
	fi

	echo "Installing DaVinci Resolve via Mac App Store (mas install ${DOTS_DAVINCI_RESOLVE_MAS_ID})..."
	if mas install "${DOTS_DAVINCI_RESOLVE_MAS_ID}"; then
		if dots_davinci_resolve_app_installed; then
			echo "OK: DaVinci Resolve installed (install-only; not launched)"
			return 0
		fi
		echo "Warn: mas install reported success but ${DOTS_DAVINCI_RESOLVE_APP_PATH} not found yet"
		return 0
	fi
	echo "Error: mas install ${DOTS_DAVINCI_RESOLVE_MAS_ID} failed" >&2
	return 1
}
