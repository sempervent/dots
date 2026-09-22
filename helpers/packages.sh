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
if [[ -n ${DIR:-} ]]; then
	# Optional when packages.sh is sourced before DIR is set (unit tests).
	# shellcheck disable=SC1091
	source "${DIR}/helpers/toml.sh" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Package-group registry (authority: configs/packages/groups.toml)
# Override for tests: DOTS_GROUPS_REGISTRY=/path/to/temp.toml
# ---------------------------------------------------------------------------

dots_groups_registry_path() {
	if [[ -n ${DOTS_GROUPS_REGISTRY:-} && -f ${DOTS_GROUPS_REGISTRY} ]]; then
		printf '%s\n' "${DOTS_GROUPS_REGISTRY}"
		return 0
	fi
	printf '%s\n' "${DIR}/configs/packages/groups.toml"
}

# Print all group ids (one per line), registry order.
dots_known_package_groups() {
	dots_toml_query "$(dots_groups_registry_path)" <<'PY'
for g in data.get("groups") or []:
    name = str(g.get("name") or "").strip()
    if name:
        print(name)
PY
}

dots_group_is_known() {
	local want="$1" id
	[[ -n ${want} ]] || return 1
	while IFS= read -r id; do
		[[ ${id} == "${want}" ]] && return 0
	done < <(dots_known_package_groups)
	return 1
}

dots_validate_package_groups() {
	local g unknown=0
	for g in "$@"; do
		[[ -z ${g} ]] && continue
		if ! dots_group_is_known "${g}"; then
			echo "Error: unknown package group '${g}'" >&2
			unknown=1
		fi
	done
	if [[ ${unknown} -ne 0 ]]; then
		echo "Supported groups: $(dots_known_package_groups | tr '\n' ' ')" >&2
		echo "Authority: $(dots_groups_registry_path)" >&2
		return 1
	fi
	return 0
}

# Description for one group id (empty if unknown / missing field).
dots_group_description() {
	local want="$1"
	[[ -n ${want} ]] || return 1
	WANT="${want}" dots_toml_query "$(dots_groups_registry_path)" <<'PY'
import os
want = os.environ.get("WANT", "").strip()
for g in data.get("groups") or []:
    if str(g.get("name") or "").strip() != want:
        continue
    print(str(g.get("description") or "").strip())
    raise SystemExit(0)
raise SystemExit(1)
PY
}

# Expand one group → portable tool ids. Arg2: required|optional|all
dots_group_package_ids() {
	local want="$1" which="${2:-all}"
	[[ -n ${want} ]] || return 1
	WANT="${want}" WHICH="${which}" dots_toml_query "$(dots_groups_registry_path)" <<'PY'
import os
want = os.environ.get("WANT", "").strip()
which = os.environ.get("WHICH", "all")
for g in data.get("groups") or []:
    if str(g.get("name") or "").strip() != want:
        continue
    items = []
    if which in ("required", "all"):
        items.extend(g.get("required") or [])
    if which in ("optional", "all"):
        items.extend(g.get("optional") or [])
    if which in ("required", "all"):
        items.extend(g.get("tools") or [])
    seen = set()
    for t in items:
        t = str(t).strip()
        if t and t not in seen:
            seen.add(t)
            print(t)
    raise SystemExit(0)
raise SystemExit(1)
PY
}

# Canonical Brewfile path for a group (relative to DIR): brew/groups/<id>.Brewfile
dots_group_brewfile() {
	local id="$1"
	[[ -n ${id} ]] || return 1
	dots_group_is_known "${id}" || return 1
	printf 'brew/groups/%s.Brewfile\n' "${id}"
}

# Count required/optional ids for a group (tab-separated: req\topt).
dots_group_counts() {
	local want="$1"
	[[ -n ${want} ]] || return 1
	WANT="${want}" dots_toml_query "$(dots_groups_registry_path)" <<'PY'
import os
want = os.environ.get("WANT", "").strip()
for g in data.get("groups") or []:
    if str(g.get("name") or "").strip() != want:
        continue
    req = list(g.get("required") or []) + list(g.get("tools") or [])
    opt = list(g.get("optional") or [])
    print("%d\t%d" % (len(req), len(opt)))
    raise SystemExit(0)
raise SystemExit(1)
PY
}

# Map portable tool id → native name for current/forced Linux mgr (or brew on Darwin).
# Prints: mapped_name | SKIP | MISSING | brew:<id>
dots_group_tool_platform_name() {
	local tool="$1"
	local mgr="" mapfile=""
	[[ -n ${tool} ]] || return 1
	if [[ -n ${DOTS_FORCE_PKG_MGR:-} ]]; then
		mgr="${DOTS_FORCE_PKG_MGR}"
	elif command -v brew >/dev/null 2>&1 || [[ "$(uname -s)" == "Darwin" ]]; then
		printf 'brew:%s\n' "${tool}"
		return 0
	else
		mgr="$(dots_detect_linux_pkg_mgr)"
	fi
	case "${mgr}" in
	apt) mapfile="${DIR}/configs/packages/apt.toml" ;;
	pacman) mapfile="${DIR}/configs/packages/pacman.toml" ;;
	xbps) mapfile="${DIR}/configs/packages/xbps.toml" ;;
	dnf) mapfile="${DIR}/configs/packages/dnf.toml" ;;
	brew | homebrew)
		printf 'brew:%s\n' "${tool}"
		return 0
		;;
	*)
		printf 'MISSING\n'
		return 0
		;;
	esac
	[[ -f ${mapfile} ]] || {
		printf 'MISSING\n'
		return 0
	}
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
	PROFILE_PACKAGES=("${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}")
	local g
	if [[ ${#PROFILE_PACKAGES[@]} -gt 0 ]]; then
		for g in "${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}"; do
			DOTS_RESOLVED_GROUPS+=("${g}")
		done
	elif [[ -n ${DOTS_PACKAGE_GROUPS:-} ]]; then
		# shellcheck disable=SC2206
		DOTS_RESOLVED_GROUPS=(${DOTS_PACKAGE_GROUPS})
	else
		# Bare setup.sh (no profile): deliberate convenience selection — not a
		# validation allowlist. Profile membership lives in profile TOMLs.
		# When TOML/Python is unavailable, same list is the Stage-0 fallback.
		if [[ "$(uname -s)" == "Linux" ]] && ! command -v brew >/dev/null 2>&1; then
			DOTS_RESOLVED_GROUPS=(core modern server)
		else
			DOTS_RESOLVED_GROUPS=(core modern workstation infra media gui)
		fi
	fi
	dots_validate_package_groups "${DOTS_RESOLVED_GROUPS[@]}" || return 1
}

# Apply one Brewfile with external-cask policy:
#   formulae via brew bundle --brews (fallback: full bundle)
#   casks via dots_ensure_cask_app (adopt, never --force / never cleanup)
# Dry-run lists the file only — never invokes brew (cache-safe).
dots_apply_brewfile_packages() {
	local file="$1"
	local label="${2:-$(basename "${file}")}"
	if [[ ! -f ${file} ]]; then
		echo "Warn: missing ${file}"
		return 0
	fi
	echo "brew bundle --file=${file}"
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] would apply ${label} (file listing only; brew not invoked):"
		sed -n '1,200p' "${file}"
		return 0
	fi

	local brew_bin="${DOTS_BREW_BIN:-brew}"
	local failed=0
	# Formulae / taps first (no cask conflict with external .apps)
	if ! "${brew_bin}" bundle --file="${file}" --brews --taps 2>/dev/null; then
		# Older brew may lack --brews/--taps; fall back carefully:
		# full bundle may fail on external casks — still reconcile casks below.
		if ! "${brew_bin}" bundle --file="${file}"; then
			echo "Warn: brew bundle reported errors for ${label} (continuing cask reconcile)"
			failed=1
		fi
	fi

	if declare -F dots_ensure_brewfile_casks >/dev/null 2>&1; then
		if ! dots_ensure_brewfile_casks "${file}"; then
			echo "Error: one or more casks failed for ${label}" >&2
			return 1
		fi
		# Casks reconciled: clear soft formula-bundle failure if all desired
		# formulae from the file are present (avoid failing solely on EXTERNAL).
		failed=0
		local f
		while IFS= read -r f || [[ -n ${f} ]]; do
			[[ -z ${f} ]] && continue
			if ! "${brew_bin}" list --formula "${f}" >/dev/null 2>&1; then
				# Short name / tap-qualified
				if ! "${brew_bin}" list --formula "${f##*/}" >/dev/null 2>&1; then
					echo "Error: formula '${f}' missing after bundle (${label})" >&2
					failed=1
				fi
			fi
		done < <(
			if declare -F dots_brewfile_tokens >/dev/null 2>&1; then
				dots_brewfile_tokens "${file}" brew
			else
				sed -nE 's/^[[:space:]]*brew[[:space:]]+"([^"]+)".*/\1/p' "${file}"
			fi
		)
	elif [[ ${failed} -ne 0 ]]; then
		echo "Error: brew bundle failed for ${label}" >&2
		return 1
	fi
	return "${failed}"
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
		if ! dots_apply_brewfile_packages "${file}" "group ${g}"; then
			echo "Error: package group ${g} failed" >&2
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
	WHICH="${which}" DOTS_PKG_GROUPS="${groups_csv}" dots_toml_query "$(dots_groups_registry_path)" <<'PY'
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

# ---------------------------------------------------------------------------
# Read-only CLI: groups / group / plan (no install, no auth, no outdated queries)
# ---------------------------------------------------------------------------

# True if group id is in the active/resolved set.
dots_group_is_active() {
	local want="$1" g
	DOTS_RESOLVED_GROUPS=("${DOTS_RESOLVED_GROUPS[@]+"${DOTS_RESOLVED_GROUPS[@]}"}")
	for g in "${DOTS_RESOLVED_GROUPS[@]+"${DOTS_RESOLVED_GROUPS[@]}"}"; do
		[[ ${g} == "${want}" ]] && return 0
	done
	return 1
}

# List all package groups with active marker (read-only; no brew required).
dots_packages_groups_list() {
	local g desc counts req opt active mark
	printf 'PACKAGE GROUPS  (authority: %s)\n' "$(dots_groups_registry_path)"
	printf '\n'
	printf '%-14s %-8s %8s %8s  %s\n' "GROUP" "ACTIVE" "REQUIRED" "OPTIONAL" "ROLE"
	while IFS= read -r g; do
		[[ -z ${g} ]] && continue
		desc="$(dots_group_description "${g}" 2>/dev/null || true)"
		counts="$(dots_group_counts "${g}" 2>/dev/null || echo $'0\t0')"
		req="${counts%%$'\t'*}"
		opt="${counts#*$'\t'}"
		if dots_group_is_active "${g}"; then
			active=yes
			mark="*"
		else
			active=no
			mark=" "
		fi
		printf '%s %-12s %-8s %8s %8s  %s\n' "${mark}" "${g}" "${active}" "${req}" "${opt}" "${desc}"
	done < <(dots_known_package_groups)
	printf '\n'
	printf 'Active = selected by current profile / DOTS_PACKAGE_GROUPS / resolved set.\n'
	printf 'Detail: ./dots packages group ID\n'
	printf 'Plan:   ./dots packages plan [--profile NAME|PATH]\n'
}

# Detail one group: brewfile, membership, platform map, install states (fast).
dots_packages_group_show() {
	local id="$1"
	if [[ -z ${id} ]]; then
		echo "Usage: ./dots packages group ID" >&2
		return 1
	fi
	if ! dots_group_is_known "${id}"; then
		echo "Error: unknown package group '${id}'" >&2
		echo "Supported groups: $(dots_known_package_groups | tr '\n' ' ')" >&2
		return 1
	fi

	local desc bf rel selected
	desc="$(dots_group_description "${id}" 2>/dev/null || true)"
	rel="$(dots_group_brewfile "${id}")"
	bf="${DIR}/${rel}"
	if dots_group_is_active "${id}"; then
		selected=yes
	else
		selected=no
	fi

	echo "Group: ${id}"
	echo "Description: ${desc:-"(none)"}"
	echo "Selected: ${selected}"
	echo "Owner: ${rel}"
	if [[ -f ${bf} ]]; then
		echo "Brewfile: present"
	else
		echo "Brewfile: MISSING (${bf})"
	fi
	echo ""

	# Ensure ownership/classify context without outdated queries
	if declare -F dots_pkg_ownership_reset >/dev/null 2>&1; then
		dots_pkg_ownership_reset
	fi
	if declare -F dots_desired_packages_resolve >/dev/null 2>&1; then
		dots_desired_packages_resolve
	fi
	if declare -F dots_pkg_classify_resolved >/dev/null 2>&1; then
		# fast=1 → skip brew outdated
		dots_pkg_classify_resolved 1 2>/dev/null || true
	fi

	local platform_hint="brew"
	if [[ -n ${DOTS_FORCE_PKG_MGR:-} ]]; then
		platform_hint="${DOTS_FORCE_PKG_MGR}"
	elif [[ "$(uname -s)" == "Linux" ]] && ! command -v brew >/dev/null 2>&1; then
		platform_hint="$(dots_detect_linux_pkg_mgr)"
	fi
	echo "Platform map: ${platform_hint}"
	printf '%-16s %-10s %-18s %s\n' "PACKAGE" "CLASS" "PLATFORM NAME" "STATE"
	local tool class native state
	for class in required optional; do
		while IFS= read -r tool; do
			[[ -z ${tool} ]] && continue
			native="$(dots_group_tool_platform_name "${tool}" 2>/dev/null || echo MISSING)"
			case "${native}" in
			SKIP)
				native="unavailable"
				state=unsupported
				;;
			MISSING)
				native="(unmapped)"
				state=unmapped
				;;
			brew:*)
				native="${native#brew:}"
				state="$(_dots_pkg_plan_state_for "${tool}")"
				;;
			*)
				state="$(_dots_pkg_plan_state_for "${tool}")"
				;;
			esac
			printf '%-16s %-10s %-18s %s\n' "${tool}" "${class}" "${native}" "${state}"
		done < <(dots_group_package_ids "${id}" "${class}" 2>/dev/null || true)
	done
}

# Best-effort state for plan/group detail without outdated queries.
_dots_pkg_plan_state_for() {
	local name="$1"
	if ! declare -F dots_pkg_in_list >/dev/null 2>&1; then
		printf 'unknown\n'
		return 0
	fi
	DOTS_DESIRED_FORMULAE=("${DOTS_DESIRED_FORMULAE[@]+"${DOTS_DESIRED_FORMULAE[@]}"}")
	DOTS_DESIRED_CASKS=("${DOTS_DESIRED_CASKS[@]+"${DOTS_DESIRED_CASKS[@]}"}")
	DOTS_PKG_MISSING_LINES=("${DOTS_PKG_MISSING_LINES[@]+"${DOTS_PKG_MISSING_LINES[@]}"}")
	DOTS_PKG_EXTERNAL_LINES=("${DOTS_PKG_EXTERNAL_LINES[@]+"${DOTS_PKG_EXTERNAL_LINES[@]}"}")
	DOTS_PKG_INACTIVE_FORMULAE=("${DOTS_PKG_INACTIVE_FORMULAE[@]+"${DOTS_PKG_INACTIVE_FORMULAE[@]}"}")
	DOTS_PKG_INACTIVE_CASKS=("${DOTS_PKG_INACTIVE_CASKS[@]+"${DOTS_PKG_INACTIVE_CASKS[@]}"}")

	local line
	for line in "${DOTS_PKG_EXTERNAL_LINES[@]+"${DOTS_PKG_EXTERNAL_LINES[@]}"}"; do
		[[ ${line} == "${name}"* || ${line} == *" ${name}"* || ${line} == "${name}" ]] && {
			printf 'external\n'
			return 0
		}
	done
	if dots_pkg_in_list "${name}" "${DOTS_DESIRED_FORMULAE[@]+"${DOTS_DESIRED_FORMULAE[@]}"}" ||
		dots_pkg_in_list "${name}" "${DOTS_DESIRED_CASKS[@]+"${DOTS_DESIRED_CASKS[@]}"}"; then
		for line in "${DOTS_PKG_MISSING_LINES[@]+"${DOTS_PKG_MISSING_LINES[@]}"}"; do
			[[ ${line} == "${name}" || ${line} == "${name} "* ]] && {
				printf 'missing\n'
				return 0
			}
		done
		printf 'managed\n'
		return 0
	fi
	if dots_pkg_in_list "${name}" "${DOTS_PKG_INACTIVE_FORMULAE[@]+"${DOTS_PKG_INACTIVE_FORMULAE[@]}"}" ||
		dots_pkg_in_list "${name}" "${DOTS_PKG_INACTIVE_CASKS[@]+"${DOTS_PKG_INACTIVE_CASKS[@]}"}"; then
		printf 'inactive\n'
		return 0
	fi
	# Not in desired set and not classified inactive — treat as not selected
	if declare -F dots_pkg_has_known_owner >/dev/null 2>&1 && dots_pkg_has_known_owner "${name}"; then
		printf 'inactive\n'
		return 0
	fi
	printf 'not-selected\n'
}

# Resolve --profile for plan; populate PROFILE_* / DOTS_RESOLVED_GROUPS / WITH.
dots_packages_plan_load_profile() {
	local profile_arg="${1:-}"
	local path=""
	PROFILE_NAME=""
	PROFILE_PACKAGES=()
	PROFILE_WITH=()
	DOTS_WITH_COMPONENTS=()
	DOTS_RESOLVED_GROUPS=()

	if [[ -n ${profile_arg} ]]; then
		if declare -F dots_resolve_profile_path >/dev/null 2>&1; then
			path="$(dots_resolve_profile_path "${profile_arg}")" || return 1
		elif [[ -f ${profile_arg} ]]; then
			path="${profile_arg}"
		else
			path="${DIR}/configs/bootstrap/profiles/${profile_arg}.toml"
		fi
		if declare -F dots_load_profile_file >/dev/null 2>&1; then
			dots_load_profile_file "${path}" >/dev/null || return 1
			if declare -F dots_compute_effective_with >/dev/null 2>&1; then
				dots_compute_effective_with >/dev/null 2>&1 || true
			fi
		else
			echo "Error: profile helpers unavailable" >&2
			return 1
		fi
		DOTS_RESOLVED_GROUPS=("${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}")
		EFFECTIVE_WITH=("${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}")
		if [[ ${#EFFECTIVE_WITH[@]} -gt 0 ]]; then
			DOTS_WITH_COMPONENTS=("${EFFECTIVE_WITH[@]}")
		else
			DOTS_WITH_COMPONENTS=("${PROFILE_WITH[@]+"${PROFILE_WITH[@]}"}")
		fi
		PROFILE_NAME="${PROFILE_NAME:-${profile_arg}}"
	else
		# Active profile / runtime
		if declare -F dots_state_load_active >/dev/null 2>&1 && dots_state_load_active 2>/dev/null; then
			PROFILE_NAME="${DOTS_ACTIVE_PROFILE:-${DOTS_PROFILE:-active}}"
			if [[ -n ${DOTS_PACKAGE_GROUPS:-} ]]; then
				# shellcheck disable=SC2206
				DOTS_RESOLVED_GROUPS=(${DOTS_PACKAGE_GROUPS})
			fi
			if [[ -n ${DOTS_ACTIVE_COMPONENTS:-} ]]; then
				# shellcheck disable=SC2206
				DOTS_WITH_COMPONENTS=(${DOTS_ACTIVE_COMPONENTS})
			fi
			if [[ -n ${DOTS_ACTIVE_PROFILE_FILE:-} && -f ${DOTS_ACTIVE_PROFILE_FILE} ]] &&
				declare -F dots_load_profile_file >/dev/null 2>&1; then
				dots_load_profile_file "${DOTS_ACTIVE_PROFILE_FILE}" >/dev/null || true
				DOTS_RESOLVED_GROUPS=("${PROFILE_PACKAGES[@]+"${PROFILE_PACKAGES[@]}"}")
				if declare -F dots_compute_effective_with >/dev/null 2>&1; then
					dots_compute_effective_with >/dev/null 2>&1 || true
					EFFECTIVE_WITH=("${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}")
					[[ ${#EFFECTIVE_WITH[@]} -gt 0 ]] && DOTS_WITH_COMPONENTS=("${EFFECTIVE_WITH[@]}")
				fi
			fi
		fi
		if [[ ${#DOTS_RESOLVED_GROUPS[@]} -eq 0 ]]; then
			dots_resolve_package_groups || true
		fi
		PROFILE_NAME="${PROFILE_NAME:-"(none)"}"
	fi
	dots_validate_package_groups "${DOTS_RESOLVED_GROUPS[@]+"${DOTS_RESOLVED_GROUPS[@]}"}" || return 1
}

# Read-only package plan for a profile (no mutation, no outdated queries).
dots_packages_plan() {
	local profile_arg=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--profile)
			shift
			profile_arg="${1:-}"
			shift || true
			;;
		-h | --help)
			echo "Usage: ./dots packages plan [--profile NAME|PATH]"
			echo "Read-only resolved package plan (no install / no auth / no outdated queries)."
			return 0
			;;
		*)
			echo "Unknown plan option: $1" >&2
			return 1
			;;
		esac
	done

	# Ensure profiles/components helpers when invoked from unit tests
	if ! declare -F dots_load_profile_file >/dev/null 2>&1 && [[ -f ${DIR}/helpers/profiles.sh ]]; then
		# shellcheck disable=SC1091
		source "${DIR}/helpers/profiles.sh" 2>/dev/null || true
	fi
	if ! declare -F dots_component_ids >/dev/null 2>&1 && [[ -f ${DIR}/helpers/components.sh ]]; then
		# shellcheck disable=SC1091
		source "${DIR}/helpers/components.sh" 2>/dev/null || true
	fi

	dots_packages_plan_load_profile "${profile_arg}" || return 1

	local os arch platform
	os="$(uname -s)"
	arch="$(uname -m)"
	case "${os}" in
	Darwin) platform="darwin/${arch}" ;;
	Linux) platform="linux/${arch}" ;;
	*) platform="${os}/${arch}" ;;
	esac

	echo "Profile: ${PROFILE_NAME}"
	echo "Platform: ${platform}"
	echo ""
	echo "Package groups:"
	if [[ ${#DOTS_RESOLVED_GROUPS[@]} -eq 0 ]]; then
		echo "  (none)"
	else
		local g
		for g in "${DOTS_RESOLVED_GROUPS[@]}"; do
			printf '  %s\n' "${g}"
		done
	fi
	echo ""
	echo "Optional components:"
	DOTS_WITH_COMPONENTS=("${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}")
	if [[ ${#DOTS_WITH_COMPONENTS[@]} -eq 0 ]]; then
		echo "  (none)"
	else
		local c
		for c in "${DOTS_WITH_COMPONENTS[@]}"; do
			printf '  %s\n' "${c}"
		done
	fi
	echo "  (informational — reading a plan is not AI consent)"
	echo ""

	if declare -F dots_pkg_ownership_reset >/dev/null 2>&1; then
		dots_pkg_ownership_reset
	fi
	if declare -F dots_desired_packages_resolve >/dev/null 2>&1; then
		dots_desired_packages_resolve
	fi
	if declare -F dots_pkg_classify_resolved >/dev/null 2>&1; then
		dots_pkg_classify_resolved 1 2>/dev/null || true
	fi

	DOTS_DESIRED_FORMULAE=("${DOTS_DESIRED_FORMULAE[@]+"${DOTS_DESIRED_FORMULAE[@]}"}")
	DOTS_DESIRED_CASKS=("${DOTS_DESIRED_CASKS[@]+"${DOTS_DESIRED_CASKS[@]}"}")
	local managed="${DOTS_PKG_COUNT_MANAGED:-0}"
	local missing="${DOTS_PKG_COUNT_MISSING:-0}"
	local external="${DOTS_PKG_COUNT_EXTERNAL:-0}"
	local inactive="${DOTS_PKG_COUNT_INACTIVE:-0}"
	local desired=$((${#DOTS_DESIRED_FORMULAE[@]} + ${#DOTS_DESIRED_CASKS[@]}))

	# Unsupported count: optional/required ids in selected groups with empty native map
	local unsupported=0 tool native
	if [[ "$(uname -s)" == "Linux" ]] && ! command -v brew >/dev/null 2>&1; then
		while IFS= read -r tool; do
			[[ -z ${tool} ]] && continue
			native="$(dots_group_tool_platform_name "${tool}" 2>/dev/null || echo MISSING)"
			[[ ${native} == SKIP || ${native} == MISSING ]] && unsupported=$((unsupported + 1))
		done < <(dots_tools_for_groups all 2>/dev/null || true)
	fi

	echo "Summary:"
	echo "  Desired packages: ${desired}"
	echo "  Managed/present:  ${managed}"
	echo "  Would install:    ${missing}"
	echo "  External:         ${external}"
	echo "  Inactive (known): ${inactive}"
	echo "  Unsupported map:  ${unsupported}"
	echo ""
	echo "Resolved packages (desired set):"
	local name state
	for name in "${DOTS_DESIRED_FORMULAE[@]+"${DOTS_DESIRED_FORMULAE[@]}"}"; do
		state="$(_dots_pkg_plan_state_for "${name}")"
		printf '  %-24s %s\n' "${name}" "${state}"
	done
	for name in "${DOTS_DESIRED_CASKS[@]+"${DOTS_DESIRED_CASKS[@]}"}"; do
		state="$(_dots_pkg_plan_state_for "${name}")"
		printf '  %-24s %s (cask)\n' "${name}" "${state}"
	done
	echo ""
	echo "Read-only plan — no install, no auth, no brew outdated queries."
	echo "Groups vs components: profile packages= vs with=/--with (see ./dots packages groups)."
}
