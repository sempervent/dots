# shellcheck shell=bash
# helpers/components.sh — load optional-component registry + supergroups
#
# Authority: configs/components.toml
# Requires: DIR, helpers/toml.sh
#
# Expansion pipeline (callers):
#   raw selectors → dots_expand_with_selectors / dots_expand_without_selectors
#                → ordinary component ids → install/configure

# shellcheck source=toml.sh
source "${DIR}/helpers/toml.sh"

# Override for tests: DOTS_FORCE_OS=darwin|linux  DOTS_FORCE_DARWIN_MAJOR=15
dots_host_os() {
	if [[ -n ${DOTS_FORCE_OS:-} ]]; then
		printf '%s\n' "${DOTS_FORCE_OS}"
		return 0
	fi
	case "$(uname -s)" in
	Darwin) printf 'darwin\n' ;;
	Linux) printf 'linux\n' ;;
	*) printf 'unknown\n' ;;
	esac
}

dots_darwin_major() {
	if [[ -n ${DOTS_FORCE_DARWIN_MAJOR:-} ]]; then
		printf '%s\n' "${DOTS_FORCE_DARWIN_MAJOR}"
		return 0
	fi
	local ver
	ver="$(sw_vers -productVersion 2>/dev/null || true)"
	printf '%s\n' "${ver%%.*}"
}

dots_components_registry_path() {
	printf '%s\n' "${DIR}/configs/components.toml"
}

# Print all component ids (one per line), registry order.
dots_component_ids() {
	dots_toml_query "$(dots_components_registry_path)" <<'PY'
for c in data.get("components") or []:
    cid = (c.get("id") or "").strip()
    if cid:
        print(cid)
PY
}

# Print ids suitable for profile `all` (omit_from_all skipped).
dots_component_ids_for_all() {
	dots_toml_query "$(dots_components_registry_path)" <<'PY'
for c in data.get("components") or []:
    cid = (c.get("id") or "").strip()
    if not cid:
        continue
    if c.get("omit_from_all"):
        continue
    print(cid)
PY
}

dots_supergroup_ids() {
	dots_toml_query "$(dots_components_registry_path)" <<'PY'
for g in data.get("supergroups") or []:
    gid = (g.get("id") or "").strip()
    if gid:
        print(gid)
PY
}

# Map optional component id → Brewfile path (relative to DIR) via components.toml.
# Authority: optional `brewfile` field on [[components]]. No hard-coded case map.
dots_component_brewfile() {
	local id="$1"
	[[ -n ${id} ]] || return 1
	WANT="${id}" dots_toml_query "$(dots_components_registry_path)" <<'PY'
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

dots_component_is_known() {
	local want="$1" id
	while IFS= read -r id; do
		[[ "${id}" == "${want}" ]] && return 0
	done < <(dots_component_ids)
	return 1
}

dots_supergroup_is_known() {
	local want="$1" id
	while IFS= read -r id; do
		[[ "${id}" == "${want}" ]] && return 0
	done < <(dots_supergroup_ids)
	return 1
}

# Selector is a known component OR known supergroup.
dots_selector_is_known() {
	local want="$1"
	dots_component_is_known "${want}" || dots_supergroup_is_known "${want}"
}

# Validate registry integrity: no id collisions; group members exist.
dots_validate_component_registry() {
	dots_toml_query "$(dots_components_registry_path)" <<'PY'
comps = []
seen = set()
for c in data.get("components") or []:
    cid = (c.get("id") or "").strip()
    if not cid:
        raise SystemExit("Error: component missing id")
    if cid in seen:
        raise SystemExit("Error: duplicate component id '%s'" % cid)
    seen.add(cid)
    comps.append(cid)
groups = []
for g in data.get("supergroups") or []:
    gid = (g.get("id") or "").strip()
    if not gid:
        raise SystemExit("Error: supergroup missing id")
    if gid in seen:
        raise SystemExit("Error: supergroup id '%s' collides with a component id" % gid)
    if gid in groups:
        raise SystemExit("Error: duplicate supergroup id '%s'" % gid)
    groups.append(gid)
    members = g.get("members") or []
    if not isinstance(members, list) or not members:
        raise SystemExit("Error: supergroup '%s' has no members" % gid)
    for m in members:
        mid = str(m).strip()
        if mid not in seen:
            raise SystemExit("Error: supergroup '%s' references unknown component '%s'" % (gid, mid))
print("OK")
PY
}

# Returns 0 if component is supported on current host OS (+ darwin min version).
dots_component_supported_here() {
	local want="$1"
	local os
	os="$(dots_host_os)"
	WANT="${want}" OS="${os}" MAJOR="$(dots_darwin_major)" dots_toml_query "$(dots_components_registry_path)" <<'PY'
import os, sys
want = os.environ.get("WANT", "")
host = os.environ.get("OS", "unknown")
major_s = os.environ.get("MAJOR", "").strip()
for c in data.get("components") or []:
    if (c.get("id") or "").strip() != want:
        continue
    plats = c.get("platforms")
    if plats is None:
        plats = ["darwin", "linux"]
    plats = [str(p).strip() for p in plats]
    if host not in plats:
        sys.exit(1)
    if host == "darwin":
        min_d = c.get("min_darwin")
        if min_d is not None:
            try:
                need = int(str(min_d).split(".")[0])
                have = int(major_s) if major_s else 0
            except ValueError:
                sys.exit(1)
            if have < need:
                sys.exit(1)
    sys.exit(0)
sys.exit(1)
PY
}

# Human-readable reason when unsupported (empty if supported).
dots_component_unsupported_reason() {
	local want="$1"
	local os
	os="$(dots_host_os)"
	WANT="${want}" OS="${os}" MAJOR="$(dots_darwin_major)" dots_toml_query "$(dots_components_registry_path)" <<'PY'
import os
want = os.environ.get("WANT", "")
host = os.environ.get("OS", "unknown")
major_s = os.environ.get("MAJOR", "").strip()
for c in data.get("components") or []:
    if (c.get("id") or "").strip() != want:
        continue
    plats = c.get("platforms")
    if plats is None:
        plats = ["darwin", "linux"]
    plats = [str(p).strip() for p in plats]
    if host not in plats:
        if plats == ["darwin"]:
            print("macOS only")
        else:
            print("unsupported on %s (allowed: %s)" % (host, ", ".join(plats)))
        raise SystemExit(0)
    if host == "darwin":
        min_d = c.get("min_darwin")
        if min_d is not None:
            try:
                need = int(str(min_d).split(".")[0])
                have = int(major_s) if major_s else 0
            except ValueError:
                print("requires macOS %s+" % min_d)
                raise SystemExit(0)
            if have < need:
                print("requires macOS %s+ (this host reports %s)" % (min_d, major_s or "?"))
                raise SystemExit(0)
    raise SystemExit(0)
print("unknown component")
PY
}

# Print members of a supergroup (registry order), one per line.
dots_supergroup_members() {
	local gid="$1"
	GID="${gid}" dots_toml_query "$(dots_components_registry_path)" <<'PY'
import os
gid = os.environ.get("GID", "")
for g in data.get("supergroups") or []:
    if (g.get("id") or "").strip() != gid:
        continue
    for m in g.get("members") or []:
        mid = str(m).strip()
        if mid:
            print(mid)
    break
PY
}

# Expand --with / profile with selectors.
# Groups → platform-filtered members (skips announced on stderr).
# Leaf components are left as-is (caller validates support for explicit leaves).
# Prints component ids to stdout (deduped, stable order).
dots_expand_with_selectors() {
	local tok member reason
	local -a out=() selected=() skipped=()
	local seen_pipe="|"
	for tok in "$@"; do
		[[ -z ${tok} ]] && continue
		if dots_supergroup_is_known "${tok}"; then
			selected=()
			skipped=()
			while IFS= read -r member; do
				[[ -z ${member} ]] && continue
				if dots_component_supported_here "${member}"; then
					selected+=("${member}")
					case "${seen_pipe}" in
					*"|${member}|"*) ;;
					*)
						out+=("${member}")
						seen_pipe="${seen_pipe}${member}|"
						;;
					esac
				else
					reason="$(dots_component_unsupported_reason "${member}")"
					skipped+=("${member} (${reason})")
				fi
			done < <(dots_supergroup_members "${tok}")
			echo "Supergroup '${tok}':" >&2
			if [[ ${#selected[@]} -gt 0 ]]; then
				echo "  selected: ${selected[*]}" >&2
			else
				echo "  selected: (none)" >&2
			fi
			if [[ ${#skipped[@]} -gt 0 ]]; then
				local s
				for s in "${skipped[@]}"; do
					echo "  skipped for platform: ${s}" >&2
				done
			fi
		elif dots_component_is_known "${tok}"; then
			case "${seen_pipe}" in
			*"|${tok}|"*) ;;
			*)
				out+=("${tok}")
				seen_pipe="${seen_pipe}${tok}|"
				;;
			esac
		else
			echo "Error: unknown component or supergroup '${tok}'" >&2
			dots_print_selector_help >&2
			return 1
		fi
	done
	printf '%s\n' "${out[@]+"${out[@]}"}"
}

# Expand --without / profile without: groups → ALL members (no platform filter).
dots_expand_without_selectors() {
	local tok member
	local -a out=() seen_pipe="|"
	for tok in "$@"; do
		[[ -z ${tok} ]] && continue
		if dots_supergroup_is_known "${tok}"; then
			while IFS= read -r member; do
				[[ -z ${member} ]] && continue
				case "${seen_pipe}" in
				*"|${member}|"*) ;;
				*)
					out+=("${member}")
					seen_pipe="${seen_pipe}${member}|"
					;;
				esac
			done < <(dots_supergroup_members "${tok}")
		elif dots_component_is_known "${tok}"; then
			case "${seen_pipe}" in
			*"|${tok}|"*) ;;
			*)
				out+=("${tok}")
				seen_pipe="${seen_pipe}${tok}|"
				;;
			esac
		else
			echo "Error: unknown component or supergroup '${tok}'" >&2
			dots_print_selector_help >&2
			return 1
		fi
	done
	printf '%s\n' "${out[@]+"${out[@]}"}"
}

# Fail if an explicit leaf component is unsupported here.
dots_require_explicit_component_supported() {
	local c reason
	for c in "$@"; do
		[[ -z ${c} ]] && continue
		dots_component_is_known "${c}" || continue
		if ! dots_component_supported_here "${c}"; then
			reason="$(dots_component_unsupported_reason "${c}")"
			case "${reason}" in
			"macOS only")
				echo "Error: component '${c}' is supported only on macOS." >&2
				;;
			requires\ macOS*)
				if [[ ${c} == fluidvoice ]]; then
					echo "Error: FluidVoice requires macOS 15 or newer" >&2
				else
					echo "Error: component '${c}' ${reason}" >&2
				fi
				;;
			*)
				echo "Error: component '${c}' is not supported on this platform (${reason})." >&2
				;;
			esac
			return 1
		fi
	done
	return 0
}

dots_print_selector_help() {
	echo "Components:"
	dots_toml_query "$(dots_components_registry_path)" <<'PY'
for c in data.get("components") or []:
    cid = (c.get("id") or "").strip()
    desc = (c.get("description") or c.get("label") or cid).strip()
    if cid:
        print("  %-12s %s" % (cid, desc))
PY
	echo "Supergroups:"
	dots_toml_query "$(dots_components_registry_path)" <<'PY'
groups = data.get("supergroups") or []
if not groups:
    print("  (none)")
for g in groups:
    gid = (g.get("id") or "").strip()
    lab = (g.get("label") or gid).strip()
    desc = (g.get("description") or "").strip()
    if gid:
        print("  %-12s %s%s" % (gid, lab, (" — " + desc) if desc else ""))
PY
	echo "List: ./dots components list"
}

# Validate CSV / list of component names (not groups); print unknowns to stderr.
dots_validate_components() {
	local unknown=0 c
	for c in "$@"; do
		[[ -z ${c} ]] && continue
		if ! dots_component_is_known "${c}"; then
			echo "Error: unknown component '${c}'" >&2
			unknown=1
		fi
	done
	if [[ ${unknown} -ne 0 ]]; then
		dots_print_selector_help >&2
		return 1
	fi
	return 0
}

# Validate selectors that may be components or groups (pre-expansion).
dots_validate_selectors() {
	local unknown=0 c
	for c in "$@"; do
		[[ -z ${c} ]] && continue
		if ! dots_selector_is_known "${c}"; then
			echo "Error: unknown component or supergroup '${c}'" >&2
			unknown=1
		fi
	done
	if [[ ${unknown} -ne 0 ]]; then
		dots_print_selector_help >&2
		return 1
	fi
	return 0
}

# Cloud/external AI notice for selected components.
dots_print_cloud_notice() {
	local wanted
	wanted="$(printf '%s\n' "$@")"
	WANTED="${wanted}" dots_toml_query "$(dots_components_registry_path)" <<'PY'
import os
wanted = {x.strip() for x in os.environ.get("WANTED", "").splitlines() if x.strip()}
for c in data.get("components") or []:
    cid = (c.get("id") or "").strip()
    if cid in wanted and c.get("cloud"):
        print(cid)
PY
}

dots_print_provider_implications() {
	local wanted
	wanted="$(printf '%s\n' "$@")"
	WANTED="${wanted}" dots_toml_query "$(dots_components_registry_path)" <<'PY'
import os
wanted = {x.strip() for x in os.environ.get("WANTED", "").splitlines() if x.strip()}
local_ai, cloud_ai, image_ai, voice_ai = [], [], [], []
for c in data.get("components") or []:
    cid = (c.get("id") or "").strip()
    if cid not in wanted:
        continue
    cat = c.get("category") or ""
    if c.get("cloud"):
        cloud_ai.append(cid)
    if c.get("local_ai") and cat not in ("image_ai", "voice_ai"):
        local_ai.append(cid)
    if cat == "image_ai":
        image_ai.append(cid)
    if cat == "voice_ai":
        voice_ai.append(cid)
print("explicit provider implications:")
print("  local AI: %s" % (", ".join(local_ai) if local_ai else "(none)"))
print("  cloud AI: %s" % (", ".join(cloud_ai) if cloud_ai else "(none)"))
print("  image AI: %s" % (", ".join(image_ai) if image_ai else "(none)"))
print("  voice AI: %s" % (", ".join(voice_ai) if voice_ai else "(none)"))
PY
}

# Populate bash array name with registry ids (for setup SUPPORTED_WITH).
dots_load_supported_with_into() {
	local dest="$1"
	eval "${dest}=()"
	local id
	while IFS= read -r id; do
		[[ -n ${id} ]] && eval "${dest}+=(\"\${id}\")"
	done < <(dots_component_ids)
	while IFS= read -r id; do
		[[ -n ${id} ]] && eval "${dest}+=(\"\${id}\")"
	done < <(dots_supergroup_ids)
}

# Show expansion for --show (requested groups vs effective leaves).
dots_print_supergroup_resolution() {
	local -a requested=("$@")
	local tok
	local -a groups=()
	for tok in "${requested[@]+"${requested[@]}"}"; do
		dots_supergroup_is_known "${tok}" && groups+=("${tok}")
	done
	if [[ ${#groups[@]} -eq 0 ]]; then
		return 0
	fi
	echo ""
	echo "=== Supergroup expansion ==="
	echo "requested:"
	printf '  %s\n' "${groups[@]}"
}

# --- Read-only component discovery (./dots components) ---------------------

# Print id + short description for one component (registry-driven).
dots_component_description() {
	local want="$1"
	WANT="${want}" dots_toml_query "$(dots_components_registry_path)" <<'PY'
import os
want = os.environ.get("WANT", "").strip()
for c in data.get("components") or []:
    if (c.get("id") or "").strip() != want:
        continue
    print((c.get("description") or c.get("label") or want).strip())
    raise SystemExit(0)
raise SystemExit(1)
PY
}

dots_component_label() {
	local want="$1"
	WANT="${want}" dots_toml_query "$(dots_components_registry_path)" <<'PY'
import os
want = os.environ.get("WANT", "").strip()
for c in data.get("components") or []:
    if (c.get("id") or "").strip() != want:
        continue
    print((c.get("label") or want).strip())
    raise SystemExit(0)
raise SystemExit(1)
PY
}

# List components + supergroups with host compatibility (read-only).
dots_components_list() {
	echo "Components (configs/components.toml):"
	local id desc ok reason
	while IFS= read -r id; do
		[[ -z ${id} ]] && continue
		desc="$(dots_component_description "${id}" 2>/dev/null || true)"
		if dots_component_supported_here "${id}"; then
			printf '  %-14s %s\n' "${id}" "${desc}"
		else
			reason="$(dots_component_unsupported_reason "${id}" 2>/dev/null || echo "unsupported here")"
			printf '  %-14s %s  [%s]\n' "${id}" "${desc}" "${reason}"
		fi
	done < <(dots_component_ids)
	echo ""
	echo "Supergroups:"
	dots_toml_query "$(dots_components_registry_path)" <<'PY'
for g in data.get("supergroups") or []:
    gid = (g.get("id") or "").strip()
    if not gid:
        continue
    lab = (g.get("label") or gid).strip()
    desc = (g.get("description") or "").strip()
    members = ", ".join(str(m).strip() for m in (g.get("members") or []))
    print("  %-14s %s" % (gid, lab))
    if desc:
        print("                 %s" % desc)
    print("                 members: %s" % members)
PY
	echo ""
	echo "Select with: ./dots setup --with <id>[,id…]   or profile with = […]"
	echo "Docs: https://sempervent.github.io/dots/using/components/"
}

# Show active profile / groups / components from machine state (informational).
dots_components_active() {
	local profile="(none)" pkg_groups="(none)" comps="(none)"
	if declare -F dots_state_load_active >/dev/null 2>&1 && dots_state_load_active 2>/dev/null; then
		profile="${DOTS_ACTIVE_PROFILE:-unknown}"
		pkg_groups="${DOTS_ACTIVE_PACKAGE_GROUPS:-${DOTS_PACKAGE_GROUPS:-(none)}}"
		comps="${DOTS_ACTIVE_COMPONENTS:-${DOTS_LAST_WITH_INFO:-(none)}}"
		[[ -z ${comps} ]] && comps="(none)"
		[[ -z ${pkg_groups} ]] && pkg_groups="(none)"
	fi
	echo "Active selection (read-only / informational):"
	echo "  profile:     ${profile}"
	echo "  groups:      ${pkg_groups}"
	echo "  components:  ${comps}"
	echo ""
	echo "Consent disclaimer:"
	echo "  DOTS_LAST_WITH_INFO / DOTS_ACTIVE_COMPONENTS record the last"
	echo "  bootstrap selection for discovery only. They do NOT authorize"
	echo "  mutating AI setup. Binary presence ≠ consent."
	echo "  Mutating setup still needs profile with / ./setup.sh --with"
	echo "  for that run. Exclusions: profile without = […] / --without."
	echo ""
	echo "Detail: ./dots components show <id>"
	echo "Docs: https://sempervent.github.io/dots/using/components/"
}

# Show one component or supergroup (Brewfile tokens without invoking brew).
dots_components_show() {
	local id="$1"
	[[ -n ${id} ]] || {
		echo "Usage: ./dots components show ID" >&2
		return 1
	}
	if dots_supergroup_is_known "${id}"; then
		echo "Supergroup: ${id}"
		WANT="${id}" dots_toml_query "$(dots_components_registry_path)" <<'PY'
import os
want = os.environ.get("WANT", "").strip()
for g in data.get("supergroups") or []:
    if (g.get("id") or "").strip() != want:
        continue
    print("  label:       %s" % ((g.get("label") or want).strip()))
    print("  description: %s" % ((g.get("description") or "").strip() or "(none)"))
    members = [str(m).strip() for m in (g.get("members") or [])]
    print("  members:")
    for m in members:
        print("    - %s" % m)
    raise SystemExit(0)
raise SystemExit(1)
PY
		echo "  activate:    ./dots setup --with ${id}"
		return 0
	fi
	if ! dots_component_is_known "${id}"; then
		echo "Error: unknown component or supergroup '${id}'" >&2
		dots_print_selector_help >&2
		return 1
	fi
	echo "Component: ${id}"
	WANT="${id}" dots_toml_query "$(dots_components_registry_path)" <<'PY'
import os
want = os.environ.get("WANT", "").strip()
for c in data.get("components") or []:
    if (c.get("id") or "").strip() != want:
        continue
    print("  label:       %s" % ((c.get("label") or want).strip()))
    print("  category:    %s" % ((c.get("category") or "").strip() or "(none)"))
    print("  description: %s" % ((c.get("description") or "").strip() or "(none)"))
    plats = c.get("platforms") or ["darwin", "linux"]
    print("  platforms:   %s" % ", ".join(str(p) for p in plats))
    bf = (c.get("brewfile") or "").strip()
    print("  brewfile:    %s" % (bf or "(none)"))
    if c.get("omit_from_all"):
        print("  omit_from_all: yes")
    raise SystemExit(0)
raise SystemExit(1)
PY
	if dots_component_supported_here "${id}"; then
		echo "  host:        supported"
	else
		echo "  host:        $(dots_component_unsupported_reason "${id}" 2>/dev/null || echo unsupported)"
	fi
	local rel
	if rel="$(dots_component_brewfile "${id}" 2>/dev/null)"; then
		if [[ -f ${DIR}/${rel} ]]; then
			echo "  formulae/casks (from ${rel}, brew not invoked):"
			local kind token
			if ! declare -F dots_brewfile_tokens >/dev/null 2>&1; then
				# shellcheck source=package_state.sh
				[[ -f ${DIR}/helpers/package_state.sh ]] && source "${DIR}/helpers/package_state.sh" 2>/dev/null || true
			fi
			if declare -F dots_brewfile_tokens >/dev/null 2>&1; then
				while IFS=$'\t' read -r kind token; do
					[[ -z ${token} ]] && continue
					printf '    %s %s\n' "${kind}" "${token}"
				done < <(dots_brewfile_tokens "${DIR}/${rel}" all)
			else
				echo "    (Brewfile parse helper unavailable)"
			fi
		fi
	fi
	# Skills from manifest for skill packs
	case "${id}" in
	skills | ai-skills | archify)
		echo "  skills (configs/skills/manifest.toml):"
		PACK="${id}" dots_toml_query "${DIR}/configs/skills/manifest.toml" <<'PY'
import os
pack = os.environ.get("PACK", "").strip()
packs = data.get("packs") or {}
if pack == "archify":
    print("    (Archify skill only — also included when --with skills)")
    print("    Shared Brewfile.archify with skills / ai-skills")
    raise SystemExit(0)
pdata = packs.get(pack) or {}
groups = set(pdata.get("groups") or [])
desc = (pdata.get("description") or "").strip()
if desc:
    print("    pack: %s" % desc)
printed = False
for s in data.get("skills") or []:
    if not s.get("enabled", True):
        continue
    g = (s.get("group") or "").strip()
    if g not in groups:
        continue
    print("    - %s (%s)" % ((s.get("name") or ""), g))
    printed = True
if not printed:
    print("    (no enabled skills for this pack)")
PY
		echo "  note: Brewfile.archify is shared by archify/skills/ai-skills"
		;;
	esac
	echo "  activate:    ./dots setup --with ${id}"
}

