# helpers/agent_skills.sh — reusable agent-skill install helpers for setup.sh
#
# Skills are installed globally via the upstream `skills` CLI:
#   npx -y skills add <owner/repo> -g -y
#
# Canonical global store: ~/.agents/skills/<name>
# Hermes discovers them via the symlink the skills CLI creates under
# ~/.hermes/skills/<name> (no dots-side copy/symlink required).
#
# To add another skill later:
#   1. Add the component name to SUPPORTED_WITH in setup.sh
#   2. Map it in agent_skill_package() below
#   3. Add brew/Brewfile.<name> only if the skill needs Homebrew deps

# Return the skills.sh package spec (owner/repo) for a component name.
agent_skill_package() {
  case "$1" in
    archify) printf '%s\n' "tt-a1i/archify" ;;
    *) return 1 ;;
  esac
}

is_agent_skill_component() {
  agent_skill_package "$1" >/dev/null 2>&1
}

# Parse `node -v` → major integer. Empty on failure.
node_major_version() {
  local ver
  command -v node >/dev/null 2>&1 || return 1
  ver="$(node -v 2>/dev/null || true)"
  ver="${ver#v}"
  ver="${ver%%.*}"
  [[ "${ver}" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "${ver}"
}

# Fail with a clear diagnostic unless Node major >= min (default 18).
ensure_node_major() {
  local min="${1:-18}"
  local major

  if ! command -v node >/dev/null 2>&1; then
    echo "Error: Node.js is required (need >= ${min}) but 'node' was not found on PATH." >&2
    echo "       Install via Homebrew (./setup.sh --with archify applies brew/Brewfile.archify)" >&2
    echo "       or ensure a Node ${min}+ runtime is available, then re-run." >&2
    return 1
  fi

  if ! command -v npx >/dev/null 2>&1; then
    echo "Error: 'npx' not found on PATH (required to install agent skills)." >&2
    echo "       Node/npm from Homebrew normally provides npx; check your PATH." >&2
    return 1
  fi

  major="$(node_major_version)" || {
    echo "Error: could not parse Node version from: $(node -v 2>/dev/null || echo unknown)" >&2
    return 1
  }

  if [[ "${major}" -lt "${min}" ]]; then
    echo "Error: Node.js ${major} is too old; agent skills require Node >= ${min}." >&2
    echo "       Current: $(command -v node) → $(node -v 2>/dev/null)" >&2
    echo "       Upgrade Node (Homebrew: brew upgrade node) and re-run." >&2
    return 1
  fi

  echo "OK: Node $(node -v 2>/dev/null) (>= ${min}), npx $(command -v npx)"
  return 0
}

# True when the skills CLI global store has this skill (canonical path + lock when present).
agent_skill_is_installed() {
  local name="$1"
  python3 - "$name" <<'PY'
import json
import pathlib
import sys

name = sys.argv[1]
home = pathlib.Path.home()
skill_md = home / ".agents" / "skills" / name / "SKILL.md"
lock = home / ".agents" / ".skill-lock.json"

if not skill_md.is_file():
    sys.exit(1)

# Prefer lock confirmation when the skills CLI has written one.
if lock.is_file():
    try:
        data = json.loads(lock.read_text(encoding="utf-8"))
        skills = data.get("skills") or {}
        if name in skills:
            sys.exit(0)
        # SKILL.md present but lock stale/partial — still accept the install.
    except Exception:
        pass

sys.exit(0)
PY
}

install_agent_skill() {
  local name="$1"
  local spec
  local min_node=18

  if ! spec="$(agent_skill_package "${name}")"; then
    echo "Error: unknown agent skill: ${name}" >&2
    return 1
  fi

  echo "=== Agent skill: ${name} ==="

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[dry-run] ensure Node >= ${min_node} and npx"
    if agent_skill_is_installed "${name}"; then
      echo "[dry-run] would skip install (${name} already present under ~/.agents/skills/${name})"
    else
      echo "[dry-run] npx -y skills add ${spec} -g -y"
    fi
    return 0
  fi

  ensure_node_major "${min_node}" || return 1

  if agent_skill_is_installed "${name}"; then
    echo "OK: agent skill '${name}' already installed (~/.agents/skills/${name})"
    if [[ -L "${HOME}/.hermes/skills/${name}" ]] || [[ -d "${HOME}/.hermes/skills/${name}" ]]; then
      echo "OK: Hermes discovers '${name}' via ~/.hermes/skills/${name}"
    elif [[ -d "${HOME}/.hermes" ]]; then
      echo "Note: ~/.hermes exists but no skills/${name} link yet; Hermes may still see it after next skills sync."
    fi
    return 0
  fi

  echo "Installing agent skill '${name}' from ${spec} (global)..."
  if ! npx -y skills add "${spec}" -g -y; then
    echo "Warn: npx skills add exited non-zero; verifying install..." >&2
  fi

  if ! agent_skill_is_installed "${name}"; then
    echo "Error: agent skill '${name}' was not installed under ~/.agents/skills/${name}." >&2
    echo "       Manual install: npx -y skills add ${spec} -g -y" >&2
    return 1
  fi

  echo "OK: installed agent skill '${name}' → ~/.agents/skills/${name}"
  if [[ -L "${HOME}/.hermes/skills/${name}" ]] || [[ -e "${HOME}/.hermes/skills/${name}" ]]; then
    echo "OK: Hermes symlink present (~/.hermes/skills/${name})"
  fi
  return 0
}

install_requested_agent_skills() {
  local c
  local any=0
  for c in "${DOTS_WITH_COMPONENTS[@]+"${DOTS_WITH_COMPONENTS[@]}"}"; do
    if is_agent_skill_component "${c}"; then
      any=1
      install_agent_skill "${c}" || return 1
    fi
  done
  [[ "${any}" -eq 1 ]] || return 0
}
