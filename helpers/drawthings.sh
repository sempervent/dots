# helpers/drawthings.sh — reproducible Draw Things MCP bridge installer.
#
# Dependency graph (authoritative — from code inspection):
#   Homebrew: drawthingsai/draw-things tap + draw-things-cli
#   Base Brewfile already: uv, jq (jq unused by bridge; uv required)
#   Python: 3.11+ via uv project tools/drawthings_mcp (dep: mcp>=1.2,<2)
#   stdlib only besides mcp: os, re, shutil, subprocess, tomllib, pathlib, datetime, urllib
#   Runtime binaries: draw-things-cli, uv; optional: ollama (memory.policy=unload_ollama), hermes (MCP register)
#   Draw Things.app: NOT required for CLI generation; models often live under its container path
#
# Requires from setup.sh: DIR, DRY_RUN, has_component, ensure_dir

DOTS_DRAWTHINGS_MCP_NAME="${DOTS_DRAWTHINGS_MCP_NAME:-drawthings}"
DOTS_DRAWTHINGS_LIVE_CONFIG="${HOME}/.config/drawthings-mcp/config.toml"
DOTS_DRAWTHINGS_LAUNCHER="${HOME}/.local/bin/drawthings-mcp"

drawthings_repo_config() {
  printf '%s\n' "${DIR}/configs/drawthings/config.toml"
}

drawthings_live_config() {
  printf '%s\n' "${DOTS_DRAWTHINGS_LIVE_CONFIG}"
}

drawthings_output_dir_from() {
  local cfg="$1"
  local raw
  raw="$(dots_python3 - "${cfg}" <<'PY'
import sys, tomllib
from pathlib import Path
path = Path(sys.argv[1])
cfg = tomllib.loads(path.read_text()) if path.is_file() else {}
print((cfg.get("output") or {}).get("dir", "~/Pictures/AI/DrawThings"))
PY
)"
  printf '%s\n' "${raw/#\~/${HOME}}"
}

drawthings_app_present() {
  local app="/Applications/Draw Things.app"
  if [[ -f "$(drawthings_live_config)" ]]; then
    app="$(dots_python3 - "$(drawthings_live_config)" <<'PY'
import sys, tomllib
from pathlib import Path
path = Path(sys.argv[1])
cfg = tomllib.loads(path.read_text()) if path.is_file() else {}
print((cfg.get("app") or {}).get("path", "/Applications/Draw Things.app"))
PY
)"
  fi
  [[ -d "${app/#\~/${HOME}}" ]]
}

# Deploy managed defaults without overwriting an existing live config (local overrides win).
deploy_drawthings_config() {
  local src dest
  src="$(drawthings_repo_config)"
  dest="$(drawthings_live_config)"

  if [[ ! -f "${src}" ]]; then
    echo "Error: missing repo Draw Things config: ${src}" >&2
    return 1
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] deploy ${src} → ${dest} (skip if live exists)"
    return 0
  fi

  ensure_dir "$(dirname "${dest}")"
  if [[ -f "${dest}" ]]; then
    echo "OK: live Draw Things config present (${dest})"
  else
    cp "${src}" "${dest}"
    echo "OK: deployed Draw Things config → ${dest}"
  fi
}

ensure_drawthings_output_dir() {
  local cfg dest
  cfg="$(drawthings_live_config)"
  [[ -f "${cfg}" ]] || cfg="$(drawthings_repo_config)"
  dest="$(drawthings_output_dir_from "${cfg}")"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] mkdir -p ${dest} && write-check"
    return 0
  fi
  mkdir -p "${dest}"
  if [[ ! -w "${dest}" ]]; then
    echo "Error: Draw Things output dir not writable: ${dest}" >&2
    return 1
  fi
  echo "OK: Draw Things output dir ${dest}"
}

prepare_drawthings_mcp_env() {
  local project="${DIR}/tools/drawthings_mcp"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] uv sync --directory ${project}"
    return 0
  fi
  if ! command -v uv >/dev/null 2>&1; then
    echo "Error: uv not found (required for Draw Things MCP). Install via brew/Brewfile." >&2
    return 1
  fi
  if [[ ! -f "${project}/pyproject.toml" ]]; then
    echo "Error: missing ${project}/pyproject.toml" >&2
    return 1
  fi
  # Create/update project venv + lock-resolved deps without installing a package.
  uv sync --directory "${project}" --python-preference system 2>&1 || {
    echo "Error: uv sync failed for ${project}" >&2
    return 1
  }
  echo "OK: Draw Things MCP Python env (uv project)"
}

install_drawthings_launcher() {
  local src="${DIR}/scripts/drawthings-mcp"
  local dest="${DOTS_DRAWTHINGS_LAUNCHER}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] link ${src} → ${dest}"
    return 0
  fi

  if [[ ! -f "${src}" ]]; then
    echo "Error: missing launcher source ${src}" >&2
    return 1
  fi
  chmod +x "${src}" "${DIR}/scripts/drawthings_smoke.sh" "${DIR}/scripts/drawthings_mcp_probe.sh" 2>/dev/null || true
  ensure_dir "$(dirname "${dest}")"

  if [[ -L "${dest}" ]] && [[ "$(readlink "${dest}")" == "${src}" ]]; then
    echo "OK: ${dest}"
    return 0
  fi
  if [[ -e "${dest}" ]] || [[ -L "${dest}" ]]; then
    rm -f "${dest}"
  fi
  ln -s "${src}" "${dest}"
  echo "OK: linked ${dest} → ${src}"
}

verify_drawthings_cli() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] verify draw-things-cli"
    return 0
  fi
  if ! command -v draw-things-cli >/dev/null 2>&1; then
    echo "Error: draw-things-cli missing after Brewfile.drawthings." >&2
    echo "       Check: brew tap drawthingsai/draw-things && brew install draw-things-cli" >&2
    return 1
  fi
  echo "OK: draw-things-cli → $(command -v draw-things-cli)"
  # Lightweight model inventory (no generation)
  if draw-things-cli models list --downloaded-only --offline >/tmp/dots-dt-models.$$ 2>&1; then
    local count
    count="$(dots_python3 - /tmp/dots-dt-models.$$ <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
n = 0
for line in text.splitlines():
    if re.match(r"^\S+\.ckpt\b", line.strip()):
        n += 1
print(n)
PY
)"
    rm -f /tmp/dots-dt-models.$$
    if [[ "${count}" -eq 0 ]]; then
      echo "Note: draw-things-cli works but no downloaded models found yet."
      echo "      Install models in Draw Things (or set DRAWTHINGS_MODELS_DIR). Setup will not download them."
    else
      echo "OK: ${count} downloaded Draw Things model(s) visible to CLI"
    fi
  else
    rm -f /tmp/dots-dt-models.$$
    echo "Warn: draw-things-cli models list failed (CLI present; models probe inconclusive)"
  fi
}

# Idempotent Hermes registration — ONLY when hermes was explicitly selected this run.
register_hermes_drawthings_mcp() {
  local launcher="${DOTS_DRAWTHINGS_LAUNCHER}"
  local cfg
  cfg="$(drawthings_live_config)"

  if ! dots_may_configure_hermes; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] skip Hermes MCP for drawthings (hermes not selected this run)"
    else
      echo "Note: hermes not selected — Draw Things backend only; no Hermes MCP mutation."
      echo "      Later: ./setup.sh --with hermes,drawthings"
    fi
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] register Hermes MCP '${DOTS_DRAWTHINGS_MCP_NAME}' → ${launcher}"
    return 0
  fi

  if ! command -v hermes >/dev/null 2>&1; then
    echo "Note: hermes selected but not on PATH — MCP registration deferred."
    echo "      Later: ./setup.sh --with hermes,drawthings   # or: hermes mcp add drawthings --command ${launcher}"
    return 0
  fi

  local hermes_py="${HOME}/.hermes/hermes-agent/venv/bin/python"
  if [[ ! -x "${hermes_py}" ]]; then
    echo "Warn: Hermes venv python missing; cannot register MCP non-interactively"
    echo "      Manual: hermes mcp add ${DOTS_DRAWTHINGS_MCP_NAME} --command ${launcher}"
    return 0
  fi

  "${hermes_py}" - "${DOTS_DRAWTHINGS_MCP_NAME}" "${launcher}" "${cfg}" "${DIR}" <<'PY'
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
        "DOTS_DRAWTHINGS_CONFIG": cfg,
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

write_drawthings_client_snippet() {
  local gen_dir="${HOME}/.config/dots"
  local gen_snippet="${gen_dir}/drawthings-mcp.client.json"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] write ${gen_snippet}"
    return 0
  fi
  ensure_dir "${gen_dir}"
  dots_python3 - "${gen_snippet}" "${DOTS_DRAWTHINGS_LAUNCHER}" "$(drawthings_live_config)" "${DIR}" <<'PY'
import json, sys
from pathlib import Path
dest, launcher, cfg, dots = sys.argv[1:5]
data = {
    "mcpServers": {
        "drawthings": {
            "command": launcher,
            "args": [],
            "env": {
                "DOTS_DRAWTHINGS_CONFIG": cfg,
                "DOTS_DIR": dots,
            },
        }
    }
}
Path(dest).write_text(json.dumps(data, indent=2) + "\n")
print(f"OK: wrote reusable MCP client config → {dest}")
PY
}

validate_drawthings_bridge() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] probe Draw Things MCP (status + list_models)"
    return 0
  fi
  if [[ ! -x "${DOTS_DRAWTHINGS_LAUNCHER}" ]] && [[ ! -L "${DOTS_DRAWTHINGS_LAUNCHER}" ]]; then
    echo "Error: stable launcher missing: ${DOTS_DRAWTHINGS_LAUNCHER}" >&2
    return 1
  fi
  if [[ -x "${DIR}/scripts/drawthings_mcp_probe.sh" ]]; then
    "${DIR}/scripts/drawthings_mcp_probe.sh" || {
      echo "Error: Draw Things MCP probe failed" >&2
      return 1
    }
  fi
  if dots_may_configure_hermes && command -v hermes >/dev/null 2>&1; then
    if hermes mcp test "${DOTS_DRAWTHINGS_MCP_NAME}" >/tmp/dots-hermes-dt-test.$$ 2>&1; then
      echo "OK: hermes mcp test ${DOTS_DRAWTHINGS_MCP_NAME}"
      rm -f /tmp/dots-hermes-dt-test.$$
    else
      echo "Error: hermes mcp test ${DOTS_DRAWTHINGS_MCP_NAME} failed:" >&2
      cat /tmp/dots-hermes-dt-test.$$ >&2 || true
      rm -f /tmp/dots-hermes-dt-test.$$
      return 1
    fi
  fi
}

install_img_launchers() {
  local src="${DIR}/scripts/img"
  local dest="${HOME}/.local/bin/img"
  if [[ ! -f "${src}" ]]; then
    echo "Warn: missing ${src}"
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] link ${dest} → ${src}"
    echo "[dry-run] deploy img-square / img-wide / pfl-icon helpers"
    return 0
  fi
  ensure_dir "${HOME}/.local/bin"
  chmod +x "${src}"
  ln -sfn "${src}" "${dest}"
  echo "OK: ${dest} → ${src}"

  # Thin dimension wrappers (call img; no duplicated generate logic)
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
  echo "OK: img-square, img-wide, pfl-icon → ~/.local/bin/"
}

dots_setup_drawthings() {
  if ! has_component drawthings; then
    return 0
  fi

  echo "=== Draw Things (image tool bridge) ==="

  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Warn: draw-things-cli is macOS-oriented; continuing with bridge config only."
  fi

  # Order: config → uv env → launcher → img → output → CLI verify → client MCP → probe
  deploy_drawthings_config || return 1
  prepare_drawthings_mcp_env || return 1
  install_drawthings_launcher || return 1
  install_img_launchers || true
  ensure_drawthings_output_dir || return 1

  if drawthings_app_present; then
    echo "OK: Draw Things.app present (optional at runtime; models often live under its container)"
  else
    echo "Note: Draw Things.app not found (optional)."
    echo "      CLI generation does not require the GUI process."
    echo "      Models typically live under the app container after a GUI install,"
    echo "      or set DRAWTHINGS_MODELS_DIR. Dots never auto-downloads models."
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    register_hermes_drawthings_mcp
    if dots_may_configure_cursor; then
      echo "[dry-run] Cursor MCP for drawthings (via dots_setup_cursor)"
    else
      echo "[dry-run] skip Cursor MCP for drawthings (cursor not selected this run)"
    fi
    echo "[dry-run] verify CLI / probe bridge (skipped)"
    return 0
  fi

  verify_drawthings_cli || return 1
  register_hermes_drawthings_mcp || return 1
  write_drawthings_client_snippet || true
  validate_drawthings_bridge || return 1

  echo "Draw Things is a TOOL (pixels), not a Hermes reasoning model."
  echo "img CLI: img \"prompt\"  |  img-square / img-wide / pfl-icon"
  echo "Hermes MCP only when hermes co-selected; Cursor MCP only when cursor co-selected."
  echo "Smoke (optional): ${DIR}/scripts/drawthings_smoke.sh"
}
