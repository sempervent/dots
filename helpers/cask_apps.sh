#!/usr/bin/env bash
# shellcheck shell=bash
# helpers/cask_apps.sh — satisfy macOS GUI cask requirements without overwriting
# externally installed apps.
#
# Policy:
#   Homebrew-managed cask  → MANAGED (normal brew ownership)
#   .app present, brew does not own cask
#       → WARN EXTERNAL; attempt safe `brew install --cask --adopt`
#       → success → MANAGED / adopted
#       → failure → leave app untouched; report EXTERNAL; continue (not ERROR)
#   Missing → install cask (never --force); genuine install failure → ERROR
#
# Test hooks:
#   DOTS_BREW_BIN             — brew executable (mock)
#   DOTS_APPLICATIONS_DIR     — remap /Applications/<App>.app → $DIR/<App>.app
#   DOTS_CASK_MOCK_ARTIFACTS  — newline "cask<TAB>App.app" or "cask<TAB>/full/path"

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

# Print artifact .app basenames or paths for a cask (one per line).
# Prefers Homebrew cask JSON; falls back to mock / heuristic.
dots_cask_artifact_apps() {
	local cask="$1"
	local line tok art json

	if [[ -n ${DOTS_CASK_MOCK_ARTIFACTS+x} ]]; then
		while IFS= read -r line || [[ -n ${line} ]]; do
			[[ -z ${line} ]] && continue
			tok="${line%%$'\t'*}"
			art="${line#*$'\t'}"
			[[ ${tok} == "${cask}" && -n ${art} ]] && printf '%s\n' "${art}"
		done <<<"${DOTS_CASK_MOCK_ARTIFACTS}"
		return 0
	fi

	json="$(dots_brew info --json=v2 --cask "${cask}" 2>/dev/null || true)"
	if [[ -n ${json} ]]; then
		if command -v python3 >/dev/null 2>&1; then
			printf '%s' "${json}" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
casks = data.get("casks") or []
if not casks:
    sys.exit(0)
for art in (casks[0].get("artifacts") or []):
    if not isinstance(art, dict):
        continue
    apps = art.get("app")
    if apps is None:
        continue
    if isinstance(apps, str):
        apps = [apps]
    for a in apps:
        if a:
            print(a)
' 2>/dev/null && return 0
		fi
	fi
	# Last-resort heuristic (unusual casks should come from JSON).
	printf '%s.app\n' "${cask}"
}

# Resolve a preferred .app path for a cask: first existing artifact, else first listed.
dots_cask_discover_app() {
	local cask="$1"
	local art path resolved first=""
	while IFS= read -r art || [[ -n ${art} ]]; do
		[[ -z ${art} ]] && continue
		if [[ ${art} == /* ]]; then
			path="${art}"
		else
			path="/Applications/${art}"
		fi
		resolved="$(dots_cask_resolve_app_path "${path}")"
		if [[ -d ${resolved} || -e ${resolved} ]]; then
			printf '%s\n' "${resolved}"
			return 0
		fi
		[[ -z ${first} ]] && first="${resolved}"
	done < <(dots_cask_artifact_apps "${cask}")
	if [[ -n ${first} ]]; then
		printf '%s\n' "${first}"
		return 0
	fi
	dots_cask_resolve_app_path "/Applications/${cask}.app"
}

# Attempt safe Homebrew adoption of an existing identical artifact. Never --force.
# Returns 0 on success; leaves app untouched on failure.
dots_cask_try_adopt() {
	local cask="$1"
	local label="${2:-$1}"
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] brew install --cask --adopt ${cask}"
		return 0
	fi
	if dots_brew install --adopt --cask "${cask}"; then
		echo "OK: adopted existing ${label} into Homebrew cask '${cask}'"
		return 0
	fi
	return 1
}

# Ensure a GUI cask's application requirement is satisfied.
# Usage: dots_ensure_cask_app <cask> [app_path|auto] [label]
# Prints status lines; returns 0 if satisfied, 1 on genuine failure.
# Sets DOTS_CASK_LAST_STATUS=managed|external|installed|adopted|dry-run|failed
dots_ensure_cask_app() {
	local cask="$1"
	local app_spec="${2:-auto}"
	local label="${3:-$1}"
	local app
	DOTS_CASK_LAST_STATUS=""

	if [[ -z ${app_spec} || ${app_spec} == auto ]]; then
		app="$(dots_cask_discover_app "${cask}")"
	else
		app="$(dots_cask_resolve_app_path "${app_spec}")"
	fi

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		# Never invoke brew during dry-run (cache / lock contention).
		echo "[dry-run] would ensure cask '${cask}' for ${label} (no brew invoke)"
		DOTS_CASK_LAST_STATUS="dry-run"
		return 0
	fi

	if dots_cask_is_managed "${cask}"; then
		echo "OK: ${label} managed by Homebrew cask '${cask}'"
		DOTS_CASK_LAST_STATUS="managed"
		return 0
	fi

	if [[ -d ${app} || -e ${app} ]]; then
		echo "Warn: ${label} present at ${app} but Homebrew does not own cask '${cask}' (EXTERNAL)"
		if dots_cask_try_adopt "${cask}" "${label}"; then
			DOTS_CASK_LAST_STATUS="managed"
			return 0
		fi
		echo "OK: ${label} left untouched at ${app} (EXTERNAL; adoption failed or unsupported)"
		echo "    DOTS will not --force or delete this application."
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
		if dots_cask_try_adopt "${cask}" "${label}"; then
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

# Apply cask policy for every cask token in a Brewfile (formulae handled separately).
# Returns 0 if all casks are managed/external/installed; 1 if any genuine failure.
dots_ensure_brewfile_casks() {
	local file="$1"
	local cask rc=0
	[[ -f ${file} ]] || return 0
	while IFS= read -r cask || [[ -n ${cask} ]]; do
		[[ -z ${cask} ]] && continue
		if ! dots_ensure_cask_app "${cask}" auto "${cask}"; then
			rc=1
		fi
	done < <(
		if declare -F dots_brewfile_tokens >/dev/null 2>&1; then
			dots_brewfile_tokens "${file}" cask
		else
			# Minimal fallback parser
			sed -nE 's/^[[:space:]]*cask[[:space:]]+"([^"]+)".*/\1/p' "${file}"
		fi
	)
	return "${rc}"
}
