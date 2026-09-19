#!/usr/bin/env bash
# shellcheck shell=bash
# helpers/package_state.sh — DOTS package ownership / drift (Homebrew-focused)
#
# States:
#   MANAGED    declared by resolved desired set + package-manager owned
#   MISSING    declared but absent
#   OUTDATED   declared, managed, update available
#   EXTERNAL   declared (usually cask); artifact present but brew does not own it
#   UNDECLARED brew leaves / casks installed but not in desired set
#
# Desired set = union of active package-group Brewfiles + selected optional
# component Brewfiles. Inactive optional Brewfiles are ignored.
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
	DOTS_PKG_COUNT_UNDECLARED=0
	DOTS_PKG_EXTERNAL_LINES=()
	DOTS_PKG_UNDECLARED_FORMULAE=()
	DOTS_PKG_UNDECLARED_CASKS=()
	DOTS_PKG_MISSING_LINES=()
	DOTS_PKG_OUTDATED_LINES=()

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

	for f in "${leaves[@]+"${leaves[@]}"}"; do
		if ! dots_pkg_in_list "${f}" "${DOTS_DESIRED_FORMULAE[@]+"${DOTS_DESIRED_FORMULAE[@]}"}"; then
			DOTS_PKG_COUNT_UNDECLARED=$((DOTS_PKG_COUNT_UNDECLARED + 1))
			DOTS_PKG_UNDECLARED_FORMULAE+=("${f}")
		fi
	done
	for f in "${casks[@]+"${casks[@]}"}"; do
		if ! dots_pkg_in_list "${f}" "${DOTS_DESIRED_CASKS[@]+"${DOTS_DESIRED_CASKS[@]}"}"; then
			DOTS_PKG_COUNT_UNDECLARED=$((DOTS_PKG_COUNT_UNDECLARED + 1))
			DOTS_PKG_UNDECLARED_CASKS+=("${f}")
		fi
	done
}

# Initialize print arrays if classify never ran (set -u safety)
dots_pkg_status_print() {
	DOTS_PKG_EXTERNAL_LINES=("${DOTS_PKG_EXTERNAL_LINES[@]+"${DOTS_PKG_EXTERNAL_LINES[@]}"}")
	DOTS_PKG_UNDECLARED_FORMULAE=("${DOTS_PKG_UNDECLARED_FORMULAE[@]+"${DOTS_PKG_UNDECLARED_FORMULAE[@]}"}")
	DOTS_PKG_UNDECLARED_CASKS=("${DOTS_PKG_UNDECLARED_CASKS[@]+"${DOTS_PKG_UNDECLARED_CASKS[@]}"}")
	DOTS_PKG_MISSING_LINES=("${DOTS_PKG_MISSING_LINES[@]+"${DOTS_PKG_MISSING_LINES[@]}"}")
	DOTS_PKG_OUTDATED_LINES=("${DOTS_PKG_OUTDATED_LINES[@]+"${DOTS_PKG_OUTDATED_LINES[@]}"}")
	echo "Packages:"
	echo "  managed:      ${DOTS_PKG_COUNT_MANAGED:-0}"
	echo "  missing:      ${DOTS_PKG_COUNT_MISSING:-0}"
	echo "  outdated:     ${DOTS_PKG_COUNT_OUTDATED:-0}"
	echo "  external:     ${DOTS_PKG_COUNT_EXTERNAL:-0}"
	echo "  undeclared:   ${DOTS_PKG_COUNT_UNDECLARED:-0}"
	DOTS_RESOLVED_GROUPS=("${DOTS_RESOLVED_GROUPS[@]+"${DOTS_RESOLVED_GROUPS[@]}"}")
	DOTS_WITH_COMPONENTS=("${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}")
	if [[ ${#DOTS_RESOLVED_GROUPS[@]} -gt 0 ]]; then
		echo "  groups:       ${DOTS_RESOLVED_GROUPS[*]}"
	fi
	if [[ ${#DOTS_WITH_COMPONENTS[@]} -gt 0 ]]; then
		echo "  components:   ${DOTS_WITH_COMPONENTS[*]}"
	fi

	local e
	if [[ ${#DOTS_PKG_EXTERNAL_LINES[@]} -gt 0 ]]; then
		echo ""
		echo "External:"
		for e in "${DOTS_PKG_EXTERNAL_LINES[@]}"; do
			printf '  %s\n' "${e}"
		done
	fi
	if [[ ${#DOTS_PKG_UNDECLARED_FORMULAE[@]} -gt 0 ]]; then
		echo ""
		echo "Undeclared Homebrew formulae (leaves):"
		for e in "${DOTS_PKG_UNDECLARED_FORMULAE[@]}"; do
			printf '  %s\n' "${e}"
		done
	fi
	if [[ ${#DOTS_PKG_UNDECLARED_CASKS[@]} -gt 0 ]]; then
		echo ""
		echo "Undeclared casks:"
		for e in "${DOTS_PKG_UNDECLARED_CASKS[@]}"; do
			printf '  %s\n' "${e}"
		done
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
	fi
	echo ""
	echo "Note: undeclared/external are advisories. DOTS never runs brew bundle cleanup"
	echo "      or uninstalls undeclared software automatically."
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
dots_pkg_suggest_declare() {
	local kind="$1" name="$2" dest="${3:-}"
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
