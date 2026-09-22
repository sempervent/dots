# shellcheck shell=bash
# helpers/profiles.sh — declarative bootstrap profile load / resolve / show
#
# Profiles are data only (TOML). Never execute profile contents.
# Requires: DIR, helpers/components.sh (dots_component_*), helpers/toml.sh
#
# Inheritance:
#   [profile] extends = "server"   # builtin name or relative/absolute path
# Merge (child wins for scalars; packages/components are additive with remove/without):
#   repository defaults < builtin base < extends chain < leaf profile < CLI --with/--without
#
# Custom profiles live under ~/.config/dots/profiles/ (explicit path preferred).
# Builtin names never silently resolve to user-owned files (no name-shadowing).

dots_builtin_profile_dir() {
	printf '%s\n' "${DIR}/configs/bootstrap/profiles"
}

dots_user_profile_dir() {
	printf '%s\n' "${HOME}/.config/dots/profiles"
}

# Resolve --profile argument to an absolute TOML path.
# Recognizes: builtin name, user profile name (non-builtin only), path, ~/path, *.toml
dots_resolve_profile_path() {
	local arg="$1"
	local builtin_dir user_dir path
	builtin_dir="$(dots_builtin_profile_dir)"
	user_dir="$(dots_user_profile_dir)"

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
		if [[ ! -r ${path} ]]; then
			echo "Error: profile file not readable: ${path}" >&2
			return 1
		fi
		printf '%s\n' "${path}"
		return 0
	fi

	# Builtin name (never shadowed by ~/.config/dots/profiles/<name>.toml)
	path="${builtin_dir}/${arg}.toml"
	if [[ -f ${path} ]]; then
		printf '%s\n' "${path}"
		return 0
	fi

	# Non-builtin short name → user profiles dir only (explicit; no silent override of builtins)
	path="${user_dir}/${arg}.toml"
	if [[ -f ${path} ]]; then
		printf '%s\n' "${path}"
		return 0
	fi

	echo "Error: unknown profile '${arg}' (missing ${builtin_dir}/${arg}.toml)" >&2
	echo "Available builtins:" >&2
	ls -1 "${builtin_dir}"/*.toml 2>/dev/null | xargs -n1 basename | sed 's/\.toml$//' >&2 || true
	echo "Or pass a custom TOML path: --profile ${user_dir}/name.toml" >&2
	return 1
}

# Load profile TOML (with extends) → print lines for dots_load_profile_file.
# Emits: name:, desc:, extends:, chain:, with:, without:, open:, all:, pkg:, runtime.*, error:
dots_profile_parse() {
	local file="$1"
	local builtin_dir
	builtin_dir="$(dots_builtin_profile_dir)"
	dots_require_python 0 || return 1
	if [[ ! -f ${file} ]]; then
		echo "Error: profile file not found: ${file}" >&2
		return 1
	fi
	if [[ ! -r ${file} ]]; then
		echo "Error: profile file not readable: ${file}" >&2
		return 1
	fi

	local pyhome rc=0
	local bin="${DOTS_PYTHON}"
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pyhome.XXXXXX")"
	FILE="${file}" BUILTIN_DIR="${builtin_dir}" USER_DIR="$(dots_user_profile_dir)" \
	DOTS_GROUPS_REGISTRY="${DOTS_GROUPS_REGISTRY:-}" \
	HOME="${pyhome}" \
	PYTHONDONTWRITEBYTECODE=1 \
	PYTHONNOUSERSITE=1 \
		"${bin}" -B <<'PY' || rc=$?
import os, sys
from pathlib import Path
import tomllib

file = Path(os.environ["FILE"]).resolve()
builtin_dir = Path(os.environ["BUILTIN_DIR"]).resolve()
user_dir = Path(os.environ.get("USER_DIR", "")).expanduser()

ALLOWED_TOP = {"profile", "runtime", "packages", "components"}
ALLOWED_PROFILE = {
    "name", "description", "extends", "with", "without", "packages",
    "open_apps", "include_all_optional",
}
ALLOWED_RUNTIME = {"multiplexer", "greeting", "prompt_stats", "auto_tmux"}
ALLOWED_PACKAGES = {"add", "remove", "groups"}
ALLOWED_COMPONENTS = {"with", "without"}
KNOWN_MUX = {"tmux", "herdr", "none"}

# Load package group ids from registry (configs/packages/groups.toml).
# Override: DOTS_GROUPS_REGISTRY (tests).
KNOWN_GROUPS = set()
_groups_env = os.environ.get("DOTS_GROUPS_REGISTRY", "").strip()
groups_reg = Path(_groups_env) if _groups_env else (builtin_dir.parent.parent / "packages" / "groups.toml")
if groups_reg.is_file():
    try:
        gdata = tomllib.loads(groups_reg.read_text(encoding="utf-8"))
        for g in gdata.get("groups") or []:
            gid = str(g.get("name") or "").strip()
            if gid:
                KNOWN_GROUPS.add(gid)
    except Exception:
        pass
if not KNOWN_GROUPS:
    fail("package group registry unreadable: %s" % groups_reg)

# Load component + supergroup ids from registry (configs/components.toml)
known_components = set()
known_selectors = set()
reg = builtin_dir.parent.parent / "components.toml"
if reg.is_file():
    try:
        rdata = tomllib.loads(reg.read_text(encoding="utf-8"))
        for c in rdata.get("components") or []:
            cid = (c.get("id") or "").strip()
            if cid:
                known_components.add(cid)
                known_selectors.add(cid)
        for g in rdata.get("supergroups") or []:
            gid = (g.get("id") or "").strip()
            if gid:
                known_selectors.add(gid)
    except Exception:
        pass


def fail(msg: str) -> None:
    sys.stderr.write("Error: %s\n" % msg)
    sys.exit(1)


def load_toml(path: Path) -> dict:
    if not path.is_file():
        fail("profile file not found: %s" % path)
    if not os.access(path, os.R_OK):
        fail("profile file not readable: %s" % path)
    try:
        return tomllib.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail("malformed TOML (%s): %s" % (path, exc))


def validate_keys(data: dict, path: Path) -> None:
    for k in data:
        if k not in ALLOWED_TOP:
            fail("unknown top-level key '%s' in %s (allowed: %s)" % (
                k, path, ", ".join(sorted(ALLOWED_TOP))))
    prof = data.get("profile") or {}
    if not isinstance(prof, dict):
        fail("[profile] must be a table in %s" % path)
    for k in prof:
        if k not in ALLOWED_PROFILE:
            fail("unknown profile key '%s' in %s" % (k, path))
    runtime = data.get("runtime") or {}
    if runtime and not isinstance(runtime, dict):
        fail("[runtime] must be a table in %s" % path)
    for k in runtime:
        if k not in ALLOWED_RUNTIME:
            fail("unknown runtime key '%s' in %s" % (k, path))
    packages = data.get("packages") or {}
    if packages and not isinstance(packages, dict):
        fail("[packages] must be a table in %s" % path)
    for k in packages:
        if k not in ALLOWED_PACKAGES:
            fail("unknown packages key '%s' in %s" % (k, path))
    comps = data.get("components") or {}
    if comps and not isinstance(comps, dict):
        fail("[components] must be a table in %s" % path)
    for k in comps:
        if k not in ALLOWED_COMPONENTS:
            fail("unknown components key '%s' in %s" % (k, path))


def resolve_extends_path(extends: str, from_path: Path) -> Path:
    extends = extends.strip()
    if not extends:
        fail("empty extends in %s" % from_path)
    if extends.endswith(".toml") or "/" in extends or extends.startswith("~") or extends.startswith("."):
        p = Path(os.path.expanduser(extends))
        if not p.is_absolute():
            p = (from_path.parent / p).resolve()
        return p
    # Builtin first (no user shadowing for builtin names)
    builtin = builtin_dir / ("%s.toml" % extends)
    if builtin.is_file():
        return builtin.resolve()
    user = user_dir / ("%s.toml" % extends)
    if user.is_file():
        return user.resolve()
    fail("unknown base profile '%s' (extends in %s)" % (extends, from_path))


def list_str(val, label: str, path: Path):
    if val is None:
        return []
    if not isinstance(val, list):
        fail("%s must be an array in %s" % (label, path))
    out = []
    for item in val:
        s = str(item).strip()
        if s:
            out.append(s)
    return out


def merge_chain(leaf: Path):
    chain = []
    seen = set()
    cur = leaf.resolve()
    while True:
        key = str(cur)
        if key in seen:
            fail("inheritance loop detected involving %s" % cur)
        seen.add(key)
        data = load_toml(cur)
        validate_keys(data, cur)
        chain.append((cur, data))
        prof = data.get("profile") or {}
        extends = (prof.get("extends") or "").strip() if isinstance(prof.get("extends"), str) else ""
        if not extends:
            # also allow bare extends at top if someone used wrong schema — already rejected
            break
        cur = resolve_extends_path(extends, cur)
    chain.reverse()  # base → leaf
    return chain


chain = merge_chain(file)

# Merged state
name = ""
desc = ""
extends_leaf = ""
include_all = False
packages = []  # ordered unique
with_list = []
without_set = set()
open_apps = []
runtime = {}
pkg_explicit = False  # True once any profile sets packages= list

for path, data in chain:
    prof = data.get("profile") or {}
    if prof.get("name"):
        name = str(prof.get("name")).strip()
    if prof.get("description") is not None:
        desc = str(prof.get("description") or "").strip()
    if path == file.resolve():
        ext = prof.get("extends")
        if isinstance(ext, str) and ext.strip():
            extends_leaf = ext.strip()

    if prof.get("include_all_optional"):
        include_all = True

    # packages = [...] replaces when present
    if "packages" in prof and prof.get("packages") is not None:
        packages = list_str(prof.get("packages"), "profile.packages", path)
        pkg_explicit = True
        for g in packages:
            if g not in KNOWN_GROUPS:
                fail("Unknown package group '%s' in %s" % (g, path))

    pkg_tbl = data.get("packages") or {}
    for g in list_str(pkg_tbl.get("add"), "packages.add", path):
        if g not in KNOWN_GROUPS:
            fail("Unknown package group '%s' in %s" % (g, path))
        if g not in packages:
            packages.append(g)
        pkg_explicit = True
    for g in list_str(pkg_tbl.get("remove"), "packages.remove", path):
        if g not in KNOWN_GROUPS:
            fail("Unknown package group '%s' in %s" % (g, path))
        packages = [x for x in packages if x != g]
        pkg_explicit = True
    if "groups" in pkg_tbl and pkg_tbl.get("groups") is not None:
        packages = list_str(pkg_tbl.get("groups"), "packages.groups", path)
        for g in packages:
            if g not in KNOWN_GROUPS:
                fail("Unknown package group '%s' in %s" % (g, path))
        pkg_explicit = True

    # components (ids or supergroup selectors; expansion happens in shell)
    for item in list_str(prof.get("with"), "profile.with", path):
        if known_selectors and item not in known_selectors:
            fail("Unknown component or supergroup '%s' in %s" % (item, path))
        if item not in with_list:
            with_list.append(item)
    for item in list_str(prof.get("without"), "profile.without", path):
        if known_selectors and item not in known_selectors:
            fail("Unknown component or supergroup '%s' in %s" % (item, path))
        without_set.add(item)

    comps = data.get("components") or {}
    for item in list_str(comps.get("with"), "components.with", path):
        if known_selectors and item not in known_selectors:
            fail("Unknown component or supergroup '%s' in %s" % (item, path))
        if item not in with_list:
            with_list.append(item)
    for item in list_str(comps.get("without"), "components.without", path):
        if known_selectors and item not in known_selectors:
            fail("Unknown component or supergroup '%s' in %s" % (item, path))
        without_set.add(item)

    if "open_apps" in prof:
        open_apps = list_str(prof.get("open_apps"), "profile.open_apps", path)

    rt = data.get("runtime") or {}
    for k, v in rt.items():
        runtime[k] = v

# without wins over with
final_with = []
seen_w = set()
dupes = []
for item in with_list:
    if item in without_set:
        continue
    if item in seen_w:
        dupes.append(item)
        continue
    seen_w.add(item)
    final_with.append(item)
# contradictory: listed in both with and without after merge — without already wins;
# still error if same profile listed both in leaf without inheritance clarity? Spec says without wins.
# Duplicate component in with lists: warn via fail for strictness
if dupes:
    fail("duplicate component '%s' after profile merge" % dupes[0])

# Contradictory: in without and also only in without is fine; if explicitly both in SAME file check:
for path, data in chain:
    prof = data.get("profile") or {}
    comps = data.get("components") or {}
    wset = set(list_str(prof.get("with"), "profile.with", path) + list_str(comps.get("with"), "components.with", path))
    oset = set(list_str(prof.get("without"), "profile.without", path) + list_str(comps.get("without"), "components.without", path))
    both = wset & oset
    if both:
        fail("contradictory with/without for '%s' in %s" % (sorted(both)[0], path))

mux = runtime.get("multiplexer")
if mux is not None:
    mux_s = str(mux).strip()
    if mux_s not in KNOWN_MUX:
        fail("invalid multiplexer '%s' (allowed: tmux, herdr, none)" % mux_s)

if not name:
    name = file.stem

print("name:%s" % name)
print("desc:%s" % desc)
if extends_leaf:
    print("extends:%s" % extends_leaf)
for path, _ in chain:
    print("chain:%s" % path)
if include_all:
    print("all:1")
for item in final_with:
    print("with:%s" % item)
for item in sorted(without_set):
    print("without:%s" % item)
for item in open_apps:
    print("open:%s" % item)
for item in packages:
    print("pkg:%s" % item)
if pkg_explicit:
    print("pkg_explicit:1")
if "multiplexer" in runtime and runtime.get("multiplexer") is not None:
    print("runtime.multiplexer:%s" % str(runtime.get("multiplexer")).strip())
if "greeting" in runtime:
    print("runtime.greeting:%s" % ("1" if runtime.get("greeting") else "0"))
if "prompt_stats" in runtime:
    print("runtime.prompt_stats:%s" % ("1" if runtime.get("prompt_stats") else "0"))
if "auto_tmux" in runtime:
    print("runtime.auto_tmux:%s" % ("1" if runtime.get("auto_tmux") else "0"))
PY
	rm -rf "${pyhome}"
	return "${rc}"
}

# Fill PROFILE_* globals from path. Honors include_all_optional / builtin name "all".
dots_load_profile_file() {
	local file="$1"
	local line
	local parse_tmp parse_rc=0
	PROFILE_NAME=""
	PROFILE_DESC=""
	PROFILE_EXTENDS=""
	PROFILE_CHAIN=()
	PROFILE_WITH=()
	PROFILE_WITHOUT=()
	PROFILE_WITH_RAW=()
	PROFILE_WITHOUT_RAW=()
	PROFILE_OPEN_APPS=()
	PROFILE_PACKAGES=()
	PROFILE_RUNTIME_MULTIPLEXER=""
	PROFILE_RUNTIME_GREETING=""
	PROFILE_RUNTIME_PROMPT_STATS=""
	PROFILE_RUNTIME_AUTO_TMUX=""
	local include_all=0
	local pkg_explicit=0
	local _exp="" _cid="" _raw="" _reason=""

	parse_tmp="$(mktemp "${TMPDIR:-/tmp}/dots-prof.XXXXXX")"
	dots_profile_parse "${file}" >"${parse_tmp}" 2>"${parse_tmp}.err" || parse_rc=$?
	if [[ ${parse_rc} -ne 0 ]]; then
		cat "${parse_tmp}.err" >&2 || true
		rm -f "${parse_tmp}" "${parse_tmp}.err"
		return "${parse_rc}"
	fi
	# Surface any stderr warnings
	if [[ -s ${parse_tmp}.err ]]; then
		cat "${parse_tmp}.err" >&2 || true
	fi
	rm -f "${parse_tmp}.err"

	while IFS= read -r line; do
		[[ -z ${line} ]] && continue
		case "${line}" in
		name:*) PROFILE_NAME="${line#name:}" ;;
		desc:*) PROFILE_DESC="${line#desc:}" ;;
		extends:*) PROFILE_EXTENDS="${line#extends:}" ;;
		chain:*) PROFILE_CHAIN+=("${line#chain:}") ;;
		all:*) include_all=1 ;;
		with:*) PROFILE_WITH+=("${line#with:}") ;;
		without:*) PROFILE_WITHOUT+=("${line#without:}") ;;
		open:*) PROFILE_OPEN_APPS+=("${line#open:}") ;;
		pkg:*) PROFILE_PACKAGES+=("${line#pkg:}") ;;
		pkg_explicit:*) pkg_explicit=1 ;;
		runtime.multiplexer:*) PROFILE_RUNTIME_MULTIPLEXER="${line#runtime.multiplexer:}" ;;
		runtime.greeting:*) PROFILE_RUNTIME_GREETING="${line#runtime.greeting:}" ;;
		runtime.prompt_stats:*) PROFILE_RUNTIME_PROMPT_STATS="${line#runtime.prompt_stats:}" ;;
		runtime.auto_tmux:*) PROFILE_RUNTIME_AUTO_TMUX="${line#runtime.auto_tmux:}" ;;
		esac
	done <"${parse_tmp}"
	rm -f "${parse_tmp}"

	if [[ ${include_all} -eq 1 ]] || [[ ${PROFILE_NAME} == "all" && ${#PROFILE_WITH[@]} -eq 0 ]]; then
		# Aggregate `all`: platform-aware like a supergroup (omit unsupported).
		PROFILE_WITH=()
		local _cid _reason
		echo "Supergroup-equivalent 'all' (registry omit_from_all skipped):" >&2
		while IFS= read -r _cid; do
			[[ -z ${_cid} ]] && continue
			if dots_component_supported_here "${_cid}"; then
				PROFILE_WITH+=("${_cid}")
			else
				_reason="$(dots_component_unsupported_reason "${_cid}")"
				echo "  skipped for platform: ${_cid} (${_reason})" >&2
			fi
		done < <(dots_component_ids_for_all)
	fi

	# Default package groups when profile omits packages=
	# Prefer packages= from the named builtin profile TOML (authoritative SoT).
	# Minimal core+modern hard-code only if that TOML cannot be read.
	if [[ ${pkg_explicit} -eq 0 && ${#PROFILE_PACKAGES[@]} -eq 0 ]]; then
		local _fb="${DIR}/configs/bootstrap/profiles/${PROFILE_NAME}.toml"
		[[ -f ${_fb} ]] || _fb="${DIR}/configs/bootstrap/profiles/base.toml"
		if [[ -f ${_fb} ]] && declare -F dots_toml_query >/dev/null 2>&1; then
			while IFS= read -r _g; do
				[[ -n ${_g} ]] && PROFILE_PACKAGES+=("${_g}")
			done < <(
				dots_toml_query "${_fb}" <<'PY'
prof = data.get("profile") or {}
for g in prof.get("packages") or []:
    g = str(g).strip()
    if g:
        print(g)
PY
			)
		fi
		if [[ ${#PROFILE_PACKAGES[@]} -eq 0 ]]; then
			# Stage-0 / unreadable TOML fallback — lean baseline only.
			# Do not duplicate home/work/server/all membership here.
			PROFILE_PACKAGES=(core modern)
		fi
	fi

	# Default runtime multiplexer by profile role when omitted
	if [[ -z ${PROFILE_RUNTIME_MULTIPLEXER} ]]; then
		case "${PROFILE_NAME}" in
		home) PROFILE_RUNTIME_MULTIPLEXER="herdr" ;;
		*) PROFILE_RUNTIME_MULTIPLEXER="tmux" ;;
		esac
	fi

	# Selecting herdr as automatic multiplexer implies herdr component availability
	if [[ ${PROFILE_RUNTIME_MULTIPLEXER} == "herdr" ]]; then
		if ! dots_array_contains herdr "${PROFILE_WITH[@]+"${PROFILE_WITH[@]}"}"; then
			if ! dots_array_contains herdr "${PROFILE_WITHOUT[@]+"${PROFILE_WITHOUT[@]}"}"; then
				PROFILE_WITH+=("herdr")
			fi
		fi
	fi

	# Expand profile selectors (supergroups → leaves). Keep raw for --show.
	PROFILE_WITH_RAW=("${PROFILE_WITH[@]+"${PROFILE_WITH[@]}"}")
	PROFILE_WITHOUT_RAW=("${PROFILE_WITHOUT[@]+"${PROFILE_WITHOUT[@]}"}")
	if [[ ${#PROFILE_WITH[@]} -gt 0 ]]; then
		dots_validate_selectors "${PROFILE_WITH[@]}" || return 1
		local _exp
		_exp="$(dots_expand_with_selectors "${PROFILE_WITH[@]}")" || return 1
		PROFILE_WITH=()
		while IFS= read -r _cid; do
			[[ -n ${_cid} ]] && PROFILE_WITH+=("${_cid}")
		done <<<"${_exp}"
	fi
	if [[ ${#PROFILE_WITHOUT[@]} -gt 0 ]]; then
		dots_validate_selectors "${PROFILE_WITHOUT[@]}" || return 1
		_exp="$(dots_expand_without_selectors "${PROFILE_WITHOUT[@]}")" || return 1
		PROFILE_WITHOUT=()
		while IFS= read -r _cid; do
			[[ -n ${_cid} ]] && PROFILE_WITHOUT+=("${_cid}")
		done <<<"${_exp}"
	fi

	# Explicit leaf components in the profile must be supported here.
	if [[ ${#PROFILE_WITH_RAW[@]} -gt 0 ]]; then
		local _raw
		for _raw in "${PROFILE_WITH_RAW[@]}"; do
			if dots_component_is_known "${_raw}"; then
				dots_require_explicit_component_supported "${_raw}" || return 1
			fi
		done
	fi

	echo "OK: loaded profile '${PROFILE_NAME:-unknown}' from ${file}"
	if [[ -n ${PROFILE_EXTENDS} ]]; then
		echo "OK: extends=${PROFILE_EXTENDS}"
	fi
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

# PROFILE_WITH + CLI_WITH - (PROFILE_WITHOUT ∪ CLI_WITHOUT) → EFFECTIVE_WITH (deduped)
# CLI --without wins over everything; CLI --with adds after profile resolution.
# Supergroups are expanded before this merge (profile) / here (CLI).
dots_compute_effective_with() {
	EFFECTIVE_WITH=()
	CLI_WITH=("${CLI_WITH[@]+"${CLI_WITH[@]}"}")
	CLI_WITHOUT=("${CLI_WITHOUT[@]+"${CLI_WITHOUT[@]}"}")
	CLI_WITH_RAW=("${CLI_WITH[@]+"${CLI_WITH[@]}"}")
	CLI_WITHOUT_RAW=("${CLI_WITHOUT[@]+"${CLI_WITHOUT[@]}"}")

	# Expand CLI selectors → leaf components
	if [[ ${#CLI_WITH[@]} -gt 0 ]]; then
		dots_validate_selectors "${CLI_WITH[@]}" || return 1
		local _exp _cid _raw
		_exp="$(dots_expand_with_selectors "${CLI_WITH[@]}")" || return 1
		CLI_WITH=()
		while IFS= read -r _cid; do
			[[ -n ${_cid} ]] && CLI_WITH+=("${_cid}")
		done <<<"${_exp}"
		# Explicit CLI leaf components must be supported on this platform.
		for _raw in "${CLI_WITH_RAW[@]}"; do
			if dots_component_is_known "${_raw}"; then
				dots_require_explicit_component_supported "${_raw}" || return 1
			fi
		done
	fi
	if [[ ${#CLI_WITHOUT[@]} -gt 0 ]]; then
		dots_validate_selectors "${CLI_WITHOUT[@]}" || return 1
		_exp="$(dots_expand_without_selectors "${CLI_WITHOUT[@]}")" || return 1
		CLI_WITHOUT=()
		while IFS= read -r _cid; do
			[[ -n ${_cid} ]] && CLI_WITHOUT+=("${_cid}")
		done <<<"${_exp}"
	fi

	local c
	local -a without_all=()
	for c in "${PROFILE_WITHOUT[@]+"${PROFILE_WITHOUT[@]}"}"; do
		without_all+=("${c}")
	done
	for c in "${CLI_WITHOUT[@]+"${CLI_WITHOUT[@]}"}"; do
		without_all+=("${c}")
	done
	for c in "${PROFILE_WITH[@]+"${PROFILE_WITH[@]}"}"; do
		dots_array_contains "${c}" "${without_all[@]+"${without_all[@]}"}" && continue
		dots_array_contains "${c}" "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}" && continue
		EFFECTIVE_WITH+=("${c}")
	done
	for c in "${CLI_WITH[@]+"${CLI_WITH[@]}"}"; do
		dots_array_contains "${c}" "${without_all[@]+"${without_all[@]}"}" && continue
		dots_array_contains "${c}" "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}" && continue
		EFFECTIVE_WITH+=("${c}")
	done
	# Auto-include herdr when multiplexer demands it (unless CLI --without herdr)
	if [[ ${PROFILE_RUNTIME_MULTIPLEXER} == "herdr" ]]; then
		if ! dots_array_contains herdr "${without_all[@]+"${without_all[@]}"}"; then
			if ! dots_array_contains herdr "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
				EFFECTIVE_WITH+=("herdr")
			fi
		fi
	fi
	if [[ ${#EFFECTIVE_WITH[@]} -gt 0 ]]; then
		dots_validate_components "${EFFECTIVE_WITH[@]}" || return 1
	fi
}

dots_show_profile_resolution() {
	local label="${1:-resolved}"
	echo "profile: ${PROFILE_NAME:-${label}}"
	if [[ -n ${PROFILE_EXTENDS} ]]; then
		echo "extends: ${PROFILE_EXTENDS}"
	fi
	if [[ -n ${PROFILE_DESC} ]]; then
		echo "description: ${PROFILE_DESC}"
	fi
	if [[ ${#PROFILE_CHAIN[@]} -gt 0 ]]; then
		echo ""
		echo "source chain:"
		local i p
		for i in "${!PROFILE_CHAIN[@]}"; do
			p="${PROFILE_CHAIN[$i]}"
			if [[ ${i} -eq 0 ]]; then
				echo "  ${p}"
			else
				echo "  -> ${p}"
			fi
		done
		if [[ ${#CLI_WITH[@]} -gt 0 || ${#CLI_WITHOUT[@]} -gt 0 ]]; then
			echo "  -> CLI overrides"
		fi
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
	echo "  multiplexer = ${PROFILE_RUNTIME_MULTIPLEXER:-tmux}"
	[[ -n ${PROFILE_RUNTIME_GREETING} ]] && echo "  greeting = ${PROFILE_RUNTIME_GREETING}"
	[[ -n ${PROFILE_RUNTIME_PROMPT_STATS} ]] && echo "  prompt_stats = ${PROFILE_RUNTIME_PROMPT_STATS}"
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
	# Transparent supergroup resolution for --show
	local -a _req_groups=()
	for c in "${PROFILE_WITH_RAW[@]+"${PROFILE_WITH_RAW[@]}"}" "${CLI_WITH_RAW[@]+"${CLI_WITH_RAW[@]}"}"; do
		dots_supergroup_is_known "${c}" && _req_groups+=("${c}")
	done
	if [[ ${#_req_groups[@]} -gt 0 ]]; then
		echo ""
		echo "requested:"
		echo "  supergroups: ${_req_groups[*]}"
		echo "expanded components:"
		if [[ ${#EFFECTIVE_WITH[@]} -eq 0 ]]; then
			echo "  (none)"
		else
			for c in "${EFFECTIVE_WITH[@]}"; do
				echo "  ${c}"
			done
		fi
	fi
	echo ""
	if [[ ${#EFFECTIVE_WITH[@]} -gt 0 ]]; then
		dots_print_provider_implications "${EFFECTIVE_WITH[@]}"
	else
		echo "explicit provider implications:"
		echo "  local AI: (none)"
		echo "  cloud AI: (none)"
		echo "  image AI: (none)"
		echo "  voice AI: (none)"
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
