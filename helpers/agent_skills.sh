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
    echo "       Install via ./setup.sh (fnm + configs/node/default.toml) then re-run." >&2
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
    echo "       Upgrade Node via fnm (fnm install 24 && fnm default 24) and re-run." >&2
    return 1
  fi

  echo "OK: Node $(node -v 2>/dev/null) (>= ${min}), npx $(command -v npx)"
  return 0
}

# Candidate skill roots (filesystem order). Does not configure providers.
dots_skill_candidates() {
  local name="$1"
  printf '%s\n' \
    "${HOME}/.agents/skills/${name}" \
    "${HOME}/.hermes/skills/${name}"
}

# First candidate containing SKILL.md (follows valid symlinks).
dots_skill_find() {
  local name="$1" cand
  while IFS= read -r cand; do
    [[ -z ${cand} ]] && continue
    if [[ -L ${cand} ]]; then
      # Broken symlink → skip
      [[ -e ${cand} ]] || continue
    fi
    if [[ -f ${cand}/SKILL.md ]]; then
      printf '%s\n' "${cand}"
      return 0
    fi
  done < <(dots_skill_candidates "${name}")
  return 1
}

# True when a valid installed skill exists in any accepted location.
# Lockfile is provenance only — never required if SKILL.md is present.
agent_skill_is_installed() {
  local name="$1"
  dots_skill_find "${name}" >/dev/null 2>&1
}

dots_skill_is_installed() {
  agent_skill_is_installed "$@"
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
      echo "[dry-run] would skip install (${name} already at $(dots_skill_find "${name}"))"
    else
      echo "[dry-run] npx -y skills add ${spec} -g -y"
    fi
    return 0
  fi

  ensure_node_major "${min_node}" || return 1

  local found=""
  if found="$(dots_skill_find "${name}")"; then
    echo "OK: agent skill '${name}' already installed"
    echo "    path: ${found}"
    return 0
  fi

  echo "Installing agent skill '${name}' from ${spec} (global)..."
  if ! npx -y skills add "${spec}" -g -y </dev/null; then
    echo "Warn: npx skills add exited non-zero; verifying install..." >&2
  fi

  if ! found="$(dots_skill_find "${name}")"; then
    echo "Error: agent skill '${name}' not found under ~/.agents/skills or ~/.hermes/skills." >&2
    echo "       Manual install: npx -y skills add ${spec} -g -y" >&2
    return 1
  fi

  echo "OK: installed agent skill '${name}'"
  echo "    path: ${found}"
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
