# helpers/agent_router.sh — DOTS-local Hermes skill: explicit routing/delegation policy.
#
# Not an external package. Version-controlled under skills/agent-router/.
# Installed as symlinks into ~/.agents/skills and ~/.hermes/skills.

DOTS_ROUTER_SKILL_NAME="${DOTS_ROUTER_SKILL_NAME:-agent-router}"
DOTS_ROUTER_LIVE_CONFIG="${HOME}/.config/dots/agents/router.toml"

agent_router_repo_dir() {
  printf '%s\n' "${DIR}/skills/agent-router"
}

agent_router_should_install() {
  has_component hermes || has_component opencode || has_component codex ||
    has_component drawthings || has_component archify || has_component ollama
}

deploy_router_config() {
  local src="${DIR}/configs/agents/router.toml"
  local dest="${DOTS_ROUTER_LIVE_CONFIG}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] ensure ${dest}"
    return 0
  fi
  if [[ ! -f "${src}" ]]; then
    echo "Error: missing ${src}" >&2
    return 1
  fi
  ensure_dir "$(dirname "${dest}")"
  if [[ -f "${dest}" ]]; then
    echo "OK: keep existing router config ${dest}"
  else
    cp "${src}" "${dest}"
    echo "OK: wrote ${dest}"
  fi
}

install_agent_router_skill() {
  local src dest_agents dest_hermes
  src="$(agent_router_repo_dir)"
  dest_agents="${HOME}/.agents/skills/${DOTS_ROUTER_SKILL_NAME}"
  dest_hermes="${HOME}/.hermes/skills/${DOTS_ROUTER_SKILL_NAME}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] link ${dest_agents} → ${src}"
    echo "[dry-run] link ${dest_hermes} → ${src} (if ~/.hermes exists)"
    return 0
  fi

  if [[ ! -f "${src}/SKILL.md" ]]; then
    echo "Error: missing ${src}/SKILL.md" >&2
    return 1
  fi

  ensure_dir "${HOME}/.agents/skills"
  ln -sfn "${src}" "${dest_agents}"
  echo "OK: ${dest_agents} → ${src}"

  if [[ -d "${HOME}/.hermes" ]]; then
    ensure_dir "${HOME}/.hermes/skills"
    ln -sfn "${src}" "${dest_hermes}"
    echo "OK: ${dest_hermes} → ${src}"
  else
    echo "Note: ~/.hermes missing — skill linked under ~/.agents/skills; Hermes link deferred"
  fi
}

dots_setup_agent_router() {
  if ! agent_router_should_install; then
    return 0
  fi
  echo "=== Agent router (explicit delegation policy) ==="
  deploy_router_config || return 1
  install_agent_router_skill || return 1
  if [[ "${DRY_RUN}" -eq 0 ]] && [[ -x "${DIR}/scripts/router_policy_test.sh" ]]; then
    "${DIR}/scripts/router_policy_test.sh" || {
      echo "Error: router policy tests failed" >&2
      return 1
    }
  elif [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] scripts/router_policy_test.sh"
  fi
}
