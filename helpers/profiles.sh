# shellcheck shell=bash
# helpers/profiles.sh — declarative bootstrap profile load / resolve / show
#
# Profiles are data only (TOML). Never execute profile contents.
# Requires: DIR, helpers/components.sh (dots_component_*), helpers/toml.sh

dots_builtin_profile_dir() {
	printf '%s\n' "${DIR}/configs/bootstrap/profiles"
}

# Resolve --profile argument to an absolute TOML path.
# Recognizes: builtin name, absolute/relative path, ~/path, *.toml
dots_resolve_profile_path() {
	local arg="$1"
	local builtin_dir path
	builtin_dir="$(dots_builtin_profile_dir)"

	if [[ -z ${arg} ]]; then
		echo "Error: empty profile" >&2
		return 1
	fi

	if [[ ${arg} == "current" ]]; then
		local state="${HOME}/.config/dots/active-profile"
		if [[ -f ${state} ]]; then
			# shellcheck disable=SC1090
			# active-profile is KEY=value shell
			# shellcheck source=/dev/null
			source "${state}"
			if [[ -n ${DOTS_PROFILE_FILE:-} && -f ${DOTS_PROFILE_FILE} ]]; then
				printf '%s\n' "${DOTS_PROFILE_FILE}"
				return 0
			fi
			if [[ -n ${DOTS_PROFILE:-} ]]; then
				arg="${DOTS_PROFILE}"
			else
				echo "Error: ~/.config/dots/active-profile has no DOTS_PROFILE / DOTS_PROFILE_FILE" >&2
				return 1
			fi
		else
			echo "Error: no active profile recorded (run bootstrap once, or pass --profile explicitly)" >&2
			return 1
		fi
	fi

	# Path-like: contains / or starts with . ~ or ends with .toml
	if [[ ${arg} == */* ]] || [[ ${arg} == .* ]] || [[ ${arg} == ~* ]] || [[ ${arg} == *.toml ]]; then
		path="${arg/#\~/${HOME}}"
		if [[ ${path} != /* ]]; then
			path="$(pwd)/${path}"
		fi
		if [[ ! -f ${path} ]]; then
			echo "Error: profile file not found: ${arg} (resolved ${path})" >&2
			return 1
		fi
		printf '%s\n' "${path}"
		return 0
	fi

	# Builtin name
	path="${builtin_dir}/${arg}.toml"
	if [[ ! -f ${path} ]]; then
		echo "Error: unknown profile '${arg}' (missing ${path})" >&2
		echo "Available builtins:" >&2
		ls -1 "${builtin_dir}"/*.toml 2>/dev/null | xargs -n1 basename | sed 's/\.toml$//' >&2 || true
		echo "Or pass a custom TOML path: --profile /path/to/profile.toml" >&2
		return 1
	fi
	printf '%s\n' "${path}"
}

# Load profile TOML → print lines: name:, desc:, with:, open:, all:, pkg:, runtime.*
dots_profile_parse() {
	local file="$1"
	dots_toml_query "${file}" <<'PY'
prof = data.get("profile") or data
name = (prof.get("name") or path.stem).strip()
desc = (prof.get("description") or "").strip()
print("name:%s" % name)
print("desc:%s" % desc)
if prof.get("include_all_optional"):
    print("all:1")
for item in prof.get("with") or []:
    item = str(item).strip()
    if item:
        print("with:%s" % item)
for item in prof.get("open_apps") or []:
    item = str(item).strip()
    if item:
        print("open:%s" % item)
for item in prof.get("packages") or []:
    item = str(item).strip()
    if item:
        print("pkg:%s" % item)
runtime = data.get("runtime") or {}
if runtime.get("multiplexer"):
    print("runtime.multiplexer:%s" % str(runtime.get("multiplexer")).strip())
if "greeting" in runtime:
    print("runtime.greeting:%s" % ("1" if runtime.get("greeting") else "0"))
if "prompt_stats" in runtime:
    print("runtime.prompt_stats:%s" % ("1" if runtime.get("prompt_stats") else "0"))
if "auto_tmux" in runtime:
    print("runtime.auto_tmux:%s" % ("1" if runtime.get("auto_tmux") else "0"))
PY
}

# Fill PROFILE_* globals from path. Honors include_all_optional / builtin name "all".
dots_load_profile_file() {
	local file="$1"
	local line
	PROFILE_NAME=""
	PROFILE_DESC=""
	PROFILE_WITH=()
	PROFILE_OPEN_APPS=()
	PROFILE_PACKAGES=()
	PROFILE_RUNTIME_MULTIPLEXER=""
	PROFILE_RUNTIME_GREETING=""
	PROFILE_RUNTIME_PROMPT_STATS=""
	PROFILE_RUNTIME_AUTO_TMUX=""
	local include_all=0

	while IFS= read -r line; do
		[[ -z ${line} ]] && continue
		case "${line}" in
		name:*) PROFILE_NAME="${line#name:}" ;;
		desc:*) PROFILE_DESC="${line#desc:}" ;;
		all:*) include_all=1 ;;
		with:*) PROFILE_WITH+=("${line#with:}") ;;
		open:*) PROFILE_OPEN_APPS+=("${line#open:}") ;;
		pkg:*) PROFILE_PACKAGES+=("${line#pkg:}") ;;
		runtime.multiplexer:*) PROFILE_RUNTIME_MULTIPLEXER="${line#runtime.multiplexer:}" ;;
		runtime.greeting:*) PROFILE_RUNTIME_GREETING="${line#runtime.greeting:}" ;;
		runtime.prompt_stats:*) PROFILE_RUNTIME_PROMPT_STATS="${line#runtime.prompt_stats:}" ;;
		runtime.auto_tmux:*) PROFILE_RUNTIME_AUTO_TMUX="${line#runtime.auto_tmux:}" ;;
		esac
	done < <(dots_profile_parse "${file}")

	if [[ ${include_all} -eq 1 ]] || [[ ${PROFILE_NAME} == "all" && ${#PROFILE_WITH[@]} -eq 0 ]]; then
		PROFILE_WITH=()
		while IFS= read -r line; do
			[[ -n ${line} ]] && PROFILE_WITH+=("${line}")
		done < <(dots_component_ids_for_all)
	fi

	# Default package groups when profile omits packages=
	if [[ ${#PROFILE_PACKAGES[@]} -eq 0 ]]; then
		case "${PROFILE_NAME}" in
		server) PROFILE_PACKAGES=(core modern server) ;;
		work) PROFILE_PACKAGES=(core modern workstation) ;;
		home | all) PROFILE_PACKAGES=(core modern workstation infra media gui) ;;
		base | *) PROFILE_PACKAGES=(core modern) ;;
		esac
	fi

	# Default runtime multiplexer by profile role when omitted
	if [[ -z ${PROFILE_RUNTIME_MULTIPLEXER} ]]; then
		case "${PROFILE_NAME}" in
		home) PROFILE_RUNTIME_MULTIPLEXER="herdr" ;;
		*) PROFILE_RUNTIME_MULTIPLEXER="tmux" ;;
		esac
	fi

	if [[ ${#PROFILE_WITH[@]} -gt 0 ]]; then
		dots_validate_components "${PROFILE_WITH[@]}" || return 1
	fi

	echo "OK: loaded profile '${PROFILE_NAME:-unknown}' from ${file}"
	if [[ -n ${PROFILE_DESC} ]]; then
		echo "OK: ${PROFILE_DESC}"
	fi
	echo "OK: packages=${PROFILE_PACKAGES[*]}"
	echo "OK: runtime.multiplexer=${PROFILE_RUNTIME_MULTIPLEXER}"
	if [[ ${#PROFILE_WITH[@]} -eq 0 ]]; then
		echo "OK: profile with=[] (no optional components)"
	else
		echo "OK: profile with=${PROFILE_WITH[*]}"
	fi
}

dots_array_contains() {
	local needle="$1" x
	shift
	for x in "$@"; do
		[[ ${x} == "${needle}" ]] && return 0
	done
	return 1
}

# PROFILE_WITH + CLI_WITH - CLI_WITHOUT → EFFECTIVE_WITH (deduped)
dots_compute_effective_with() {
	EFFECTIVE_WITH=()
	local c
	for c in "${PROFILE_WITH[@]+"${PROFILE_WITH[@]}"}"; do
		dots_array_contains "${c}" "${CLI_WITHOUT[@]+"${CLI_WITHOUT[@]}"}" && continue
		dots_array_contains "${c}" "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}" && continue
		EFFECTIVE_WITH+=("${c}")
	done
	for c in "${CLI_WITH[@]+"${CLI_WITH[@]}"}"; do
		dots_array_contains "${c}" "${CLI_WITHOUT[@]+"${CLI_WITHOUT[@]}"}" && continue
		dots_array_contains "${c}" "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}" && continue
		EFFECTIVE_WITH+=("${c}")
	done
	if [[ ${#EFFECTIVE_WITH[@]} -gt 0 ]]; then
		dots_validate_components "${EFFECTIVE_WITH[@]}" || return 1
	fi
	if [[ ${#CLI_WITH[@]} -gt 0 ]]; then
		dots_validate_components "${CLI_WITH[@]}" || return 1
	fi
	if [[ ${#CLI_WITHOUT[@]} -gt 0 ]]; then
		dots_validate_components "${CLI_WITHOUT[@]}" || return 1
	fi
}

dots_show_profile_resolution() {
	local label="${1:-resolved}"
	echo "profile: ${PROFILE_NAME:-${label}}"
	if [[ -n ${PROFILE_DESC} ]]; then
		echo "description: ${PROFILE_DESC}"
	fi
	echo ""
	echo "package groups:"
	if [[ ${#PROFILE_PACKAGES[@]} -eq 0 ]]; then
		echo "  (none)"
	else
		local g
		for g in "${PROFILE_PACKAGES[@]}"; do
			echo "  ${g}"
		done
	fi
	echo ""
	echo "runtime:"
	echo "  multiplexer: ${PROFILE_RUNTIME_MULTIPLEXER:-tmux}"
	[[ -n ${PROFILE_RUNTIME_GREETING} ]] && echo "  greeting: ${PROFILE_RUNTIME_GREETING}"
	[[ -n ${PROFILE_RUNTIME_PROMPT_STATS} ]] && echo "  prompt_stats: ${PROFILE_RUNTIME_PROMPT_STATS}"
	echo ""
	echo "components:"
	if [[ ${#EFFECTIVE_WITH[@]} -eq 0 ]]; then
		echo "  (none)"
	else
		local c
		for c in "${EFFECTIVE_WITH[@]}"; do
			echo "  ${c}"
		done
	fi
	echo ""
	if [[ ${#EFFECTIVE_WITH[@]} -gt 0 ]]; then
		dots_print_provider_implications "${EFFECTIVE_WITH[@]}"
	else
		echo "explicit provider implications:"
		echo "  local AI: (none)"
		echo "  cloud AI: (none)"
		echo "  image AI: (none)"
	fi
}

dots_warn_cloud_components() {
	local cloud
	cloud="$(dots_print_cloud_notice "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}")"
	if [[ -z ${cloud} ]]; then
		return 0
	fi
	echo ""
	echo "Cloud/external AI components selected:"
	while IFS= read -r c; do
		[[ -n ${c} ]] && echo "  - ${c}"
	done <<<"${cloud}"
	echo "(Informational — binary presence elsewhere still does not imply consent.)"
}

# Persist non-secret runtime policy + active profile markers.
dots_write_runtime_policy() {
	local dest_dir="${HOME}/.config/dots"
	local runtime_env="${dest_dir}/runtime.env"
	local active="${dest_dir}/active-profile"
	local profile_file="${1:-}"

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] write ${runtime_env} and ${active}"
		return 0
	fi

	mkdir -p "${dest_dir}"

	local mux="${PROFILE_RUNTIME_MULTIPLEXER:-tmux}"
	# Herdr multiplexer only when herdr was selected THIS run (binary presence ≠ consent).
	if [[ ${mux} == "herdr" ]]; then
		if ! dots_array_contains herdr "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
			echo "Note: runtime.multiplexer=herdr but herdr not selected this run — writing tmux"
			mux="tmux"
		fi
	fi

	local greeting="${PROFILE_RUNTIME_GREETING:-1}"
	local prompt_stats="${PROFILE_RUNTIME_PROMPT_STATS:-0}"
	local auto_tmux="${PROFILE_RUNTIME_AUTO_TMUX:-1}"

	cat >"${runtime_env}" <<EOF
# Generated by DOTS bootstrap/setup — non-secret runtime policy.
# Uses := so pre-set process environment is preserved.
# local.sh (sourced later) may override with plain exports.
# Do not put secrets here.
: "\${DOTS_PROFILE:=${PROFILE_NAME:-unknown}}"
: "\${DOTS_MULTIPLEXER:=${mux}}"
: "\${DOTS_GREETING:=${greeting}}"
: "\${DOTS_PROMPT_STATS:=${prompt_stats}}"
: "\${DOTS_AUTO_TMUX:=${auto_tmux}}"
: "\${DOTS_PACKAGE_GROUPS:=${PROFILE_PACKAGES[*]}}"
export DOTS_PROFILE DOTS_MULTIPLEXER DOTS_GREETING DOTS_PROMPT_STATS DOTS_AUTO_TMUX DOTS_PACKAGE_GROUPS
EOF

	cat >"${active}" <<EOF
# Last bootstrap profile selection (non-secret).
# DOTS_EFFECTIVE_WITH is informational only — NOT configuration consent.
# AI consent remains invocation-scoped via setup.sh --with for that run.
DOTS_PROFILE='${PROFILE_NAME:-unknown}'
DOTS_PROFILE_FILE='${profile_file}'
DOTS_PACKAGE_GROUPS='${PROFILE_PACKAGES[*]}'
DOTS_LAST_WITH_INFO='${EFFECTIVE_WITH[*]:-}'
EOF

	# Seed local.sh once (never overwrite)
	if [[ ! -f "${dest_dir}/local.sh" ]]; then
		cat >"${dest_dir}/local.sh" <<'EOF'
# ~/.config/dots/local.sh — machine-local non-secret overrides (Bash + Zsh)
# Sourced late by DOTS shells. Not committed. Safe to edit.
#
# Examples:
#   export DOTS_MULTIPLEXER=tmux
#   export AWS_PROFILE=work
#   export KUBECONFIG="$HOME/.kube/config"
#
# Do not store secrets here — use your OS keychain / agent / private env files.
EOF
		echo "OK: created ${dest_dir}/local.sh (edit for machine overrides)"
	fi

	echo "OK: wrote ${runtime_env}"
}
