# helpers/launchers.sh — keep ~/.local/bin DOTS launchers linked (every setup)
#
# Launchers are deployed by optional components, but new scripts added later
# were easy to miss until the next --with re-run. This pass re-links based on
# managed/local state so new shells always find img / agent-stats / etc.
#
# Requires: DIR, DRY_RUN, ensure_dir

_dots_link_script() {
  local name="$1"
  local src="${DIR}/scripts/${name}"
  local dest="${HOME}/.local/bin/${name}"
  if [[ ! -f "${src}" ]]; then
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] link ${dest} → ${src}"
    return 0
  fi
  ensure_dir "${HOME}/.local/bin"
  chmod +x "${src}" 2>/dev/null || true
  ln -sfn "${src}" "${dest}"
  echo "OK: ${dest}"
}

_dots_write_img_wrappers() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] ensure img-square / img-wide / pfl-icon wrappers"
    return 0
  fi
  ensure_dir "${HOME}/.local/bin"
  cat >"${HOME}/.local/bin/img-square" <<'EOF'
#!/usr/bin/env bash
exec img -w 1024 -h 1024 "$@"
EOF
  cat >"${HOME}/.local/bin/img-wide" <<'EOF'
#!/usr/bin/env bash
exec img -w 1536 -h 1024 "$@"
EOF
  cat >"${HOME}/.local/bin/pfl-icon" <<'EOF'
#!/usr/bin/env bash
exec img -w 1024 -h 1024 "$@"
EOF
  chmod +x "${HOME}/.local/bin/img-square" "${HOME}/.local/bin/img-wide" "${HOME}/.local/bin/pfl-icon"
  echo "OK: img-square, img-wide, pfl-icon"
}

dots_ensure_launchers() {
  echo "=== DOTS launchers (~/.local/bin) ==="
  ensure_dir "${HOME}/.local/bin"

  # Always-on harness helpers
  _dots_link_script notify
  _dots_link_script hermes-notify-hook
  _dots_link_script agent-telemetry
  _dots_link_script agent-stats

  # Draw Things: link when already managed / previously installed
  if [[ -f "${HOME}/.config/drawthings-mcp/config.toml" ]] \
    || [[ -L "${HOME}/.local/bin/drawthings-mcp" ]] \
    || [[ -x "${HOME}/.local/bin/drawthings-mcp" ]] \
    || (declare -F has_component >/dev/null 2>&1 && has_component drawthings); then
    _dots_link_script drawthings-mcp
    _dots_link_script img
    _dots_write_img_wrappers
  fi

  # OpenCode
  if [[ -f "${HOME}/.config/dots/agents/execution.toml" ]] \
    || [[ -L "${HOME}/.local/bin/opencode-agent" ]] \
    || (declare -F has_component >/dev/null 2>&1 && has_component opencode); then
    _dots_link_script opencode-agent
    _dots_link_script opencode-mcp
  fi

  # Codex bridge launcher (safe even if native mcp-server exists)
  if [[ -L "${HOME}/.local/bin/codex-mcp" ]] \
    || [[ -x "${HOME}/.local/bin/codex-mcp" ]] \
    || (declare -F has_component >/dev/null 2>&1 && has_component codex); then
    _dots_link_script codex-mcp
  fi

  # Cursor thin runner
  if [[ -f "${HOME}/.config/dots/managed/cursor" ]] \
    || command -v agent >/dev/null 2>&1 \
    || command -v cursor-agent >/dev/null 2>&1 \
    || (declare -F has_component >/dev/null 2>&1 && has_component cursor); then
    _dots_link_script cursor-agent-run
  fi
}
