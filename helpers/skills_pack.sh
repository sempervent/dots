# helpers/skills_pack.sh — curated --with skills Engineering Pack
#
# Manifest: configs/skills/manifest.toml
# Uses skills CLI (npx -y skills …) with -s per skill for multi-skill repos.
# Provenance: ~/.agents/.skill-lock.json (skills CLI)
#
# Requires: DIR, DRY_RUN, ensure_node_major, agent_skill_is_installed (agent_skills.sh)

dots_skills_manifest_path() {
  printf '%s\n' "${DIR}/configs/skills/manifest.toml"
}

# List enabled skill names from manifest (one per line: name<TAB>source)
dots_skills_manifest_entries() {
  local manifest
  manifest="$(dots_skills_manifest_path)"
  [[ -f "${manifest}" ]] || return 1
  python3 - "${manifest}" <<'PY'
import sys
from pathlib import Path
try:
    import tomllib
except ImportError:
    sys.exit(1)
data = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for s in data.get("skills") or []:
    if not s.get("enabled", True):
        continue
    name = (s.get("name") or "").strip()
    source = (s.get("source") or "").strip()
    if name and source:
        print(f"{name}\t{source}")
PY
}

dots_skill_lock_has() {
  local name="$1"
  python3 - "$name" <<'PY'
import json, pathlib, sys
name = sys.argv[1]
lock = pathlib.Path.home() / ".agents" / ".skill-lock.json"
if not lock.is_file():
    sys.exit(1)
try:
    data = json.loads(lock.read_text(encoding="utf-8"))
except Exception:
    sys.exit(1)
skills = data.get("skills") or {}
sys.exit(0 if name in skills else 1)
PY
}

install_skill_from_source() {
  local name="$1" source="$2"
  local min_node=18
  local hermes_link="${HOME}/.hermes/skills/${name}"
  local need_install=1
  local need_hermes=0

  echo "=== Skill pack: ${name} (${source}) ==="

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    if agent_skill_is_installed "${name}"; then
      echo "[dry-run] skip content install (${name} already under ~/.agents/skills)"
      if [[ -d "${HOME}/.hermes" ]] && [[ ! -e "${hermes_link}" ]]; then
        echo "[dry-run] would ensure Hermes discovery: npx skills add … -a hermes-agent"
      fi
    else
      echo "[dry-run] npx -y skills add ${source} -g -y -s ${name} -a hermes-agent"
    fi
    return 0
  fi

  ensure_node_major "${min_node}" || return 1

  if agent_skill_is_installed "${name}"; then
    need_install=0
    echo "OK: '${name}' already installed under ~/.agents/skills"
  fi

  if [[ -d "${HOME}/.hermes" ]] && [[ ! -e "${hermes_link}" ]]; then
    need_hermes=1
  fi

  if [[ "${need_install}" -eq 0 ]] && [[ "${need_hermes}" -eq 0 ]]; then
    echo "OK: Hermes discovery present (~/.hermes/skills/${name})"
    return 0
  fi

  # Always target hermes-agent so ~/.hermes/skills/<name> is created/updated.
  # </dev/null: skills CLI must not consume the manifest install loop's stdin.
  if [[ "${source}" == *"/skill-security-review" ]] || [[ "${source}" == "tt-a1i/archify" ]]; then
    echo "Installing/linking '${name}' from ${source} (Hermes)..."
    npx -y skills add "${source}" -g -y -a hermes-agent </dev/null || true
  else
    echo "Installing/linking '${name}' from ${source} (-s ${name}, Hermes)..."
    npx -y skills add "${source}" -g -y -s "${name}" -a hermes-agent </dev/null || true
  fi

  if ! agent_skill_is_installed "${name}"; then
    echo "Error: skill '${name}' not found under ~/.agents/skills/${name}" >&2
    return 1
  fi
  echo "OK: installed '${name}'"
  if [[ -e "${hermes_link}" ]] || [[ -L "${hermes_link}" ]]; then
    echo "OK: Hermes discovers '${name}' via ~/.hermes/skills/${name}"
  elif [[ -d "${HOME}/.hermes" ]]; then
    echo "Warn: ~/.hermes exists but skills/${name} link missing after install" >&2
  fi
  if dots_skill_lock_has "${name}"; then
    echo "OK: lock entry present (~/.agents/.skill-lock.json)"
  else
    echo "Note: skill installed; lock entry may appear after skills CLI flush"
  fi
}

dots_install_skills_pack() {
  local manifest line name source
  manifest="$(dots_skills_manifest_path)"
  if [[ ! -f "${manifest}" ]]; then
    echo "Error: missing skills manifest ${manifest}" >&2
    return 1
  fi

  echo "=== Curated skills pack (${manifest}) ==="
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[dry-run] would install enabled skills from manifest"
  fi

  while IFS=$'\t' read -r name source; do
    [[ -z "${name}" ]] && continue
    install_skill_from_source "${name}" "${source}" || return 1
  done < <(dots_skills_manifest_entries)

  # Snapshot lock into repo-managed path for provenance visibility (copy, don't invent)
  if [[ "${DRY_RUN:-0}" -eq 0 ]] && [[ -f "${HOME}/.agents/.skill-lock.json" ]]; then
    ensure_dir "${HOME}/.config/dots/skills"
    cp "${HOME}/.agents/.skill-lock.json" "${HOME}/.config/dots/skills/skills-lock.json"
    echo "OK: copied skills lock → ~/.config/dots/skills/skills-lock.json"
  elif [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[dry-run] copy ~/.agents/.skill-lock.json → ~/.config/dots/skills/skills-lock.json"
  fi
}

# Update curated skills only (opt-in; not run during setup)
dots_update_skills_pack() {
  ensure_node_major 18 || return 1
  local names=()
  local name source
  while IFS=$'\t' read -r name source; do
    [[ -n "${name}" ]] && names+=("${name}")
  done < <(dots_skills_manifest_entries)
  if [[ ${#names[@]} -eq 0 ]]; then
    echo "No skills in manifest"
    return 0
  fi
  echo "Updating curated skills: ${names[*]}"
  npx -y skills update -g -y "${names[@]}" || npx -y skills update -g -y
}
