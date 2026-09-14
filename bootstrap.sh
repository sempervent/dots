#!/usr/bin/env bash
# bootstrap.sh — onboard a new machine via declarative profiles + setup.sh
#
# Does NOT duplicate setup.sh. Orchestrates:
#   detect → load profile → merge --with/--without → setup.sh → check → report
#
# Semantics:
#   profile `with` = baseline optional components
#   CLI --with     = add components
#   CLI --without  = remove components (from profile + --with)
#   Explicit CLI never silently configures unselected AI clients.
#
# Examples:
#   ./bootstrap.sh --profile base
#   ./bootstrap.sh --profile work
#   ./bootstrap.sh --profile home
#   ./bootstrap.sh --profile work --with hermes
#   ./bootstrap.sh --profile home --without cursor
#   ./bootstrap.sh --profile base --dry-run
#   ./bootstrap.sh --profile home --open-apps
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROFILE="base"
DRY_RUN=0
CHECK_ONLY=0
OPEN_APPS=0
CLI_WITH=()
CLI_WITHOUT=()
PROFILE_WITH=()
PROFILE_OPEN_APPS=()
EFFECTIVE_WITH=()

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [options]

Onboard / refresh a machine using a declarative profile, then invoke setup.sh.

Options:
  --profile <name>   base | home | work  (default: base)
                     Profiles live in configs/bootstrap/profiles/<name>.toml
  --with <list>      Add components (comma-separated), merged onto profile
  --without <list>   Remove components from the effective set
  --dry-run          Preview (passed through to setup.sh)
  --check-only       Run scripts/check.sh only (no setup)
  --open-apps        After setup, open selected/installed apps (macOS GUI only)
  --no-open          Never open apps (default)
  -h, --help         Show this help

Semantics:
  profile provides baseline optional components
  --with adds components
  --without removes components

Policy:
  Installing DOTS never configures an AI client merely because its binary exists.
  See helpers/ai_consent.sh and README (Consent vs presence).

Examples:
  ./bootstrap.sh --profile base
  ./bootstrap.sh --profile work --dry-run
  ./bootstrap.sh --profile home
  ./bootstrap.sh --profile work --with hermes,images
  ./bootstrap.sh --profile home --without cursor --dry-run
EOF
}

parse_csv_add() {
  # Append CSV items into a global array named by first arg (bash 3.2-safe)
  local dest_name="$1" raw="$2" item
  local -a _parts=()
  IFS=',' read -r -a _parts <<<"${raw}"
  for item in "${_parts[@]}"; do
    item="$(echo "${item}" | tr -d '[:space:]')"
    [[ -z "${item}" ]] && continue
    eval "${dest_name}+=(\"\${item}\")"
  done
}

load_profile() {
  local name="$1"
  local file="${DIR}/configs/bootstrap/profiles/${name}.toml"
  if [[ ! -f "${file}" ]]; then
    echo "Error: unknown profile '${name}' (missing ${file})" >&2
    echo "Available:" >&2
    ls -1 "${DIR}/configs/bootstrap/profiles/"*.toml 2>/dev/null | xargs -n1 basename | sed 's/\.toml$//' >&2 || true
    exit 1
  fi
  # shellcheck disable=SC2034
  PROFILE_WITH=()
  PROFILE_OPEN_APPS=()
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    case "${line}" in
      with:*) PROFILE_WITH+=("${line#with:}") ;;
      open:*) PROFILE_OPEN_APPS+=("${line#open:}") ;;
    esac
  done < <(python3 - "${file}" <<'PY'
import sys
from pathlib import Path
try:
    import tomllib
except ImportError:
    sys.exit(1)
data = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
prof = data.get("profile") or data
for item in prof.get("with") or []:
    item = str(item).strip()
    if item:
        print(f"with:{item}")
for item in prof.get("open_apps") or []:
    item = str(item).strip()
    if item:
        print(f"open:{item}")
PY
)
  echo "OK: loaded profile '${name}' from ${file}"
  if [[ ${#PROFILE_WITH[@]} -eq 0 ]]; then
    echo "OK: profile with=[] (no optional AI components)"
  else
    echo "OK: profile with=${PROFILE_WITH[*]}"
  fi
}

array_contains() {
  local needle="$1" x
  shift
  for x in "$@"; do
    [[ "${x}" == "${needle}" ]] && return 0
  done
  return 1
}

compute_effective_with() {
  EFFECTIVE_WITH=()
  local c
  for c in "${PROFILE_WITH[@]+"${PROFILE_WITH[@]}"}"; do
    array_contains "${c}" "${CLI_WITHOUT[@]+"${CLI_WITHOUT[@]}"}" && continue
    array_contains "${c}" "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}" && continue
    EFFECTIVE_WITH+=("${c}")
  done
  for c in "${CLI_WITH[@]+"${CLI_WITH[@]}"}"; do
    array_contains "${c}" "${CLI_WITHOUT[@]+"${CLI_WITHOUT[@]}"}" && continue
    array_contains "${c}" "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}" && continue
    EFFECTIVE_WITH+=("${c}")
  done
}

detect_platform() {
  echo "=== Platform ==="
  echo "OS: $(uname -s)  arch: $(uname -m)"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Warn: bootstrap is optimized for macOS; continuing carefully."
  fi
  if command -v brew >/dev/null 2>&1; then
    echo "OK: Homebrew → $(command -v brew)"
  else
    echo "Note: Homebrew not found. setup.sh will skip brew bundle until brew exists."
    echo "      Install from https://brew.sh if policy permits."
  fi
}

maybe_open_apps() {
  if [[ "${OPEN_APPS}" -ne 1 ]]; then
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] would open apps: ${PROFILE_OPEN_APPS[*]:-none}"
    return 0
  fi
  if [[ -n "${SSH_CONNECTION:-}" ]] || [[ -n "${SSH_TTY:-}" ]]; then
    echo "Note: SSH session — skipping --open-apps"
    return 0
  fi
  if [[ ! -t 0 ]] || [[ "${CI:-}" == "true" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "Note: noninteractive/CI — skipping --open-apps"
    return 0
  fi
  if [[ "$(uname -s)" != "Darwin" ]] || ! command -v open >/dev/null 2>&1; then
    return 0
  fi
  echo "=== Opening apps (--open-apps) ==="
  local app
  for app in "${PROFILE_OPEN_APPS[@]+"${PROFILE_OPEN_APPS[@]}"}"; do
    case "${app}" in
      iTerm|iTerm2)
        if [[ -d "/Applications/iTerm.app" ]]; then
          open -a iTerm || true
        fi
        ;;
      "Draw Things")
        if array_contains drawthings "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}" \
          && [[ -d "/Applications/Draw Things.app" ]]; then
          open -a "Draw Things" || true
        fi
        ;;
      Cursor)
        if array_contains cursor "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}" \
          && [[ -d "/Applications/Cursor.app" ]]; then
          open -a Cursor || true
        fi
        ;;
      *)
        echo "Note: unknown open_apps entry '${app}'"
        ;;
    esac
  done
}

manual_followups() {
  echo ""
  echo "=== Manual follow-ups (selected components only) ==="
  echo "• Set iTerm font to JetBrainsMono Nerd Font (Profiles → Text)"
  echo "• Enable terminal-notifier notification permission if prompted"
  if array_contains hermes "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
    echo "• Authenticate Hermes (hermes login / first-run flow)"
  fi
  if array_contains codex "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
    echo "• Authenticate Codex (interactive \`codex\` login; DOTS never copies tokens)"
  fi
  if array_contains cursor "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
    echo "• Authenticate Cursor Agent CLI (\`agent\` first-time login)"
  fi
  if array_contains ollama "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
    echo "• Start Ollama and pull models you need (DOTS never auto-pulls)"
  fi
  if array_contains drawthings "${EFFECTIVE_WITH[@]+"${EFFECTIVE_WITH[@]}"}"; then
    echo "• Ensure Draw Things models are downloaded (GUI or DRAWTHINGS_MODELS_DIR)"
  fi
  if [[ ${#EFFECTIVE_WITH[@]} -eq 0 ]]; then
    echo "• No AI clients selected — no AI auth steps required"
  fi
}

# --- args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --profile=*)
      PROFILE="${1#*=}"
      shift
      ;;
    --with)
      parse_csv_add CLI_WITH "${2:-}"
      shift 2
      ;;
    --with=*)
      parse_csv_add CLI_WITH "${1#*=}"
      shift
      ;;
    --without)
      parse_csv_add CLI_WITHOUT "${2:-}"
      shift 2
      ;;
    --without=*)
      parse_csv_add CLI_WITHOUT "${1#*=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --check-only)
      CHECK_ONLY=1
      shift
      ;;
    --open-apps)
      OPEN_APPS=1
      shift
      ;;
    --no-open)
      OPEN_APPS=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

detect_platform
load_profile "${PROFILE}"
compute_effective_with

echo "=== Effective optional components ==="
if [[ ${#EFFECTIVE_WITH[@]} -eq 0 ]]; then
  echo "(none — base/core only)"
else
  echo "${EFFECTIVE_WITH[*]}"
fi

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  echo "=== check-only ==="
  exec "${DIR}/scripts/check.sh"
fi

SETUP_ARGS=()
[[ "${DRY_RUN}" -eq 1 ]] && SETUP_ARGS+=(--dry-run)
if [[ ${#EFFECTIVE_WITH[@]} -gt 0 ]]; then
  IFS=','
  SETUP_ARGS+=(--with "${EFFECTIVE_WITH[*]}")
  unset IFS
fi

echo "=== Invoking setup.sh ${SETUP_ARGS[*]:-} ==="
"${DIR}/setup.sh" "${SETUP_ARGS[@]+"${SETUP_ARGS[@]}"}"

if [[ "${DRY_RUN}" -eq 0 ]]; then
  echo "=== Verification ==="
  "${DIR}/scripts/check.sh" || true
fi

maybe_open_apps
manual_followups

echo ""
echo "Bootstrap complete (profile=${PROFILE}$([ "${DRY_RUN}" -eq 1 ] && echo ', dry-run'))."
echo "Consent model: binary presence ≠ configuration authorization."
