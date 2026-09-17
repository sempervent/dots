# shellcheck shell=bash
# helpers/optional_components.sh — optional --with component side effects.
#
# Brewfile application for optional fragments, Hermes PATH warnings, Herdr
# integrations, and agent-skill installation. Keeps setup.sh as orchestration.
#
# Requires (from setup.sh): DIR, DRY_RUN, has_component, DOTS_WITH_COMPONENTS
# Also expects agent-skill helpers from helpers/agent_skills.sh when installing skills.
# apply_optional_brewfiles expects apply_brewfile() and brew_failed in caller scope.
#
# Failure tracking: OPTIONAL_COMPONENT_FAILURES+=( "id|reason" )

OPTIONAL_COMPONENT_FAILURES=()

dots_optional_record_failure() {
	local id="$1" reason="$2"
	OPTIONAL_COMPONENT_FAILURES+=("${id}|${reason}")
	brew_failed=1
}

dots_optional_print_failures() {
	local entry id reason
	if [[ ${#OPTIONAL_COMPONENT_FAILURES[@]} -eq 0 ]]; then
		return 0
	fi
	echo "Optional component failures:" >&2
	for entry in "${OPTIONAL_COMPONENT_FAILURES[@]}"; do
		id="${entry%%|*}"
		reason="${entry#*|}"
		printf '  %-18s %s\n' "${id}" "${reason}" >&2
	done
}

apply_optional_brewfiles() {
	OPTIONAL_COMPONENT_FAILURES=()

	if has_component herdr; then
		if command -v brew >/dev/null 2>&1; then
			apply_brewfile "${DIR}/brew/Brewfile.herdr" || dots_optional_record_failure "herdr" "brew bundle failed"
		elif declare -F dots_ensure_herdr >/dev/null 2>&1; then
			# Linux without brew: official Herdr installer (Stage 0 helper)
			dots_ensure_herdr || dots_optional_record_failure "herdr" "official installer failed"
		else
			echo "Error: herdr selected but no Homebrew and no dots_ensure_herdr" >&2
			dots_optional_record_failure "herdr" "no installer available"
		fi
	fi
	if has_component hermes; then
		if ! apply_brewfile "${DIR}/brew/Brewfile.hermes"; then
			dots_optional_record_failure "hermes-agent" "brew bundle failed"
		fi
		if [[ "$(uname -s)" == "Darwin" ]]; then
			# GUI desktop: tolerate pre-existing /Applications/Hermes.app
			if declare -F dots_ensure_cask_app >/dev/null 2>&1; then
				if ! dots_ensure_cask_app "hermes-desktop" "/Applications/Hermes.app" "Hermes.app"; then
					dots_optional_record_failure "hermes-desktop" "cask installation failed"
				fi
			else
				echo "Installing hermes-desktop cask (macOS)..."
				if [[ ${DRY_RUN:-0} -eq 1 ]]; then
					echo "[dry-run] brew install --cask hermes-desktop"
				else
					brew install --cask hermes-desktop || {
						dots_optional_record_failure "hermes-desktop" "cask installation failed"
						echo "Warn: hermes-desktop cask install failed"
					}
				fi
			fi
		else
			echo "Note: hermes-desktop cask skipped (macOS only)"
		fi
	fi
	if has_component ollama; then
		apply_brewfile "${DIR}/brew/Brewfile.ollama" || dots_optional_record_failure "ollama" "brew bundle failed"
	fi
	if has_component llamacpp; then
		if command -v brew >/dev/null 2>&1; then
			apply_brewfile "${DIR}/brew/Brewfile.llamacpp" || dots_optional_record_failure "llamacpp" "brew bundle failed"
		else
			echo "Error: llamacpp selected but Homebrew is required for the canonical install." >&2
			echo "       Install Homebrew, or build llama.cpp from https://github.com/ggml-org/llama.cpp" >&2
			dots_optional_record_failure "llamacpp" "Homebrew required"
		fi
	fi
	if has_component archify || has_component skills || has_component ai-skills; then
		apply_brewfile "${DIR}/brew/Brewfile.archify" || dots_optional_record_failure "archify" "brew bundle failed"
	fi
	if has_component drawthings; then
		apply_brewfile "${DIR}/brew/Brewfile.drawthings" || dots_optional_record_failure "drawthings" "brew bundle failed"
	fi
	if has_component opencode; then
		apply_brewfile "${DIR}/brew/Brewfile.opencode" || dots_optional_record_failure "opencode" "brew bundle failed"
	fi
	if has_component codex; then
		# npm @openai/codex under /opt/homebrew blocks the cask binary path — migrate first.
		if [[ ${DRY_RUN:-0} -eq 0 ]] && declare -F codex_is_npm_backed >/dev/null 2>&1; then
			if codex_is_npm_backed; then
				local _creal
				_creal="$(codex_real_path "$(codex_resolve_bin)")"
				if [[ ${_creal} == /opt/homebrew/lib/node_modules/@openai/codex/* ]]; then
					codex_migrate_npm_to_cask || true
				else
					warn_codex_npm_conflict
				fi
			fi
		elif [[ ${DRY_RUN:-0} -eq 1 ]]; then
			echo "[dry-run] migrate npm Codex if blocking Homebrew cask, then Brewfile.codex"
		fi
		apply_brewfile "${DIR}/brew/Brewfile.codex" || dots_optional_record_failure "codex" "brew bundle failed"
	fi
	if has_component images; then
		apply_brewfile "${DIR}/brew/Brewfile.images" || dots_optional_record_failure "images" "brew bundle failed"
	fi
	if has_component tex; then
		apply_brewfile "${DIR}/brew/Brewfile.tex" || dots_optional_record_failure "tex" "brew bundle failed"
	fi
	if has_component cursor; then
		apply_brewfile "${DIR}/brew/Brewfile.cursor" || dots_optional_record_failure "cursor" "brew bundle failed"
	fi
	if has_component fluidvoice; then
		# macOS 15+ only; platform gate runs before install. No models, no launch.
		# Prefer cask-app helper so a pre-existing FluidVoice.app is not an ERROR.
		if [[ "$(uname -s)" == "Darwin" ]] && declare -F dots_ensure_cask_app >/dev/null 2>&1; then
			if ! dots_ensure_cask_app "fluidvoice" "/Applications/FluidVoice.app" "FluidVoice.app"; then
				dots_optional_record_failure "fluidvoice" "cask installation failed"
			fi
		else
			apply_brewfile "${DIR}/brew/Brewfile.fluidvoice" || dots_optional_record_failure "fluidvoice" "brew bundle failed"
		fi
	fi
}
dots_install_requested_agent_skills() {
  # Pack selection uses set semantics (union / dedupe inside dots_install_skill_packs).
  local packs=()
  if has_component skills; then
    packs+=(skills)
  fi
  if has_component ai-skills; then
    packs+=(ai-skills)
  fi

  if [[ ${#packs[@]} -gt 0 ]]; then
    # Brewfile.archify when skills pack (or archify alone) needs Node tooling path
    dots_install_skill_packs "${packs[@]}" || {
      echo "Error: skill pack installation failed (${packs[*]})." >&2
      return 1
    }
    # --with archify alongside packs: already covered if skills selected; else install once
    if has_component archify && ! has_component skills; then
      # ai-skills alone does not include archify — honor explicit archify
      install_agent_skill archify || {
        echo "Error: archify installation failed." >&2
        return 1
      }
    elif has_component archify && has_component skills; then
      echo "OK: archify covered by skills pack (no duplicate install)"
    fi
    return 0
  fi

  # archify-only (no packs)
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
  # Dry-run announces intent even when herdr is not yet on PATH (Stage 0/install follows).
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] herdr integration install ${name}"
    return 0
  fi
  if ! command -v herdr >/dev/null 2>&1; then
    echo "Skip integration ${name}: herdr not on PATH"
    return 0
  fi
  if [[ -n "${need_cli}" ]] && ! command -v "${need_cli}" >/dev/null 2>&1; then
    # Cursor: official CLI is `agent`; Brew cask also provides cursor-agent
    if [[ "${name}" == "cursor" ]]; then
      if ! command -v agent >/dev/null 2>&1 && ! command -v cursor-agent >/dev/null 2>&1; then
        echo "Skip integration cursor: agent/cursor-agent not installed"
        return 0
      fi
    else
      echo "Skip integration ${name}: ${need_cli} not installed"
      return 0
    fi
  fi
  # Idempotent: skip when status already reports current
  if herdr integration status 2>/dev/null | rg -q "^${name}:[[:space:]]*current"; then
    echo "OK: herdr integration ${name} (current)"
    return 0
  fi
  herdr integration install "${name}" 2>&1 || echo "Warn: herdr integration ${name} failed"
}

# STRICT OPT-IN: only install integrations for agents co-selected with herdr.
# Binary presence alone never authorizes herdr integration install.
dots_ensure_herdr_integrations() {
  if ! has_component herdr; then
    return 0
  fi
  echo "=== Herdr integrations (explicit co-selected agents only) ==="
  local any=0
  if dots_may_install_herdr_integration hermes; then
    any=1
    ensure_herdr_integration hermes hermes
  fi
  if dots_may_install_herdr_integration opencode; then
    any=1
    ensure_herdr_integration opencode opencode
  fi
  if dots_may_install_herdr_integration codex; then
    any=1
    ensure_herdr_integration codex codex
  fi
  if dots_may_install_herdr_integration cursor; then
    any=1
    ensure_herdr_integration cursor agent
  fi
  if [[ "${any}" -eq 0 ]]; then
    echo "Note: --with herdr alone installs Herdr only; no AI-client integrations."
    echo "      Co-select agents, e.g. --with herdr,hermes or --with herdr,cursor"
  fi
}
