# shellcheck shell=bash
# helpers/optional_components.sh — optional --with component side effects.
#
# Brewfile application for optional fragments, Hermes PATH warnings, Herdr
# integrations, and agent-skill installation. Keeps setup.sh as orchestration.
#
# Requires (from setup.sh): DIR, DRY_RUN, has_component, DOTS_WITH_COMPONENTS
# Also expects agent-skill helpers from helpers/agent_skills.sh when installing skills.
# apply_optional_brewfiles = package acquisition (before config/links).
# dots_optional_configure = post-link config (e.g. mactools deploy).
# Prefer dots_apply_brewfile_packages; else caller-defined apply_brewfile.
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

# Internal: apply one optional Brewfile via package helper or legacy apply_brewfile.
_dots_optional_apply_file() {
	local file="$1" id="$2"
	if declare -F dots_apply_brewfile_packages >/dev/null 2>&1; then
		dots_apply_brewfile_packages "${file}" "${id}" || return 1
		return 0
	fi
	if declare -F apply_brewfile >/dev/null 2>&1; then
		apply_brewfile "${file}" || return 1
		return 0
	fi
	echo "Error: no brewfile apply helper available for ${file}" >&2
	return 1
}

# Resolve brewfile path from configs/components.toml (via dots_component_brewfile).
_dots_optional_ensure_brewfile_helper() {
	if declare -F dots_component_brewfile >/dev/null 2>&1; then
		return 0
	fi
	# Prefer components.sh (registry) over package_state to avoid pulling brew helpers.
	if [[ -n ${DIR:-} && -f ${DIR}/helpers/components.sh ]]; then
		# shellcheck disable=SC1091
		source "${DIR}/helpers/components.sh" || return 1
	fi
	declare -F dots_component_brewfile >/dev/null 2>&1
}

_dots_optional_brewfile_path() {
	local id="$1" rel
	_dots_optional_ensure_brewfile_helper || {
		echo "Error: dots_component_brewfile unavailable (source helpers/components.sh)" >&2
		return 1
	}
	rel="$(dots_component_brewfile "${id}")" || return 1
	printf '%s\n' "${DIR}/${rel}"
}

# Plain Brewfile apply using registry metadata. Args: component_id [failure_id]
_dots_optional_apply_registry_brewfile() {
	local id="$1" fail_id="${2:-$1}" file
	file="$(_dots_optional_brewfile_path "${id}")" || {
		dots_optional_record_failure "${fail_id}" "no brewfile in components.toml"
		return 1
	}
	_dots_optional_apply_file "${file}" "${id}" || {
		dots_optional_record_failure "${fail_id}" "brew bundle failed"
		return 1
	}
	return 0
}

# Package acquisition for selected optional components (before config/links).
# Plain Brewfile paths come from components.toml; specialized side effects stay here.
apply_optional_brewfiles() {
	OPTIONAL_COMPONENT_FAILURES=()
	# Shared brewfile (archify/skills/ai-skills) applied at most once per run.
	local _archify_bf_done=0

	if has_component herdr; then
		if command -v brew >/dev/null 2>&1 || [[ -n ${DOTS_BREW_BIN:-} ]]; then
			_dots_optional_apply_registry_brewfile "herdr" || true
		elif declare -F dots_ensure_herdr >/dev/null 2>&1; then
			# Linux without brew: official Herdr installer (Stage 0 helper)
			dots_ensure_herdr || dots_optional_record_failure "herdr" "official installer failed"
		else
			echo "Error: herdr selected but no Homebrew and no dots_ensure_herdr" >&2
			dots_optional_record_failure "herdr" "no installer available"
		fi
	fi
	if has_component hermes; then
		_dots_optional_apply_registry_brewfile "hermes" "hermes-agent" || true
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
		_dots_optional_apply_registry_brewfile "ollama" || true
	fi
	if has_component llamacpp; then
		if command -v brew >/dev/null 2>&1 || [[ -n ${DOTS_BREW_BIN:-} ]]; then
			_dots_optional_apply_registry_brewfile "llamacpp" || true
		else
			echo "Error: llamacpp selected but Homebrew is required for the canonical install." >&2
			echo "       Install Homebrew, or build llama.cpp from https://github.com/ggml-org/llama.cpp" >&2
			dots_optional_record_failure "llamacpp" "Homebrew required"
		fi
	fi
	if has_component archify || has_component skills || has_component ai-skills; then
		if [[ ${_archify_bf_done} -eq 0 ]]; then
			_archify_bf_done=1
			# Failure id stays "archify" (shared Brewfile.archify for all three).
			local _skill_id=archify
			if has_component archify; then
				_skill_id=archify
			elif has_component skills; then
				_skill_id=skills
			else
				_skill_id=ai-skills
			fi
			_dots_optional_apply_registry_brewfile "${_skill_id}" "archify" || true
		fi
	fi
	if has_component drawthings; then
		_dots_optional_apply_registry_brewfile "drawthings" || true
	fi
	if has_component opencode; then
		_dots_optional_apply_registry_brewfile "opencode" || true
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
		_dots_optional_apply_registry_brewfile "codex" || true
	fi
	if has_component images; then
		_dots_optional_apply_registry_brewfile "images" || true
	fi
	if has_component tex; then
		_dots_optional_apply_registry_brewfile "tex" || true
	fi
	if has_component cursor; then
		_dots_optional_apply_registry_brewfile "cursor" || true
	fi
	if has_component fluidvoice; then
		# macOS 15+ only; platform gate runs before install. No models, no launch.
		# Prefer cask-app helper so a pre-existing FluidVoice.app is not an ERROR.
		if [[ "$(uname -s)" == "Darwin" ]] && declare -F dots_ensure_cask_app >/dev/null 2>&1; then
			if ! dots_ensure_cask_app "fluidvoice" "/Applications/FluidVoice.app" "FluidVoice.app"; then
				dots_optional_record_failure "fluidvoice" "cask installation failed"
			fi
		else
			_dots_optional_apply_registry_brewfile "fluidvoice" || true
		fi
	fi
	if has_component mactools; then
		# Darwin-only (registry platforms); explicit --with on Linux errors before here.
		_dots_optional_apply_registry_brewfile "mactools" || true
	fi
	if has_component lsp; then
		_dots_optional_apply_registry_brewfile "lsp" || true
	fi
	if has_component ai-server; then
		_dots_optional_apply_registry_brewfile "ai-server" || true
	fi
}

# Configuration / post-package side effects that must run AFTER backup + links.
dots_optional_configure() {
	if has_component mactools && declare -F dots_mactools_deploy_configs >/dev/null 2>&1; then
		dots_mactools_deploy_configs || true
		if declare -F dots_mactools_postinstall_notes >/dev/null 2>&1; then
			dots_mactools_postinstall_notes
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
