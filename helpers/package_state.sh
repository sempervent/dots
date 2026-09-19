#!/usr/bin/env bash
# shellcheck shell=bash
# helpers/package_state.sh — DOTS package ownership / drift (Homebrew-focused)
#
# States:
#   MANAGED    declared by resolved desired set + package-manager owned
#   MISSING    declared but absent
#   OUTDATED   declared, managed, update available
#   EXTERNAL   declared (usually cask); artifact present but brew does not own it
#   INACTIVE   installed; known DOTS owner(s) exist but none are active
#   UNDECLARED brew leaves / casks installed; no DOTS group/component owner
#
# known ≠ selected ≠ installed:
#   known     = appears in brew/groups/*.Brewfile or a component brewfile=
#   selected  = active package group or active --with / LAST_WITH_INFO component
#   installed = present on the machine
#
# Desired set = union of active package-group Brewfiles + selected optional
# component Brewfiles. Inactive optional Brewfiles are ignored for MANAGED.
# Ownership catalog (for INACTIVE vs UNDECLARED) scans those same sources —
# never the aggregate brew/Brewfile.
#
# Never runs: brew bundle cleanup / uninstall of undeclared software.
#
# Requires: DIR
# Optional: DOTS_RESOLVED_GROUPS[], DOTS_WITH_COMPONENTS[], DRY_RUN
# Test hooks: DOTS_BREW_BIN, DOTS_PKG_MOCK_* (see tests)

# shellcheck source=packages.sh
[[ -n ${DIR:-} && -f ${DIR}/helpers/packages.sh ]] && source "${DIR}/helpers/packages.sh" 2>/dev/null || true
# shellcheck source=cask_apps.sh
[[ -n ${DIR:-} && -f ${DIR}/helpers/cask_apps.sh ]] && source "${DIR}/helpers/cask_apps.sh" 2>/dev/null || true
# Brewfile lookup lives in helpers/components.sh (components.toml brewfile=).
# Ensure it exists when package_state is sourced without components.sh (unit tests).
if ! declare -F dots_component_brewfile >/dev/null 2>&1; then
	if [[ -n ${DIR:-} && -f ${DIR}/helpers/components.sh ]]; then
		# shellcheck source=components.sh
		# shellcheck disable=SC1091
		source "${DIR}/helpers/components.sh" 2>/dev/null || true
	fi
fi
# Fallback identical to components.sh if still missing (isolated test envs).
if ! declare -F dots_component_brewfile >/dev/null 2>&1; then
	dots_component_brewfile() {
		local id="$1" registry="${DIR}/configs/components.toml"
		[[ -n ${id} && -f ${registry} ]] || return 1
		if ! declare -F dots_toml_query >/dev/null 2>&1; then
			# shellcheck disable=SC1091
			source "${DIR}/helpers/toml.sh" || return 1
		fi
		WANT="${id}" dots_toml_query "${registry}" <<'PY'
import os
want = os.environ.get("WANT", "").strip()
for c in data.get("components") or []:
    if (c.get("id") or "").strip() != want:
        continue
    bf = (c.get("brewfile") or "").strip()
    if bf:
        print(bf)
        raise SystemExit(0)
    raise SystemExit(1)
raise SystemExit(1)
PY
	}
fi

# Parse brew/cask tokens from a Brewfile. Args: file  type=brew|cask|all
dots_brewfile_tokens() {
	local file="$1" want="${2:-all}"
	[[ -f ${file} ]] || return 0
	local line kind name
	while IFS= read -r line || [[ -n ${line} ]]; do
		line="${line%%#*}"
		line="$(printf '%s' "${line}" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
		[[ -z ${line} ]] && continue
		case "${line}" in
		brew\ \"*\")
			kind=brew
			name="${line#brew \"}"
			name="${name%\"*}"
			;;
		cask\ \"*\")
			kind=cask
			name="${line#cask \"}"
			name="${name%\"*}"
			;;
		*) continue ;;
		esac
		[[ -z ${name} ]] && continue
		# Normalize tap/formula to short name for comparison where useful
		case "${want}" in
		all) printf '%s\t%s\n' "${kind}" "${name}" ;;
		brew | formula | formulae)
			[[ ${kind} == brew ]] && printf '%s\n' "${name}"
			;;
		cask | casks)
			[[ ${kind} == cask ]] && printf '%s\n' "${name}"
			;;
		esac
	done <"${file}"
}

# --- Ownership catalog (group:<name> / component:<id>) ---------------------
# Index lines: shortname<TAB>owner  (owner = group:X or component:Y)
# Built from brew/groups/*.Brewfile + components.toml brewfile= only.

dots_pkg_ownership_reset() {
	DOTS_PKG_OWNERSHIP_INDEX=""
	DOTS_PKG_OWNERSHIP_BUILT=0
}

# Append ownership rows from one Brewfile. Args: file  owner_tag
_dots_pkg_ownership_ingest_file() {
	local file="$1" owner="$2"
	local kind token short
	[[ -f ${file} ]] || return 0
	while IFS=$'\t' read -r kind token; do
		[[ -z ${token} ]] && continue
		short="$(dots_pkg_short "${token}")"
		DOTS_PKG_OWNERSHIP_INDEX="${DOTS_PKG_OWNERSHIP_INDEX}${short}"$'\t'"${owner}"$'\n'
	done < <(dots_brewfile_tokens "${file}" all)
}

# Build global ownership catalog (idempotent per process unless reset).
dots_pkg_build_ownership_catalog() {
	if [[ ${DOTS_PKG_OWNERSHIP_BUILT:-0} -eq 1 ]]; then
		return 0
	fi
	DOTS_PKG_OWNERSHIP_INDEX=""
	local f base id rel
	# Package groups
	if [[ -d ${DIR}/brew/groups ]]; then
		for f in "${DIR}/brew/groups/"*.Brewfile; do
			[[ -f ${f} ]] || continue
			base="$(basename "${f}" .Brewfile)"
			_dots_pkg_ownership_ingest_file "${f}" "group:${base}"
		done
	fi
	# Optional components with brewfile= in registry (not aggregate Brewfile)
	if declare -F dots_component_ids >/dev/null 2>&1; then
		while IFS= read -r id; do
			[[ -z ${id} ]] && continue
			rel=""
			if rel="$(dots_component_brewfile "${id}" 2>/dev/null)"; then
				[[ -n ${rel} && -f ${DIR}/${rel} ]] || continue
				_dots_pkg_ownership_ingest_file "${DIR}/${rel}" "component:${id}"
			fi
		done < <(dots_component_ids)
	elif [[ -f ${DIR}/configs/components.toml ]]; then
		# Fallback without components.sh: parse brewfile= via toml helper
		if ! declare -F dots_toml_query >/dev/null 2>&1 && [[ -f ${DIR}/helpers/toml.sh ]]; then
			# shellcheck disable=SC1091
			source "${DIR}/helpers/toml.sh" 2>/dev/null || true
		fi
		if declare -F dots_toml_query >/dev/null 2>&1; then
			while IFS=$'\t' read -r id rel; do
				[[ -z ${id} || -z ${rel} ]] && continue
				[[ -f ${DIR}/${rel} ]] || continue
				_dots_pkg_ownership_ingest_file "${DIR}/${rel}" "component:${id}"
			done < <(
				dots_toml_query "${DIR}/configs/components.toml" <<'PY'
for c in data.get("components") or []:
    cid = (c.get("id") or "").strip()
    bf = (c.get("brewfile") or "").strip()
    if cid and bf:
        print("%s\t%s" % (cid, bf))
PY
			)
		fi
	fi
	DOTS_PKG_OWNERSHIP_BUILT=1
}

# Print known owners for a package (group:X / component:Y), unique, sorted.
dots_pkg_known_owners() {
	local want="$1" short line name owner
	short="$(dots_pkg_short "${want}")"
	dots_pkg_build_ownership_catalog
	local -a out=()
	local seen=$'\n' o
	while IFS=$'\t' read -r name owner; do
		[[ -z ${name} || -z ${owner} ]] && continue
		[[ ${name} == "${short}" || ${name} == "${want}" ]] || continue
		case "${seen}" in
		*$'\n'"${owner}"$'\n'*) continue ;;
		esac
		seen="${seen}${owner}"$'\n'
		out+=("${owner}")
	done <<<"${DOTS_PKG_OWNERSHIP_INDEX}"
	if [[ ${#out[@]} -eq 0 ]]; then
		return 1
	fi
	printf '%s\n' "${out[@]}" | LC_ALL=C sort -u
	return 0
}

# True if package has at least one known DOTS owner.
dots_pkg_has_known_owner() {
	dots_pkg_known_owners "$1" >/dev/null 2>&1
}

# Print active owners (intersection of known owners with resolved groups /
# selected components). Any active owner ⇒ package is in desired set / MANAGED.
dots_pkg_active_owners() {
	local want="$1" owner kind id
	local -a known=()
	local line
	while IFS= read -r line; do
		[[ -n ${line} ]] && known+=("${line}")
	done < <(dots_pkg_known_owners "${want}" 2>/dev/null || true)
	[[ ${#known[@]} -eq 0 ]] && return 1

	DOTS_RESOLVED_GROUPS=("${DOTS_RESOLVED_GROUPS[@]+"${DOTS_RESOLVED_GROUPS[@]}"}")
	DOTS_WITH_COMPONENTS=("${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}")

	local -a active=()
	local g c match
	for owner in "${known[@]}"; do
		kind="${owner%%:*}"
		id="${owner#*:}"
		match=0
		case "${kind}" in
		group)
			for g in "${DOTS_RESOLVED_GROUPS[@]+"${DOTS_RESOLVED_GROUPS[@]}"}"; do
				[[ ${g} == "${id}" ]] && match=1 && break
			done
			;;
		component)
			for c in "${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}"; do
				[[ ${c} == "${id}" ]] && match=1 && break
			done
			;;
		esac
		[[ ${match} -eq 1 ]] && active+=("${owner}")
	done
	if [[ ${#active[@]} -eq 0 ]]; then
		return 1
	fi
	printf '%s\n' "${active[@]}"
	return 0
}

# Suggest how to activate a package that has known component/group owners.
dots_pkg_activate_hint() {
	local want="$1"
	local -a comps=() groups=()
	local line kind id
	while IFS= read -r line; do
		[[ -z ${line} ]] && continue
		kind="${line%%:*}"
		id="${line#*:}"
		case "${kind}" in
		component) comps+=("${id}") ;;
		group) groups+=("${id}") ;;
		esac
	done < <(dots_pkg_known_owners "${want}" 2>/dev/null || true)
	if [[ ${#comps[@]} -gt 0 ]]; then
		local uniq="" c
		for c in "${comps[@]}"; do
			case " ${uniq} " in
			*" ${c} "*) ;;
			*) uniq="${uniq}${uniq:+ }${c}" ;;
			esac
		done
		echo "./dots setup --with ${uniq// /,}"
		echo "(or add with = […] to your profile; see https://sempervent.github.io/dots/using/components/)"
		return 0
	fi
	if [[ ${#groups[@]} -gt 0 ]]; then
		echo "Enable package group(s) in your profile: ${groups[*]}"
		echo "(configs/packages/groups.toml + profile packages = […])"
		return 0
	fi
	echo "./dots packages adopt ${want}   # no DOTS owner; suggest Brewfile declaration"
	return 0
}

# Populate DOTS_DESIRED_FORMULAE[] and DOTS_DESIRED_CASKS[] (unique).
# Uses DOTS_RESOLVED_GROUPS (or resolves defaults) + DOTS_WITH_COMPONENTS.
dots_desired_packages_resolve() {
	DOTS_DESIRED_FORMULAE=()
	DOTS_DESIRED_CASKS=()
	DOTS_RESOLVED_GROUPS=("${DOTS_RESOLVED_GROUPS[@]+"${DOTS_RESOLVED_GROUPS[@]}"}")
	DOTS_WITH_COMPONENTS=("${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}")
	local -a files=()
	local g f c token seen_f seen_c

	if [[ ${#DOTS_RESOLVED_GROUPS[@]} -eq 0 ]]; then
		if declare -F dots_resolve_package_groups >/dev/null 2>&1; then
			dots_resolve_package_groups || true
		fi
	fi

	for g in "${DOTS_RESOLVED_GROUPS[@]+"${DOTS_RESOLVED_GROUPS[@]}"}"; do
		[[ -z ${g} ]] && continue
		f="${DIR}/brew/groups/${g}.Brewfile"
		[[ -f ${f} ]] && files+=("${f}")
	done

	for c in "${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}"; do
		[[ -z ${c} ]] && continue
		if f="$(dots_component_brewfile "${c}" 2>/dev/null)"; then
			[[ -f ${DIR}/${f} ]] && files+=("${DIR}/${f}")
		fi
	done

	# Deduplicate paths
	local -a uniq_files=()
	local p u skip
	for p in "${files[@]+"${files[@]}"}"; do
		skip=0
		for u in "${uniq_files[@]+"${uniq_files[@]}"}"; do
			[[ ${u} == "${p}" ]] && skip=1 && break
		done
		[[ ${skip} -eq 0 ]] && uniq_files+=("${p}")
	done

	seen_f=$'\n'
	seen_c=$'\n'
	for p in "${uniq_files[@]+"${uniq_files[@]}"}"; do
		while IFS=$'\t' read -r kind token; do
			[[ -z ${token} ]] && continue
			case "${kind}" in
			brew)
				case "${seen_f}" in
				*$'\n'"${token}"$'\n'*) ;;
				*)
					DOTS_DESIRED_FORMULAE+=("${token}")
					seen_f="${seen_f}${token}"$'\n'
					;;
				esac
				;;
			cask)
				case "${seen_c}" in
				*$'\n'"${token}"$'\n'*) ;;
				*)
					DOTS_DESIRED_CASKS+=("${token}")
					seen_c="${seen_c}${token}"$'\n'
					;;
				esac
				;;
			esac
		done < <(dots_brewfile_tokens "${p}" all)
	done
}

dots_pkg_brew() {
	if declare -F dots_brew >/dev/null 2>&1; then
		dots_brew "$@"
	else
		command "${DOTS_BREW_BIN:-brew}" "$@"
	fi
}

# Short name for comparison (strip tap prefix)
dots_pkg_short() {
	local n="$1"
	printf '%s\n' "${n##*/}"
}

dots_pkg_in_list() {
	local want="$1"
	shift
	local x want_s xs
	want_s="$(dots_pkg_short "${want}")"
	for x in "$@"; do
		xs="$(dots_pkg_short "${x}")"
		if [[ ${x} == "${want}" || ${x} == "${want_s}" || ${xs} == "${want_s}" ]]; then
			return 0
		fi
	done
	return 1
}

# Installed top-level formulae (leaves). Mock: DOTS_PKG_MOCK_LEAVES newline list
dots_pkg_installed_leaves() {
	if [[ -n ${DOTS_PKG_MOCK_LEAVES+x} ]]; then
		printf '%s\n' "${DOTS_PKG_MOCK_LEAVES}"
		return 0
	fi
	dots_pkg_brew leaves 2>/dev/null || true
}

# All installed formulae (for MANAGED check of desired non-leaves)
dots_pkg_installed_formulae() {
	if [[ -n ${DOTS_PKG_MOCK_FORMULAE+x} ]]; then
		printf '%s\n' "${DOTS_PKG_MOCK_FORMULAE}"
		return 0
	fi
	dots_pkg_brew list --formula 2>/dev/null || true
}

dots_pkg_installed_casks() {
	if [[ -n ${DOTS_PKG_MOCK_CASKS+x} ]]; then
		printf '%s\n' "${DOTS_PKG_MOCK_CASKS}"
		return 0
	fi
	dots_pkg_brew list --cask 2>/dev/null || true
}

dots_pkg_outdated_formulae() {
	if [[ -n ${DOTS_PKG_MOCK_OUTDATED_FORMULAE+x} ]]; then
		printf '%s\n' "${DOTS_PKG_MOCK_OUTDATED_FORMULAE}"
		return 0
	fi
	dots_pkg_brew outdated --formula --quiet 2>/dev/null || true
}

dots_pkg_outdated_casks() {
	if [[ -n ${DOTS_PKG_MOCK_OUTDATED_CASKS+x} ]]; then
		printf '%s\n' "${DOTS_PKG_MOCK_OUTDATED_CASKS}"
		return 0
	fi
	dots_pkg_brew outdated --cask --quiet 2>/dev/null || true
}

# Classify installed inventory against already-populated
# DOTS_DESIRED_FORMULAE[] / DOTS_DESIRED_CASKS[]. Sets count globals.
# Arg1: fast=1 skip outdated queries (for ./dots status)
dots_pkg_classify_resolved() {
	local fast="${1:-0}"
	DOTS_PKG_COUNT_MANAGED=0
	DOTS_PKG_COUNT_MISSING=0
	DOTS_PKG_COUNT_OUTDATED=0
	DOTS_PKG_COUNT_EXTERNAL=0
	DOTS_PKG_COUNT_INACTIVE=0
	DOTS_PKG_COUNT_UNDECLARED=0
	DOTS_PKG_EXTERNAL_LINES=()
	DOTS_PKG_INACTIVE_FORMULAE=()
	DOTS_PKG_INACTIVE_CASKS=()
	DOTS_PKG_UNDECLARED_FORMULAE=()
	DOTS_PKG_UNDECLARED_CASKS=()
	DOTS_PKG_MISSING_LINES=()
	DOTS_PKG_OUTDATED_LINES=()

	dots_pkg_build_ownership_catalog

	local -a leaves=() formulae=() casks=() out_f=() out_c=()
	local line f app

	while IFS= read -r line; do
		[[ -n ${line} ]] && leaves+=("${line}")
	done < <(dots_pkg_installed_leaves)
	while IFS= read -r line; do
		[[ -n ${line} ]] && formulae+=("${line}")
	done < <(dots_pkg_installed_formulae)
	while IFS= read -r line; do
		[[ -n ${line} ]] && casks+=("${line}")
	done < <(dots_pkg_installed_casks)
	if [[ ${fast} -eq 0 ]]; then
		while IFS= read -r line; do
			[[ -n ${line} ]] && out_f+=("${line}")
		done < <(dots_pkg_outdated_formulae)
		while IFS= read -r line; do
			[[ -n ${line} ]] && out_c+=("${line}")
		done < <(dots_pkg_outdated_casks)
	fi

	for f in "${DOTS_DESIRED_FORMULAE[@]+"${DOTS_DESIRED_FORMULAE[@]}"}"; do
		if dots_pkg_in_list "${f}" "${formulae[@]+"${formulae[@]}"}"; then
			DOTS_PKG_COUNT_MANAGED=$((DOTS_PKG_COUNT_MANAGED + 1))
			if dots_pkg_in_list "${f}" "${out_f[@]+"${out_f[@]}"}"; then
				DOTS_PKG_COUNT_OUTDATED=$((DOTS_PKG_COUNT_OUTDATED + 1))
				DOTS_PKG_OUTDATED_LINES+=("formula ${f}")
			fi
		else
			DOTS_PKG_COUNT_MISSING=$((DOTS_PKG_COUNT_MISSING + 1))
			DOTS_PKG_MISSING_LINES+=("formula ${f}")
		fi
	done

	for f in "${DOTS_DESIRED_CASKS[@]+"${DOTS_DESIRED_CASKS[@]}"}"; do
		if dots_pkg_in_list "${f}" "${casks[@]+"${casks[@]}"}"; then
			DOTS_PKG_COUNT_MANAGED=$((DOTS_PKG_COUNT_MANAGED + 1))
			if dots_pkg_in_list "${f}" "${out_c[@]+"${out_c[@]}"}"; then
				DOTS_PKG_COUNT_OUTDATED=$((DOTS_PKG_COUNT_OUTDATED + 1))
				DOTS_PKG_OUTDATED_LINES+=("cask ${f}")
			fi
		else
			app=""
			if declare -F dots_cask_discover_app >/dev/null 2>&1; then
				app="$(dots_cask_discover_app "${f}" 2>/dev/null || true)"
			fi
			if [[ -n ${app} ]] && { [[ -d ${app} ]] || [[ -e ${app} ]]; }; then
				DOTS_PKG_COUNT_EXTERNAL=$((DOTS_PKG_COUNT_EXTERNAL + 1))
				DOTS_PKG_EXTERNAL_LINES+=("${f} ${app}")
			elif [[ -n ${DOTS_PKG_MOCK_EXTERNAL_APPS:-} ]] && printf '%s\n' "${DOTS_PKG_MOCK_EXTERNAL_APPS}" | grep -qx "${f}"; then
				DOTS_PKG_COUNT_EXTERNAL=$((DOTS_PKG_COUNT_EXTERNAL + 1))
				DOTS_PKG_EXTERNAL_LINES+=("${f} (external)")
			else
				DOTS_PKG_COUNT_MISSING=$((DOTS_PKG_COUNT_MISSING + 1))
				DOTS_PKG_MISSING_LINES+=("cask ${f}")
			fi
		fi
	done

	# Leaves/casks not in desired set: INACTIVE (known owner) vs UNDECLARED
	for f in "${leaves[@]+"${leaves[@]}"}"; do
		if ! dots_pkg_in_list "${f}" "${DOTS_DESIRED_FORMULAE[@]+"${DOTS_DESIRED_FORMULAE[@]}"}"; then
			if dots_pkg_has_known_owner "${f}"; then
				DOTS_PKG_COUNT_INACTIVE=$((DOTS_PKG_COUNT_INACTIVE + 1))
				DOTS_PKG_INACTIVE_FORMULAE+=("${f}")
			else
				DOTS_PKG_COUNT_UNDECLARED=$((DOTS_PKG_COUNT_UNDECLARED + 1))
				DOTS_PKG_UNDECLARED_FORMULAE+=("${f}")
			fi
		fi
	done
	for f in "${casks[@]+"${casks[@]}"}"; do
		if ! dots_pkg_in_list "${f}" "${DOTS_DESIRED_CASKS[@]+"${DOTS_DESIRED_CASKS[@]}"}"; then
			if dots_pkg_has_known_owner "${f}"; then
				DOTS_PKG_COUNT_INACTIVE=$((DOTS_PKG_COUNT_INACTIVE + 1))
				DOTS_PKG_INACTIVE_CASKS+=("${f}")
			else
				DOTS_PKG_COUNT_UNDECLARED=$((DOTS_PKG_COUNT_UNDECLARED + 1))
				DOTS_PKG_UNDECLARED_CASKS+=("${f}")
			fi
		fi
	done
}

# Initialize print arrays if classify never ran (set -u safety)
dots_pkg_status_print() {
	DOTS_PKG_EXTERNAL_LINES=("${DOTS_PKG_EXTERNAL_LINES[@]+"${DOTS_PKG_EXTERNAL_LINES[@]}"}")
	DOTS_PKG_INACTIVE_FORMULAE=("${DOTS_PKG_INACTIVE_FORMULAE[@]+"${DOTS_PKG_INACTIVE_FORMULAE[@]}"}")
	DOTS_PKG_INACTIVE_CASKS=("${DOTS_PKG_INACTIVE_CASKS[@]+"${DOTS_PKG_INACTIVE_CASKS[@]}"}")
	DOTS_PKG_UNDECLARED_FORMULAE=("${DOTS_PKG_UNDECLARED_FORMULAE[@]+"${DOTS_PKG_UNDECLARED_FORMULAE[@]}"}")
	DOTS_PKG_UNDECLARED_CASKS=("${DOTS_PKG_UNDECLARED_CASKS[@]+"${DOTS_PKG_UNDECLARED_CASKS[@]}"}")
	DOTS_PKG_MISSING_LINES=("${DOTS_PKG_MISSING_LINES[@]+"${DOTS_PKG_MISSING_LINES[@]}"}")
	DOTS_PKG_OUTDATED_LINES=("${DOTS_PKG_OUTDATED_LINES[@]+"${DOTS_PKG_OUTDATED_LINES[@]}"}")

	echo "Packages:"
	echo "  managed:      ${DOTS_PKG_COUNT_MANAGED:-0}"
	echo "  missing:      ${DOTS_PKG_COUNT_MISSING:-0}"
	echo "  outdated:     ${DOTS_PKG_COUNT_OUTDATED:-0}"
	echo "  external:     ${DOTS_PKG_COUNT_EXTERNAL:-0}"
	echo "  inactive:     ${DOTS_PKG_COUNT_INACTIVE:-0}"
	echo "  undeclared:   ${DOTS_PKG_COUNT_UNDECLARED:-0}"

	DOTS_RESOLVED_GROUPS=("${DOTS_RESOLVED_GROUPS[@]+"${DOTS_RESOLVED_GROUPS[@]}"}")
	DOTS_WITH_COMPONENTS=("${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}")
	local profile_hint="${DOTS_ACTIVE_PROFILE:-${DOTS_PROFILE:-}}"
	if [[ -n ${profile_hint} ]]; then
		echo "  profile:      ${profile_hint}"
	fi
	if [[ ${#DOTS_RESOLVED_GROUPS[@]} -gt 0 ]]; then
		echo "  groups:       ${DOTS_RESOLVED_GROUPS[*]}"
	fi
	if [[ ${#DOTS_WITH_COMPONENTS[@]} -gt 0 ]]; then
		echo "  components:   ${DOTS_WITH_COMPONENTS[*]}"
	else
		echo "  components:   (none active — last-with is informational;"
		echo "                 mutating setup needs profile/--with)"
	fi

	local e owners
	if [[ ${#DOTS_PKG_EXTERNAL_LINES[@]} -gt 0 ]]; then
		echo ""
		echo "External:"
		for e in "${DOTS_PKG_EXTERNAL_LINES[@]}"; do
			printf '  %s\n' "${e}"
		done
	fi
	if [[ ${#DOTS_PKG_INACTIVE_FORMULAE[@]} -gt 0 || ${#DOTS_PKG_INACTIVE_CASKS[@]} -gt 0 ]]; then
		echo ""
		echo "Inactive (known DOTS owner, not selected):"
		for e in "${DOTS_PKG_INACTIVE_FORMULAE[@]+"${DOTS_PKG_INACTIVE_FORMULAE[@]}"}"; do
			owners="$(dots_pkg_known_owners "${e}" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
			printf '  %s  [%s]\n' "${e}" "${owners:-?}"
		done
		for e in "${DOTS_PKG_INACTIVE_CASKS[@]+"${DOTS_PKG_INACTIVE_CASKS[@]}"}"; do
			owners="$(dots_pkg_known_owners "${e}" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
			printf '  %s  [%s] (cask)\n' "${e}" "${owners:-?}"
		done
		echo "  hint: activate via ./dots setup --with <component> (not adopt)"
		echo "        detail: ./dots packages explain <name>"
	fi
	if [[ ${#DOTS_PKG_UNDECLARED_FORMULAE[@]} -gt 0 ]]; then
		echo ""
		echo "Undeclared Homebrew formulae (leaves; no DOTS owner):"
		for e in "${DOTS_PKG_UNDECLARED_FORMULAE[@]}"; do
			printf '  %s\n' "${e}"
		done
		echo "  hint: ./dots packages adopt <name>  # suggest Brewfile line"
	fi
	if [[ ${#DOTS_PKG_UNDECLARED_CASKS[@]} -gt 0 ]]; then
		echo ""
		echo "Undeclared casks (no DOTS owner):"
		for e in "${DOTS_PKG_UNDECLARED_CASKS[@]}"; do
			printf '  %s\n' "${e}"
		done
		echo "  hint: ./dots packages adopt <name> --cask"
	fi
	if [[ ${#DOTS_PKG_MISSING_LINES[@]} -gt 0 ]]; then
		echo ""
		echo "Missing (declared):"
		for e in "${DOTS_PKG_MISSING_LINES[@]}"; do
			printf '  %s\n' "${e}"
		done
	fi
	if [[ ${#DOTS_PKG_OUTDATED_LINES[@]} -gt 0 ]]; then
		echo ""
		echo "Outdated (managed):"
		for e in "${DOTS_PKG_OUTDATED_LINES[@]}"; do
			printf '  %s\n' "${e}"
		done
		echo "  hint: ./dots packages upgrade   # active managed only"
		echo "        ./dots packages upgrade --all   # broader (opt-in)"
	fi
	echo ""
	echo "Note: inactive/undeclared/external are advisories."
	echo "      DOTS never runs brew bundle cleanup or uninstalls software automatically."
	echo "      known ≠ selected ≠ installed — see ./dots components active"
	echo "      Docs: https://sempervent.github.io/dots/using/components/"
}

# Explain one package name (formula or cask). Read-only.
dots_pkg_explain() {
	local name="$1"
	[[ -n ${name} ]] || {
		echo "Usage: ./dots packages explain NAME" >&2
		return 1
	}
	dots_desired_packages_resolve
	dots_pkg_build_ownership_catalog

	local -a formulae=() casks=() leaves=() out_f=() out_c=()
	local line kind=unknown installed=no brew_owned=no outdated=no state=UNKNOWN
	local in_desired=0

	while IFS= read -r line; do
		[[ -n ${line} ]] && leaves+=("${line}")
	done < <(dots_pkg_installed_leaves)
	while IFS= read -r line; do
		[[ -n ${line} ]] && formulae+=("${line}")
	done < <(dots_pkg_installed_formulae)
	while IFS= read -r line; do
		[[ -n ${line} ]] && casks+=("${line}")
	done < <(dots_pkg_installed_casks)
	while IFS= read -r line; do
		[[ -n ${line} ]] && out_f+=("${line}")
	done < <(dots_pkg_outdated_formulae)
	while IFS= read -r line; do
		[[ -n ${line} ]] && out_c+=("${line}")
	done < <(dots_pkg_outdated_casks)

	if dots_pkg_in_list "${name}" "${DOTS_DESIRED_CASKS[@]+"${DOTS_DESIRED_CASKS[@]}"}" ||
		dots_pkg_in_list "${name}" "${casks[@]+"${casks[@]}"}"; then
		kind=cask
		if dots_pkg_in_list "${name}" "${DOTS_DESIRED_CASKS[@]+"${DOTS_DESIRED_CASKS[@]}"}"; then
			in_desired=1
		fi
		if dots_pkg_in_list "${name}" "${casks[@]+"${casks[@]}"}"; then
			installed=yes
			brew_owned=yes
			dots_pkg_in_list "${name}" "${out_c[@]+"${out_c[@]}"}" && outdated=yes
		else
			local app=""
			if declare -F dots_cask_discover_app >/dev/null 2>&1; then
				app="$(dots_cask_discover_app "${name}" 2>/dev/null || true)"
			fi
			if [[ -n ${app} ]] && { [[ -d ${app} ]] || [[ -e ${app} ]]; }; then
				installed=yes
				brew_owned=no
			elif [[ -n ${DOTS_PKG_MOCK_EXTERNAL_APPS:-} ]] && printf '%s\n' "${DOTS_PKG_MOCK_EXTERNAL_APPS}" | grep -qx "${name}"; then
				installed=yes
				brew_owned=no
			fi
		fi
	elif dots_pkg_in_list "${name}" "${DOTS_DESIRED_FORMULAE[@]+"${DOTS_DESIRED_FORMULAE[@]}"}" ||
		dots_pkg_in_list "${name}" "${formulae[@]+"${formulae[@]}"}" ||
		dots_pkg_in_list "${name}" "${leaves[@]+"${leaves[@]}"}" ||
		dots_pkg_has_known_owner "${name}"; then
		kind=formula
		if dots_pkg_in_list "${name}" "${DOTS_DESIRED_FORMULAE[@]+"${DOTS_DESIRED_FORMULAE[@]}"}"; then
			in_desired=1
		fi
		if dots_pkg_in_list "${name}" "${formulae[@]+"${formulae[@]}"}"; then
			installed=yes
			brew_owned=yes
			dots_pkg_in_list "${name}" "${out_f[@]+"${out_f[@]}"}" && outdated=yes
		fi
	fi

	if [[ ${in_desired} -eq 1 ]]; then
		if [[ ${installed} == yes && ${brew_owned} == yes ]]; then
			if [[ ${outdated} == yes ]]; then
				state=OUTDATED
			else
				state=MANAGED
			fi
		elif [[ ${installed} == yes && ${brew_owned} == no ]]; then
			state=EXTERNAL
		else
			state=MISSING
		fi
	elif [[ ${installed} == yes ]]; then
		if dots_pkg_has_known_owner "${name}"; then
			state=INACTIVE
		else
			state=UNDECLARED
		fi
	elif dots_pkg_has_known_owner "${name}"; then
		# Known owner(s) but not installed — INACTIVE requires installed.
		state="known (not installed)"
	else
		state=UNDECLARED
	fi

	echo "Package: ${name}"
	echo "  kind:          ${kind}"
	echo "  installed:     ${installed}"
	echo "  brew-owned:    ${brew_owned}"
	echo "  outdated:      ${outdated}"
	echo "  state:         ${state}"
	echo -n "  active owners: "
	if dots_pkg_active_owners "${name}" >/dev/null 2>&1; then
		dots_pkg_active_owners "${name}" | tr '\n' ' '
		echo ""
	else
		echo "(none)"
	fi
	echo -n "  known owners:  "
	if dots_pkg_known_owners "${name}" >/dev/null 2>&1; then
		dots_pkg_known_owners "${name}" | tr '\n' ' '
		echo ""
	else
		echo "(none — not in group/component Brewfiles)"
	fi
	echo "  activate:"
	dots_pkg_activate_hint "${name}" | sed 's/^/    /'
}

# Resolve desired set, classify inventory, optionally print.
# Arg1: quiet=1 suppress detail sections
# Arg2: fast=1 skip outdated queries (for ./dots status)
dots_pkg_status_report() {
	local quiet="${1:-0}"
	local fast="${2:-0}"
	DOTS_RESOLVED_GROUPS=("${DOTS_RESOLVED_GROUPS[@]+"${DOTS_RESOLVED_GROUPS[@]}"}")
	DOTS_WITH_COMPONENTS=("${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}")

	if ! command -v "${DOTS_BREW_BIN:-brew}" >/dev/null 2>&1 && [[ -z ${DOTS_PKG_MOCK_LEAVES+x} ]]; then
		[[ ${quiet} -eq 0 ]] && echo "Packages: Homebrew unavailable"
		return 0
	fi

	dots_desired_packages_resolve
	dots_pkg_classify_resolved "${fast}"
	[[ ${quiet} -eq 1 ]] && return 0
	dots_pkg_status_print
}

# Suggest Brewfile declaration for an undeclared package (no file edits).
# If the package already has component/group owners, point to --with instead.
dots_pkg_suggest_declare() {
	local kind="$1" name="$2" dest="${3:-}"
	if dots_pkg_has_known_owner "${name}"; then
		echo "Package '${name}' already has DOTS ownership — do not adopt."
		echo "Known owners:"
		dots_pkg_known_owners "${name}" | sed 's/^/  /'
		echo "Activate instead:"
		dots_pkg_activate_hint "${name}" | sed 's/^/  /'
		return 0
	fi
	echo "Suggested declaration:"
	if [[ ${kind} == cask ]]; then
		echo "  cask \"${name}\""
	else
		echo "  brew \"${name}\""
	fi
	if [[ -n ${dest} ]]; then
		echo "Suggested destination:"
		echo "  ${dest}"
	else
		echo "Suggested destination:"
		echo "  brew/groups/modern.Brewfile   # or brew/Brewfile.<component>"
	fi
	echo "DOTS does not edit Brewfiles automatically during setup."
}

# Upgrade only managed (desired) outdated packages. --all upgrades undeclared too (opt-in).
dots_pkg_upgrade() {
	local all=0
	local a
	for a in "$@"; do
		[[ ${a} == --all ]] && all=1
	done
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] would upgrade managed outdated packages (all=${all})"
		return 0
	fi
	dots_desired_packages_resolve
	local -a to_f=() to_c=()
	local line f
	while IFS= read -r line; do
		[[ -z ${line} ]] && continue
		if [[ ${all} -eq 1 ]] || dots_pkg_in_list "${line}" "${DOTS_DESIRED_FORMULAE[@]+"${DOTS_DESIRED_FORMULAE[@]}"}"; then
			to_f+=("${line}")
		fi
	done < <(dots_pkg_outdated_formulae)
	while IFS= read -r line; do
		[[ -z ${line} ]] && continue
		if [[ ${all} -eq 1 ]] || dots_pkg_in_list "${line}" "${DOTS_DESIRED_CASKS[@]+"${DOTS_DESIRED_CASKS[@]}"}"; then
			to_c+=("${line}")
		fi
	done < <(dots_pkg_outdated_casks)

	if [[ ${all} -eq 1 ]]; then
		echo "Warn: --all may update packages not declared by DOTS (Homebrew will upgrade them)."
	fi
	if [[ ${#to_f[@]} -eq 0 && ${#to_c[@]} -eq 0 ]]; then
		echo "OK: nothing outdated in scope"
		return 0
	fi
	[[ ${#to_f[@]} -gt 0 ]] && dots_pkg_brew upgrade --formula "${to_f[@]}"
	[[ ${#to_c[@]} -gt 0 ]] && dots_pkg_brew upgrade --cask "${to_c[@]}"
}

# Guard: never invoke cleanup from package helpers (tested via source scan + runtime).
dots_pkg_forbid_cleanup() {
	# No-op marker for tests; real cleanup must not be called.
	return 0
}
