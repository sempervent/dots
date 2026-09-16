# helpers/cursor.sh — optional Cursor Agent CLI (explicit --with cursor only)
#
# Install: Homebrew cask cursor-cli (Brewfile.cursor) — preferred over curl|bash.
# Upstream also ships: curl https://cursor.com/install -fsS | bash
# which installs ~/.local/bin/{agent,cursor-agent}. We mirror that layout after
# the cask install so `command -v agent` works.
#
# Config (ONLY when cursor selected):
#   ~/.cursor/cli-config.json  — merge non-secret defaults
#   ~/.cursor/mcp.json         — merge MCP servers for co-selected tools
#
# Does NOT touch Cursor auth/tokens.
# Does NOT configure Cursor when the binary merely exists.
#
# Requires: DIR, DRY_RUN, has_component, ensure_dir, dots_may_configure_*

DOTS_CURSOR_AGENT_BIN="${DOTS_CURSOR_AGENT_BIN:-${HOME}/.local/bin/agent}"
DOTS_CURSOR_LEGACY_BIN="${DOTS_CURSOR_LEGACY_BIN:-${HOME}/.local/bin/cursor-agent}"
DOTS_CURSOR_CLI_CONFIG="${HOME}/.cursor/cli-config.json"
DOTS_CURSOR_MCP_CONFIG="${HOME}/.cursor/mcp.json"

cursor_resolve_upstream_bin() {
  if [[ -x /opt/homebrew/bin/cursor-agent ]]; then
    printf '%s\n' "/opt/homebrew/bin/cursor-agent"
    return 0
  fi
  if [[ -x /usr/local/bin/cursor-agent ]]; then
    printf '%s\n' "/usr/local/bin/cursor-agent"
    return 0
  fi
  # Official installer layout
  local verdir
  verdir="$(ls -d "${HOME}/.local/share/cursor-agent/versions/"* 2>/dev/null | sort | tail -1 || true)"
  if [[ -n "${verdir}" ]] && [[ -x "${verdir}/cursor-agent" ]]; then
    printf '%s\n' "${verdir}/cursor-agent"
    return 0
  fi
  return 1
}

# Ensure stable names: agent (official) + cursor-agent (Herdr/legacy)
ensure_cursor_agent_links() {
  local upstream
  if ! upstream="$(cursor_resolve_upstream_bin)"; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] would install Cursor Agent CLI via Brewfile.cursor (or official installer)"
      echo "[dry-run] link ${DOTS_CURSOR_AGENT_BIN} → upstream cursor-agent"
      return 0
    fi
    echo "Error: cursor-agent binary not found after Brewfile.cursor" >&2
    return 1
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] link ${DOTS_CURSOR_AGENT_BIN} → ${upstream}"
    echo "[dry-run] link ${DOTS_CURSOR_LEGACY_BIN} → ${upstream} (if missing)"
    return 0
  fi
  ensure_dir "${HOME}/.local/bin"
  ln -sfn "${upstream}" "${DOTS_CURSOR_AGENT_BIN}"
  # Prefer official agent; keep cursor-agent for Herdr / muscle memory
  if [[ ! -e "${DOTS_CURSOR_LEGACY_BIN}" ]] || [[ -L "${DOTS_CURSOR_LEGACY_BIN}" ]]; then
    ln -sfn "${upstream}" "${DOTS_CURSOR_LEGACY_BIN}"
  fi
  echo "OK: agent → ${upstream}"
  command -v agent >/dev/null 2>&1 || PATH="${HOME}/.local/bin:${PATH}"
  if command -v agent >/dev/null 2>&1; then
    echo "OK: $(agent --version 2>/dev/null | head -1) @ $(command -v agent)"
  fi
}

# Thin DOTS runner (does not duplicate upstream CLI)
install_cursor_run_wrapper() {
  local src="${DIR}/scripts/cursor-agent-run"
  local dest="${HOME}/.local/bin/cursor-agent-run"
  if [[ ! -f "${src}" ]]; then
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] link ${dest} → ${src}"
    return 0
  fi
  chmod +x "${src}"
  ln -sfn "${src}" "${dest}"
  echo "OK: ${dest}"
}

merge_cursor_cli_config() {
  local src="${DIR}/configs/cursor/cli-config.dots.json"
  local dest="${DOTS_CURSOR_CLI_CONFIG}"
  if [[ ! -f "${src}" ]]; then
    echo "Skip: missing ${src}"
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] merge Cursor cli-config defaults → ${dest} (preserve user keys)"
    return 0
  fi
  ensure_dir "$(dirname "${dest}")"
  dots_python3 - "${src}" "${dest}" <<'PY'
import json, sys
from pathlib import Path
src, dest = Path(sys.argv[1]), Path(sys.argv[2])
base = json.loads(src.read_text(encoding="utf-8"))
live = {}
if dest.is_file():
    try:
        live = json.loads(dest.read_text(encoding="utf-8"))
    except Exception:
        live = {}
# Shallow merge: live wins on conflict for top-level keys except nested permissions allow/deny extend
out = dict(base)
for k, v in live.items():
    if k == "permissions" and isinstance(v, dict) and isinstance(out.get("permissions"), dict):
        perm = dict(out["permissions"])
        for pk, pv in v.items():
            if pk in ("allow", "deny") and isinstance(pv, list):
                existing = list(perm.get(pk) or [])
                for item in pv:
                    if item not in existing:
                        existing.append(item)
                perm[pk] = existing
            else:
                perm[pk] = pv
        out["permissions"] = perm
    else:
        out[k] = v
# Strip DOTS notes from live write noise
out.pop("notes", None)
dest.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
print(f"OK: merged Cursor cli-config → {dest}")
PY
}

# Merge Draw Things MCP into Cursor only when both components selected.
merge_cursor_mcp_servers() {
  if ! dots_may_configure_cursor; then
    return 0
  fi
  local dest="${DOTS_CURSOR_MCP_CONFIG}"
  local servers_json="{}"

  if has_component drawthings; then
    servers_json="$(dots_python3 - <<'PY'
import json, os
from pathlib import Path
home = Path.home()
launcher = home / ".local" / "bin" / "drawthings-mcp"
cfg = home / ".config" / "drawthings-mcp" / "config.toml"
print(json.dumps({
  "drawthings": {
    "command": str(launcher),
    "args": [],
    "env": {
      "DOTS_DRAWTHINGS_CONFIG": str(cfg),
      "DOTS_DIR": os.environ.get("DIR", str(home / "dots")),
    },
  }
}))
PY
)"
  fi

  if [[ "${servers_json}" == "{}" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] no Cursor MCP servers to merge (select drawthings with cursor to add Draw Things)"
    fi
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] merge Cursor MCP servers → ${dest}: ${servers_json}"
    return 0
  fi

  ensure_dir "$(dirname "${dest}")"
  DIR="${DIR}" dots_python3 - "${dest}" "${servers_json}" <<'PY'
import json, sys
from pathlib import Path
dest = Path(sys.argv[1])
incoming = json.loads(sys.argv[2])
live = {"mcpServers": {}}
if dest.is_file():
    try:
        live = json.loads(dest.read_text(encoding="utf-8"))
    except Exception:
        live = {"mcpServers": {}}
servers = live.setdefault("mcpServers", {})
for name, cfg in incoming.items():
    servers[name] = cfg
    print(f"OK: Cursor MCP '{name}' → {cfg.get('command')}")
dest.write_text(json.dumps(live, indent=2) + "\n", encoding="utf-8")
print(f"OK: wrote {dest}")
PY
}

dots_setup_cursor() {
  if ! has_component cursor; then
    return 0
  fi
  echo "=== Cursor Agent CLI (explicit --with cursor) ==="
  ensure_cursor_agent_links || return 1
  install_cursor_run_wrapper || true
  merge_cursor_cli_config || true
  merge_cursor_mcp_servers || true
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    ensure_dir "${HOME}/.config/dots/managed"
    printf 'cursor\n' >"${HOME}/.config/dots/managed/cursor"
    echo "OK: managed marker ~/.config/dots/managed/cursor"
  else
    echo "[dry-run] write ~/.config/dots/managed/cursor"
  fi
  echo "Cursor auth is NOT managed by DOTS (run: agent  # first-time login)."
  echo "OpenCode/Codex are NOT registered as Cursor MCP tools (Cursor is itself a coding agent)."
}
