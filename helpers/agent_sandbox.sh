# shellcheck shell=bash
# helpers/agent_sandbox.sh — DOTS agent-sandbox component (provider: pi-sandbox)
#
# Installing a Pi package/extension is privileged code execution. The extension
# is part of the trusted computing base and cannot sandbox itself.
# Provenance: configs/agents/pi-sandbox-provenance.toml

DOTS_PI_SANDBOX_PKG="${DOTS_PI_SANDBOX_PKG:-pi-sandbox}"
DOTS_PI_SANDBOX_REVIEWED="${DOTS_PI_SANDBOX_REVIEWED:-0.7.3}"

dots_agent_sandbox_linux_deps() {
  # bubblewrap + socat required by pi-sandbox / sandbox-runtime on Linux.
  if [[ "$(uname -s)" != "Linux" ]]; then
    return 0
  fi
  local missing=()
  command -v bwrap >/dev/null 2>&1 || missing+=(bubblewrap)
  command -v socat >/dev/null 2>&1 || missing+=(socat)
  command -v rg >/dev/null 2>&1 || missing+=(ripgrep)
  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "OK: Linux sandbox backends present (bwrap/socat/rg)"
    return 0
  fi
  echo "Note: missing sandbox backends: ${missing[*]}"
  if [[ ${DRY_RUN:-0} -eq 1 ]]; then
    echo "[dry-run] would install: ${missing[*]}"
    return 0
  fi
  # Prefer existing DOTS linux package install helpers when available.
  if declare -F dots_linux_install_named >/dev/null 2>&1; then
    dots_linux_install_named "${missing[@]}" || {
      echo "Error: failed to install ${missing[*]}" >&2
      return 1
    }
    return 0
  fi
  # Fallback: native package managers (no curl|sh).
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y "${missing[@]}" || return 1
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "${missing[@]}" || return 1
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm "${missing[@]}" || return 1
  elif command -v xbps-install >/dev/null 2>&1; then
    sudo xbps-install -Sy "${missing[@]}" || return 1
  else
    echo "Error: cannot install ${missing[*]} — unknown package manager" >&2
    return 1
  fi
}

dots_agent_sandbox_pi_ready() {
  command -v pi >/dev/null 2>&1
}

dots_agent_sandbox_installed() {
  # Detect via pi list / settings — never assume from npm alone.
  if ! dots_agent_sandbox_pi_ready; then
    return 1
  fi
  pi list 2>/dev/null | grep -qi 'pi-sandbox' && return 0
  # Fallback: npm global / pi package store hints
  if [[ -d ${HOME}/.pi/agent/packages/pi-sandbox ]] ||
    [[ -d ${HOME}/.pi/packages/pi-sandbox ]]; then
    return 0
  fi
  return 1
}

dots_agent_sandbox_install() {
  echo "=== Agent Sandbox (provider: ${DOTS_PI_SANDBOX_PKG}) ==="
  echo "WARNING: Pi packages execute with your user privileges."
  echo "         Reviewed version: ${DOTS_PI_SANDBOX_REVIEWED}"
  echo "         Provenance: configs/agents/pi-sandbox-provenance.toml"
  if [[ ${DRY_RUN:-0} -eq 1 ]]; then
    echo "[dry-run] ensure ripgrep / Linux bubblewrap+socat"
    echo "[dry-run] pi install npm:${DOTS_PI_SANDBOX_PKG}"
    echo "[dry-run] merge ~/.pi/agent/sandbox.json (DOTS policy)"
    return 0
  fi
  if ! command -v rg >/dev/null 2>&1; then
    echo "Error: ripgrep (rg) required for pi-sandbox initialization" >&2
    return 1
  fi
  dots_agent_sandbox_linux_deps || return 1
  if ! dots_agent_sandbox_pi_ready; then
    echo "Error: Pi is required for agent-sandbox. Run: ./dots setup --with pi" >&2
    return 1
  fi
  if dots_agent_sandbox_installed; then
    echo "OK: ${DOTS_PI_SANDBOX_PKG} already installed"
  else
    pi install "npm:${DOTS_PI_SANDBOX_PKG}" || {
      echo "Error: pi install npm:${DOTS_PI_SANDBOX_PKG} failed" >&2
      return 1
    }
    echo "OK: installed npm:${DOTS_PI_SANDBOX_PKG}"
  fi
  if ! dots_agent_sandbox_merge_global_policy; then
    echo "Error: failed to merge DOTS sandbox policy" >&2
    return 1
  fi
  return 0
}

dots_agent_sandbox_merge_global_policy() {
  local py project
  project="${DIR}/tools/dots_agent"
  py="${project}/.venv/bin/python"
  if [[ ! -x ${py} ]]; then
    py="$(command -v python3 || true)"
  fi
  [[ -n ${py} ]] || {
    echo "Error: python required to merge sandbox policy" >&2
    return 1
  }
  DOTS_DIR="${DIR}" "${py}" - <<'PY'
import os, sys
sys.path.insert(0, os.path.join(os.environ["DOTS_DIR"], "tools", "dots_agent"))
from dots_agent.sandbox.policy import merge_global_sandbox_policy
result = merge_global_sandbox_policy()
if not result.get("ok"):
    print(f"Error: {result.get('error')}", file=sys.stderr)
    raise SystemExit(1)
print(f"OK: sandbox policy {result.get('path')} changed={result.get('changed')}")
PY
}
