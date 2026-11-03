# shellcheck shell=bash
# helpers/openrig.sh — OpenRig orchestration component (npm @openrig/cli)
#
# Official package: @openrig/cli  (docs: https://openrig.dev/docs/getting-started)
# Do NOT use curl|sh installers from DOTS.
# Do NOT run `rig setup` blindly — it may rewrite ~/.tmux.conf and install Herdr/providers.
#
# Ownership (Phase 4):
#   DOTS: Node, tmux policy, Herdr, Pi, Codex, LiteLLM, sandbox, routing, MCP, team templates
#   OpenRig: daemon, kernel, queue, seat lifecycle, snapshots/restore, OpenRig views

DOTS_OPENRIG_NPM_PKG="${DOTS_OPENRIG_NPM_PKG:-@openrig/cli}"
DOTS_OPENRIG_MIN_NODE="${DOTS_OPENRIG_MIN_NODE:-22.0.0}"
# Reviewed against openrig.dev docs at Phase 4 authoring (npm latest was 0.7.7).
DOTS_OPENRIG_REVIEWED_VERSION="${DOTS_OPENRIG_REVIEWED_VERSION:-0.7.7}"
DOTS_OPENRIG_REVIEWED_DATE="${DOTS_OPENRIG_REVIEWED_DATE:-2026-11-03}"

dots_openrig_node_version() {
  node -v 2>/dev/null | sed 's/^v//' || true
}

dots_openrig_node_ok() {
  local got min
  got="$(dots_openrig_node_version)"
  [[ -n ${got} ]] || return 1
  min="${DOTS_OPENRIG_MIN_NODE}"
  if printf '%s\n' "${min}" "${got}" | sort -V | head -1 | grep -qx "${min}"; then
    [[ ${got} == "${min}" ]] && return 0
    printf '%s\n' "${min}" "${got}" | sort -V | tail -1 | grep -qx "${got}"
    return $?
  fi
  return 1
}

dots_openrig_ensure_node() {
  if dots_openrig_node_ok; then
    echo "OK: Node $(dots_openrig_node_version) satisfies OpenRig (≥ ${DOTS_OPENRIG_MIN_NODE})"
    return 0
  fi
  if declare -F dots_setup_fnm_node >/dev/null 2>&1; then
    dots_setup_fnm_node || true
    if command -v fnm >/dev/null 2>&1; then
      eval "$(fnm env)" 2>/dev/null || true
    fi
  fi
  if dots_openrig_node_ok; then
    echo "OK: Node $(dots_openrig_node_version) satisfies OpenRig"
    return 0
  fi
  echo "Error: OpenRig requires Node.js ≥ ${DOTS_OPENRIG_MIN_NODE} (found: $(dots_openrig_node_version:-none))" >&2
  return 1
}

dots_openrig_version() {
  if ! command -v rig >/dev/null 2>&1; then
    return 1
  fi
  rig --version 2>/dev/null | head -1 || true
}

dots_openrig_home() {
  printf '%s\n' "${OPENRIG_HOME:-${HOME}/.openrig}"
}

# Managed tmux fragment — preserve DOTS Ctrl-Space prefix; do not run full rig setup.
dots_openrig_tmux_fragment() {
  cat <<'EOF'
# BEGIN DOTS-OPENRIG
# Compatibility fragment only — DOTS owns prefix (Ctrl-Space).
# Mouse + scrollback help OpenRig seat panes; do not change prefix here.
set -g mouse on
set -g history-limit 50000
# END DOTS-OPENRIG
EOF
}

dots_openrig_merge_tmux_fragment() {
  local conf="${HOME}/.tmux.conf"
  local fragment tmp
  fragment="$(dots_openrig_tmux_fragment)"
  if [[ ${DRY_RUN:-0} -eq 1 ]]; then
    echo "[dry-run] merge OpenRig tmux fragment into ${conf} (preserve DOTS prefix)"
    return 0
  fi
  touch "${conf}"
  if grep -q 'BEGIN DOTS-OPENRIG' "${conf}" 2>/dev/null; then
    tmp="$(mktemp)"
    # shellcheck disable=SC2016
    awk '
			/BEGIN DOTS-OPENRIG/ {skip=1; next}
			/END DOTS-OPENRIG/ {skip=0; next}
			!skip {print}
		' "${conf}" >"${tmp}"
    mv "${tmp}" "${conf}"
  fi
  {
    echo ""
    printf '%s\n' "${fragment}"
  } >>"${conf}"
  echo "OK: merged DOTS-managed OpenRig tmux fragment (prefix unchanged)"
}

dots_openrig_install() {
  echo "=== OpenRig ==="
  echo "Reviewed: ${DOTS_OPENRIG_REVIEWED_VERSION} (${DOTS_OPENRIG_REVIEWED_DATE})"
  if [[ ${DRY_RUN:-0} -eq 1 ]]; then
    echo "[dry-run] ensure Node ≥ ${DOTS_OPENRIG_MIN_NODE}"
    echo "[dry-run] npm install -g --ignore-scripts ${DOTS_OPENRIG_NPM_PKG}"
    echo "[dry-run] merge tmux fragment (not rig setup)"
    echo "[dry-run] skip Herdr/provider install (DOTS owns those)"
    return 0
  fi
  if command -v rig >/dev/null 2>&1; then
    echo "OK: OpenRig already installed ($(dots_openrig_version || echo present))"
  else
    dots_openrig_ensure_node || return 1
    if ! command -v npm >/dev/null 2>&1; then
      echo "Error: npm required to install ${DOTS_OPENRIG_NPM_PKG}" >&2
      return 1
    fi
    if ! command -v tmux >/dev/null 2>&1; then
      echo "Error: tmux required for OpenRig seats (install via herdr/modern packages)" >&2
      return 1
    fi
    npm install -g --ignore-scripts "${DOTS_OPENRIG_NPM_PKG}" || {
      echo "Error: npm install failed for ${DOTS_OPENRIG_NPM_PKG}" >&2
      return 1
    }
    echo "OK: installed ${DOTS_OPENRIG_NPM_PKG}"
  fi
  if ! command -v rig >/dev/null 2>&1; then
    echo "Error: rig not on PATH after install" >&2
    return 1
  fi
  dots_openrig_merge_tmux_fragment || true
  echo "Note: DOTS does not run 'rig setup' (avoids rewriting tmux/Herdr/providers)."
  echo "      Use: dots agent team doctor"
  return 0
}

dots_openrig_daemon_start() {
  command -v rig >/dev/null 2>&1 || {
    echo "Error: rig not installed" >&2
    return 1
  }
  if [[ ${DRY_RUN:-0} -eq 1 ]]; then
    echo "[dry-run] rig daemon start"
    return 0
  fi
  rig daemon start
}

dots_openrig_daemon_stop() {
  command -v rig >/dev/null 2>&1 || {
    echo "Error: rig not installed" >&2
    return 1
  }
  if [[ ${DRY_RUN:-0} -eq 1 ]]; then
    echo "[dry-run] rig daemon stop"
    return 0
  fi
  rig daemon stop
}

dots_openrig_status() {
  echo "OpenRig status"
  echo "  package     ${DOTS_OPENRIG_NPM_PKG}"
  echo "  reviewed    ${DOTS_OPENRIG_REVIEWED_VERSION} (${DOTS_OPENRIG_REVIEWED_DATE})"
  if command -v rig >/dev/null 2>&1; then
    echo "  installed   yes"
    echo "  version     $(dots_openrig_version || echo unknown)"
  else
    echo "  installed   no"
  fi
  echo "  state root  $(dots_openrig_home)"
  echo "  node        $(dots_openrig_node_version:-missing)"
  echo "  tmux        $(command -v tmux >/dev/null 2>&1 && echo yes || echo no)"
  echo "  herdr       $(command -v herdr >/dev/null 2>&1 && herdr --version 2>/dev/null | head -1 || echo missing)"
  echo "  pi          $(command -v pi >/dev/null 2>&1 && echo yes || echo no)"
  if command -v rig >/dev/null 2>&1; then
    rig status 2>/dev/null || echo "  daemon      (rig status unavailable)"
    rig terminal status 2>/dev/null || true
  fi
}

dots_openrig_doctor() {
  local rc=0
  echo "OpenRig doctor"
  if ! dots_openrig_node_ok; then
    echo "  FAIL  Node ≥ ${DOTS_OPENRIG_MIN_NODE} required"
    rc=1
  else
    echo "  OK    Node $(dots_openrig_node_version)"
  fi
  if ! command -v tmux >/dev/null 2>&1; then
    echo "  FAIL  tmux missing"
    rc=1
  else
    echo "  OK    tmux present"
  fi
  if ! command -v rig >/dev/null 2>&1; then
    echo "  FAIL  rig CLI missing (npm i -g ${DOTS_OPENRIG_NPM_PKG})"
    rc=1
  else
    echo "  OK    rig $(dots_openrig_version || echo present)"
    if command -v rig >/dev/null 2>&1 && rig doctor >/dev/null 2>&1; then
      echo "  OK    rig doctor"
    else
      echo "  WARN  rig doctor reported issues (run: rig doctor)"
    fi
  fi
  if command -v herdr >/dev/null 2>&1; then
    echo "  OK    Herdr preferred terminal provider"
  else
    echo "  WARN  Herdr missing — fallback to plain tmux"
  fi
  if command -v pi >/dev/null 2>&1; then
    echo "  OK    Pi runtime present"
  else
    echo "  WARN  Pi missing — default DOTS teams need Pi seats"
  fi
  if [[ -f ${HOME}/.tmux.conf ]] && grep -q 'BEGIN DOTS-OPENRIG' "${HOME}/.tmux.conf" 2>/dev/null; then
    echo "  OK    DOTS OpenRig tmux fragment present"
  else
    echo "  WARN  DOTS OpenRig tmux fragment not merged"
  fi
  if [[ -f ${HOME}/.tmux.conf ]] && ! grep -q 'prefix' "${HOME}/.tmux.conf" 2>/dev/null; then
    :
  fi
  # Never claim DOTS prefix was rewritten by OpenRig block
  if [[ -f ${HOME}/.tmux.conf ]] && grep -A5 'BEGIN DOTS-OPENRIG' "${HOME}/.tmux.conf" 2>/dev/null | grep -q 'prefix'; then
    echo "  FAIL  OpenRig fragment must not set tmux prefix"
    rc=1
  else
    echo "  OK    OpenRig fragment does not override tmux prefix"
  fi
  return "${rc}"
}

dots_openrig_kernel_status() {
  command -v rig >/dev/null 2>&1 || return 1
  rig ps --nodes --rig kernel 2>/dev/null || rig status 2>/dev/null || true
}

dots_openrig_terminal_status() {
  command -v rig >/dev/null 2>&1 || return 1
  rig terminal status 2>/dev/null || true
  if command -v herdr >/dev/null 2>&1; then
    echo "preferred_provider=herdr"
  else
    echo "preferred_provider=tmux"
  fi
}
