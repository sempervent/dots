#!/usr/bin/env bash
# shellcheck shell=bash
# helpers/cask_apps.sh — satisfy macOS GUI cask requirements without overwriting
# externally installed apps.
#
# Policy (v1.2.1):
#   Homebrew-managed cask  → OK (normal brew ownership)
#   Expected .app present  → OK / WARN (external; leave untouched; no --force)
#   Missing                → install cask; genuine install failure → ERROR
#
# Optional adoption (--adopt) may be attempted after a conflict-style install
# failure only when the app exists; adoption failure still leaves the app and
# counts as external satisfaction (not ERROR).
#
# Test hooks:
#   DOTS_BREW_BIN          — brew executable (mock)
#   DOTS_APPLICATIONS_DIR  — remap /Applications/<App>.app → $DIR/<App>.app

dots_brew_bin() {
	printf '%s\n' "${DOTS_BREW_BIN:-brew}"
}

dots_brew() {
	local bin
	bin="$(dots_brew_bin)"
	if ! command -v "${bin}" >/dev/null 2>&1 && [[ ! -x ${bin} ]]; then
		echo "Error: brew not found (${bin})" >&2
		return 127
	fi
	"${bin}" "$@"
}

# Resolve app path; honors DOTS_APPLICATIONS_DIR for tests.
dots_cask_resolve_app_path() {
	local app="$1"
	local base
	base="$(basename "${app}")"
	if [[ -n ${DOTS_APPLICATIONS_DIR:-} ]]; then
		printf '%s/%s\n' "${DOTS_APPLICATIONS_DIR%/}" "${base}"
		return 0
	fi
	printf '%s\n' "${app}"
}

dots_cask_is_managed() {
	local cask="$1"
	dots_brew list --cask "${cask}" >/dev/null 2>&1
}

dots_cask_app_present() {
	local app
	app="$(dots_cask_resolve_app_path "$1")"
	[[ -d ${app} || -e ${app} ]]
}

# Ensure a GUI cask's application requirement is satisfied.
# Usage: dots_ensure_cask_app <cask> <app_path> [label]
# Prints status lines; returns 0 if satisfied, 1 on genuine failure.
# Sets DOTS_CASK_LAST_STATUS=managed|external|installed|dry-run|failed
dots_ensure_cask_app() {
	local cask="$1"
	local app_spec="$2"
	local label="${3:-$1}"
	local app
	app="$(dots_cask_resolve_app_path "${app_spec}")"
	DOTS_CASK_LAST_STATUS=""

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		if dots_cask_is_managed "${cask}"; then
			echo "[dry-run] ${label}: Homebrew cask '${cask}' already managed"
			DOTS_CASK_LAST_STATUS="dry-run"
			return 0
		fi
		if [[ -d ${app} || -e ${app} ]]; then
			echo "[dry-run] ${label} already present at ${app}; would treat as satisfying '${cask}'"
			DOTS_CASK_LAST_STATUS="dry-run"
			return 0
		fi
		echo "[dry-run] brew install --cask ${cask}"
		DOTS_CASK_LAST_STATUS="dry-run"
		return 0
	fi

	if dots_cask_is_managed "${cask}"; then
		echo "OK: ${label} managed by Homebrew cask '${cask}'"
		DOTS_CASK_LAST_STATUS="managed"
		return 0
	fi

	if [[ -d ${app} || -e ${app} ]]; then
		echo "OK: ${label} already present at ${app}"
		echo "    Homebrew cask '${cask}' is not managing this copy; leaving it untouched."
		DOTS_CASK_LAST_STATUS="external"
		return 0
	fi

	# --no-install: require presence without installing
	if [[ ${NO_INSTALL:-0} -eq 1 ]]; then
		echo "Error: ${label} missing (${app}); cask '${cask}' not installed (--no-install)" >&2
		DOTS_CASK_LAST_STATUS="failed"
		return 1
	fi

	echo "Installing ${cask} cask (macOS)..."
	if dots_brew install --cask "${cask}"; then
		echo "OK: installed ${cask}"
		DOTS_CASK_LAST_STATUS="installed"
		return 0
	fi

	# Install failed. If the app is now present (or was race-created), do not
	# destroy it. Optionally try --adopt once; never --force.
	if [[ -d ${app} || -e ${app} ]]; then
		if dots_brew install --adopt --cask "${cask}" >/dev/null 2>&1; then
			echo "OK: adopted existing ${label} into Homebrew cask '${cask}'"
			DOTS_CASK_LAST_STATUS="managed"
			return 0
		fi
		echo "OK: ${label} already present at ${app}"
		echo "    Homebrew cask '${cask}' is not managing this copy; leaving it untouched."
		DOTS_CASK_LAST_STATUS="external"
		return 0
	fi

	echo "Error: ${label}: cask '${cask}' installation failed and ${app} is absent" >&2
	DOTS_CASK_LAST_STATUS="failed"
	return 1
}
