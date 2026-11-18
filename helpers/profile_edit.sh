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
    for cls in ("required", "optional", "tools"):
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
			HOME="${pyhome}" \
			PYTHONDONTWRITEBYTECODE=1 \
			PYTHONNOUSERSITE=1 \
			"${py}" -B <<'PY'
import os
import sys
import tomllib
from pathlib import Path

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
        members = supergroups.get(w, [w])
        for m in members:
            if m not in expanded_without and m not in expanded_with:
                expanded_with.append(m)

    return pkgs, with_raw, without_raw, expanded_with

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

eff_pkgs, eff_with_raw, eff_without_raw, eff_with = effective_state(eff_chain)
if parent_chain:
    par_pkgs, par_with_raw, par_without_raw, par_with = effective_state(parent_chain)
else:
    par_pkgs, par_with_raw, par_without_raw, par_with = ([], [], set(), [])

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
