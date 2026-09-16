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
		for g in "${PROFILE_PACKAGES[@]}"; do
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
	WHICH="${which}" GROUPS="${groups_csv}" dots_toml_query "${DIR}/configs/packages/groups.toml" <<'PY'
import os
wanted = {g.strip() for g in os.environ.get("GROUPS", "").replace(",", " ").split() if g.strip()}
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
	local tools pkgs=() skip_opt=() skip_req=() t native
	while IFS= read -r t; do
		[[ -z ${t} ]] && continue
		tools+=("${t}")
	done < <(dots_tools_for_groups all)

	for t in "${tools[@]}"; do
		native="$(
			TOOL="${t}" dots_toml_query "${mapfile}" <<'PY'
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
		)"
		case "${native}" in
		MISSING)
			echo "Error: tool '${t}' has no mapping in $(basename "${mapfile}")" >&2
			return 1
			;;
		SKIP)
			if dots_tool_is_required "${t}"; then
				skip_req+=("${t}")
			else
				skip_opt+=("${t}")
			fi
			;;
		*)
			pkgs+=("${native}")
			;;
		esac
	done

	if [[ ${#skip_opt[@]} -gt 0 ]]; then
		echo "Note: optional tools unavailable via ${mgr} (WARN later if still missing): ${skip_opt[*]}"
	fi
	if [[ ${#skip_req[@]} -gt 0 ]]; then
		echo "Error: required tools have no ${mgr} package (install manually or use another platform): ${skip_req[*]}" >&2
		return 1
	fi

	if [[ ${#pkgs[@]} -eq 0 ]]; then
		echo "OK: no native packages to install for selected groups"
		return 0
	fi

	# Deduplicate without associative arrays (macOS /bin/bash is 3.2)
	local uniq=() p u dup
	for p in "${pkgs[@]}"; do
		dup=0
		for u in "${uniq[@]+"${uniq[@]}"}"; do
			[[ ${u} == "${p}" ]] && {
				dup=1
				break
			}
		done
		[[ ${dup} -eq 1 ]] && continue
		uniq+=("${p}")
	done

	echo "Installing: ${uniq[*]}"
	if [[ ${DRY_RUN} -eq 1 ]]; then
		echo "[dry-run] ${mgr} install ${uniq[*]}"
		return 0
	fi

	case "${mgr}" in
	apt)
		sudo apt-get update -qq || return 1
		sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${uniq[@]}" || return 1
		;;
	pacman)
		sudo pacman -Sy --noconfirm --needed "${uniq[@]}" || return 1
		;;
	xbps)
		sudo xbps-install -Sy "${uniq[@]}" || return 1
		;;
	dnf)
		if command -v dnf >/dev/null 2>&1; then
			sudo dnf install -y "${uniq[@]}" || return 1
		else
			sudo yum install -y "${uniq[@]}" || return 1
		fi
		;;
	esac
	echo "OK: Linux packages installed via ${mgr}"
}

# Homebrew policy for macOS (deliberate — do not auto curl|bash install).
dots_require_homebrew_macos() {
	if [[ "$(uname -s)" != "Darwin" ]]; then
		return 0
	fi
	if command -v brew >/dev/null 2>&1; then
		return 0
	fi
	cat >&2 <<'EOF'
Error: Homebrew is required on macOS but was not found.

DOTS does not auto-install Homebrew (deliberate policy).

Install it, then re-run bootstrap:

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

After install, ensure brew is on PATH (Apple Silicon usually needs):

  eval "$(/opt/homebrew/bin/brew shellenv)"

Then:

  ./bootstrap.sh --profile <your-profile>
EOF
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
