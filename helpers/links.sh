# shellcheck shell=bash
# helpers/links.sh — declarative symlink deployment from configs/links.toml
#
# Requires: DIR, DRY_RUN, HOME, move_sym (from setup.sh) OR standalone fallback
# Optional: PROFILE_NAME for profile-filtered links

dots_links_manifest() {
	printf '%s\n' "${DIR}/configs/links.toml"
}

# Expand ~ in target paths
dots_expand_target() {
	local t="$1"
	t="${t/#\~/${HOME}}"
	printf '%s\n' "${t}"
}

# Print "source<TAB>target" lines applicable to current profile/platform
dots_links_list() {
	local profile="${PROFILE_NAME:-${DOTS_PROFILE:-base}}"
	local platform
	case "$(uname -s)" in
	Darwin) platform=darwin ;;
	Linux) platform=linux ;;
	*) platform=other ;;
	esac
	PROFILE="${profile}" PLATFORM="${platform}" dots_toml_query "$(dots_links_manifest)" <<'PY'
import os
profile = os.environ.get("PROFILE", "base")
platform = os.environ.get("PLATFORM", "other")
for link in data.get("links") or []:
    src = (link.get("source") or "").strip()
    tgt = (link.get("target") or "").strip()
    if not src or not tgt:
        continue
    profiles = link.get("profiles")
    if profiles:
        names = {str(x).strip() for x in profiles}
        if profile not in names and "all" not in names:
            # server skips workstation-only links that list explicit profiles
            continue
    platforms = link.get("platforms")
    if platforms:
        plats = {str(x).strip().lower() for x in platforms}
        if platform not in plats:
            continue
    print("%s\t%s" % (src, tgt))
PY
}

dots_deploy_links() {
	echo "=== Managed links (configs/links.toml) ==="
	local src tgt label dest fullsrc
	while IFS=$'\t' read -r src tgt; do
		[[ -z ${src} ]] && continue
		fullsrc="${DIR}/${src}"
		dest="$(dots_expand_target "${tgt}")"
		label="$(basename "${dest}")"
		if [[ ! -e ${fullsrc} && ! -L ${fullsrc} ]]; then
			echo "Warn: link source missing: ${src}"
			continue
		fi
		if [[ ${DRY_RUN:-0} -eq 1 ]]; then
			echo "[dry-run] link ${dest} → ${fullsrc}"
			continue
		fi
		ensure_dir "$(dirname "${dest}")"
		if declare -F move_sym >/dev/null 2>&1; then
			move_sym "${label}" "${dest}" "${fullsrc}"
		else
			ln -sfn "${fullsrc}" "${dest}"
			echo "OK: ${dest}"
		fi
	done < <(dots_links_list)
}

# Health: verify each applicable link; print FAIL lines to stdout, return count via global
dots_check_links() {
	local src tgt dest fullsrc errors=0
	while IFS=$'\t' read -r src tgt; do
		[[ -z ${src} ]] && continue
		fullsrc="${DIR}/${src}"
		dest="$(dots_expand_target "${tgt}")"
		if [[ ! -e ${fullsrc} && ! -L ${fullsrc} ]]; then
			echo "ERROR:link source missing: ${src}"
			errors=$((errors + 1))
			continue
		fi
		if [[ -L ${dest} ]]; then
			local cur
			cur="$(readlink "${dest}")"
			if [[ ${cur} == "${fullsrc}" ]] || [[ "$(cd "$(dirname "${dest}")" && realpath "${cur}" 2>/dev/null || echo "${cur}")" == "$(realpath "${fullsrc}" 2>/dev/null || echo "${fullsrc}")" ]]; then
				echo "OK:link ${dest}"
			else
				echo "ERROR:link ${dest} → ${cur} (expected ${fullsrc})"
				errors=$((errors + 1))
			fi
		elif [[ -e ${dest} ]]; then
			echo "WARN:link ${dest} exists but is not a symlink"
		else
			echo "ERROR:link missing ${dest}"
			errors=$((errors + 1))
		fi
	done < <(dots_links_list)
	return "${errors}"
}
