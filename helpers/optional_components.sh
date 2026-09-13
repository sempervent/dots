# helpers/optional_components.sh — optional --with component side effects.
#
# Brewfile application for optional fragments, Hermes PATH warnings, Herdr
# integrations, and agent-skill installation. Keeps setup.sh as orchestration.
#
# Requires (from setup.sh): DIR, DRY_RUN, has_component, DOTS_WITH_COMPONENTS
# Also expects agent-skill helpers from helpers/agent_skills.sh when installing skills.
# apply_optional_brewfiles expects apply_brewfile() and brew_failed in caller scope.

apply_optional_brewfiles() {
  if has_component herdr; then
    apply_brewfile "${DIR}/brew/Brewfile.herdr"
  fi
  if has_component hermes; then
    apply_brewfile "${DIR}/brew/Brewfile.hermes"
    if [[ "$(uname -s)" == "Darwin" ]]; then
      echo "Installing hermes-desktop cask (macOS)..."
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "[dry-run] brew install --cask hermes-desktop"
      else
        brew install --cask hermes-desktop || {
          brew_failed=1
          echo "Warn: hermes-desktop cask install failed"
        }
      fi
    else
      echo "Note: hermes-desktop cask skipped (macOS only)"
    fi
  fi
  if has_component ollama; then
    apply_brewfile "${DIR}/brew/Brewfile.ollama"
  fi
  if has_component archify; then
    apply_brewfile "${DIR}/brew/Brewfile.archify"
  fi
  if has_component drawthings; then
    apply_brewfile "${DIR}/brew/Brewfile.drawthings"
  fi
}

dots_install_requested_agent_skills() {
  local c want_skills=0
  [[ ${#DOTS_WITH_COMPONENTS[@]} -gt 0 ]] || return 0
  for c in "${DOTS_WITH_COMPONENTS[@]}"; do
    if is_agent_skill_component "${c}"; then
      want_skills=1
      break
    fi
  done
  [[ "${want_skills}" -eq 1 ]] || return 0
  install_requested_agent_skills || {
    echo "Error: agent skill installation failed." >&2
    return 1
  }
}

dots_check_hermes_path() {
  if ! has_component hermes && ! command -v hermes >/dev/null 2>&1; then
    return 0
  fi
  echo "=== Hermes PATH check ==="
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] would run: type -a hermes"
    return 0
  fi
  type -a hermes 2>/dev/null || true
  local hermes_win
  hermes_win="$(command -v hermes 2>/dev/null || true)"
  if [[ "${hermes_win}" == "${HOME}/.local/bin/hermes" ]]; then
    echo "Warn: ~/.local/bin/hermes currently wins PATH (likely git install)."
    echo "      After verifying Homebrew hermes-agent, remove/rename the old shim manually."
    echo "      Prefer Homebrew PATH (brew shellenv) ahead of ~/.local/bin if desired."
  fi
}

ensure_herdr_integration() {
  local name="$1" need_cli="$2"
  if ! command -v herdr >/dev/null 2>&1; then
    return 0
  fi
  if [[ -n "${need_cli}" ]] && ! command -v "${need_cli}" >/dev/null 2>&1; then
    echo "Skip integration ${name}: ${need_cli} not installed"
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] herdr integration install ${name} (if needed)"
    return 0
  fi
  # Idempotent: skip when status already reports current
  if herdr integration status 2>/dev/null | rg -q "^${name}:[[:space:]]*current"; then
    echo "OK: herdr integration ${name} (current)"
    return 0
  fi
  herdr integration install "${name}" 2>&1 || echo "Warn: herdr integration ${name} failed"
}

dots_ensure_herdr_integrations() {
  if ! has_component herdr && ! command -v herdr >/dev/null 2>&1; then
    return 0
  fi
  echo "=== Herdr integrations ==="
  ensure_herdr_integration hermes hermes
  ensure_herdr_integration codex codex
  if command -v opencode >/dev/null 2>&1 || command -v open-code >/dev/null 2>&1; then
    ensure_herdr_integration opencode opencode
  elif has_component herdr; then
    echo "Note: OpenCode CLI not found; skip opencode integration unless already present"
    if [[ "${DRY_RUN}" -eq 0 ]]; then
      herdr integration status 2>/dev/null | rg -i '^opencode:' || true
    fi
  fi
}
