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
  if has_component archify || has_component skills; then
    apply_brewfile "${DIR}/brew/Brewfile.archify"
  fi
  if has_component drawthings; then
    apply_brewfile "${DIR}/brew/Brewfile.drawthings"
  fi
  if has_component opencode; then
    apply_brewfile "${DIR}/brew/Brewfile.opencode"
  fi
  if has_component codex; then
    # npm @openai/codex under /opt/homebrew blocks the cask binary path — migrate first.
    if [[ "${DRY_RUN}" -eq 0 ]] && declare -F codex_is_npm_backed >/dev/null 2>&1; then
      if codex_is_npm_backed; then
        local _creal
        _creal="$(codex_real_path "$(codex_resolve_bin)")"
        if [[ "${_creal}" == /opt/homebrew/lib/node_modules/@openai/codex/* ]]; then
          codex_migrate_npm_to_cask || true
        else
          warn_codex_npm_conflict
        fi
      fi
    elif [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] migrate npm Codex if blocking Homebrew cask, then Brewfile.codex"
    fi
    apply_brewfile "${DIR}/brew/Brewfile.codex"
  fi
  if has_component images; then
    apply_brewfile "${DIR}/brew/Brewfile.images"
  fi
  if has_component tex; then
    apply_brewfile "${DIR}/brew/Brewfile.tex"
  fi
}

dots_install_requested_agent_skills() {
  # --with skills: curated Engineering Pack (includes Archify)
  if has_component skills; then
    dots_install_skills_pack || {
      echo "Error: curated skills pack installation failed." >&2
      return 1
    }
    return 0
  fi

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
    echo "[dry-run] would verify Homebrew hermes-agent wins PATH"
    return 0
  fi
  type -a hermes 2>/dev/null || true
  local hermes_win brew_hermes=""
  hermes_win="$(command -v hermes 2>/dev/null || true)"
  if [[ -x /opt/homebrew/bin/hermes ]]; then
    brew_hermes="/opt/homebrew/bin/hermes"
  elif [[ -x /usr/local/bin/hermes ]]; then
    brew_hermes="/usr/local/bin/hermes"
  fi

  if [[ -n "${brew_hermes}" ]]; then
    local win_real brew_real
    win_real="$(realpath "${hermes_win}" 2>/dev/null || echo "${hermes_win}")"
    brew_real="$(realpath "${brew_hermes}" 2>/dev/null || echo "${brew_hermes}")"
    if [[ "${hermes_win}" == "${brew_hermes}" ]] || [[ "${win_real}" == "${brew_real}" ]]; then
      echo "OK: canonical Hermes is Homebrew (${hermes_win})"
    else
      echo "Warn: Hermes on PATH is ${hermes_win} (expected Homebrew ${brew_hermes})"
      echo "      Re-run ./setup.sh (PATH hygiene) or retire ~/.local/bin/hermes"
    fi
  elif [[ "${hermes_win}" == "${HOME}/.local/bin/hermes" ]]; then
    echo "Note: using git-install Hermes at ~/.local/bin/hermes (Homebrew hermes-agent not installed)"
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
  if has_component codex || command -v codex >/dev/null 2>&1; then
    ensure_herdr_integration codex codex
  fi
  if has_component opencode || command -v opencode >/dev/null 2>&1 || command -v open-code >/dev/null 2>&1; then
    ensure_herdr_integration opencode opencode
  elif has_component herdr; then
    echo "Note: OpenCode CLI not found; skip opencode integration unless already present"
    if [[ "${DRY_RUN}" -eq 0 ]]; then
      herdr integration status 2>/dev/null | rg -i '^opencode:' || true
    fi
  fi
}
