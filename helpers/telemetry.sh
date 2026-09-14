# helpers/telemetry.sh — deploy private local agent telemetry (base harness)
#
# Not a provider. Observational only. Never transmits off-machine.
# Requires: DIR, DRY_RUN, ensure_dir

dots_deploy_telemetry() {
  echo "=== Agent telemetry (local SQLite) ==="
  local src_cfg="${DIR}/configs/agents/telemetry.toml"
  local dest_cfg="${HOME}/.config/dots/agents/telemetry.toml"
  local bin_src="${DIR}/scripts/agent-telemetry"
  local stats_src="${DIR}/scripts/agent-stats"
  local bin_dest="${HOME}/.local/bin/agent-telemetry"
  local stats_dest="${HOME}/.local/bin/agent-stats"
  local data_dir="${HOME}/.local/share/dots/telemetry"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] ensure ${dest_cfg} (copy-if-missing)"
    echo "[dry-run] link ${bin_dest} → ${bin_src}"
    echo "[dry-run] link ${stats_dest} → ${stats_src}"
    echo "[dry-run] mkdir ${data_dir}; agent-telemetry doctor"
    return 0
  fi

  ensure_dir "$(dirname "${dest_cfg}")"
  ensure_dir "${data_dir}"
  ensure_dir "${HOME}/.local/bin"

  if [[ -f "${src_cfg}" ]] && [[ ! -f "${dest_cfg}" ]]; then
    cp "${src_cfg}" "${dest_cfg}"
    echo "OK: wrote ${dest_cfg}"
  else
    echo "OK: keep existing ${dest_cfg}"
  fi

  chmod +x "${bin_src}" "${stats_src}" 2>/dev/null || true
  ln -sfn "${bin_src}" "${bin_dest}"
  ln -sfn "${stats_src}" "${stats_dest}"
  echo "OK: ${bin_dest}"
  echo "OK: ${stats_dest}"

  if DOTS_DIR="${DIR}" "${bin_src}" doctor >/tmp/dots-tele-doctor.$$ 2>&1; then
    echo "OK: agent-telemetry doctor"
    rm -f /tmp/dots-tele-doctor.$$
  else
    echo "Warn: agent-telemetry doctor failed (non-fatal):" >&2
    cat /tmp/dots-tele-doctor.$$ >&2 || true
    rm -f /tmp/dots-tele-doctor.$$
  fi
  echo "Opt-out: DOTS_TELEMETRY=0 or enabled=false in telemetry.toml"
  echo "Stats: agent-stats   Reset: agent-telemetry reset --yes"
}
