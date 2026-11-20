# shellcheck shell=bash
# helpers/profile_edit.sh — persistent desired-state profile overlay engine
#
# Shared by: ./dots install, ./dots profile, ./configure.sh
#
# Guarantees:
#   - Never edits builtin profiles (configs/bootstrap/profiles/*.toml)
#   - Never destructively rewrites user-authored custom profiles
#   - Uses sparse DOTS-managed overlays (<name>-local.toml) with explicit marker
#   - Atomic writes: temp file -> validate via dots_profile_parse -> backup -> mv
#   - Removing desired state never uninstalls software
#
# Requires: DIR, helpers/toml.sh, helpers/components.sh, helpers/profiles.sh, helpers/packages.sh, helpers/state.sh

DOTS_OVERLAY_MARKER="# DOTS managed profile overlay"

_dots_pe_groups_registry() {
	if [[ -n ${DOTS_GROUPS_REGISTRY:-} && -f ${DOTS_GROUPS_REGISTRY} ]]; then
		printf '%s\n' "${DOTS_GROUPS_REGISTRY}"
	else
		printf '%s\n' "${DIR}/configs/packages/groups.toml"
	fi
}

_dots_pe_components_registry() {
	if [[ -n ${DOTS_COMPONENTS_REGISTRY:-} && -f ${DOTS_COMPONENTS_REGISTRY} ]]; then
		printf '%s\n' "${DOTS_COMPONENTS_REGISTRY}"
	else
		printf '%s\n' "${DIR}/configs/components.toml"
	fi
}

# True if file is a DOTS-managed sparse overlay.
dots_profile_is_managed_overlay() {
	local file="$1"
	[[ -f ${file} ]] || return 1
	grep -qF "${DOTS_OVERLAY_MARKER}" "${file}" 2>/dev/null
}

# True if path is inside builtin profiles dir.
dots_profile_is_builtin_path() {
	local file="$1" bdir
	bdir="$(dots_builtin_profile_dir)"
	case "${file}" in
	"${bdir}"/*) return 0 ;;
	*) return 1 ;;
	esac
}

# Resolve a capability selector (group, component, supergroup, or known package).
# Args: selector [allow_prompt=0]
# Sets globals:
#   DOTS_SEL_STATUS   ok | ambiguous | unknown
#   DOTS_SEL_OWNER    e.g. group:dev | component:karabiner-elements | supergroup:ai
#   DOTS_SEL_KIND     group | component | supergroup
#   DOTS_SEL_ID       id within kind
#   DOTS_SEL_VIA_PKG  package name if resolved via package ownership, else empty
#   DOTS_SEL_CHOICES  newline-separated candidate owners when ambiguous
dots_resolve_capability_selector() {
	local raw="$1" allow_prompt="${2:-0}"
	DOTS_SEL_STATUS="unknown"
	DOTS_SEL_OWNER=""
	DOTS_SEL_KIND=""
	DOTS_SEL_ID=""
	DOTS_SEL_VIA_PKG=""
	DOTS_SEL_CHOICES=""

	if [[ -z ${raw} ]]; then
		echo "Error: empty selector" >&2
		return 1
	fi

	dots_require_python 0 || return 1
	local py="${DOTS_PYTHON}"
	local pyhome out rc=0
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-py.XXXXXX")"
	out="$(
		RAW="${raw}" \
			REPO_DIR="${DIR}" \
			GROUPS_REG="$(_dots_pe_groups_registry)" \
			COMPS_REG="$(_dots_pe_components_registry)" \
			HOME="${pyhome}" \
			PYTHONDONTWRITEBYTECODE=1 \
			PYTHONNOUSERSITE=1 \
			"${py}" -B <<'PY'
import os
import re
import sys
import tomllib
from pathlib import Path

raw = os.environ["RAW"].strip()
repo = Path(os.environ["REPO_DIR"])
groups_reg = Path(os.environ["GROUPS_REG"])
comps_reg = Path(os.environ["COMPS_REG"])

groups_data = tomllib.loads(groups_reg.read_text(encoding="utf-8")) if groups_reg.is_file() else {}
comps_data = tomllib.loads(comps_reg.read_text(encoding="utf-8")) if comps_reg.is_file() else {}

known_groups = set()
pkg_owners = {}  # short_name -> set of owner strings

for g in groups_data.get("groups") or []:
    gname = str(g.get("name") or "").strip()
    if not gname:
        continue
    known_groups.add(gname)
    for cls in ("required", "optional", "tools", "brew_companions"):
        for pkg in g.get(cls) or []:
            p = str(pkg).strip()
            if p:
                pkg_owners.setdefault(p, set()).add(f"group:{gname}")
                pkg_owners.setdefault(p.split("/")[-1], set()).add(f"group:{gname}")
    bf = repo / "brew" / "groups" / f"{gname}.Brewfile"
    if bf.is_file():
        for line in bf.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].strip()
            m = re.match(r'^(?:brew|cask)\s+"([^"]+)"', line)
            if m:
                tok = m.group(1).strip()
                pkg_owners.setdefault(tok, set()).add(f"group:{gname}")
                pkg_owners.setdefault(tok.split("/")[-1], set()).add(f"group:{gname}")

for pid, hspec in (groups_data.get("helper_packages") or {}).items():
    if isinstance(hspec, dict) and str(hspec.get("owner") or "").strip():
        pkg_owners.setdefault(str(pid).strip(), set()).add(str(hspec["owner"]).strip())

known_components = set()
known_supergroups = set()
for c in comps_data.get("components") or []:
    cid = str(c.get("id") or "").strip()
    if not cid:
        continue
    known_components.add(cid)
    bf_rel = str(c.get("brewfile") or "").strip()
    if bf_rel:
        bf = repo / bf_rel
        if bf.is_file():
            for line in bf.read_text(encoding="utf-8").splitlines():
                line = line.split("#", 1)[0].strip()
                m = re.match(r'^(?:brew|cask)\s+"([^"]+)"', line)
                if m:
                    tok = m.group(1).strip()
                    pkg_owners.setdefault(tok, set()).add(f"component:{cid}")
                    pkg_owners.setdefault(tok.split("/")[-1], set()).add(f"component:{cid}")
    for hp in c.get("helper_packages") or []:
        h = str(hp).strip()
        if h:
            pkg_owners.setdefault(h, set()).add(f"component:{cid}")
    for lp in c.get("linux_packages") or []:
        lpkg = str(lp).strip()
        if lpkg:
            pkg_owners.setdefault(lpkg, set()).add(f"component:{cid}")

for s in comps_data.get("supergroups") or []:
    sid = str(s.get("id") or "").strip()
    if sid:
        known_supergroups.add(sid)

explicit_kind = ""
target = raw
if ":" in raw:
    prefix, rest = raw.split(":", 1)
    if prefix in ("group", "component", "supergroup", "package") and rest:
        explicit_kind = prefix
        target = rest.strip()
    else:
        print("status=unknown")
        sys.exit(0)

candidates = []
via_pkg = ""

if explicit_kind == "group":
    if target in known_groups:
        candidates = [f"group:{target}"]
elif explicit_kind == "component":
    if target in known_components:
        candidates = [f"component:{target}"]
elif explicit_kind == "supergroup":
    if target in known_supergroups:
        candidates = [f"supergroup:{target}"]
elif explicit_kind == "package":
    via_pkg = target
    short = target.split("/")[-1]
    found = set(pkg_owners.get(target, set())) | set(pkg_owners.get(short, set()))
    candidates = sorted(found)
else:
    direct = []
    if target in known_groups:
        direct.append(f"group:{target}")
    if target in known_components:
        direct.append(f"component:{target}")
    if target in known_supergroups:
        direct.append(f"supergroup:{target}")
    short = target.split("/")[-1]
    pkg_found = set(pkg_owners.get(target, set())) | set(pkg_owners.get(short, set()))
    if direct:
        # Merge any distinct package owners (e.g., if a name is both a component and in another group),
        # while avoiding duplicate self-ownership (karabiner-elements -> component:karabiner-elements).
        merged = sorted(set(direct) | pkg_found)
        candidates = merged
        if len(merged) > len(direct):
            via_pkg = target
    elif pkg_found:
        candidates = sorted(pkg_found)
        via_pkg = target

if not candidates:
    print("status=unknown")
elif len(candidates) == 1:
    print("status=ok")
    print(f"owner={candidates[0]}")
    print(f"via_pkg={via_pkg}")
else:
    print("status=ambiguous")
    print(f"via_pkg={via_pkg or target}")
    for c in candidates:
        print(f"choice={c}")
PY
	)" || rc=$?
	rm -rf "${pyhome}"
	[[ ${rc} -eq 0 ]] || return 1

	local line
	local -a choices=()
	while IFS= read -r line; do
		case "${line}" in
		status=*) DOTS_SEL_STATUS="${line#status=}" ;;
		owner=*) DOTS_SEL_OWNER="${line#owner=}" ;;
		via_pkg=*) DOTS_SEL_VIA_PKG="${line#via_pkg=}" ;;
		choice=*) choices+=("${line#choice=}") ;;
		esac
	done <<<"${out}"

	if [[ ${DOTS_SEL_STATUS} == "ok" ]]; then
		DOTS_SEL_KIND="${DOTS_SEL_OWNER%%:*}"
		DOTS_SEL_ID="${DOTS_SEL_OWNER#*:}"
		return 0
	fi

	if [[ ${DOTS_SEL_STATUS} == "ambiguous" ]]; then
		DOTS_SEL_CHOICES="$(printf '%s\n' "${choices[@]+"${choices[@]}"}")"
		if [[ ${allow_prompt} -eq 1 ]] && [[ ${DOTS_UI_NONINTERACTIVE:-0} -ne 1 ]] && { [[ -t 0 ]] || [[ -n ${DOTS_UI_ANSWERS:-} ]]; }; then
			[[ -z ${DOTS_UI_ANSWER_FD:-} ]] && dots_ui_load_answers
			echo "" >&2
			echo "Package '${raw}' has multiple owners:" >&2
			local idx=1 c
			for c in "${choices[@]}"; do
				echo "  ${idx}) ${c}" >&2
				idx=$((idx + 1))
			done
			local pick=""
			while true; do
				pick="$(dots_ui_read_line "Choose [1-${#choices[@]}]" "")" || return 1
				case "${pick}" in
				*[!0-9]* | "")
					echo "Enter a number 1-${#choices[@]}" >&2
					continue
					;;
				esac
				if [[ ${pick} -ge 1 && ${pick} -le ${#choices[@]} ]]; then
					DOTS_SEL_OWNER="${choices[$((pick - 1))]}"
					DOTS_SEL_KIND="${DOTS_SEL_OWNER%%:*}"
					DOTS_SEL_ID="${DOTS_SEL_OWNER#*:}"
					DOTS_SEL_STATUS="ok"
					return 0
				fi
				echo "Enter a number 1-${#choices[@]}" >&2
			done
		fi
		echo "Error: selector '${raw}' has multiple owners:" >&2
		local c
		for c in "${choices[@]}"; do
			echo "  ${c}" >&2
		done
		echo "Disambiguate explicitly, for example:" >&2
		echo "  ./dots install ${choices[0]}" >&2
		return 1
	fi

	# Unknown selector: suggest adoption (never invoke brew install)
	echo "Error: '${raw}' is not declared in DOTS." >&2
	if declare -F dots_suggest_print >/dev/null 2>&1; then
		local -a all_cands=()
		local x
		while IFS= read -r x; do [[ -n ${x} ]] && all_cands+=("${x}"); done < <(dots_known_package_groups 2>/dev/null || true)
		while IFS= read -r x; do [[ -n ${x} ]] && all_cands+=("${x}"); done < <(dots_component_ids 2>/dev/null || true)
		while IFS= read -r x; do [[ -n ${x} ]] && all_cands+=("${x}"); done < <(dots_supergroup_ids 2>/dev/null || true)
		dots_suggest_print "${raw}" "${all_cands[@]+"${all_cands[@]}"}" >&2 || true
	fi
	echo "" >&2
	echo "Repository-maintainer workflow:" >&2
	echo "  dots packages adopt ${raw} --group modern" >&2
	return 1
}

# Validate that a resolved selector is actually installable on the current platform.
# Rejects:
#   - direct package requests (DOTS_SEL_VIA_PKG set) when package has no installer here
#   - groups whose REQUIRED packages have no installer here
#   - components unsupported on current platform
# Sets DOTS_SEL_INSTALL_SUMMARY for display when group has optional unavailable packages.
dots_require_selector_installable() {
	DOTS_SEL_INSTALL_SUMMARY=""
	dots_require_python 0 || return 1
	local check_sel="${DOTS_SEL_OWNER}"
	if [[ -n ${DOTS_SEL_VIA_PKG:-} && ${DOTS_SEL_KIND:-} == "group" ]]; then
		# Query the exact package truth within the chosen group
		local pyhome out rc=0
		pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-inst.XXXXXX")"
		out="$(
			DOTS_DIR="${DIR}" \
				DOTS_GROUPS_REGISTRY="$(_dots_pe_groups_registry)" \
				DOTS_COMPONENTS_REGISTRY="$(_dots_pe_components_registry)" \
				TARGET_GROUP="${DOTS_SEL_ID}" \
				TARGET_PKG="${DOTS_SEL_VIA_PKG}" \
				HOME="${pyhome}" \
				PYTHONDONTWRITEBYTECODE=1 \
				PYTHONNOUSERSITE=1 \
				"${DOTS_PYTHON}" -B - <<'PY'
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(os.environ["DOTS_DIR"]) / "helpers"))
import package_truth as pt

root = Path(os.environ["DOTS_DIR"])
os_name, _, pkg_mgr = pt.detect_platform()
gdata = pt.compute_groups_data(root, None, os_name=os_name, pkg_mgr=pkg_mgr, probe_installed=False)
tgrp = os.environ["TARGET_GROUP"]
tpkg = os.environ["TARGET_PKG"]
short = tpkg.split("/")[-1]
grp = next((g for g in gdata["groups"] if g["name"] == tgrp), None)
if not grp:
    raise SystemExit(0)
groups_toml = pt._load_toml(pt._groups_registry_path(root))
aliases = {str(v).split("/")[-1]: str(k) for k, v in (groups_toml.get("brew_aliases") or {}).items()}
mapped = aliases.get(short, tpkg)
pkg = next((p for p in grp["packages"] if p["name"] in (tpkg, short, mapped) or (p.get("install_token") or "").split("/")[-1] == short), None)
if pkg is not None and not pkg["installable"]:
    print("ERR\t" + (
        f"{pkg['name']} is known to DOTS through group:{tgrp},\\n"
        f"but DOTS has no supported installer for {pkg['name']} on {os_name}.\\n\\n"
        f"Selecting group:{tgrp} is still valid, but this direct package request\\n"
        f"cannot be satisfied."
    ))
    raise SystemExit(2)
if not grp["platform_supported"]:
    print("ERR\t" + (
        f"group:{tgrp} requires {', '.join(grp['required_unsupported'])} which has no supported installer on {os_name}/{pkg_mgr}."
    ))
    raise SystemExit(2)
print(f"SUM\t{grp['supported_package_count']}/{grp['package_count']}\t{','.join(grp['unsupported_packages'])}")
PY
		)" || rc=$?
		rm -rf "${pyhome}"
		if [[ ${rc} -ne 0 ]]; then
			local msg="${out#ERR$'\t'}"
			printf 'ERROR:\n' >&2
			printf '%b\n' "${msg}" | sed 's/^/  /;s/^  $//' >&2
			return 1
		fi
		DOTS_SEL_INSTALL_SUMMARY="${out#SUM$'\t'}"
		return 0
	fi

	if [[ ${DOTS_SEL_KIND:-} == "group" ]]; then
		local pyhome out rc=0
		pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-inst.XXXXXX")"
		out="$(
			DOTS_DIR="${DIR}" \
				DOTS_GROUPS_REGISTRY="$(_dots_pe_groups_registry)" \
				DOTS_COMPONENTS_REGISTRY="$(_dots_pe_components_registry)" \
				TARGET_GROUP="${DOTS_SEL_ID}" \
				HOME="${pyhome}" \
				PYTHONDONTWRITEBYTECODE=1 \
				PYTHONNOUSERSITE=1 \
				"${DOTS_PYTHON}" -B - <<'PY'
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(os.environ["DOTS_DIR"]) / "helpers"))
import package_truth as pt

root = Path(os.environ["DOTS_DIR"])
os_name, _, pkg_mgr = pt.detect_platform()
gdata = pt.compute_groups_data(root, None, os_name=os_name, pkg_mgr=pkg_mgr, probe_installed=False)
tgrp = os.environ["TARGET_GROUP"]
grp = next((g for g in gdata["groups"] if g["name"] == tgrp), None)
if not grp:
    raise SystemExit(0)
if not grp["platform_supported"]:
    print("ERR\t" + (
        f"group:{tgrp} requires {', '.join(grp['required_unsupported'])}, which has no supported installer on {os_name}/{pkg_mgr}."
    ))
    raise SystemExit(2)
print(f"SUM\t{grp['supported_package_count']}/{grp['package_count']}\t{','.join(grp['unsupported_packages'])}")
PY
		)" || rc=$?
		rm -rf "${pyhome}"
		if [[ ${rc} -ne 0 ]]; then
			local msg="${out#ERR$'\t'}"
			printf 'ERROR:\n  %s\n' "${msg}" >&2
			return 1
		fi
		DOTS_SEL_INSTALL_SUMMARY="${out#SUM$'\t'}"
		return 0
	fi

	if [[ ${DOTS_SEL_KIND:-} == "package" ]]; then
		dots_require_python 0 || return 1
		local pyhome out rc=0
		pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-leaf.XXXXXX")"
		out="$(
			DOTS_DIR="${DIR}" \
				HOME="${pyhome}" \
				PYTHONDONTWRITEBYTECODE=1 \
				PYTHONNOUSERSITE=1 \
				"${DOTS_PYTHON}" -B - <<PY
import os, sys, json
from pathlib import Path
sys.path.insert(0, str(Path(os.environ["DOTS_DIR"]) / "helpers"))
import package_truth as pt
root = Path(os.environ["DOTS_DIR"])
meta = pt.find_package_meta(root, "${DOTS_SEL_ID}")
if not meta.get("installable"):
    print("ERR\t" + (meta.get("unsupported_reason") or "not installable"))
    raise SystemExit(2)
if not meta.get("leaf_selectable"):
    print("ERR\t" + (meta.get("leaf_reason") or "not leaf-selectable"))
    raise SystemExit(2)
print("OK")
PY
		)" || rc=$?
		rm -rf "${pyhome}"
		if [[ ${rc} -ne 0 ]]; then
			printf 'ERROR: %s\n' "${out#ERR$'\t'}" >&2
			return 1
		fi
		return 0
	fi

	return 0
}

# After selector resolution: --only persists package:ID; otherwise optional TTY menu for leaf packages.
dots_install_pick_owner_mode() {
	local only="${1:-0}" allow_prompt="${2:-0}" yes="${3:-0}"
	local raw="${DOTS_SEL_VIA_PKG:-}"
	[[ -n ${raw} || ${DOTS_SEL_KIND:-} == "package" ]] || return 0
	local canon="${raw:-${DOTS_SEL_ID}}"
	[[ -n ${canon} ]] || return 0

	local leaf owner_hint="${DOTS_SEL_OWNER:-}"
	local pyhome
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-leafpick.XXXXXX")"
	leaf="$(
		DOTS_DIR="${DIR}" \
			CANON="${canon}" \
			HOME="${pyhome}" \
			PYTHONDONTWRITEBYTECODE=1 \
			PYTHONNOUSERSITE=1 \
			"${DOTS_PYTHON}" -B - <<'PY'
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(os.environ["DOTS_DIR"]) / "helpers"))
import package_truth as pt

root = Path(os.environ["DOTS_DIR"])
out = pt.resolve_selector(root, os.environ["CANON"], None, probe_installed=False)
print("1" if out.get("leaf_selectable") else "0")
PY
	)" || {
		rm -rf "${pyhome}"
		return 1
	}
	rm -rf "${pyhome}"

	if [[ ${only} -eq 1 ]]; then
		if [[ ${leaf} != 1 ]]; then
			echo "Error: '${canon}' is not leaf-selectable on this platform; cannot use --only." >&2
			echo "Enable ${owner_hint} instead." >&2
			return 1
		fi
		DOTS_SEL_OWNER="package:${canon}"
		DOTS_SEL_KIND="package"
		DOTS_SEL_ID="${canon}"
		return 0
	fi

	[[ ${leaf} == 1 ]] || return 0

	# Non-interactive / --yes: keep group or component owner (legacy install hyperfine -> group:dev).
	if [[ ${only} -eq 0 ]] && { [[ ${allow_prompt} -eq 0 ]] || [[ ${yes} -eq 1 ]]; }; then
		return 0
	fi

	if [[ ${allow_prompt} -eq 1 ]] && { [[ -t 0 ]] || [[ -n ${DOTS_UI_ANSWERS:-} ]]; }; then
		[[ -z ${DOTS_UI_ANSWER_FD:-} ]] && dots_ui_load_answers
		echo ""
		echo "${canon} belongs to ${owner_hint}."
		echo "1) Install ${canon} only (explicit desired state)"
		echo "2) Enable full ${owner_hint}"
		echo "q) Cancel"
		local pick=""
		pick="$(dots_ui_read_line "Choose [1/2/q]" "1")" || return 1
		case "${pick}" in
		1 | "")
			DOTS_SEL_OWNER="package:${canon}"
			DOTS_SEL_KIND="package"
			DOTS_SEL_ID="${canon}"
			;;
		2) ;;
		q | Q)
			echo "Aborted."
			return 1
			;;
		*)
			echo "Invalid choice." >&2
			return 1
			;;
		esac
	fi
	return 0
}

# Print packages belonging to a group (one per line), using registry + Brewfile.
dots_pe_group_packages() {
	local gid="$1"
	dots_group_package_ids "${gid}" all 2>/dev/null || true
}

# Resolve target source profile and persistent overlay destination.
# Args: [explicit_profile] [allow_prompt=0]
# Sets:
#   DOTS_PE_SOURCE_FILE   resolved base/active profile file
#   DOTS_PE_SOURCE_NAME   resolved profile name
#   DOTS_PE_OVERLAY_FILE  writable DOTS-managed overlay file
#   DOTS_PE_OVERLAY_NAME  overlay profile name
#   DOTS_PE_EXTENDS_VAL   extends value for new/existing overlay
#   DOTS_PE_REUSE_EXISTING  1 if overlay already exists, 0 if new
dots_profile_edit_resolve_target() {
	local explicit="${1:-}" allow_prompt="${2:-0}"
	DOTS_PE_SOURCE_FILE=""
	DOTS_PE_SOURCE_NAME=""
	DOTS_PE_OVERLAY_FILE=""
	DOTS_PE_OVERLAY_NAME=""
	DOTS_PE_EXTENDS_VAL=""
	DOTS_PE_REUSE_EXISTING=0

	local chosen="${explicit}"
	if [[ -z ${chosen} ]]; then
		if dots_state_load_active 2>/dev/null; then
			chosen="${DOTS_ACTIVE_PROFILE_FILE:-${DOTS_ACTIVE_PROFILE:-}}"
		fi
	fi

	if [[ -z ${chosen} ]]; then
		if [[ ${allow_prompt} -eq 1 ]] && [[ ${DOTS_UI_NONINTERACTIVE:-0} -ne 1 ]] && { [[ -t 0 ]] || [[ -n ${DOTS_UI_ANSWERS:-} ]]; }; then
			[[ -z ${DOTS_UI_ANSWER_FD:-} ]] && dots_ui_load_answers
			echo "No active profile recorded." >&2
			local c
			DOTS_UI_CHOICE_DEFAULT=1
			c="$(dots_prompt_choice "Choose a base profile:" "home" "work" "server" "base" "all")" || return 1
			case "${c}" in
			1) chosen="home" ;;
			2) chosen="work" ;;
			3) chosen="server" ;;
			4) chosen="base" ;;
			5) chosen="all" ;;
			esac
		else
			echo "Error: no active profile recorded." >&2
			echo "Pass --profile NAME (e.g. --profile home) or run ./dots setup first." >&2
			return 1
		fi
	fi

	DOTS_PE_SOURCE_FILE="$(dots_resolve_profile_path "${chosen}")" || return 1
	local parsed line sname="" sext=""
	parsed="$(dots_profile_parse "${DOTS_PE_SOURCE_FILE}")" || return 1
	while IFS= read -r line; do
		case "${line}" in
		name:*) sname="${line#name:}" ;;
		extends:*) sext="${line#extends:}" ;;
		esac
	done <<<"${parsed}"
	[[ -z ${sname} ]] && sname="$(basename "${DOTS_PE_SOURCE_FILE}" .toml)"
	DOTS_PE_SOURCE_NAME="${sname}"

	local udir
	udir="$(dots_user_profiles_dir)"

	if dots_profile_is_builtin_path "${DOTS_PE_SOURCE_FILE}"; then
		DOTS_PE_OVERLAY_NAME="${sname}-local"
		DOTS_PE_OVERLAY_FILE="${udir}/${DOTS_PE_OVERLAY_NAME}.toml"
		DOTS_PE_EXTENDS_VAL="${sname}"
	elif dots_profile_is_managed_overlay "${DOTS_PE_SOURCE_FILE}"; then
		# Already a DOTS-managed overlay — edit in place (never -local-local)
		DOTS_PE_OVERLAY_NAME="${sname}"
		DOTS_PE_OVERLAY_FILE="${DOTS_PE_SOURCE_FILE}"
		DOTS_PE_EXTENDS_VAL="${sext}"
	else
		# User-authored custom profile: preserve byte-for-byte; use sparse overlay
		if [[ ${sname} == *-local ]]; then
			DOTS_PE_OVERLAY_NAME="${sname}-overlay"
		else
			DOTS_PE_OVERLAY_NAME="${sname}-local"
		fi
		DOTS_PE_OVERLAY_FILE="${udir}/${DOTS_PE_OVERLAY_NAME}.toml"
		if [[ "$(dirname "${DOTS_PE_SOURCE_FILE}")" == "${udir}" ]] &&
			[[ "$(basename "${DOTS_PE_SOURCE_FILE}" .toml)" == "${sname}" ]] &&
			! [[ -f "$(dots_builtin_profile_dir)/${sname}.toml" ]]; then
			DOTS_PE_EXTENDS_VAL="${sname}"
		else
			DOTS_PE_EXTENDS_VAL="${DOTS_PE_SOURCE_FILE}"
		fi
	fi

	if [[ -f ${DOTS_PE_OVERLAY_FILE} ]]; then
		DOTS_PE_REUSE_EXISTING=1
	fi
	return 0
}

# Compute sparse overlay update and diff without writing destination files.
# Args: action(add|remove) owner(kind:id) source_file overlay_file overlay_name extends_val out_toml out_diff
# Sets:
#   DOTS_PE_CHANGED  1 if overlay would change, 0 if NO_CHANGE
#   DOTS_PE_STATUS_MSG  short explanation when NO_CHANGE or summary
dots_profile_edit_compute() {
	local action="$1" owner="$2" source_file="$3" overlay_file="$4"
	local overlay_name="$5" extends_val="$6" out_toml="$7" out_diff="$8"
	DOTS_PE_CHANGED=0
	DOTS_PE_STATUS_MSG=""

	dots_require_python 0 || return 1
	local py="${DOTS_PYTHON}"
	local pyhome out rc=0
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-edit.XXXXXX")"
	out="$(
		ACTION="${action}" \
			OWNER="${owner}" \
			SOURCE_FILE="${source_file}" \
			OVERLAY_FILE="${overlay_file}" \
			OVERLAY_NAME="${overlay_name}" \
			EXTENDS_VAL="${extends_val}" \
			OUT_TOML="${out_toml}" \
			OUT_DIFF="${out_diff}" \
			BUILTIN_DIR="$(dots_builtin_profile_dir)" \
			USER_DIR="$(dots_user_profiles_dir)" \
			GROUPS_REG="$(_dots_pe_groups_registry)" \
			COMPS_REG="$(_dots_pe_components_registry)" \
			MARKER="${DOTS_OVERLAY_MARKER}" \
			DOTS_DIR="${DIR}" \
			HOME="${pyhome}" \
			PYTHONDONTWRITEBYTECODE=1 \
			PYTHONNOUSERSITE=1 \
			"${py}" -B <<'PY'
import os
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["DOTS_DIR"]) / "helpers"))
import profile_merge as pm
import package_truth as pt

action = os.environ["ACTION"]
owner = os.environ["OWNER"]
kind, item_id = owner.split(":", 1)
source_file = Path(os.environ["SOURCE_FILE"]).resolve()
overlay_file = Path(os.environ["OVERLAY_FILE"])
overlay_name = os.environ["OVERLAY_NAME"]
extends_val = os.environ["EXTENDS_VAL"]
out_toml = Path(os.environ["OUT_TOML"])
out_diff = Path(os.environ["OUT_DIFF"])
builtin_dir = Path(os.environ["BUILTIN_DIR"]).resolve()
user_dir = Path(os.environ["USER_DIR"])
groups_reg = Path(os.environ["GROUPS_REG"])
comps_reg = Path(os.environ["COMPS_REG"])
marker = os.environ["MARKER"]

comps_data = tomllib.loads(comps_reg.read_text(encoding="utf-8")) if comps_reg.is_file() else {}
supergroups = {}
for s in comps_data.get("supergroups") or []:
    sid = str(s.get("id") or "").strip()
    if sid:
        supergroups[sid] = [str(m).strip() for m in (s.get("members") or []) if str(m).strip()]

def resolve_extends_path(ext: str, from_path: Path) -> Path:
    ext = ext.strip()
    if ext.endswith(".toml") or "/" in ext or ext.startswith("~") or ext.startswith("."):
        p = Path(os.path.expanduser(ext))
        if not p.is_absolute():
            p = (from_path.parent / p).resolve()
        return p
    b = builtin_dir / f"{ext}.toml"
    if b.is_file():
        return b.resolve()
    u = user_dir / f"{ext}.toml"
    if u.is_file():
        return u.resolve()
    raise SystemExit(f"Error: unknown extends base '{ext}' in {from_path}")

def load_chain(leaf: Path):
    chain = []
    seen = set()
    cur = leaf.resolve()
    while True:
        k = str(cur)
        if k in seen:
            raise SystemExit(f"Error: inheritance loop at {cur}")
        seen.add(k)
        data = tomllib.loads(cur.read_text(encoding="utf-8"))
        chain.append((cur, data))
        ext = (data.get("profile") or {}).get("extends") or ""
        if not isinstance(ext, str) or not ext.strip():
            break
        cur = resolve_extends_path(ext, cur)
    chain.reverse()
    return chain

def str_list(val):
    if not val:
        return []
    return [str(x).strip() for x in val if str(x).strip()]

# Determine existing overlay data if overlay already exists and is reusable
use_existing_overlay = False
if overlay_file.is_file():
    existing_text = overlay_file.read_text(encoding="utf-8")
    if marker in existing_text or overlay_file.resolve() == source_file:
        use_existing_overlay = True
    else:
        raise SystemExit(
            f"Error: {overlay_file} already exists and is not a DOTS-managed overlay. "
            f"Pass --profile {overlay_file} explicitly or rename it."
        )

if use_existing_overlay:
    overlay_data = tomllib.loads(overlay_file.read_text(encoding="utf-8"))
    base_chain = load_chain(overlay_file)
else:
    overlay_data = {
        "profile": {
            "name": overlay_name,
            "extends": extends_val,
        }
    }
    base_chain = load_chain(source_file)

# Parent chain = base_chain excluding leaf if overlay exists, or full base_chain for new overlay
if use_existing_overlay:
    parent_chain = base_chain[:-1]
    eff_chain = base_chain
else:
    parent_chain = base_chain
    eff_chain = base_chain

eff = pm.effective_state(eff_chain, comps_data=comps_data, builtin_dir=builtin_dir)
if parent_chain:
    par = pm.effective_state(parent_chain, comps_data=comps_data, builtin_dir=builtin_dir)
else:
    par = {
        "groups": [],
        "with_raw": [],
        "without_raw": set(),
        "expanded_with": [],
        "pkg_include": [],
        "pkg_exclude": set(),
        "supergroups": eff["supergroups"],
    }
eff_pkgs, eff_with_raw, eff_without_raw, eff_with = (
    eff["groups"],
    eff["with_raw"],
    eff["without_raw"],
    eff["expanded_with"],
)
eff_pkg_inc = eff["pkg_include"]
par_pkgs = par["groups"]
par_pkg_inc = par["pkg_include"]
par_with = par["expanded_with"]
par_with_raw = par["with_raw"]
par_without_raw = par["without_raw"]
supergroups = eff["supergroups"]

# Extract editable overlay fields while preserving unrelated fields
prof_sec = dict(overlay_data.get("profile") or {})
pkg_sec = dict(overlay_data.get("packages") or {})
comp_sec = dict(overlay_data.get("components") or {})
rt_sec = dict(overlay_data.get("runtime") or {})

if not prof_sec.get("name"):
    prof_sec["name"] = overlay_name
if not prof_sec.get("extends") and extends_val:
    prof_sec["extends"] = extends_val

pkg_add = str_list(pkg_sec.get("add"))
pkg_remove = str_list(pkg_sec.get("remove"))
pkg_groups = str_list(pkg_sec.get("groups")) if pkg_sec.get("groups") is not None else None
pkg_include = str_list(pkg_sec.get("include"))
pkg_exclude = str_list(pkg_sec.get("exclude"))
prof_pkgs = str_list(prof_sec.get("packages")) if prof_sec.get("packages") is not None else None

prof_with = str_list(prof_sec.get("with"))
prof_without = str_list(prof_sec.get("without"))
comp_with = str_list(comp_sec.get("with"))
comp_without = str_list(comp_sec.get("without"))

def unique_add(lst, val):
    if val not in lst:
        lst.append(val)

def list_del(lst, val):
    return [x for x in lst if x != val]

diff_lines = []
changed = False

if kind == "group":
    if action == "add":
        if item_id in eff_pkgs:
            print("changed=0")
            print(f"msg=group:{item_id} is already desired. No profile change required.")
            sys.exit(0)
        changed = True
        if item_id in pkg_remove:
            pkg_remove = list_del(pkg_remove, item_id)
            diff_lines.append(f"- remove exclusion: group:{item_id}")
        if item_id not in par_pkgs:
            if prof_pkgs is not None:
                unique_add(prof_pkgs, item_id)
            elif pkg_groups is not None:
                unique_add(pkg_groups, item_id)
            else:
                unique_add(pkg_add, item_id)
            diff_lines.append(f"+ group:{item_id}")
        else:
            diff_lines.append(f"+ group:{item_id} (restored from parent)")
    elif action == "remove":
        if item_id not in eff_pkgs:
            print("changed=0")
            print(f"msg=group:{item_id} is not currently desired. No profile change required.")
            sys.exit(0)
        changed = True
        if item_id in pkg_add:
            pkg_add = list_del(pkg_add, item_id)
        if prof_pkgs is not None and item_id in prof_pkgs:
            prof_pkgs = list_del(prof_pkgs, item_id)
        if pkg_groups is not None and item_id in pkg_groups:
            pkg_groups = list_del(pkg_groups, item_id)
        if item_id in par_pkgs and prof_pkgs is None and pkg_groups is None:
            unique_add(pkg_remove, item_id)
        diff_lines.append(f"- group:{item_id}")

elif kind in ("component", "supergroup"):
    if action == "add":
        if kind == "component":
            already = item_id in eff_with
        else:
            members = supergroups.get(item_id, [])
            already = (item_id in eff_with_raw and item_id not in eff_without_raw) or (
                bool(members) and all(m in eff_with for m in members)
            )
        if already:
            print("changed=0")
            print(f"msg={kind}:{item_id} is already desired. No profile change required.")
            sys.exit(0)
        changed = True
        was_excluded = (item_id in prof_without) or (item_id in comp_without)
        prof_without = list_del(prof_without, item_id)
        comp_without = list_del(comp_without, item_id)
        if kind == "supergroup":
            for m in supergroups.get(item_id, []):
                prof_without = list_del(prof_without, m)
                comp_without = list_del(comp_without, m)
        if was_excluded:
            diff_lines.append(f"- remove exclusion: {kind}:{item_id}")
        # Determine if parent already provides it
        if kind == "component":
            parent_has = item_id in par_with
        else:
            members = supergroups.get(item_id, [])
            parent_has = (item_id in par_with_raw and item_id not in par_without_raw) or (
                bool(members) and all(m in par_with for m in members)
            )
        if not parent_has and item_id not in prof_with and item_id not in comp_with:
            unique_add(comp_with, item_id)
            diff_lines.append(f"+ {kind}:{item_id}")
    elif action == "remove":
        if kind == "component":
            present = (item_id in eff_with) or (item_id in prof_with) or (item_id in comp_with)
        else:
            members = supergroups.get(item_id, [])
            present = (item_id in eff_with_raw) or any(m in eff_with for m in members)
        if not present:
            print("changed=0")
            print(f"msg={kind}:{item_id} is not currently desired. No profile change required.")
            sys.exit(0)
        changed = True
        prof_with = list_del(prof_with, item_id)
        comp_with = list_del(comp_with, item_id)
        if kind == "supergroup":
            for m in supergroups.get(item_id, []):
                prof_with = list_del(prof_with, m)
                comp_with = list_del(comp_with, m)
        if kind == "component":
            parent_has = item_id in par_with
        else:
            members = supergroups.get(item_id, [])
            parent_has = (item_id in par_with_raw) or any(m in par_with for m in members)
        if parent_has and item_id not in prof_without and item_id not in comp_without:
            unique_add(comp_without, item_id)
        diff_lines.append(f"- {kind}:{item_id}")

elif kind == "package":
    root = Path(os.environ["DOTS_DIR"])
    known = pt.known_package_ids(root)
    canon = item_id.split("/")[-1]
    if canon not in known and item_id not in known:
        raise SystemExit(f"Error: unknown package id '{item_id}' (not in DOTS registry)")
    if action == "add":
        if canon in eff_pkg_inc:
            print("changed=0")
            print(f"msg=package:{canon} is already desired. No profile change required.")
            sys.exit(0)
        meta = pt.find_package_meta(root, canon)
        if not meta.get("installable"):
            raise SystemExit(
                f"Error: package '{canon}' is not installable on this platform "
                f"({meta.get('unsupported_reason') or 'no route'})"
            )
        if not meta.get("leaf_selectable"):
            raise SystemExit(
                f"Error: package '{canon}' cannot be selected independently "
                f"({meta.get('leaf_reason') or meta.get('owner')}). "
                f"Enable its owner capability instead."
            )
        changed = True
        if canon in pkg_exclude:
            pkg_exclude = list_del(pkg_exclude, canon)
            diff_lines.append(f"- remove exclusion: package:{canon}")
        if canon not in par_pkg_inc:
            unique_add(pkg_include, canon)
            diff_lines.append(f"+ package:{canon}")
        else:
            diff_lines.append(f"+ package:{canon} (restored from parent)")
    elif action == "remove":
        if canon not in eff_pkg_inc:
            print("changed=0")
            print(f"msg=package:{canon} is not in desired explicit packages. No profile change required.")
            sys.exit(0)
        changed = True
        pkg_include = list_del(pkg_include, canon)
        if canon in par_pkg_inc and canon not in pkg_exclude:
            unique_add(pkg_exclude, canon)
        diff_lines.append(f"- package:{canon}")
else:
    raise SystemExit(f"Error: unsupported owner kind '{kind}'")

def fmt_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, list):
        return "[" + ", ".join('"' + str(x).replace('"', '\\"') + '"' for x in v) + "]"
    s = str(v).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'

lines = [
    marker,
    "# Safe to edit via: dots profile ...",
    f"# Apply with: ./dots profile apply",
    "",
    "[profile]",
    f"name = {fmt_val(prof_sec['name'])}",
]
if prof_sec.get("extends"):
    lines.append(f"extends = {fmt_val(prof_sec['extends'])}")
if prof_sec.get("description"):
    lines.append(f"description = {fmt_val(prof_sec['description'])}")
if prof_sec.get("include_all_optional"):
    lines.append(f"include_all_optional = {fmt_val(bool(prof_sec['include_all_optional']))}")
if prof_pkgs is not None:
    lines.append(f"packages = {fmt_val(prof_pkgs)}")
if prof_with:
    lines.append(f"with = {fmt_val(prof_with)}")
if prof_without:
    lines.append(f"without = {fmt_val(prof_without)}")
if prof_sec.get("open_apps") is not None:
    lines.append(f"open_apps = {fmt_val(str_list(prof_sec.get('open_apps')))}")

need_pkg_tbl = bool(pkg_add or pkg_remove or pkg_groups is not None or pkg_include or pkg_exclude)
if need_pkg_tbl:
    lines.append("")
    lines.append("[packages]")
    if pkg_groups is not None:
        lines.append(f"groups = {fmt_val(pkg_groups)}")
    if pkg_add:
        lines.append(f"add = {fmt_val(pkg_add)}")
    if pkg_remove:
        lines.append(f"remove = {fmt_val(pkg_remove)}")
    if pkg_include:
        lines.append(f"include = {fmt_val(pkg_include)}")
    if pkg_exclude:
        lines.append(f"exclude = {fmt_val(pkg_exclude)}")

if comp_with or comp_without:
    lines.append("")
    lines.append("[components]")
    if comp_with:
        lines.append(f"with = {fmt_val(comp_with)}")
    if comp_without:
        lines.append(f"without = {fmt_val(comp_without)}")

if rt_sec:
    lines.append("")
    lines.append("[runtime]")
    for k in sorted(rt_sec.keys()):
        lines.append(f"{k} = {fmt_val(rt_sec[k])}")

out_toml.write_text("\n".join(lines) + "\n", encoding="utf-8")

diff_text = [
    f"Profile: {prof_sec['name']}",
]
if prof_sec.get("extends"):
    diff_text.append(f"Extends: {prof_sec['extends']}")
diff_text.append(f"Overlay: {overlay_file}")
for dl in diff_lines:
    diff_text.append(f"  {dl}")
out_diff.write_text("\n".join(diff_text) + "\n", encoding="utf-8")

print("changed=1" if changed else "changed=0")
print("msg=updated")
PY
	)" || rc=$?
	rm -rf "${pyhome}"
	[[ ${rc} -eq 0 ]] || return 1

	local line
	while IFS= read -r line; do
		case "${line}" in
		changed=*) DOTS_PE_CHANGED="${line#changed=}" ;;
		msg=*) DOTS_PE_STATUS_MSG="${line#msg=}" ;;
		esac
	done <<<"${out}"
	return 0
}

# Atomically persist active-profile pointer for a profile file without touching runtime.env.
dots_profile_write_active_marker() {
	local profile_file="$1"
	local dest_dir active tmp
	dest_dir="$(dots_config_dir)"
	active="$(dots_active_profile_file)"
	mkdir -p "${dest_dir}"

	local PROFILE_NAME="" PROFILE_DESC="" PROFILE_EXTENDS=""
	local -a PROFILE_CHAIN=() PROFILE_WITH=() PROFILE_WITHOUT=() PROFILE_WITH_RAW=() PROFILE_WITHOUT_RAW=()
	local -a PROFILE_OPEN_APPS=() PROFILE_PACKAGES=() EFFECTIVE_WITH=() CLI_WITH=() CLI_WITHOUT=()
	local PROFILE_RUNTIME_MULTIPLEXER="" PROFILE_RUNTIME_GREETING="" PROFILE_RUNTIME_PROMPT_STATS="" PROFILE_RUNTIME_AUTO_TMUX=""

	dots_load_profile_file "${profile_file}" >/dev/null || return 1
	dots_compute_effective_with >/dev/null 2>&1 || true

	tmp="$(mktemp "${dest_dir}/.active-profile.XXXXXX")"
	cat >"${tmp}" <<EOF
# Last bootstrap profile selection (non-secret).
# DOTS_LAST_WITH_INFO / DOTS_ACTIVE_COMPONENTS are INFORMATIONAL only —
# NOT configuration consent and MUST NOT auto-feed mutating AI setup.
# AI consent remains invocation-scoped via profile with / setup.sh --with
# for that run. Binary presence ≠ authorization.
# DOTS_ACTIVE_COMPONENTS mirrors LAST_WITH_INFO for read-only discovery
# (./dots packages, ./dots components); mutating setup still needs --with.
DOTS_PROFILE='${PROFILE_NAME:-unknown}'
DOTS_PROFILE_FILE='${profile_file}'
DOTS_PACKAGE_GROUPS='${PROFILE_PACKAGES[*]}'
DOTS_LAST_WITH_INFO='${EFFECTIVE_WITH[*]:-}'
DOTS_ACTIVE_COMPONENTS='${EFFECTIVE_WITH[*]:-}'
EOF
	mv -f "${tmp}" "${active}"
}

# Validate temp TOML, back up previous overlay if any, atomically rename, and activate marker.
# Args: overlay_file out_toml_tmp
dots_profile_edit_commit_atomic() {
	local overlay_file="$1" new_toml_tmp="$2"
	local odir stage_tmp bak_dir bak_file

	if dots_profile_is_builtin_path "${overlay_file}"; then
		echo "Error: refusing to modify builtin profile: ${overlay_file}" >&2
		return 1
	fi

	# Validate before touching destination
	dots_profile_parse "${new_toml_tmp}" >/dev/null || {
		echo "Error: generated overlay failed profile validation; aborted without write." >&2
		return 1
	}

	odir="$(dirname "${overlay_file}")"
	mkdir -p "${odir}"
	stage_tmp="$(mktemp "${odir}/.$(basename "${overlay_file}").XXXXXX")"
	cp "${new_toml_tmp}" "${stage_tmp}"

	if [[ -f ${overlay_file} ]]; then
		bak_dir="$(dots_state_dir)/profile-backups"
		mkdir -p "${bak_dir}"
		bak_file="${bak_dir}/$(basename "${overlay_file}" .toml)-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo bak).toml"
		cp -p "${overlay_file}" "${bak_file}" || {
			rm -f "${stage_tmp}"
			echo "Error: failed to back up existing overlay ${overlay_file}" >&2
			return 1
		}
	fi

	mv -f "${stage_tmp}" "${overlay_file}"
	dots_profile_write_active_marker "${overlay_file}" || return 1
	return 0
}

# Print read-only diff of a profile / overlay's local additions and removals.
dots_profile_show_diff() {
	local target="${1:-}"
	local file=""
	if [[ -n ${target} ]]; then
		file="$(dots_resolve_profile_path "${target}")" || return 1
	elif dots_state_load_active 2>/dev/null; then
		file="$(dots_resolve_profile_path "${DOTS_ACTIVE_PROFILE_FILE:-${DOTS_ACTIVE_PROFILE}}")" || return 1
	else
		echo "Error: no active profile recorded; pass profile name or path." >&2
		return 1
	fi

	dots_require_python 0 || return 1
	local py="${DOTS_PYTHON}"
	local pyhome rc=0
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-diff.XXXXXX")"
	FILE="${file}" COMPS_REG="$(_dots_pe_components_registry)" \
	HOME="${pyhome}" PYTHONDONTWRITEBYTECODE=1 PYTHONNOUSERSITE=1 \
		"${py}" -B <<'PY' || rc=$?
import os
import tomllib
from pathlib import Path

path = Path(os.environ["FILE"]).resolve()
comps_reg = Path(os.environ["COMPS_REG"])
data = tomllib.loads(path.read_text(encoding="utf-8"))
comps_data = tomllib.loads(comps_reg.read_text(encoding="utf-8")) if comps_reg.is_file() else {}
sg_ids = {str(s.get("id") or "").strip() for s in (comps_data.get("supergroups") or []) if s.get("id")}

prof = data.get("profile") or {}
pkg = data.get("packages") or {}
comp = data.get("components") or {}
rt = data.get("runtime") or {}

name = str(prof.get("name") or path.stem).strip()
ext = str(prof.get("extends") or "").strip()

def str_list(v):
    return [str(x).strip() for x in (v or []) if str(x).strip()]

adds = []
rems = []

for g in str_list(pkg.get("add")):
    adds.append(f"group:{g}")
if pkg.get("groups") is not None:
    adds.append("packages.groups=" + ",".join(str_list(pkg.get("groups"))))
if prof.get("packages") is not None and ext:
    adds.append("profile.packages=" + ",".join(str_list(prof.get("packages"))))
for g in str_list(pkg.get("remove")):
    rems.append(f"group:{g}")

for c in str_list(prof.get("with")) + str_list(comp.get("with")):
    kind = "supergroup" if c in sg_ids else "component"
    adds.append(f"{kind}:{c}")
for c in str_list(prof.get("without")) + str_list(comp.get("without")):
    kind = "supergroup" if c in sg_ids else "component"
    rems.append(f"{kind}:{c}")

print("Profile:")
print(f"  {name}")
print("")
print("Extends:")
print(f"  {ext or '(none — standalone)'}")
print("")
print("Source:")
print(f"  {path}")
print("")
print("Local additions:")
if adds:
    for a in adds:
        print(f"  + {a}")
else:
    print("  (none)")
print("")
print("Local removals:")
if rems:
    for r in rems:
        print(f"  - {r}")
else:
    print("  (none)")
if rt:
    print("")
    print("Runtime overrides:")
    for k in sorted(rt.keys()):
        print(f"  {k} = {rt[k]}")
PY
	rm -rf "${pyhome}"
	return "${rc}"
}

# SHA-256 hash of a file (portable via Python).
dots_profile_file_hash() {
	local file="$1"
	[[ -f ${file} ]] || return 1
	dots_require_python 0 || return 1
	"${DOTS_PYTHON}" -B - "$file" <<'PY'
import hashlib, sys
from pathlib import Path
print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
}

# Structured JSON owner resolution (non-mutating; reuses selector ownership model).
dots_profile_resolve_json() {
	local raw="$1"
	[[ -n ${raw} ]] || {
		echo '{"status":"error","error":"empty selector"}'
		return 1
	}
	dots_require_python 0 || return 1
	local pjson=""
	pjson="$(dots_profile_show_json "" 2>/dev/null || true)"
	local pyhome rc=0
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-rjson.XXXXXX")"
	PJSON="${pjson}" \
		DOTS_DIR="${DIR}" \
		DOTS_GROUPS_REGISTRY="$(_dots_pe_groups_registry)" \
		DOTS_COMPONENTS_REGISTRY="$(_dots_pe_components_registry)" \
		HOME="${pyhome}" \
		PYTHONDONTWRITEBYTECODE=1 \
		PYTHONNOUSERSITE=1 \
		"${DOTS_PYTHON}" -B "${DIR}/helpers/package_truth.py" resolve --selector "${raw}" || rc=$?
	rm -rf "${pyhome}"
	return "${rc}"
}

# Structured JSON representation of a profile (active or explicit).
# Output: schema_version=1 JSON with groups/components/supergroups selection states.
dots_profile_show_json() {
	local target="${1:-}"
	local file="" active_flag=1
	if [[ -n ${target} ]]; then
		file="$(dots_resolve_profile_path "${target}")" || return 1
	elif dots_state_load_active 2>/dev/null; then
		file="$(dots_resolve_profile_path "${DOTS_ACTIVE_PROFILE_FILE:-${DOTS_ACTIVE_PROFILE}}")" || return 1
	else
		active_flag=0
		file=""
	fi

	dots_require_python 0 || return 1
	local pyhome os_name darwin_major
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-sjson.XXXXXX")"
	os_name="$(dots_host_os)"
	darwin_major="$(dots_darwin_major)"
	FILE="${file}" \
		ACTIVE_FLAG="${active_flag}" \
		BUILTIN_DIR="$(dots_builtin_profile_dir)" \
		USER_DIR="$(dots_user_profile_dir)" \
		GROUPS_REG="$(_dots_pe_groups_registry)" \
		COMPS_REG="$(_dots_pe_components_registry)" \
		OS_NAME="${os_name}" \
		DARWIN_MAJOR="${darwin_major}" \
		MARKER="${DOTS_OVERLAY_MARKER}" \
		HOME="${pyhome}" \
		PYTHONDONTWRITEBYTECODE=1 \
		PYTHONNOUSERSITE=1 \
		"${DOTS_PYTHON}" -B <<'PY'
import hashlib, json, os, tomllib
from pathlib import Path

file_arg = os.environ.get("FILE", "").strip()
active_flag = os.environ.get("ACTIVE_FLAG", "0") == "1"
builtin_dir = Path(os.environ["BUILTIN_DIR"]).resolve()
user_dir = Path(os.environ["USER_DIR"])
groups_reg = Path(os.environ["GROUPS_REG"])
comps_reg = Path(os.environ["COMPS_REG"])
os_name = os.environ.get("OS_NAME", "unknown")
darwin_major = os.environ.get("DARWIN_MAJOR", "").strip()
marker = os.environ["MARKER"]

groups_data = tomllib.loads(groups_reg.read_text(encoding="utf-8")) if groups_reg.is_file() else {}
comps_data = tomllib.loads(comps_reg.read_text(encoding="utf-8")) if comps_reg.is_file() else {}

all_groups = [str(g.get("name") or "").strip() for g in (groups_data.get("groups") or []) if g.get("name")]
all_comps = list(comps_data.get("components") or [])
all_sgs = list(comps_data.get("supergroups") or [])
supergroups = {
    str(s.get("id") or "").strip(): [str(m).strip() for m in (s.get("members") or []) if str(m).strip()]
    for s in all_sgs if s.get("id")
}

def comp_supported(c):
    plats = [str(p).strip().lower() for p in (c.get("platforms") or ["darwin", "linux"])]
    if os_name not in plats:
        reason = "macOS only" if plats == ["darwin"] else f"unsupported on {os_name}"
        return False, reason
    if os_name == "darwin" and c.get("min_darwin") is not None:
        try:
            need = int(str(c["min_darwin"]).split(".")[0])
            have = int(darwin_major) if darwin_major else 0
        except ValueError:
            return False, f"requires macOS {c['min_darwin']}+"
        if have < need:
            return False, f"requires macOS {c['min_darwin']}+ (host {darwin_major or '?'})"
    return True, ""

def resolve_extends_path(ext: str, from_path: Path) -> Path:
    ext = ext.strip()
    if ext.endswith(".toml") or "/" in ext or ext.startswith("~") or ext.startswith("."):
        p = Path(os.path.expanduser(ext))
        if not p.is_absolute():
            p = (from_path.parent / p).resolve()
        return p
    b = builtin_dir / f"{ext}.toml"
    if b.is_file():
        return b.resolve()
    u = user_dir / f"{ext}.toml"
    if u.is_file():
        return u.resolve()
    raise SystemExit(f"Error: unknown extends base '{ext}' in {from_path}")

def load_chain(leaf: Path):
    chain = []
    seen = set()
    cur = leaf.resolve()
    while True:
        k = str(cur)
        if k in seen:
            raise SystemExit(f"Error: inheritance loop at {cur}")
        seen.add(k)
        data = tomllib.loads(cur.read_text(encoding="utf-8"))
        chain.append((cur, data))
        ext = (data.get("profile") or {}).get("extends") or ""
        if not isinstance(ext, str) or not ext.strip():
            break
        cur = resolve_extends_path(ext, cur)
    chain.reverse()
    return chain

def str_list(v):
    return [str(x).strip() for x in (v or []) if str(x).strip()]

def resolve_state(chain):
    pkgs = []
    pkg_include = []
    pkg_exclude = set()
    with_raw = []
    without_raw = set()
    include_all = False
    pkg_explicit = False
    prof_name = ""
    runtime = {}
    for _p, data in chain:
        prof = data.get("profile") or {}
        if prof.get("name"):
            prof_name = str(prof["name"]).strip()
        if prof.get("include_all_optional"):
            include_all = True
        if "packages" in prof and prof["packages"] is not None:
            pkgs = str_list(prof["packages"])
            pkg_explicit = True
        ptbl = data.get("packages") or {}
        for g in str_list(ptbl.get("add")):
            if g not in pkgs:
                pkgs.append(g)
            pkg_explicit = True
        for g in str_list(ptbl.get("remove")):
            pkgs = [x for x in pkgs if x != g]
            pkg_explicit = True
        if "groups" in ptbl and ptbl["groups"] is not None:
            pkgs = str_list(ptbl["groups"])
            pkg_explicit = True
        for p in str_list(ptbl.get("include")):
            if p not in pkg_exclude and p not in pkg_include:
                pkg_include.append(p)
        for p in str_list(ptbl.get("exclude")):
            pkg_exclude.add(p)
            pkg_include = [x for x in pkg_include if x != p]
        for w in str_list(prof.get("with")):
            if w not in with_raw:
                with_raw.append(w)
        for o in str_list(prof.get("without")):
            without_raw.add(o)
        ctbl = data.get("components") or {}
        for w in str_list(ctbl.get("with")):
            if w not in with_raw:
                with_raw.append(w)
        for o in str_list(ctbl.get("without")):
            without_raw.add(o)
        rt = data.get("runtime") or {}
        for k, v in rt.items():
            runtime[k] = v

    if include_all:
        for c in all_comps:
            cid = str(c.get("id") or "").strip()
            if cid and not c.get("omit_from_all") and cid not in with_raw:
                with_raw.append(cid)

    if not pkg_explicit and prof_name:
        fb = builtin_dir / f"{prof_name}.toml"
        if fb.is_file():
            fb_data = tomllib.loads(fb.read_text(encoding="utf-8"))
            pkgs = str_list((fb_data.get("profile") or {}).get("packages"))
    if not pkg_explicit and not pkgs:
        pkgs = ["core", "modern"]

    mux = str(runtime.get("multiplexer") or "").strip()
    if not mux:
        mux = "herdr" if prof_name == "home" else "tmux"
    runtime["multiplexer"] = mux
    if mux == "herdr" and "herdr" not in without_raw and "herdr" not in with_raw:
        with_raw.append("herdr")

    exp_without = set()
    for o in without_raw:
        if o in supergroups:
            exp_without.update(supergroups[o])
        else:
            exp_without.add(o)

    exp_with = []
    for w in with_raw:
        for m in supergroups.get(w, [w]):
            if m not in exp_without and m not in exp_with:
                exp_with.append(m)

    eff_inc = [p for p in pkg_include if p not in pkg_exclude]
    return (
        set(pkgs),
        set(with_raw),
        without_raw,
        set(exp_with),
        exp_without,
        runtime,
        set(eff_inc),
        pkg_exclude,
    )

def profile_kind(p: Path) -> str:
    try:
        if p.resolve().parent == builtin_dir:
            return "builtin"
    except Exception:
        pass
    try:
        if marker in p.read_text(encoding="utf-8"):
            return "overlay"
    except Exception:
        pass
    return "custom"

if not file_arg:
    groups_map = {g: {"state": "absent"} for g in all_groups}
    comps_map = {}
    for c in all_comps:
        cid = str(c.get("id") or "").strip()
        sup, reason = comp_supported(c)
        comps_map[cid] = {
            "state": "absent" if sup else "unsupported",
            "supported": sup,
            "unsupported_reason": reason,
        }
    sgs_map = {}
    for s in all_sgs:
        sid = str(s.get("id") or "").strip()
        members = supergroups.get(sid, [])
        sup_members = [m for m in members if comps_map.get(m, {}).get("supported", True)]
        sgs_map[sid] = {"state": "absent", "members": members, "supported_members": sup_members}
    print(json.dumps({
        "schema_version": 1,
        "active": False,
        "profile": None,
        "profile_file": None,
        "profile_kind": None,
        "profile_hash": None,
        "extends": None,
        "source_chain": [],
        "runtime": {"multiplexer": "tmux"},
        "groups": groups_map,
        "components": comps_map,
        "supergroups": sgs_map,
        "explicit_packages": {},
        "local_additions": {"groups": [], "components": [], "supergroups": [], "packages": []},
        "local_removals": {"groups": [], "components": [], "supergroups": [], "packages": []},
    }, indent=2))
    raise SystemExit(0)

leaf_path = Path(file_arg).resolve()
chain = load_chain(leaf_path)
leaf_prof = chain[-1][1].get("profile") or {}
leaf_pkg = chain[-1][1].get("packages") or {}
leaf_comp = chain[-1][1].get("components") or {}

prof_name = str(leaf_prof.get("name") or leaf_path.stem).strip()
ext_val = str(leaf_prof.get("extends") or "").strip() or None
pkind = profile_kind(leaf_path)
phash = hashlib.sha256(leaf_path.read_bytes()).hexdigest()

(
    eff_pkgs,
    eff_wraw,
    eff_oraw,
    eff_with,
    eff_without,
    runtime,
    eff_pkg_inc,
    eff_pkg_exc,
) = resolve_state(chain)
if len(chain) > 1:
    (
        par_pkgs,
        par_wraw,
        par_oraw,
        par_with,
        par_without,
        _rt,
        par_pkg_inc,
        par_pkg_exc,
    ) = resolve_state(chain[:-1])
else:
    if pkind == "builtin":
        par_pkgs, par_wraw, par_oraw, par_with, par_without = (eff_pkgs, eff_wraw, eff_oraw, eff_with, eff_without)
        par_pkg_inc, par_pkg_exc = (eff_pkg_inc, eff_pkg_exc)
    else:
        par_pkgs, par_wraw, par_oraw, par_with, par_without = (set(), set(), set(), set(), set())
        par_pkg_inc, par_pkg_exc = (set(), set())

leaf_pkg_remove = set(str_list(leaf_pkg.get("remove")))
leaf_pkg_exclude = set(str_list(leaf_pkg.get("exclude")))
leaf_comp_without = set(str_list(leaf_prof.get("without")) + str_list(leaf_comp.get("without")))

groups_map = {}
for g in all_groups:
    if g in eff_pkgs:
        st = "inherited" if g in par_pkgs else "local"
    elif g in par_pkgs or g in leaf_pkg_remove:
        st = "excluded"
    else:
        st = "absent"
    groups_map[g] = {"state": st}

comps_map = {}
for c in all_comps:
    cid = str(c.get("id") or "").strip()
    sup, reason = comp_supported(c)
    if not sup:
        st = "unsupported"
    elif cid in eff_with:
        st = "inherited" if cid in par_with else "local"
    elif cid in par_with or cid in leaf_comp_without or cid in eff_without:
        st = "excluded"
    else:
        st = "absent"
    comps_map[cid] = {
        "state": st,
        "supported": sup,
        "unsupported_reason": reason,
    }

sgs_map = {}
for s in all_sgs:
    sid = str(s.get("id") or "").strip()
    members = supergroups.get(sid, [])
    sup_members = [m for m in members if comps_map.get(m, {}).get("supported", True)]
    in_eff = (sid in eff_wraw and sid not in eff_oraw) or (bool(sup_members) and all(m in eff_with for m in sup_members))
    in_par = (sid in par_wraw and sid not in par_oraw) or (bool(sup_members) and all(m in par_with for m in sup_members))
    if in_eff:
        st = "inherited" if in_par else "local"
    elif in_par or sid in leaf_comp_without or sid in eff_oraw:
        st = "excluded"
    else:
        st = "absent"
    sgs_map[sid] = {
        "state": st,
        "members": members,
        "supported_members": sup_members,
    }

source_chain = []
for cp, cd in chain:
    cp_prof = cd.get("profile") or {}
    source_chain.append({
        "name": str(cp_prof.get("name") or cp.stem).strip(),
        "file": str(cp),
        "kind": profile_kind(cp),
    })

loc_add_groups = [g for g in all_groups if groups_map[g]["state"] == "local"]
loc_rem_groups = [g for g in all_groups if groups_map[g]["state"] == "excluded"]
loc_add_comps = [c for c, v in comps_map.items() if v["state"] == "local"]
loc_rem_comps = [c for c, v in comps_map.items() if v["state"] == "excluded"]
loc_add_sgs = [s for s, v in sgs_map.items() if v["state"] == "local"]
loc_rem_sgs = [s for s, v in sgs_map.items() if v["state"] == "excluded"]

explicit_map = {}
all_explicit = eff_pkg_inc | par_pkg_inc | eff_pkg_exc | par_pkg_exc
for pid in sorted(all_explicit):
    if pid in eff_pkg_exc:
        st = "excluded"
    elif pid in eff_pkg_inc:
        st = "inherited" if pid in par_pkg_inc else "local"
    elif pid in par_pkg_inc and pid in leaf_pkg_exclude:
        st = "excluded"
    elif pid in par_pkg_inc:
        st = "inherited"
    else:
        st = "absent"
    explicit_map[pid] = {"state": st}
loc_add_pkgs = [p for p, v in explicit_map.items() if v["state"] == "local"]
loc_rem_pkgs = [p for p, v in explicit_map.items() if v["state"] == "excluded"]

print(json.dumps({
    "schema_version": 1,
    "active": active_flag,
    "profile": prof_name,
    "profile_file": str(leaf_path),
    "profile_kind": pkind,
    "profile_hash": phash,
    "extends": ext_val,
    "source_chain": source_chain,
    "runtime": runtime,
    "groups": groups_map,
    "components": comps_map,
    "supergroups": sgs_map,
    "explicit_packages": explicit_map,
    "local_additions": {
        "groups": loc_add_groups,
        "components": loc_add_comps,
        "supergroups": loc_add_sgs,
        "packages": loc_add_pkgs,
    },
    "local_removals": {
        "groups": loc_rem_groups,
        "components": loc_rem_comps,
        "supergroups": loc_rem_sgs,
        "packages": loc_rem_pkgs,
    },
}, indent=2))
PY
	local rc=$?
	rm -rf "${pyhome}"
	return "${rc}"
}

# Compute batch sparse overlay update and diff without writing destination files.
# Args: source_file overlay_file overlay_name extends_val adds_nl removes_nl out_toml out_diff
dots_profile_edit_compute_batch() {
	local source_file="$1" overlay_file="$2" overlay_name="$3" extends_val="$4"
	local adds_nl="$5" removes_nl="$6" out_toml="$7" out_diff="$8"
	DOTS_PE_CHANGED=0
	DOTS_PE_STATUS_MSG=""

	dots_require_python 0 || return 1
	local pyhome out rc=0
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-batch.XXXXXX")"
	out="$(
		ADDS_NL="${adds_nl}" \
			REMOVES_NL="${removes_nl}" \
			SOURCE_FILE="${source_file}" \
			OVERLAY_FILE="${overlay_file}" \
			OVERLAY_NAME="${overlay_name}" \
			EXTENDS_VAL="${extends_val}" \
			OUT_TOML="${out_toml}" \
			OUT_DIFF="${out_diff}" \
			BUILTIN_DIR="$(dots_builtin_profile_dir)" \
			USER_DIR="$(dots_user_profiles_dir)" \
			GROUPS_REG="$(_dots_pe_groups_registry)" \
			COMPS_REG="$(_dots_pe_components_registry)" \
			MARKER="${DOTS_OVERLAY_MARKER}" \
			HOME="${pyhome}" \
			PYTHONDONTWRITEBYTECODE=1 \
			PYTHONNOUSERSITE=1 \
			"${DOTS_PYTHON}" -B <<'PY'
import os, sys, tomllib
from pathlib import Path

adds_raw = [x.strip() for x in os.environ.get("ADDS_NL", "").splitlines() if x.strip()]
rems_raw = [x.strip() for x in os.environ.get("REMOVES_NL", "").splitlines() if x.strip()]
source_file = Path(os.environ["SOURCE_FILE"]).resolve()
overlay_file = Path(os.environ["OVERLAY_FILE"])
overlay_name = os.environ["OVERLAY_NAME"]
extends_val = os.environ["EXTENDS_VAL"]
out_toml = Path(os.environ["OUT_TOML"])
out_diff = Path(os.environ["OUT_DIFF"])
builtin_dir = Path(os.environ["BUILTIN_DIR"]).resolve()
user_dir = Path(os.environ["USER_DIR"])
comps_reg = Path(os.environ["COMPS_REG"])
marker = os.environ["MARKER"]

comps_data = tomllib.loads(comps_reg.read_text(encoding="utf-8")) if comps_reg.is_file() else {}
supergroups = {}
for s in comps_data.get("supergroups") or []:
    sid = str(s.get("id") or "").strip()
    if sid:
        supergroups[sid] = [str(m).strip() for m in (s.get("members") or []) if str(m).strip()]

def resolve_extends_path(ext: str, from_path: Path) -> Path:
    ext = ext.strip()
    if ext.endswith(".toml") or "/" in ext or ext.startswith("~") or ext.startswith("."):
        p = Path(os.path.expanduser(ext))
        if not p.is_absolute():
            p = (from_path.parent / p).resolve()
        return p
    b = builtin_dir / f"{ext}.toml"
    if b.is_file():
        return b.resolve()
    u = user_dir / f"{ext}.toml"
    if u.is_file():
        return u.resolve()
    raise SystemExit(f"Error: unknown extends base '{ext}' in {from_path}")

def load_chain(leaf: Path):
    chain = []
    seen = set()
    cur = leaf.resolve()
    while True:
        k = str(cur)
        if k in seen:
            raise SystemExit(f"Error: inheritance loop at {cur}")
        seen.add(k)
        data = tomllib.loads(cur.read_text(encoding="utf-8"))
        chain.append((cur, data))
        ext = (data.get("profile") or {}).get("extends") or ""
        if not isinstance(ext, str) or not ext.strip():
            break
        cur = resolve_extends_path(ext, cur)
    chain.reverse()
    return chain

def str_list(val):
    if not val:
        return []
    return [str(x).strip() for x in val if str(x).strip()]

def effective_state(chain):
    pkgs = []
    with_raw = []
    without_raw = set()
    include_all = False
    pkg_explicit = False
    prof_name = ""
    for _p, data in chain:
        prof = data.get("profile") or {}
        if prof.get("name"):
            prof_name = str(prof["name"]).strip()
        if prof.get("include_all_optional"):
            include_all = True
        if "packages" in prof and prof["packages"] is not None:
            pkgs = str_list(prof["packages"])
            pkg_explicit = True
        ptbl = data.get("packages") or {}
        for g in str_list(ptbl.get("add")):
            if g not in pkgs:
                pkgs.append(g)
            pkg_explicit = True
        for g in str_list(ptbl.get("remove")):
            pkgs = [x for x in pkgs if x != g]
            pkg_explicit = True
        if "groups" in ptbl and ptbl["groups"] is not None:
            pkgs = str_list(ptbl["groups"])
            pkg_explicit = True
        for w in str_list(prof.get("with")):
            if w not in with_raw:
                with_raw.append(w)
        for o in str_list(prof.get("without")):
            without_raw.add(o)
        ctbl = data.get("components") or {}
        for w in str_list(ctbl.get("with")):
            if w not in with_raw:
                with_raw.append(w)
        for o in str_list(ctbl.get("without")):
            without_raw.add(o)

    if include_all:
        for c in comps_data.get("components") or []:
            cid = str(c.get("id") or "").strip()
            if cid and not c.get("omit_from_all") and cid not in with_raw:
                with_raw.append(cid)

    if not pkg_explicit and prof_name:
        fb = builtin_dir / f"{prof_name}.toml"
        if fb.is_file():
            fb_data = tomllib.loads(fb.read_text(encoding="utf-8"))
            pkgs = str_list((fb_data.get("profile") or {}).get("packages"))
    if not pkg_explicit and not pkgs:
        pkgs = ["core", "modern"]

    expanded_without = set()
    for o in without_raw:
        if o in supergroups:
            expanded_without.update(supergroups[o])
        else:
            expanded_without.add(o)

    expanded_with = []
    for w in with_raw:
        for m in supergroups.get(w, [w]):
            if m not in expanded_without and m not in expanded_with:
                expanded_with.append(m)

    return pkgs, with_raw, without_raw, expanded_with

use_existing_overlay = False
if overlay_file.is_file():
    existing_text = overlay_file.read_text(encoding="utf-8")
    if marker in existing_text or overlay_file.resolve() == source_file:
        use_existing_overlay = True
    else:
        raise SystemExit(
            f"Error: {overlay_file} already exists and is not a DOTS-managed overlay."
        )

if use_existing_overlay:
    overlay_data = tomllib.loads(overlay_file.read_text(encoding="utf-8"))
    base_chain = load_chain(overlay_file)
    parent_chain = base_chain[:-1]
    eff_chain = base_chain
else:
    overlay_data = {"profile": {"name": overlay_name, "extends": extends_val}}
    base_chain = load_chain(source_file)
    parent_chain = base_chain
    eff_chain = base_chain

eff_pkgs, eff_with_raw, eff_without_raw, eff_with = effective_state(eff_chain)
if parent_chain:
    par_pkgs, par_with_raw, par_without_raw, par_with = effective_state(parent_chain)
else:
    par_pkgs, par_with_raw, par_without_raw, par_with = ([], [], set(), [])

prof_sec = dict(overlay_data.get("profile") or {})
pkg_sec = dict(overlay_data.get("packages") or {})
comp_sec = dict(overlay_data.get("components") or {})
rt_sec = dict(overlay_data.get("runtime") or {})

if not prof_sec.get("name"):
    prof_sec["name"] = overlay_name
if not prof_sec.get("extends") and extends_val:
    prof_sec["extends"] = extends_val

pkg_add = str_list(pkg_sec.get("add"))
pkg_remove = str_list(pkg_sec.get("remove"))
pkg_groups = str_list(pkg_sec.get("groups")) if pkg_sec.get("groups") is not None else None
prof_pkgs = str_list(prof_sec.get("packages")) if prof_sec.get("packages") is not None else None

prof_with = str_list(prof_sec.get("with"))
prof_without = str_list(prof_sec.get("without"))
comp_with = str_list(comp_sec.get("with"))
comp_without = str_list(comp_sec.get("without"))

def unique_add(lst, val):
    if val not in lst:
        lst.append(val)

def list_del(lst, val):
    return [x for x in lst if x != val]

diff_lines = []
changed = False

def cur_overlay_state():
    # Compute current state from parent_chain + mutated overlay dict
    cur_data = {
        "profile": {
            "name": prof_sec.get("name"),
            "extends": prof_sec.get("extends"),
            "with": list(prof_with),
            "without": list(prof_without),
        },
        "packages": {
            "add": list(pkg_add),
            "remove": list(pkg_remove),
        },
        "components": {
            "with": list(comp_with),
            "without": list(comp_without),
        },
    }
    if prof_pkgs is not None:
        cur_data["profile"]["packages"] = list(prof_pkgs)
    if pkg_groups is not None:
        cur_data["packages"]["groups"] = list(pkg_groups)
    return effective_state(parent_chain + [(overlay_file, cur_data)])

for owner in adds_raw:
    kind, item_id = owner.split(":", 1)
    c_pkgs, c_wraw, c_oraw, c_with = cur_overlay_state()
    if kind == "group":
        if item_id in c_pkgs:
            continue
        changed = True
        if item_id in pkg_remove:
            pkg_remove = list_del(pkg_remove, item_id)
            diff_lines.append(f"- remove exclusion: group:{item_id}")
        if item_id not in par_pkgs:
            if prof_pkgs is not None:
                unique_add(prof_pkgs, item_id)
            elif pkg_groups is not None:
                unique_add(pkg_groups, item_id)
            else:
                unique_add(pkg_add, item_id)
            diff_lines.append(f"+ group:{item_id}")
        else:
            diff_lines.append(f"+ group:{item_id} (restored from parent)")
    elif kind in ("component", "supergroup"):
        if kind == "component":
            already = item_id in c_with
        else:
            members = supergroups.get(item_id, [])
            already = (item_id in c_wraw and item_id not in c_oraw) or (bool(members) and all(m in c_with for m in members))
        if already:
            continue
        changed = True
        was_excl = (item_id in prof_without) or (item_id in comp_without)
        prof_without = list_del(prof_without, item_id)
        comp_without = list_del(comp_without, item_id)
        if kind == "supergroup":
            for m in supergroups.get(item_id, []):
                prof_without = list_del(prof_without, m)
                comp_without = list_del(comp_without, m)
        if was_excl:
            diff_lines.append(f"- remove exclusion: {kind}:{item_id}")
        if kind == "component":
            parent_has = item_id in par_with
        else:
            members = supergroups.get(item_id, [])
            parent_has = (item_id in par_wraw and item_id not in par_oraw) or (bool(members) and all(m in par_with for m in members))
        if not parent_has and item_id not in prof_with and item_id not in comp_with:
            unique_add(comp_with, item_id)
            diff_lines.append(f"+ {kind}:{item_id}")

for owner in rems_raw:
    kind, item_id = owner.split(":", 1)
    c_pkgs, c_wraw, c_oraw, c_with = cur_overlay_state()
    if kind == "group":
        if item_id not in c_pkgs:
            continue
        changed = True
        if item_id in pkg_add:
            pkg_add = list_del(pkg_add, item_id)
        if prof_pkgs is not None and item_id in prof_pkgs:
            prof_pkgs = list_del(prof_pkgs, item_id)
        if pkg_groups is not None and item_id in pkg_groups:
            pkg_groups = list_del(pkg_groups, item_id)
        if item_id in par_pkgs and prof_pkgs is None and pkg_groups is None:
            unique_add(pkg_remove, item_id)
        diff_lines.append(f"- group:{item_id}")
    elif kind in ("component", "supergroup"):
        if kind == "component":
            present = (item_id in c_with) or (item_id in prof_with) or (item_id in comp_with)
        else:
            members = supergroups.get(item_id, [])
            present = (item_id in c_wraw) or any(m in c_with for m in members)
        if not present:
            continue
        changed = True
        prof_with = list_del(prof_with, item_id)
        comp_with = list_del(comp_with, item_id)
        if kind == "supergroup":
            for m in supergroups.get(item_id, []):
                prof_with = list_del(prof_with, m)
                comp_with = list_del(comp_with, m)
        if kind == "component":
            parent_has = item_id in par_with
        else:
            members = supergroups.get(item_id, [])
            parent_has = (item_id in par_wraw) or any(m in par_with for m in members)
        if parent_has and item_id not in prof_without and item_id not in comp_without:
            unique_add(comp_without, item_id)
        diff_lines.append(f"- {kind}:{item_id}")

if not changed:
    print("changed=0")
    print("msg=No profile change required.")
    sys.exit(0)

def fmt_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, list):
        return "[" + ", ".join('"' + str(x).replace('"', '\\"') + '"' for x in v) + "]"
    s = str(v).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'

lines = [
    marker,
    "# Safe to edit via: dots profile ...",
    "# Apply with: ./dots profile apply",
    "",
    "[profile]",
    f"name = {fmt_val(prof_sec['name'])}",
]
if prof_sec.get("extends"):
    lines.append(f"extends = {fmt_val(prof_sec['extends'])}")
if prof_sec.get("description"):
    lines.append(f"description = {fmt_val(prof_sec['description'])}")
if prof_sec.get("include_all_optional"):
    lines.append(f"include_all_optional = {fmt_val(bool(prof_sec['include_all_optional']))}")
if prof_pkgs is not None:
    lines.append(f"packages = {fmt_val(prof_pkgs)}")
if prof_with:
    lines.append(f"with = {fmt_val(prof_with)}")
if prof_without:
    lines.append(f"without = {fmt_val(prof_without)}")
if prof_sec.get("open_apps") is not None:
    lines.append(f"open_apps = {fmt_val(str_list(prof_sec.get('open_apps')))}")

if pkg_add or pkg_remove or pkg_groups is not None:
    lines.append("")
    lines.append("[packages]")
    if pkg_groups is not None:
        lines.append(f"groups = {fmt_val(pkg_groups)}")
    if pkg_add:
        lines.append(f"add = {fmt_val(pkg_add)}")
    if pkg_remove:
        lines.append(f"remove = {fmt_val(pkg_remove)}")

if comp_with or comp_without:
    lines.append("")
    lines.append("[components]")
    if comp_with:
        lines.append(f"with = {fmt_val(comp_with)}")
    if comp_without:
        lines.append(f"without = {fmt_val(comp_without)}")

if rt_sec:
    lines.append("")
    lines.append("[runtime]")
    for k in sorted(rt_sec.keys()):
        lines.append(f"{k} = {fmt_val(rt_sec[k])}")

out_toml.write_text("\n".join(lines) + "\n", encoding="utf-8")

diff_text = [f"Profile: {prof_sec['name']}"]
if prof_sec.get("extends"):
    diff_text.append(f"Extends: {prof_sec['extends']}")
diff_text.append(f"Overlay: {overlay_file}")
for dl in diff_lines:
    diff_text.append(f"  {dl}")
out_diff.write_text("\n".join(diff_text) + "\n", encoding="utf-8")

print("changed=1")
print("msg=updated")
PY
	)" || rc=$?
	rm -rf "${pyhome}"
	[[ ${rc} -eq 0 ]] || return 1

	local line
	while IFS= read -r line; do
		case "${line}" in
		changed=*) DOTS_PE_CHANGED="${line#changed=}" ;;
		msg=*) DOTS_PE_STATUS_MSG="${line#msg=}" ;;
		esac
	done <<<"${out}"
	return 0
}

# Structured JSON plan for proposed --add / --remove selectors (non-mutating).
# Args: profile_arg adds_nl removes_nl
dots_profile_plan_json() {
	local profile_arg="${1:-}" adds_nl="${2:-}" removes_nl="${3:-}"
	local target_ok=1
	if ! dots_profile_edit_resolve_target "${profile_arg}" 0 2>/dev/null; then
		# If no active profile, preview against base
		DOTS_PE_SOURCE_FILE="$(dots_resolve_profile_path base)" || return 1
		DOTS_PE_SOURCE_NAME="base"
		DOTS_PE_OVERLAY_NAME="base-local"
		DOTS_PE_OVERLAY_FILE="$(dots_user_profiles_dir)/base-local.toml"
		DOTS_PE_EXTENDS_VAL="base"
		target_ok=0
	fi

	local tmp_toml tmp_diff
	tmp_toml="$(mktemp "${TMPDIR:-/tmp}/dots-plan-toml.XXXXXX")"
	tmp_diff="$(mktemp "${TMPDIR:-/tmp}/dots-plan-diff.XXXXXX")"
	if ! dots_profile_edit_compute_batch "${DOTS_PE_SOURCE_FILE}" "${DOTS_PE_OVERLAY_FILE}" \
		"${DOTS_PE_OVERLAY_NAME}" "${DOTS_PE_EXTENDS_VAL}" \
		"${adds_nl}" "${removes_nl}" "${tmp_toml}" "${tmp_diff}"; then
		rm -f "${tmp_toml}" "${tmp_diff}"
		return 1
	fi

	# Cheap installed lists (only when brew or mock env is available; never outdated)
	local inst_f="" inst_c=""
	if command -v "${DOTS_BREW_BIN:-brew}" >/dev/null 2>&1 || [[ -n ${DOTS_PKG_MOCK_FORMULAE+x} || -n ${DOTS_PKG_MOCK_CASKS+x} ]]; then
		inst_f="$(dots_pkg_installed_formulae 2>/dev/null || true)"
		inst_c="$(dots_pkg_installed_casks 2>/dev/null || true)"
	fi

	local pyhome os_name darwin_major rc=0
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-pjson.XXXXXX")"
	os_name="$(dots_host_os)"
	darwin_major="$(dots_darwin_major)"
	SOURCE_FILE="${DOTS_PE_SOURCE_FILE}" \
		OVERLAY_FILE="${DOTS_PE_OVERLAY_FILE}" \
		OVERLAY_NAME="${DOTS_PE_OVERLAY_NAME}" \
		NEW_TOML="${tmp_toml}" \
		CHANGED="${DOTS_PE_CHANGED}" \
		ADDS_NL="${adds_nl}" \
		REMOVES_NL="${removes_nl}" \
		TARGET_OK="${target_ok}" \
		REPO_DIR="${DIR}" \
		BUILTIN_DIR="$(dots_builtin_profile_dir)" \
		USER_DIR="$(dots_user_profiles_dir)" \
		GROUPS_REG="$(_dots_pe_groups_registry)" \
		COMPS_REG="$(_dots_pe_components_registry)" \
		OS_NAME="${os_name}" \
		DARWIN_MAJOR="${darwin_major}" \
		INST_F="${inst_f}" \
		INST_C="${inst_c}" \
		HOME="${pyhome}" \
		PYTHONDONTWRITEBYTECODE=1 \
		PYTHONNOUSERSITE=1 \
		"${DOTS_PYTHON}" -B <<'PY' || rc=$?
import json, os, re, tomllib
from pathlib import Path

source_file = Path(os.environ["SOURCE_FILE"]).resolve()
overlay_file = Path(os.environ["OVERLAY_FILE"])
overlay_name = os.environ["OVERLAY_NAME"]
new_toml = Path(os.environ["NEW_TOML"])
changed = os.environ.get("CHANGED", "0") == "1"
adds_raw = [x.strip() for x in os.environ.get("ADDS_NL", "").splitlines() if x.strip()]
rems_raw = [x.strip() for x in os.environ.get("REMOVES_NL", "").splitlines() if x.strip()]
repo = Path(os.environ["REPO_DIR"])
builtin_dir = Path(os.environ["BUILTIN_DIR"]).resolve()
user_dir = Path(os.environ["USER_DIR"])
groups_reg = Path(os.environ["GROUPS_REG"])
comps_reg = Path(os.environ["COMPS_REG"])
os_name = os.environ.get("OS_NAME", "unknown")
darwin_major = os.environ.get("DARWIN_MAJOR", "").strip()
inst_f = {x.strip().split("/")[-1] for x in os.environ.get("INST_F", "").splitlines() if x.strip()}
inst_c = {x.strip().split("/")[-1] for x in os.environ.get("INST_C", "").splitlines() if x.strip()}

groups_data = tomllib.loads(groups_reg.read_text(encoding="utf-8")) if groups_reg.is_file() else {}
comps_data = tomllib.loads(comps_reg.read_text(encoding="utf-8")) if comps_reg.is_file() else {}
supergroups = {
    str(s.get("id") or "").strip(): [str(m).strip() for m in (s.get("members") or []) if str(m).strip()]
    for s in (comps_data.get("supergroups") or []) if s.get("id")
}
comps_by_id = {str(c.get("id") or "").strip(): c for c in (comps_data.get("components") or []) if c.get("id")}

def comp_supported(cid):
    c = comps_by_id.get(cid)
    if not c:
        return False, "unknown"
    plats = [str(p).strip().lower() for p in (c.get("platforms") or ["darwin", "linux"])]
    if os_name not in plats:
        return False, ("macOS only" if plats == ["darwin"] else f"unsupported on {os_name}")
    if os_name == "darwin" and c.get("min_darwin") is not None:
        try:
            need = int(str(c["min_darwin"]).split(".")[0])
            have = int(darwin_major) if darwin_major else 0
        except ValueError:
            return False, f"requires macOS {c['min_darwin']}+"
        if have < need:
            return False, f"requires macOS {c['min_darwin']}+"
    return True, ""

def resolve_extends_path(ext: str, from_path: Path) -> Path:
    ext = ext.strip()
    if ext.endswith(".toml") or "/" in ext or ext.startswith("~") or ext.startswith("."):
        p = Path(os.path.expanduser(ext))
        if not p.is_absolute():
            p = (from_path.parent / p).resolve()
        return p
    b = builtin_dir / f"{ext}.toml"
    if b.is_file():
        return b.resolve()
    u = user_dir / f"{ext}.toml"
    if u.is_file():
        return u.resolve()
    return source_file

def load_chain(leaf: Path):
    chain, seen, cur = [], set(), leaf.resolve()
    while True:
        k = str(cur)
        if k in seen:
            break
        seen.add(k)
        data = tomllib.loads(cur.read_text(encoding="utf-8"))
        chain.append((cur, data))
        ext = (data.get("profile") or {}).get("extends") or ""
        if not isinstance(ext, str) or not ext.strip():
            break
        cur = resolve_extends_path(ext, cur)
    chain.reverse()
    return chain

def str_list(v):
    return [str(x).strip() for x in (v or []) if str(x).strip()]

def resolve_pkgs_and_comps(chain):
    pkgs, wraw, oraw, include_all, pkg_explicit, pname = [], [], set(), False, False, ""
    for _p, data in chain:
        prof = data.get("profile") or {}
        if prof.get("name"):
            pname = str(prof["name"]).strip()
        if prof.get("include_all_optional"):
            include_all = True
        if "packages" in prof and prof["packages"] is not None:
            pkgs = str_list(prof["packages"])
            pkg_explicit = True
        ptbl = data.get("packages") or {}
        for g in str_list(ptbl.get("add")):
            if g not in pkgs:
                pkgs.append(g)
            pkg_explicit = True
        for g in str_list(ptbl.get("remove")):
            pkgs = [x for x in pkgs if x != g]
            pkg_explicit = True
        if "groups" in ptbl and ptbl["groups"] is not None:
            pkgs = str_list(ptbl["groups"])
            pkg_explicit = True
        for w in str_list(prof.get("with")):
            if w not in wraw:
                wraw.append(w)
        for o in str_list(prof.get("without")):
            oraw.add(o)
        ctbl = data.get("components") or {}
        for w in str_list(ctbl.get("with")):
            if w not in wraw:
                wraw.append(w)
        for o in str_list(ctbl.get("without")):
            oraw.add(o)
    if include_all:
        for cid, c in comps_by_id.items():
            if not c.get("omit_from_all") and cid not in wraw:
                wraw.append(cid)
    if not pkg_explicit and pname:
        fb = builtin_dir / f"{pname}.toml"
        if fb.is_file():
            pkgs = str_list((tomllib.loads(fb.read_text(encoding="utf-8")).get("profile") or {}).get("packages"))
    if not pkg_explicit and not pkgs:
        pkgs = ["core", "modern"]
    exp_without = set()
    for o in oraw:
        exp_without.update(supergroups.get(o, [o]))
    exp_with = []
    for w in wraw:
        for m in supergroups.get(w, [w]):
            if m not in exp_without and m not in exp_with:
                exp_with.append(m)
    return pkgs, exp_with

def brewfile_tokens(bf: Path):
    f_list, c_list = [], []
    if not bf.is_file():
        return f_list, c_list
    for line in bf.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        m = re.match(r'^brew\s+"([^"]+)"', line)
        if m:
            f_list.append(m.group(1).strip())
            continue
        m = re.match(r'^cask\s+"([^"]+)"', line)
        if m:
            c_list.append(m.group(1).strip())
    return f_list, c_list

def desired_tokens(groups_list, comps_list):
    seen_f, seen_c = set(), set()
    out_f, out_c = [], []
    for g in groups_list:
        bf = repo / "brew" / "groups" / f"{g}.Brewfile"
        fl, cl = brewfile_tokens(bf)
        if not bf.is_file():
            for grp in (groups_data.get("groups") or []):
                if grp.get("name") == g:
                    fl.extend(str_list(grp.get("required")) + str_list(grp.get("optional")))
        for x in fl:
            if x not in seen_f:
                seen_f.add(x)
                out_f.append(x)
        for x in cl:
            if x not in seen_c:
                seen_c.add(x)
                out_c.append(x)
    for cid in comps_list:
        sup, _ = comp_supported(cid)
        if not sup:
            continue
        bf_rel = str((comps_by_id.get(cid) or {}).get("brewfile") or "").strip()
        if bf_rel:
            fl, cl = brewfile_tokens(repo / bf_rel)
            for x in fl:
                if x not in seen_f:
                    seen_f.add(x)
                    out_f.append(x)
            for x in cl:
                if x not in seen_c:
                    seen_c.add(x)
                    out_c.append(x)
    return out_f, out_c

before_chain = load_chain(overlay_file if overlay_file.is_file() else source_file)
if changed and new_toml.is_file() and new_toml.stat().st_size > 0:
    # Build after chain by replacing leaf with parsed new_toml
    new_data = tomllib.loads(new_toml.read_text(encoding="utf-8"))
    if overlay_file.is_file():
        after_chain = before_chain[:-1] + [(overlay_file, new_data)]
    else:
        after_chain = before_chain + [(overlay_file, new_data)]
else:
    after_chain = before_chain

b_groups, b_comps = resolve_pkgs_and_comps(before_chain)
a_groups, a_comps = resolve_pkgs_and_comps(after_chain)

bf_before, bc_before = desired_tokens(b_groups, b_comps)
bf_after, bc_after = desired_tokens(a_groups, a_comps)

b_all = set(bf_before) | set(bc_before)
a_all = set(bf_after) | set(bc_after)

newly_desired = sorted(a_all - b_all)
no_longer_desired = sorted(b_all - a_all)

already_satisfied = []
to_install = []
for tok in newly_desired:
    short = tok.split("/")[-1]
    if tok in bf_after and (short in inst_f):
        already_satisfied.append(tok)
    elif tok in bc_after and (short in inst_c):
        already_satisfied.append(tok)
    else:
        to_install.append(tok)

unsupported = []
comps_to_cfg = []
for cid in a_comps:
    sup, reason = comp_supported(cid)
    if not sup:
        unsupported.append({"id": cid, "reason": reason})
    elif cid not in b_comps:
        comps_to_cfg.append(cid)

delta = {
    "add_groups": [x.split(":", 1)[1] for x in adds_raw if x.startswith("group:")],
    "remove_groups": [x.split(":", 1)[1] for x in rems_raw if x.startswith("group:")],
    "add_components": [x.split(":", 1)[1] for x in adds_raw if x.startswith("component:")],
    "remove_components": [x.split(":", 1)[1] for x in rems_raw if x.startswith("component:")],
    "add_supergroups": [x.split(":", 1)[1] for x in adds_raw if x.startswith("supergroup:")],
    "remove_supergroups": [x.split(":", 1)[1] for x in rems_raw if x.startswith("supergroup:")],
}

print(json.dumps({
    "schema_version": 1,
    "target_profile": source_file.stem,
    "overlay_name": overlay_name,
    "overlay_file": str(overlay_file),
    "changed": changed,
    "delta": delta,
    "newly_desired_packages": newly_desired,
    "no_longer_desired_packages": no_longer_desired,
    "already_satisfied_packages": already_satisfied,
    "packages_to_install": to_install,
    "unsupported": unsupported,
    "components_to_configure": comps_to_cfg,
    "no_uninstall_note": "Installed packages are not automatically removed.",
}, indent=2))
PY
	rm -rf "${pyhome}" "${tmp_toml}" "${tmp_diff}"
	return "${rc}"
}

# Structured JSON output for `dots components list --json [--profile NAME]`.
dots_components_list_json() {
	local profile_arg="${1:-}"
	local pjson=""
	pjson="$(dots_profile_show_json "${profile_arg}")" || return 1

	dots_require_python 0 || return 1
	local pyhome os_name darwin_major rc=0
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-cjson.XXXXXX")"
	os_name="$(dots_host_os)"
	darwin_major="$(dots_darwin_major)"
	PJSON="${pjson}" \
		REPO_DIR="${DIR}" \
		COMPS_REG="$(_dots_pe_components_registry)" \
		OS_NAME="${os_name}" \
		DARWIN_MAJOR="${darwin_major}" \
		HOME="${pyhome}" \
		PYTHONDONTWRITEBYTECODE=1 \
		PYTHONNOUSERSITE=1 \
		"${DOTS_PYTHON}" -B <<'PY' || rc=$?
import json, os, re, tomllib
from pathlib import Path

pstate = json.loads(os.environ["PJSON"])
repo = Path(os.environ["REPO_DIR"])
comps_reg = Path(os.environ["COMPS_REG"])
os_name = os.environ.get("OS_NAME", "unknown")
darwin_major = os.environ.get("DARWIN_MAJOR", "").strip()
comps_data = tomllib.loads(comps_reg.read_text(encoding="utf-8")) if comps_reg.is_file() else {}

comp_states = pstate.get("components") or {}
sg_states = pstate.get("supergroups") or {}

def parse_bf(rel):
    f, c = [], []
    if not rel:
        return f, c
    p = repo / rel
    if not p.is_file():
        return f, c
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        m = re.match(r'^brew\s+"([^"]+)"', line)
        if m:
            f.append(m.group(1).strip())
            continue
        m = re.match(r'^cask\s+"([^"]+)"', line)
        if m:
            c.append(m.group(1).strip())
    return f, c

def comp_supported(c):
    plats = [str(p).strip().lower() for p in (c.get("platforms") or ["darwin", "linux"])]
    if os_name not in plats:
        return False, ("macOS only" if plats == ["darwin"] else f"unsupported on {os_name}")
    if os_name == "darwin" and c.get("min_darwin") is not None:
        try:
            need = int(str(c["min_darwin"]).split(".")[0])
            have = int(darwin_major) if darwin_major else 0
        except ValueError:
            return False, f"requires macOS {c['min_darwin']}+"
        if have < need:
            return False, f"requires macOS {c['min_darwin']}+ (host {darwin_major or '?'})"
    return True, ""

comps_out = []
for c in comps_data.get("components") or []:
    cid = str(c.get("id") or "").strip()
    if not cid:
        continue
    sup, reason = comp_supported(c)
    bf = str(c.get("brewfile") or "").strip()
    formulae, casks = parse_bf(bf)
    st = (comp_states.get(cid) or {}).get("state") or ("absent" if sup else "unsupported")
    comps_out.append({
        "id": cid,
        "label": str(c.get("label") or cid),
        "category": str(c.get("category") or "other"),
        "description": str(c.get("description") or ""),
        "platforms": list(c.get("platforms") or ["darwin", "linux"]),
        "min_darwin": c.get("min_darwin"),
        "omit_from_all": bool(c.get("omit_from_all", False)),
        "cloud": bool(c.get("cloud", False)),
        "local_ai": bool(c.get("local_ai", False)),
        "brewfile": bf,
        "formulae": formulae,
        "casks": casks,
        "supported_on_current_platform": sup,
        "unsupported_reason": reason,
        "selected_state": st,
    })

sgs_out = []
for s in comps_data.get("supergroups") or []:
    sid = str(s.get("id") or "").strip()
    if not sid:
        continue
    members = [str(m).strip() for m in (s.get("members") or []) if str(m).strip()]
    sup_members = [c["id"] for c in comps_out if c["id"] in members and c["supported_on_current_platform"]]
    st = (sg_states.get(sid) or {}).get("state") or "absent"
    sgs_out.append({
        "id": sid,
        "label": str(s.get("label") or sid),
        "description": str(s.get("description") or ""),
        "members": members,
        "supported_members": sup_members,
        "selected_state": st,
    })

print(json.dumps({
    "schema_version": 1,
    "profile": pstate.get("profile"),
    "os": os_name,
    "components": comps_out,
    "supergroups": sgs_out,
}, indent=2))
PY
	rm -rf "${pyhome}"
	return "${rc}"
}

# Structured JSON output for `dots packages groups --json [--profile NAME]`.
dots_packages_groups_json() {
	local profile_arg="${1:-}"
	local pjson=""
	pjson="$(dots_profile_show_json "${profile_arg}")" || return 1

	# Cheap installed formula/cask check if brew/mocks available (never brew outdated)
	local inst_f="" inst_c="" have_brew_lists=0
	if [[ -n ${DOTS_PKG_MOCK_FORMULAE+x} || -n ${DOTS_PKG_MOCK_CASKS+x} ]]; then
		have_brew_lists=1
		inst_f="$(dots_pkg_installed_formulae 2>/dev/null || true)"
		inst_c="$(dots_pkg_installed_casks 2>/dev/null || true)"
	elif [[ ${DOTS_FORCE_OS:-} != "linux" && -z ${DOTS_FORCE_PKG_MGR:-} ]] || [[ ${DOTS_FORCE_PKG_MGR:-} == "brew" ]]; then
		if command -v "${DOTS_BREW_BIN:-brew}" >/dev/null 2>&1; then
			have_brew_lists=1
			inst_f="$(dots_pkg_installed_formulae 2>/dev/null || true)"
			inst_c="$(dots_pkg_installed_casks 2>/dev/null || true)"
		fi
	fi

	dots_require_python 0 || return 1
	local pyhome rc=0
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-gjson.XXXXXX")"
	if [[ ${have_brew_lists} -eq 1 ]]; then
		PJSON="${pjson}" \
			DOTS_DIR="${DIR}" \
			DOTS_GROUPS_REGISTRY="$(_dots_pe_groups_registry)" \
			DOTS_COMPONENTS_REGISTRY="$(_dots_pe_components_registry)" \
			INST_F="${inst_f}" \
			INST_C="${inst_c}" \
			HOME="${pyhome}" \
			PYTHONDONTWRITEBYTECODE=1 \
			PYTHONNOUSERSITE=1 \
			"${DOTS_PYTHON}" -B "${DIR}/helpers/package_truth.py" groups-json || rc=$?
	else
		PJSON="${pjson}" \
			DOTS_DIR="${DIR}" \
			DOTS_GROUPS_REGISTRY="$(_dots_pe_groups_registry)" \
			DOTS_COMPONENTS_REGISTRY="$(_dots_pe_components_registry)" \
			HOME="${pyhome}" \
			PYTHONDONTWRITEBYTECODE=1 \
			PYTHONNOUSERSITE=1 \
			"${DOTS_PYTHON}" -B "${DIR}/helpers/package_truth.py" groups-json || rc=$?
	fi
	rm -rf "${pyhome}"
	return "${rc}"
}

# Structured JSON list of builtin + user profiles (non-mutating).
dots_profile_list_json() {
	dots_require_python 0 || return 1
	local active_file=""
	if dots_state_load_active 2>/dev/null; then
		active_file="${DOTS_ACTIVE_PROFILE_FILE:-}"
	fi
	local pyhome rc=0
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pe-ljson.XXXXXX")"
	BUILTIN_DIR="$(dots_builtin_profile_dir)" \
	USER_DIR="$(dots_user_profiles_dir)" \
	ACTIVE_FILE="${active_file}" \
	MARKER="${DOTS_OVERLAY_MARKER}" \
	HOME="${pyhome}" \
	PYTHONDONTWRITEBYTECODE=1 \
	PYTHONNOUSERSITE=1 \
		"${DOTS_PYTHON}" -B <<'PY' || rc=$?
import json, os, tomllib
from pathlib import Path

builtin_dir = Path(os.environ["BUILTIN_DIR"]).resolve()
user_dir = Path(os.environ["USER_DIR"])
active_raw = os.environ.get("ACTIVE_FILE", "").strip()
active_res = str(Path(active_raw).resolve()) if active_raw and Path(active_raw).exists() else ""
marker = os.environ["MARKER"]

profiles = []
if builtin_dir.is_dir():
    for p in sorted(builtin_dir.glob("*.toml")):
        try:
            d = tomllib.loads(p.read_text(encoding="utf-8"))
        except Exception:
            d = {}
        prof = d.get("profile") or {}
        profiles.append({
            "name": str(prof.get("name") or p.stem).strip(),
            "file": str(p.resolve()),
            "kind": "builtin",
            "extends": None,
            "description": str(prof.get("description") or "").strip(),
            "active": str(p.resolve()) == active_res,
        })

if user_dir.is_dir():
    for p in sorted(user_dir.glob("*.toml")):
        try:
            text = p.read_text(encoding="utf-8")
            d = tomllib.loads(text)
        except Exception:
            text = ""
            d = {}
        prof = d.get("profile") or {}
        kind = "overlay" if marker in text else "custom"
        ext = str(prof.get("extends") or "").strip() or None
        profiles.append({
            "name": str(prof.get("name") or p.stem).strip(),
            "file": str(p.resolve()),
            "kind": kind,
            "extends": ext,
            "description": str(prof.get("description") or "").strip(),
            "active": str(p.resolve()) == active_res,
        })

print(json.dumps({"schema_version": 1, "profiles": profiles}, indent=2))
PY
	rm -rf "${pyhome}"
	return "${rc}"
}
