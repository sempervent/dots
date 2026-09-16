# shellcheck shell=bash
# shellcheck disable=SC1091
# helpers/packages.sh — profile-aware cross-platform package provisioning
#
# macOS / Linuxbrew → brew/groups/*.Brewfile
# Linux without brew → apt / pacman / xbps / dnf via configs/packages/*.toml
#
# Requires: DIR, DRY_RUN, helpers/toml.sh
# Optional globals: PROFILE_PACKAGES[], DOTS_PACKAGE_GROUPS, brew_failed

# shellcheck source=toml.sh
[[ -n ${DIR:-} ]] && source "${DIR}/helpers/toml.sh" 2>/dev/null || true

dots_known_package_groups() {
	printf '%s\n' core modern workstation infra media gui server
}

dots_validate_package_groups() {
	local g unknown=0
	for g in "$@"; do
		[[ -z ${g} ]] && continue
		case "${g}" in
		core | modern | workstation | infra | media | gui | server) ;;
		*)
			echo "Error: unknown package group '${g}'" >&2
			unknown=1
			;;
		esac
	done
	if [[ ${unknown} -ne 0 ]]; then
		echo "Supported groups: $(dots_known_package_groups | tr '\n' ' ')" >&2
		return 1
	fi
	return 0
}

dots_detect_linux_pkg_mgr() {
	if command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
		printf '%s\n' apt
	elif command -v pacman >/dev/null 2>&1; then
		printf '%s\n' pacman
	elif command -v xbps-install >/dev/null 2>&1; then
		printf '%s\n' xbps
	elif command -v dnf >/dev/null 2>&1; then
		printf '%s\n' dnf
	elif command -v yum >/dev/null 2>&1; then
		printf '%s\n' dnf
	else
		printf '%s\n' unknown
	fi
}

# Resolve PROFILE_PACKAGES or DOTS_PACKAGE_GROUPS into DOTS_RESOLVED_GROUPS array
dots_resolve_package_groups() {
	DOTS_RESOLVED_GROUPS=()
	local g
	if [[ ${#PROFILE_PACKAGES[@]} -gt 0 ]]; then
		for g in "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; do
			DOTS_RESOLVED_GROUPS+=("${g}")
		done
	elif [[ -n ${DOTS_PACKAGE_GROUPS:-} ]]; then
		# shellcheck disable=SC2206
		DOTS_RESOLVED_GROUPS=(${DOTS_PACKAGE_GROUPS})
	else
		# Bare setup.sh default: workstation-complete (backward compatible)
		if [[ "$(uname -s)" == "Linux" ]] && ! command -v brew >/dev/null 2>&1; then
			DOTS_RESOLVED_GROUPS=(core modern server)
		else
			DOTS_RESOLVED_GROUPS=(core modern workstation infra media gui)
		fi
	fi
	dots_validate_package_groups "${DOTS_RESOLVED_GROUPS[@]}" || return 1
}

dots_apply_brew_groups() {
	local g file
	local failed=0
	for g in "${DOTS_RESOLVED_GROUPS[@]}"; do
		# gui group is macOS-oriented; skip casks on Linux brew if desired — brew handles it
		file="${DIR}/brew/groups/${g}.Brewfile"
		if [[ ! -f ${file} ]]; then
			echo "Error: missing package group Brewfile: ${file}" >&2
			failed=1
			continue
		fi
		echo "brew bundle --file=${file}"
		if [[ ${DRY_RUN} -eq 1 ]]; then
			echo "[dry-run] would apply group ${g} (file listing only; brew not invoked)"
			# Never call brew during dry-run — it writes caches under $HOME.
			sed -n '1,200p' "${file}"
			continue
		fi
		if ! brew bundle --file="${file}"; then
			echo "Error: brew bundle failed for group ${g}" >&2
			failed=1
		fi
	done
	return "${failed}"
}

# Expand groups → portable tool ids (one per line). Arg: required|optional|all
dots_tools_for_groups() {
	local which="${1:-all}"
	local groups_csv
	groups_csv="$(
		IFS=','
		echo "${DOTS_RESOLVED_GROUPS[*]}"
	)"
	# NOTE: do not use env name GROUPS — bash treats GROUPS as a special readonly array.
	WHICH="${which}" DOTS_PKG_GROUPS="${groups_csv}" dots_toml_query "${DIR}/configs/packages/groups.toml" <<'PY'
import os
wanted = {g.strip() for g in os.environ.get("DOTS_PKG_GROUPS", "").replace(",", " ").split() if g.strip()}
which = os.environ.get("WHICH", "all")
seen = set()
for g in data.get("groups") or []:
    name = str(g.get("name") or "").strip()
    if name not in wanted:
        continue
    items = []
    if which in ("required", "all"):
        items.extend(g.get("required") or [])
    if which in ("optional", "all"):
        items.extend(g.get("optional") or [])
    # backward compat: legacy "tools" key treated as required
    if which in ("required", "all"):
        items.extend(g.get("tools") or [])
    for t in items:
        t = str(t).strip()
        if t and t not in seen:
            seen.add(t)
            print(t)
PY
}

dots_tool_is_required() {
	local tool="$1"
	while IFS= read -r t; do
		[[ ${t} == "${tool}" ]] && return 0
	done < <(dots_tools_for_groups required)
	return 1
}

dots_linux_install_packages() {
	local mgr mapfile
	mgr="$(dots_detect_linux_pkg_mgr)"
	case "${mgr}" in
	apt) mapfile="${DIR}/configs/packages/apt.toml" ;;
	pacman) mapfile="${DIR}/configs/packages/pacman.toml" ;;
	xbps) mapfile="${DIR}/configs/packages/xbps.toml" ;;
	dnf) mapfile="${DIR}/configs/packages/dnf.toml" ;;
	*)
		echo "Error: unsupported Linux package manager (need apt, pacman, xbps, or dnf)." >&2
		echo "Install one of those, or install Homebrew/Linuxbrew and re-run." >&2
		return 1
		;;
	esac

	echo "=== Linux packages (${mgr}) groups: ${DOTS_RESOLVED_GROUPS[*]} ==="
	local tools_req=() tools_opt=() pkgs_req=() pkgs_opt=() skip_opt=() skip_req=() t native
	local tools_tmp tools_rc=0
	tools_tmp="$(mktemp "${TMPDIR:-/tmp}/dots-tools.XXXXXX")"
	dots_tools_for_groups required >"${tools_tmp}" 2>"${tools_tmp}.err" || tools_rc=$?
	if [[ ${tools_rc} -ne 0 ]]; then
		cat "${tools_tmp}.err" >&2 || true
		rm -f "${tools_tmp}" "${tools_tmp}.err"
		echo "Error: failed to expand required package group tools." >&2
		return 1
	fi
	rm -f "${tools_tmp}.err"
	while IFS= read -r t; do
		[[ -z ${t} ]] && continue
		tools_req+=("${t}")
	done <"${tools_tmp}"

	tools_rc=0
	dots_tools_for_groups optional >"${tools_tmp}" 2>"${tools_tmp}.err" || tools_rc=$?
	if [[ ${tools_rc} -eq 0 ]]; then
		while IFS= read -r t; do
			[[ -z ${t} ]] && continue
			tools_opt+=("${t}")
		done <"${tools_tmp}"
	fi
	rm -f "${tools_tmp}" "${tools_tmp}.err"

	if [[ ${#tools_req[@]} -eq 0 && ${#DOTS_RESOLVED_GROUPS[@]} -gt 0 ]]; then
		echo "Error: package groups [${DOTS_RESOLVED_GROUPS[*]}] expanded to zero required tools." >&2
		echo "Check configs/packages/groups.toml and that DOTS_PKG_GROUPS is passed (not bash GROUPS)." >&2
		return 1
	fi

	_dots_map_tool_to_pkg() {
		local tool="$1"
		TOOL="${tool}" dots_toml_query "${mapfile}" <<'PY'
import os
t = os.environ.get("TOOL", "")
pkgs = data.get("packages") or {}
val = pkgs.get(t)
if val is None:
    print("MISSING")
elif str(val).strip() == "":
    print("SKIP")
else:
    print(str(val).strip())
PY
	}

	for t in "${tools_req[@]+"${tools_req[@]}"}"; do
		native="$(_dots_map_tool_to_pkg "${t}")"
		case "${native}" in
		MISSING)
			echo "Error: required tool '${t}' has no mapping in $(basename "${mapfile}")" >&2
			return 1
			;;
		SKIP) skip_req+=("${t}") ;;
		*) pkgs_req+=("${native}") ;;
		esac
	done
	for t in "${tools_opt[@]+"${tools_opt[@]}"}"; do
		native="$(_dots_map_tool_to_pkg "${t}")"
		case "${native}" in
		MISSING | SKIP) skip_opt+=("${t}") ;;
		*) pkgs_opt+=("${native}") ;;
		esac
	done

	if [[ ${#skip_opt[@]} -gt 0 ]]; then
		echo "Note: optional tools unavailable via ${mgr}: ${skip_opt[*]}"
	fi
	if [[ ${#skip_req[@]} -gt 0 ]]; then
		# macOS-oriented ids (fonts/casks) are required via Homebrew on Darwin but have
		# empty native maps on Linux — skip with a note rather than fail the profile.
		local -a skip_darwin_only=() skip_hard=()
		local _st
		for _st in "${skip_req[@]}"; do
			case "${_st}" in
			font-* | terminal-notifier) skip_darwin_only+=("${_st}") ;;
			*) skip_hard+=("${_st}") ;;
			esac
		done
		if [[ ${#skip_darwin_only[@]} -gt 0 ]]; then
			echo "Note: macOS-oriented required tools skipped on ${mgr}: ${skip_darwin_only[*]}"
		fi
		if [[ ${#skip_hard[@]} -gt 0 ]]; then
			echo "Error: required tools have no ${mgr} package: ${skip_hard[*]}" >&2
			return 1
		fi
	fi

	_dots_dedupe_pkgs() {
		local -a src=("$@") out=()
		local p u dup
		for p in "${src[@]+"${src[@]}"}"; do
			dup=0
			for u in "${out[@]+"${out[@]}"}"; do
				[[ ${u} == "${p}" ]] && {
					dup=1
					break
				}
			done
			[[ ${dup} -eq 1 ]] && continue
			out+=("${p}")
		done
		printf '%s\n' "${out[@]+"${out[@]}"}"
	}

	local -a uniq_req=() uniq_opt=()
	while IFS= read -r t; do
		[[ -n ${t} ]] && uniq_req+=("${t}")
	done < <(_dots_dedupe_pkgs "${pkgs_req[@]+"${pkgs_req[@]}"}")
	while IFS= read -r t; do
		[[ -n ${t} ]] && uniq_opt+=("${t}")
	done < <(_dots_dedupe_pkgs "${pkgs_opt[@]+"${pkgs_opt[@]}"}")

	if [[ ${#uniq_req[@]} -eq 0 && ${#uniq_opt[@]} -eq 0 ]]; then
		echo "OK: no native packages to install for selected groups"
		return 0
	fi

	if [[ ${DRY_RUN} -eq 1 ]]; then
		[[ ${#uniq_req[@]} -gt 0 ]] && echo "[dry-run] ${mgr} install (required): ${uniq_req[*]}"
		[[ ${#uniq_opt[@]} -gt 0 ]] && echo "[dry-run] ${mgr} install (optional, best-effort): ${uniq_opt[*]}"
		return 0
	fi

	_dots_mgr_install_batch() {
		local -a batch=("$@")
		[[ ${#batch[@]} -eq 0 ]] && return 0
		case "${mgr}" in
		apt)
			sudo apt-get update -qq || return 1
			sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${batch[@]}" || return 1
			;;
		pacman)
			sudo pacman -Sy --noconfirm --needed "${batch[@]}" || return 1
			;;
		xbps)
			sudo xbps-install -Sy "${batch[@]}" || return 1
			;;
		dnf)
			if command -v dnf >/dev/null 2>&1; then
				sudo dnf install -y "${batch[@]}" || return 1
			else
				sudo yum install -y "${batch[@]}" || return 1
			fi
			;;
		esac
	}

	if [[ ${#uniq_req[@]} -gt 0 ]]; then
		echo "Installing required: ${uniq_req[*]}"
		_dots_mgr_install_batch "${uniq_req[@]}" || return 1
	fi

	# Optional: best-effort one-by-one so a missing universe package cannot block bootstrap
	local op
	for op in "${uniq_opt[@]+"${uniq_opt[@]}"}"; do
		echo "Installing optional: ${op}"
		if ! _dots_mgr_install_batch "${op}"; then
			echo "Warn: optional package '${op}' failed via ${mgr} (continuing)"
		fi
	done

	echo "OK: Linux packages installed via ${mgr}"
}

# Homebrew: auto-provision via Stage 0 (helpers/bootstrap_prereqs.sh).
dots_require_homebrew_macos() {
	if [[ "$(uname -s)" != "Darwin" ]]; then
		return 0
	fi
	if declare -F dots_ensure_homebrew >/dev/null 2>&1; then
		dots_ensure_homebrew
		return $?
	fi
	if command -v brew >/dev/null 2>&1 || [[ -x /opt/homebrew/bin/brew ]] || [[ -x /usr/local/bin/brew ]]; then
		return 0
	fi
	echo "Error: Homebrew required but bootstrap_prereqs.sh not loaded." >&2
	return 1
}

# Main entry used by setup/bootstrap
dots_provision_packages() {
	dots_resolve_package_groups || return 1
	echo "=== Package groups: ${DOTS_RESOLVED_GROUPS[*]} ==="

	if command -v brew >/dev/null 2>&1; then
		if ! dots_apply_brew_groups; then
			echo "Error: one or more Homebrew package groups failed" >&2
			return 1
		fi
		return 0
	fi

	if [[ "$(uname -s)" == "Darwin" ]]; then
		dots_require_homebrew_macos
		return $?
	fi

	# Linux without brew → native package manager
	dots_linux_install_packages || return 1
}
