# helpers/profiles.sh — declarative bootstrap profile load / resolve / show
#
# Profiles are data only (TOML). Never execute profile contents.
# Requires: DIR, helpers/components.sh (dots_component_*)

dots_builtin_profile_dir() {
  printf '%s\n' "${DIR}/configs/bootstrap/profiles"
}

# Resolve --profile argument to an absolute TOML path.
# Recognizes: builtin name, absolute/relative path, ~/path, *.toml
dots_resolve_profile_path() {
  local arg="$1"
  local builtin_dir path
  builtin_dir="$(dots_builtin_profile_dir)"

  if [[ -z "${arg}" ]]; then
    echo "Error: empty profile" >&2
    return 1
  fi

  # Path-like: contains / or starts with . ~ or ends with .toml
  if [[ "${arg}" == */* ]] || [[ "${arg}" == .* ]] || [[ "${arg}" == ~* ]] || [[ "${arg}" == *.toml ]]; then
    path="${arg/#\~/${HOME}}"
    if [[ "${path}" != /* ]]; then
      path="$(pwd)/${path}"
    fi
    if [[ ! -f "${path}" ]]; then
      echo "Error: profile file not found: ${arg} (resolved ${path})" >&2
      return 1
    fi
    printf '%s\n' "${path}"
    return 0
  fi

  # Builtin name
  path="${builtin_dir}/${arg}.toml"
  if [[ ! -f "${path}" ]]; then
    echo "Error: unknown profile '${arg}' (missing ${path})" >&2
    echo "Available builtins:" >&2
    ls -1 "${builtin_dir}"/*.toml 2>/dev/null | xargs -n1 basename | sed 's/\.toml$//' >&2 || true
    echo "Or pass a custom TOML path: --profile /path/to/profile.toml" >&2
    return 1
  fi
  printf '%s\n' "${path}"
}

# Load profile TOML → print lines: name:, desc:, with:, open:, all:
dots_profile_parse() {
  local file="$1"
  python3 - "${file}" <<'PY'
import sys
from pathlib import Path
try:
    import tomllib
except ImportError:
    print("Error: tomllib required (Python 3.11+)", file=sys.stderr)
    sys.exit(1)
path = Path(sys.argv[1])
try:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"Error: malformed TOML ({path}): {exc}", file=sys.stderr)
    sys.exit(1)
prof = data.get("profile") or data
name = (prof.get("name") or path.stem).strip()
desc = (prof.get("description") or "").strip()
print(f"name:{name}")
print(f"desc:{desc}")
if prof.get("include_all_optional"):
    print("all:1")
for item in prof.get("with") or []:
    item = str(item).strip()
    if item:
        print(f"with:{item}")
for item in prof.get("open_apps") or []:
    item = str(item).strip()
    if item:
        print(f"open:{item}")
PY
}

# Fill PROFILE_NAME PROFILE_DESC PROFILE_WITH PROFILE_OPEN_APPS from path.
# Honors include_all_optional / builtin name "all".
dots_load_profile_file() {
  local file="$1"
  local line
  PROFILE_NAME=""
  PROFILE_DESC=""
  PROFILE_WITH=()
  PROFILE_OPEN_APPS=()
  local include_all=0

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    case "${line}" in
      name:*) PROFILE_NAME="${line#name:}" ;;
      desc:*) PROFILE_DESC="${line#desc:}" ;;
      all:*) include_all=1 ;;
      with:*) PROFILE_WITH+=("${line#with:}") ;;
      open:*) PROFILE_OPEN_APPS+=("${line#open:}") ;;
    esac
  done < <(dots_profile_parse "${file}")

  if [[ "${include_all}" -eq 1 ]] || [[ "${PROFILE_NAME}" == "all" && ${#PROFILE_WITH[@]} -eq 0 ]]; then
    PROFILE_WITH=()
    while IFS= read -r line; do
      [[ -n "${line}" ]] && PROFILE_WITH+=("${line}")
    done < <(dots_component_ids_for_all)
  fi

  # Validate components
  if [[ ${#PROFILE_WITH[@]} -gt 0 ]]; then
    dots_validate_components "${PROFILE_WITH[@]}" || return 1
  fi

  echo "OK: loaded profile '${PROFILE_NAME:-unknown}' from ${file}"
  if [[ -n "${PROFILE_DESC}" ]]; then
    echo "OK: ${PROFILE_DESC}"
  fi
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
    [[ "${x}" == "${needle}" ]] && return 0
  done
  return 1
}

# PROFILE_WITH + CLI_WITH - CLI_WITHOUT → EFFECTIVE_WITH (deduped)
dots_compute_effective_with() {
  EFFECTIVE_WITH=()
  local c
  for c in "${PROFILE_WITH[@]+"${PROFILE_WITH[@]}"}"; do
    dots_array_contains "${c}" "${CLI_WITHOUT[@]+"${CLI_WITHOUT[@]}"}" && continue
    dots_array_contains "${c}" "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}" && continue
    EFFECTIVE_WITH+=("${c}")
  done
  for c in "${CLI_WITH[@]+"${CLI_WITH[@]}"}"; do
    dots_array_contains "${c}" "${CLI_WITHOUT[@]+"${CLI_WITHOUT[@]}"}" && continue
    dots_array_contains "${c}" "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}" && continue
    EFFECTIVE_WITH+=("${c}")
  done
  if [[ ${#EFFECTIVE_WITH[@]} -gt 0 ]]; then
    dots_validate_components "${EFFECTIVE_WITH[@]}" || return 1
  fi
  if [[ ${#CLI_WITH[@]} -gt 0 ]]; then
    dots_validate_components "${CLI_WITH[@]}" || return 1
  fi
  if [[ ${#CLI_WITHOUT[@]} -gt 0 ]]; then
    # --without may name known components only
    dots_validate_components "${CLI_WITHOUT[@]}" || return 1
  fi
}

dots_show_profile_resolution() {
  local label="${1:-resolved}"
  echo "profile: ${PROFILE_NAME:-${label}}"
  if [[ -n "${PROFILE_DESC}" ]]; then
    echo "description: ${PROFILE_DESC}"
  fi
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
  echo ""
  if [[ ${#EFFECTIVE_WITH[@]} -gt 0 ]]; then
    dots_print_provider_implications "${EFFECTIVE_WITH[@]}"
  else
    echo "explicit provider implications:"
    echo "  local AI: (none)"
    echo "  cloud AI: (none)"
    echo "  image AI: (none)"
  fi
}

dots_warn_cloud_components() {
  local cloud
  cloud="$(dots_print_cloud_notice "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}")"
  if [[ -z "${cloud}" ]]; then
    return 0
  fi
  echo ""
  echo "Cloud/external AI components selected:"
  while IFS= read -r c; do
    [[ -n "${c}" ]] && echo "  - ${c}"
  done <<<"${cloud}"
  echo "(Informational — binary presence elsewhere still does not imply consent.)"
}
