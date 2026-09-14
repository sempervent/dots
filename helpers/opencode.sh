# helpers/opencode.sh — OpenCode CLI adapter + optional Hermes MCP bridge.
#
# Stable launchers:
#   ~/.local/bin/opencode-agent
#   ~/.local/bin/opencode-mcp
#
# Does not start a persistent `opencode serve` daemon by default.

DOTS_OPENCODE_MCP_NAME="${DOTS_OPENCODE_MCP_NAME:-opencode}"
DOTS_OPENCODE_LIVE_EXEC_CONFIG="${HOME}/.config/dots/agents/execution.toml"
DOTS_OPENCODE_LIVE_OC_CONFIG="${HOME}/.config/opencode/opencode.jsonc"
DOTS_OPENCODE_AGENT_LAUNCHER="${HOME}/.local/bin/opencode-agent"
DOTS_OPENCODE_MCP_LAUNCHER="${HOME}/.local/bin/opencode-mcp"

opencode_repo_exec_config() {
  printf '%s\n' "${DIR}/configs/agents/execution.toml"
}

opencode_repo_oc_config() {
  printf '%s\n' "${DIR}/configs/opencode/opencode.jsonc"
}

deploy_execution_config() {
  local src dest
  src="$(opencode_repo_exec_config)"
  dest="${DOTS_OPENCODE_LIVE_EXEC_CONFIG}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] ensure ${dest} (keep existing if present)"
    return 0
  fi
  if [[ ! -f "${src}" ]]; then
    echo "Error: missing ${src}" >&2
    return 1
  fi
  ensure_dir "$(dirname "${dest}")"
  if [[ -f "${dest}" ]]; then
    echo "OK: keep existing execution config ${dest}"
  else
    cp "${src}" "${dest}"
    echo "OK: wrote ${dest}"
  fi
}

# Merge DOTS Ollama provider/model into live OpenCode config without wiping extras.
deploy_opencode_provider_config() {
  local src dest
  src="$(opencode_repo_oc_config)"
  dest="${DOTS_OPENCODE_LIVE_OC_CONFIG}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] merge Ollama provider into ${dest}"
    return 0
  fi
  if [[ ! -f "${src}" ]]; then
    echo "Error: missing ${src}" >&2
    return 1
  fi
  ensure_dir "$(dirname "${dest}")"
  python3 - "${src}" "${dest}" <<'PY'
import json
import re
import sys
from pathlib import Path

src, dest = Path(sys.argv[1]), Path(sys.argv[2])

def load_jsonc(path: Path) -> dict:
    if not path.is_file():
        return {}
    text = path.read_text()
    # Strip // line comments and /* */ blocks (best-effort for our templates)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"(?m)^\s*//.*?$", "", text)
    text = re.sub(r",\s*([}\]])", r"\1", text)
    return json.loads(text) if text.strip() else {}

desired = load_jsonc(src)
existing = load_jsonc(dest)

# Preserve unrelated keys; ensure provider.ollama + default model from template.
merged = dict(existing)
if "model" not in merged or not merged.get("model"):
    merged["model"] = desired.get("model", "ollama/qwen-hermes:latest")
provider = dict(merged.get("provider") or {})
ollama_desired = (desired.get("provider") or {}).get("ollama") or {}
ollama_existing = dict(provider.get("ollama") or {})
# Keep user overrides inside ollama but ensure npm/options/models essentials
for k, v in ollama_desired.items():
    if k == "models":
        models = dict(ollama_existing.get("models") or {})
        models.update(v or {})
        ollama_existing["models"] = models
    elif k not in ollama_existing or not ollama_existing.get(k):
        ollama_existing[k] = v
    elif k in ("npm", "options", "name"):
        ollama_existing[k] = v
provider["ollama"] = ollama_existing
merged["provider"] = provider
# Also accept newer `providers` key if present — do not delete it.
if "providers" in existing and "ollama" not in (existing.get("providers") or {}):
    pass

schema = desired.get("$schema") or existing.get("$schema") or "https://opencode.ai/config.json"
out = {"$schema": schema, **{k: v for k, v in merged.items() if k != "$schema"}}
# Put $schema first
ordered = {"$schema": schema}
for k, v in merged.items():
    if k != "$schema":
        ordered[k] = v
dest.write_text(json.dumps(ordered, indent=2) + "\n")
print(f"OK: OpenCode config → {dest}")
PY
}

prepare_opencode_mcp_env() {
  local project="${DIR}/tools/opencode_mcp"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] uv sync --directory ${project}"
    return 0
  fi
  if [[ ! -f "${project}/pyproject.toml" ]]; then
    echo "Error: missing ${project}/pyproject.toml" >&2
    return 1
  fi
  if ! command -v uv >/dev/null 2>&1; then
    echo "Error: uv required for OpenCode MCP bridge" >&2
    return 1
  fi
  uv sync --directory "${project}" --python-preference system || {
    echo "Error: uv sync failed for tools/opencode_mcp" >&2
    return 1
  }
  echo "OK: OpenCode MCP env synced"
}

install_opencode_launchers() {
  local agent_src="${DIR}/scripts/opencode-agent"
  local mcp_src="${DIR}/scripts/opencode-mcp"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] link ${DOTS_OPENCODE_AGENT_LAUNCHER} → ${agent_src}"
    echo "[dry-run] link ${DOTS_OPENCODE_MCP_LAUNCHER} → ${mcp_src}"
    return 0
  fi
  chmod +x "${agent_src}" "${mcp_src}" \
    "${DIR}/scripts/opencode_smoke.sh" "${DIR}/scripts/codex_mcp_smoke.sh" 2>/dev/null || true
  ensure_dir "$(dirname "${DOTS_OPENCODE_AGENT_LAUNCHER}")"
  ln -sfn "${agent_src}" "${DOTS_OPENCODE_AGENT_LAUNCHER}"
  ln -sfn "${mcp_src}" "${DOTS_OPENCODE_MCP_LAUNCHER}"
  echo "OK: ${DOTS_OPENCODE_AGENT_LAUNCHER} → ${agent_src}"
  echo "OK: ${DOTS_OPENCODE_MCP_LAUNCHER} → ${mcp_src}"
}

register_hermes_opencode_mcp() {
  local launcher="${DOTS_OPENCODE_MCP_LAUNCHER}"
  if ! dots_may_configure_hermes; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] skip Hermes MCP for opencode (hermes not selected this run)"
    else
      echo "Note: hermes not selected — OpenCode adapter only; no Hermes MCP mutation."
      echo "      Later: ./setup.sh --with hermes,opencode"
    fi
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] register Hermes MCP '${DOTS_OPENCODE_MCP_NAME}' → ${launcher}"
    return 0
  fi
  if ! command -v hermes >/dev/null 2>&1; then
    echo "Note: hermes selected but not on PATH — MCP registration deferred."
    echo "      Later: ./setup.sh --with hermes,opencode"
    return 0
  fi
  local hermes_py="${HOME}/.hermes/hermes-agent/venv/bin/python"
  if [[ ! -x "${hermes_py}" ]]; then
    echo "Warn: Hermes venv python missing; cannot register MCP non-interactively"
    echo "      Manual: hermes mcp add ${DOTS_OPENCODE_MCP_NAME} --command ${launcher}"
    return 0
  fi
  "${hermes_py}" - "${DOTS_OPENCODE_MCP_NAME}" "${launcher}" "${DOTS_OPENCODE_LIVE_EXEC_CONFIG}" "${DIR}" <<'PY'
import sys
from pathlib import Path

name, launcher, cfg, dots = sys.argv[1:5]
sys.path.insert(0, str(Path.home() / ".hermes" / "hermes-agent"))
try:
    from hermes_cli.mcp_config import _get_mcp_servers, _save_mcp_server
except Exception as exc:  # noqa: BLE001
    print(f"Warn: could not import Hermes MCP helpers ({exc})", file=sys.stderr)
    sys.exit(0)

desired = {
    "command": launcher,
    "args": [],
    "env": {
        "DOTS_AGENTS_EXEC_CONFIG": cfg,
        "DOTS_DIR": dots,
    },
    "enabled": True,
    "connect_timeout": 60,
}

existing = _get_mcp_servers().get(name)
if isinstance(existing, dict):
    same_cmd = existing.get("command") == desired["command"]
    same_args = (existing.get("args") or []) == desired["args"]
    same_env = (existing.get("env") or {}) == desired["env"]
    enabled = existing.get("enabled", True) in (True, "true", "1", "yes", None)
    if same_cmd and same_args and same_env and enabled:
        print(f"OK: Hermes MCP '{name}' already registered → {launcher}")
        sys.exit(0)

if not _save_mcp_server(name, desired):
    print(f"Error: Hermes refused to save MCP server '{name}'", file=sys.stderr)
    sys.exit(1)
print(f"OK: registered Hermes MCP '{name}' → {launcher}")
PY
}

validate_opencode_bridge() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] probe OpenCode adapter --help + hermes mcp test"
    return 0
  fi
  if [[ ! -x "${DOTS_OPENCODE_AGENT_LAUNCHER}" ]] && [[ ! -L "${DOTS_OPENCODE_AGENT_LAUNCHER}" ]]; then
    echo "Error: missing ${DOTS_OPENCODE_AGENT_LAUNCHER}" >&2
    return 1
  fi
  if ! "${DOTS_OPENCODE_AGENT_LAUNCHER}" --help >/dev/null 2>&1; then
    echo "Error: opencode-agent --help failed" >&2
    return 1
  fi
  echo "OK: opencode-agent --help"
  if dots_may_configure_hermes && command -v hermes >/dev/null 2>&1; then
    if hermes mcp test "${DOTS_OPENCODE_MCP_NAME}" >/tmp/dots-hermes-oc-test.$$ 2>&1; then
      echo "OK: hermes mcp test ${DOTS_OPENCODE_MCP_NAME}"
      rm -f /tmp/dots-hermes-oc-test.$$
    else
      echo "Error: hermes mcp test ${DOTS_OPENCODE_MCP_NAME} failed:" >&2
      cat /tmp/dots-hermes-oc-test.$$ >&2 || true
      rm -f /tmp/dots-hermes-oc-test.$$
      return 1
    fi
  fi
}

dots_setup_opencode() {
  if ! has_component opencode; then
    return 0
  fi

  echo "=== OpenCode (local/general coding adapter) ==="
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    deploy_execution_config
    deploy_opencode_provider_config
    prepare_opencode_mcp_env
    install_opencode_launchers
    register_hermes_opencode_mcp
    return 0
  fi

  if ! command -v opencode >/dev/null 2>&1; then
    echo "Error: opencode missing after Brewfile.opencode." >&2
    echo "       Check: brew install opencode" >&2
    return 1
  fi
  echo "OK: opencode → $(command -v opencode)"
  opencode --version 2>&1 | head -1 || true

  deploy_execution_config || return 1
  deploy_opencode_provider_config || return 1
  prepare_opencode_mcp_env || return 1
  install_opencode_launchers || return 1
  register_hermes_opencode_mcp || return 1
  validate_opencode_bridge || return 1

  echo "Manual: opencode-agent run --dir <repo> --prompt '...'"
  echo "Smoke (optional): ${DIR}/scripts/opencode_smoke.sh"
  echo "Note: default mode=standalone (no persistent opencode serve)."
}
