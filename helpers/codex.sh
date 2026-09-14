# helpers/codex.sh — Codex CLI (Homebrew cask) + Hermes MCP registration.
#
# Install source: brew install --cask codex (not npm).
# Auth: ~/.codex/ — never copied into DOTS.
#
# Codex ≥0.154 removed ``codex mcp-server``. When that subcommand is absent,
# DOTS installs a thin MCP bridge (tools/codex_mcp) wrapping ``codex exec`` and
# registers ~/.local/bin/codex-mcp with Hermes. When native mcp-server exists,
# the Hermes preset path is used.

DOTS_CODEX_MCP_NAME="${DOTS_CODEX_MCP_NAME:-codex}"
DOTS_CODEX_MCP_LAUNCHER="${HOME}/.local/bin/codex-mcp"

codex_resolve_bin() {
  local configured="${1:-codex}"
  if [[ "${configured}" == /* ]] && [[ -x "${configured}" ]]; then
    printf '%s\n' "${configured}"
    return 0
  fi
  command -v "${configured}" 2>/dev/null || command -v codex 2>/dev/null || true
}

codex_real_path() {
  local bin="$1"
  if [[ -z "${bin}" ]]; then
    return 0
  fi
  if command -v realpath >/dev/null 2>&1; then
    realpath "${bin}" 2>/dev/null || readlink "${bin}" 2>/dev/null || printf '%s\n' "${bin}"
  else
    readlink "${bin}" 2>/dev/null || printf '%s\n' "${bin}"
  fi
}

codex_is_npm_backed() {
  local bin real
  bin="$(codex_resolve_bin)"
  [[ -n "${bin}" ]] || return 1
  real="$(codex_real_path "${bin}")"
  [[ "${real}" == *"/node_modules/@openai/codex/"* ]]
}

codex_is_homebrew_cask() {
  brew list --cask codex >/dev/null 2>&1
}

codex_auth_present() {
  [[ -f "${HOME}/.codex/auth.json" ]]
}

codex_native_mcp_server_ok() {
  local bin out
  bin="$(codex_resolve_bin)"
  [[ -n "${bin}" ]] || return 1
  # Codex ≥0.154 removed the subcommand but may still exit 0 when falling through
  # to the interactive CLI ("stdin is not a terminal"). Detect by help text only.
  out="$("${bin}" mcp-server -h 2>&1 || true)"
  if printf '%s\n' "${out}" | rg -qi 'unrecognized subcommand[[:space:]]+.mcp-server'; then
    return 1
  fi
  if printf '%s\n' "${out}" | rg -qi 'Start Codex as an MCP server|mcp server \(stdio\)|Run Codex as an MCP'; then
    return 0
  fi
  return 1
}

warn_codex_npm_conflict() {
  local bin real
  bin="$(codex_resolve_bin)"
  real="$(codex_real_path "${bin}")"
  echo "Warn: Codex on PATH is npm-backed (not Homebrew cask):"
  echo "      ${bin} → ${real}"
  echo "      DOTS prefers: brew install --cask codex"
  echo "      Cleanup (preserves ~/.codex auth):"
  echo "        /opt/homebrew/bin/npm uninstall -g --prefix /opt/homebrew @openai/codex"
  echo "        brew install --cask codex"
}

codex_migrate_npm_to_cask() {
  local npm_bin pkg_dir
  pkg_dir="/opt/homebrew/lib/node_modules/@openai/codex"
  if [[ ! -d "${pkg_dir}" ]]; then
    return 1
  fi
  npm_bin="/opt/homebrew/bin/npm"
  if [[ ! -x "${npm_bin}" ]]; then
    echo "Warn: cannot auto-migrate; ${npm_bin} missing."
    warn_codex_npm_conflict
    return 1
  fi
  echo "Migrating Codex: uninstall Homebrew-prefix npm @openai/codex (auth ~/.codex untouched)..."
  if ! "${npm_bin}" uninstall -g --prefix /opt/homebrew @openai/codex; then
    echo "Warn: npm uninstall failed; attempting to remove blocking symlink only"
    if [[ -L /opt/homebrew/bin/codex ]] && [[ "$(codex_real_path /opt/homebrew/bin/codex)" == *"/node_modules/@openai/codex/"* ]]; then
      rm -f /opt/homebrew/bin/codex
    else
      return 1
    fi
  fi
  return 0
}

ensure_codex_homebrew_cask() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] ensure Homebrew cask codex (migrate npm if blocking)"
    return 0
  fi

  if codex_is_homebrew_cask; then
    echo "OK: Homebrew cask codex installed"
    if codex_is_npm_backed; then
      warn_codex_npm_conflict
    fi
    return 0
  fi

  if codex_is_npm_backed; then
    warn_codex_npm_conflict
    if [[ "$(codex_real_path "$(codex_resolve_bin)")" == /opt/homebrew/lib/node_modules/@openai/codex/* ]]; then
      codex_migrate_npm_to_cask || true
    fi
  fi

  echo "Installing Codex via Homebrew cask..."
  if ! brew install --cask codex; then
    echo "Error: brew install --cask codex failed." >&2
    if command -v codex >/dev/null 2>&1; then
      echo "       A codex binary remains on PATH." >&2
      return 0
    fi
    return 1
  fi
  echo "OK: installed Homebrew cask codex"
}

prepare_codex_mcp_bridge() {
  local project="${DIR}/tools/codex_mcp"
  local src="${DIR}/scripts/codex-mcp"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] uv sync --directory ${project}; link ${DOTS_CODEX_MCP_LAUNCHER}"
    return 0
  fi
  if [[ ! -f "${project}/pyproject.toml" ]]; then
    echo "Error: missing ${project}/pyproject.toml" >&2
    return 1
  fi
  if ! command -v uv >/dev/null 2>&1; then
    echo "Error: uv required for Codex MCP bridge" >&2
    return 1
  fi
  uv sync --directory "${project}" --python-preference system || return 1
  chmod +x "${src}" "${DIR}/scripts/codex_mcp_smoke.sh" 2>/dev/null || true
  ensure_dir "$(dirname "${DOTS_CODEX_MCP_LAUNCHER}")"
  ln -sfn "${src}" "${DOTS_CODEX_MCP_LAUNCHER}"
  echo "OK: ${DOTS_CODEX_MCP_LAUNCHER} → ${src}"
}

register_hermes_codex_mcp() {
  local mode="$1" # native | bridge
  local command args_json

  if [[ "${mode}" == "native" ]]; then
    command="$(codex_resolve_bin)"
    args_json='["mcp-server"]'
  else
    command="${DOTS_CODEX_MCP_LAUNCHER}"
    args_json='[]'
  fi

  if ! dots_may_configure_hermes; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] skip Hermes MCP for codex (hermes not selected this run)"
    else
      echo "Note: hermes not selected — Codex CLI only; no Hermes MCP mutation."
      echo "      Later: ./setup.sh --with hermes,codex"
    fi
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] register Hermes MCP '${DOTS_CODEX_MCP_NAME}' → ${command} ${args_json}"
    return 0
  fi

  if ! command -v hermes >/dev/null 2>&1; then
    echo "Note: hermes selected but not on PATH — MCP registration deferred."
    return 0
  fi

  local hermes_py="${HOME}/.hermes/hermes-agent/venv/bin/python"
  if [[ ! -x "${hermes_py}" ]]; then
    echo "Warn: Hermes venv python missing; cannot register MCP non-interactively"
    return 0
  fi

  "${hermes_py}" - "${DOTS_CODEX_MCP_NAME}" "${command}" "${args_json}" <<'PY'
import json
import sys
from pathlib import Path

name, command, args_json = sys.argv[1:4]
args = json.loads(args_json)
sys.path.insert(0, str(Path.home() / ".hermes" / "hermes-agent"))
try:
    from hermes_cli.mcp_config import _get_mcp_servers, _save_mcp_server
except Exception as exc:  # noqa: BLE001
    print(f"Warn: could not import Hermes MCP helpers ({exc})", file=sys.stderr)
    sys.exit(0)

desired = {
    "command": command,
    "args": args,
    "enabled": True,
    "connect_timeout": 60,
}

existing = _get_mcp_servers().get(name)
if isinstance(existing, dict):
    same_cmd = existing.get("command") == desired["command"]
    same_args = (existing.get("args") or []) == desired["args"]
    enabled = existing.get("enabled", True) in (True, "true", "1", "yes", None)
    transport_ok = not existing.get("url")
    if same_cmd and same_args and enabled and transport_ok:
        print(f"OK: Hermes MCP '{name}' already registered → {command} {args}")
        sys.exit(0)

if not _save_mcp_server(name, desired):
    print(f"Error: Hermes refused to save MCP server '{name}'", file=sys.stderr)
    sys.exit(1)
print(f"OK: registered Hermes MCP '{name}' → {command} {args}")
PY
}

validate_codex_mcp() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] hermes mcp test ${DOTS_CODEX_MCP_NAME}"
    return 0
  fi
  if ! dots_may_configure_hermes || ! command -v hermes >/dev/null 2>&1; then
    return 0
  fi
  if hermes mcp test "${DOTS_CODEX_MCP_NAME}" >/tmp/dots-hermes-codex-test.$$ 2>&1; then
    echo "OK: hermes mcp test ${DOTS_CODEX_MCP_NAME}"
    rm -f /tmp/dots-hermes-codex-test.$$
  else
    echo "Error: hermes mcp test ${DOTS_CODEX_MCP_NAME} failed:" >&2
    cat /tmp/dots-hermes-codex-test.$$ >&2 || true
    rm -f /tmp/dots-hermes-codex-test.$$
    return 1
  fi
}

dots_setup_codex() {
  if ! has_component codex; then
    return 0
  fi

  echo "=== Codex (frontier coding via Hermes MCP) ==="
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] ensure Homebrew cask + Codex adapter"
    if dots_may_configure_hermes; then
      echo "[dry-run] register Hermes MCP for codex (hermes co-selected)"
    else
      echo "[dry-run] skip Hermes MCP for codex (hermes not selected this run)"
    fi
    return 0
  fi

  ensure_codex_homebrew_cask || return 1

  local bin
  bin="$(codex_resolve_bin)"
  if [[ -z "${bin}" ]]; then
    echo "Error: codex missing after Homebrew cask install." >&2
    return 1
  fi
  echo "OK: codex → ${bin}"
  "${bin}" --version 2>&1 | head -2 || true

  if codex_is_npm_backed; then
    warn_codex_npm_conflict
  elif codex_is_homebrew_cask; then
    echo "OK: Codex install source is Homebrew cask"
  fi

  if codex_auth_present; then
    echo "OK: Codex auth state present (~/.codex/auth.json) — not modified"
  else
    echo "Note: Codex auth not detected (~/.codex/auth.json). MCP may work for discovery;"
    echo "      cloud tasks need interactive \`codex\` login. DOTS will not re-authenticate."
  fi

  local mcp_mode="bridge"
  if codex_native_mcp_server_ok; then
    mcp_mode="native"
    echo "OK: native \`codex mcp-server\` available — using Hermes preset path"
  else
    echo "Note: \`codex mcp-server\` unavailable on this Codex build (removed ≥0.154)."
    echo "      Installing DOTS bridge wrapping \`codex exec\` for Hermes MCP."
    prepare_codex_mcp_bridge || return 1
  fi

  register_hermes_codex_mcp "${mcp_mode}" || return 1
  validate_codex_mcp || return 1
  echo "Smoke (optional): ${DIR}/scripts/codex_mcp_smoke.sh"
}
