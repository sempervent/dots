#!/usr/bin/env bash
# bootstrap.sh — onboard a machine via declarative profiles + setup.sh
#
# Profiles are data (TOML). setup.sh is the installer. configure.sh edits profiles.
#
# Semantics:
#   profile baseline + CLI --with − CLI --without → effective set → setup.sh
#
# Examples:
#   ./bootstrap.sh --profile home
#   ./bootstrap.sh --profile work
#   ./bootstrap.sh --profile server
#   ./bootstrap.sh --profile home --without cursor
#   ./bootstrap.sh --profile work --with hermes,ollama
#   ./bootstrap.sh --profile home --show
#   ./bootstrap.sh --profile server --dry-run
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# Stage 0 first — no Python required
# shellcheck source=helpers/bootstrap_prereqs.sh
source "${DIR}/helpers/bootstrap_prereqs.sh"
# shellcheck source=helpers/toml.sh
source "${DIR}/helpers/toml.sh"
# shellcheck source=helpers/components.sh
source "${DIR}/helpers/components.sh"
# shellcheck source=helpers/profiles.sh
source "${DIR}/helpers/profiles.sh"
# shellcheck source=helpers/packages.sh
source "${DIR}/helpers/packages.sh"

PROFILE="base"
DRY_RUN=0
CHECK_ONLY=0
OPEN_APPS=0
SHOW_ONLY=0
NO_INSTALL=0
CLI_WITH=()
CLI_WITHOUT=()
PROFILE_NAME=""
PROFILE_DESC=""
PROFILE_EXTENDS=""
PROFILE_CHAIN=()
PROFILE_WITH=()
PROFILE_WITHOUT=()
PROFILE_OPEN_APPS=()
PROFILE_PACKAGES=()
PROFILE_RUNTIME_MULTIPLEXER=""
PROFILE_RUNTIME_GREETING=""
PROFILE_RUNTIME_PROMPT_STATS=""
PROFILE_RUNTIME_AUTO_TMUX=""
EFFECTIVE_WITH=()

usage() {
	cat <<'EOF'
Usage: ./bootstrap.sh [options]

Onboard / refresh a machine using a declarative profile, then invoke setup.sh.

Options:
  --profile <name|path>  Builtin: base | home | work | server | all | current
                         Or a custom TOML path (absolute, relative, or ~/…)
  --with <list>          Add components onto the profile baseline
  --without <list>       Remove components from the effective set
  --show                 Print resolved components/packages/runtime and exit
  --dry-run              Preview (passed through to setup.sh; no mutations)
  --no-install           Resolve/verify only; do not install missing software
  --check-only           Run scripts/check.sh for the profile (no setup)
  --open-apps            After setup, open selected/installed apps (macOS GUI)
  --no-open              Never open apps (default)
  -h, --help             Show this help

Happy paths:
  ./bootstrap.sh --profile home      # personal Mac (auto-provisions brew/python)
  ./bootstrap.sh --profile work      # employer Mac
  ./bootstrap.sh --profile server    # headless Linux
  ./bootstrap.sh --profile base      # minimal core
  ./bootstrap.sh --profile work --no-install   # managed hosts: fail if deps missing

Policy:
  Profiles are explicit authorization for THAT run.
  Binary presence alone never authorizes configuration.
  Stage 0 auto-provisions Homebrew/Python via official channels when needed.
  --show / --dry-run never mutate.

See README.md for package groups, runtime policy, and local overrides.
EOF
}

parse_csv_add() {
	local dest_name="$1" raw="$2" item
	local -a _parts=()
	IFS=',' read -r -a _parts <<<"${raw}"
	# Bash 3.2 + set -u: empty array expansion is unbound
	for item in "${_parts[@]+"${_parts[@]}"}"; do
		item="$(echo "${item}" | tr -d '[:space:]')"
		[[ -z ${item} ]] && continue
		eval "${dest_name}+=(\"\${item}\")"
	done
}

maybe_open_apps() {
	if [[ ${OPEN_APPS} -ne 1 ]]; then
		return 0
	fi
	if [[ ${DRY_RUN} -eq 1 ]]; then
		echo "[dry-run] would open apps: ${PROFILE_OPEN_APPS[*]:-none}"
		return 0
	fi
	if [[ -n ${SSH_CONNECTION:-} ]] || [[ -n ${SSH_TTY:-} ]]; then
		echo "Note: SSH session — skipping --open-apps"
		return 0
	fi
	if [[ ! -t 0 ]] || [[ ${CI:-} == "true" ]] || [[ -n ${GITHUB_ACTIONS:-} ]]; then
		echo "Note: noninteractive/CI — skipping --open-apps"
		return 0
	fi
	if [[ "$(uname -s)" != "Darwin" ]] || ! command -v open >/dev/null 2>&1; then
		return 0
	fi
	echo "=== Opening apps (--open-apps) ==="
	local app
	for app in "${PROFILE_OPEN_APPS[@]+"${PROFILE_OPEN_APPS[@]}"}"; do
		case "${app}" in
		iTerm | iTerm2)
			[[ -d "/Applications/iTerm.app" ]] && open -a iTerm || true
			;;
		"Draw Things")
			if dots_array_contains drawthings "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}" &&
				[[ -d "/Applications/Draw Things.app" ]]; then
				open -a "Draw Things" || true
			fi
			;;
		Cursor)
			if dots_array_contains cursor "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}" &&
				[[ -d "/Applications/Cursor.app" ]]; then
				open -a Cursor || true
			fi
			;;
		*) echo "Note: unknown open_apps entry '${app}'" ;;
		esac
	done
}

manual_followups() {
	echo ""
	echo "=== Manual follow-ups ==="
	if dots_array_contains_pkg gui; then
		echo "• Set iTerm font to JetBrainsMono Nerd Font (Profiles → Text)"
	fi
	if dots_array_contains_pkg workstation && [[ "$(uname -s)" == "Darwin" ]]; then
		echo "• Enable terminal-notifier notification permission if prompted"
	fi
	if dots_array_contains hermes "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
		echo "• Authenticate Hermes (hermes login / first-run flow)"
	fi
	if dots_array_contains codex "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
		echo '• Authenticate Codex (interactive `codex` login; DOTS never copies tokens)'
	fi
	if dots_array_contains cursor "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
		echo '• Authenticate Cursor Agent CLI (`agent` first-time login)'
	fi
	if dots_array_contains ollama "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
		echo "• Start Ollama and pull models you need (DOTS never auto-pulls)"
	fi
	if dots_array_contains drawthings "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
		echo "• Ensure Draw Things models are downloaded (GUI or DRAWTHINGS_MODELS_DIR)"
	fi
	echo "• Edit ~/.config/git/personal and ~/.config/git/work with your identities"
	echo "• Machine overrides: ~/.config/dots/local.sh"
	if [[ ${#EFFECTIVE_WITH[@]} -eq 0 ]]; then
		echo "• No AI clients selected — no AI auth steps required"
	fi
}

dots_array_contains_pkg() {
	local needle="$1" x
	for x in "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; do
		[[ ${x} == "${needle}" ]] && return 0
	done
	return 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--profile)
		PROFILE="${2:-}"
		shift 2
		;;
	--profile=*)
		PROFILE="${1#*=}"
		shift
		;;
	--with)
		parse_csv_add CLI_WITH "${2:-}"
		shift 2
		;;
	--with=*)
		parse_csv_add CLI_WITH "${1#*=}"
		shift
		;;
	--without)
		parse_csv_add CLI_WITHOUT "${2:-}"
		shift 2
		;;
	--without=*)
		parse_csv_add CLI_WITHOUT "${1#*=}"
		shift
		;;
	--show)
		SHOW_ONLY=1
		shift
		;;
	--dry-run)
		DRY_RUN=1
		shift
		;;
	--no-install)
		NO_INSTALL=1
		shift
		;;
	--check-only)
		CHECK_ONLY=1
		shift
		;;
	--open-apps)
		OPEN_APPS=1
		shift
		;;
	--no-open)
		OPEN_APPS=0
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Error: unknown option: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

PROFILE_FILE="$(dots_resolve_profile_path "${PROFILE}")"

# Stage 0 before any Python/TOML requirement.
# --show/--dry-run: report only. Real runs: install CLT/brew/python as needed.
if [[ ${SHOW_ONLY} -eq 1 || ${DRY_RUN} -eq 1 ]]; then
	dots_stage0_ensure 1 || true
else
	dots_stage0_ensure 0 || exit 1
fi

# Python ≥3.11 for Stage 1 TOML. Soft on show/dry-run; may already be provisioned.
_py_soft=0
[[ ${SHOW_ONLY} -eq 1 || ${DRY_RUN} -eq 1 ]] && _py_soft=1
if ! dots_require_python "${_py_soft}"; then
	if [[ ${SHOW_ONLY} -eq 1 ]]; then
		# Useful non-mutating UX without Python: Stage 0 already reported.
		local_prof="${PROFILE}"
		[[ ${local_prof} == *.toml ]] && local_prof="$(basename "${local_prof}" .toml)"
		[[ ${local_prof} == */* ]] && local_prof="$(basename "${local_prof}" .toml)"
		dots_show_builtin_profile_fallback "${local_prof}"
		exit 0
	fi
	echo "Error: Python >=3.11 required for profile resolution and was not provisioned." >&2
	exit 1
fi

dots_load_profile_file "${PROFILE_FILE}"
dots_compute_effective_with
dots_validate_package_groups "${PROFILE_PACKAGES[@]}" || exit 1

echo ""
echo "=== Effective optional components (profile + --with − --without) ==="
if [[ ${#EFFECTIVE_WITH[@]} -eq 0 ]]; then
	echo "(none — base/core only)"
else
	printf '  %s\n' "${EFFECTIVE_WITH[@]}"
fi
echo "=== Package groups ==="
printf '  %s\n' "${PROFILE_PACKAGES[@]}"
echo "=== Runtime multiplexer ==="
echo "  ${PROFILE_RUNTIME_MULTIPLEXER:-tmux}"
dots_warn_cloud_components

if [[ ${SHOW_ONLY} -eq 1 ]]; then
	echo ""
	dots_show_profile_resolution
	exit 0
fi

if [[ ${CHECK_ONLY} -eq 1 ]]; then
	echo "=== check-only (profile=${PROFILE_NAME}) ==="
	DOTS_DIR="${DIR}" exec "${DIR}/scripts/check.sh" --profile "${PROFILE_FILE}"
fi

if [[ ${NO_INSTALL} -eq 1 ]]; then
	echo "=== --no-install: verifying prerequisites without provisioning ==="
	missing=0
	if [[ "$(uname -s)" == "Darwin" ]] && ! dots_find_brew >/dev/null 2>&1; then
		echo "Error: Homebrew missing (--no-install)" >&2
		missing=1
	fi
	if ! dots_stage0_python_present; then
		echo "Error: Python >=3.11 missing (--no-install)" >&2
		missing=1
	fi
	if dots_array_contains herdr "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
		if ! command -v herdr >/dev/null 2>&1; then
			echo "Error: herdr missing (--no-install)" >&2
			missing=1
		fi
	fi
	if [[ ${missing} -ne 0 ]]; then
		exit 1
	fi
	echo "OK: --no-install prerequisites present; skipping setup package installs"
	# Still allow check-only style verification of current machine
	DOTS_DIR="${DIR}" "${DIR}/scripts/check.sh" --profile "${PROFILE_FILE}" || exit 1
	exit 0
fi

# Persist runtime policy before setup so shells see it after install
dots_write_runtime_policy "${PROFILE_FILE}"

SETUP_ARGS=(--profile "${PROFILE_NAME}")
[[ ${DRY_RUN} -eq 1 ]] && SETUP_ARGS+=(--dry-run)
if [[ ${#PROFILE_PACKAGES[@]} -gt 0 ]]; then
	IFS=','
	SETUP_ARGS+=(--packages "${PROFILE_PACKAGES[*]}")
	unset IFS
fi
if [[ ${#EFFECTIVE_WITH[@]} -gt 0 ]]; then
	IFS=','
	SETUP_ARGS+=(--with "${EFFECTIVE_WITH[*]}")
	unset IFS
fi

echo ""
echo "=== Invoking setup.sh ${SETUP_ARGS[*]:-} ==="
"${DIR}/setup.sh" "${SETUP_ARGS[@]+"${SETUP_ARGS[@]}"}"

CHECK_STATUS=0
if [[ ${DRY_RUN} -eq 0 ]]; then
	echo "=== Verification (profile=${PROFILE_NAME}) ==="
	# Herdr/official installers often land in ~/.local/bin
	export PATH="${HOME}/.local/bin:${PATH}"
	if ! DOTS_DIR="${DIR}" "${DIR}/scripts/check.sh" --profile "${PROFILE_FILE}"; then
		CHECK_STATUS=1
	fi
fi

maybe_open_apps
manual_followups

echo ""
if [[ ${DRY_RUN} -eq 1 ]]; then
	echo "Bootstrap dry-run finished (profile=${PROFILE_NAME}). No health-check gate."
	exit 0
fi

if [[ ${CHECK_STATUS} -eq 0 ]]; then
	echo "Bootstrap complete: profile contract satisfied (profile=${PROFILE_NAME})."
	echo "Consent model: binary presence ≠ configuration authorization."
	exit 0
else
	echo "Bootstrap FAILED: required health checks failed (profile=${PROFILE_NAME})." >&2
	echo "Fix the errors above, then re-run: ./bootstrap.sh --profile ${PROFILE_NAME}" >&2
	exit 1
fi
