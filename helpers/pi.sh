# shellcheck shell=bash
# helpers/pi.sh — Pi coding agent component (npm; Node ≥22.19)
#
# Official package: @earendil-works/pi-coding-agent
# Docs: https://pi.dev/docs/latest/quickstart
# Do NOT use curl|sh installers from DOTS setup.

DOTS_PI_NPM_PKG="${DOTS_PI_NPM_PKG:-@earendil-works/pi-coding-agent}"
DOTS_PI_MIN_NODE="${DOTS_PI_MIN_NODE:-22.19.0}"

dots_pi_node_version() {
	node -v 2>/dev/null | sed 's/^v//' || true
}

dots_pi_node_ok() {
	local got min
	got="$(dots_pi_node_version)"
	[[ -n ${got} ]] || return 1
	min="${DOTS_PI_MIN_NODE}"
	# shellcheck disable=SC2072
	if printf '%s\n' "${min}" "${got}" | sort -V | head -1 | grep -qx "${min}"; then
		# got >= min when min sorts first or equal
		[[ ${got} == "${min}" ]] && return 0
		printf '%s\n' "${min}" "${got}" | sort -V | tail -1 | grep -qx "${got}"
		return $?
	fi
	return 1
}

dots_pi_ensure_node() {
	# Prefer existing fnm/default Node policy; do not gratuitously replace.
	if dots_pi_node_ok; then
		echo "OK: Node $(dots_pi_node_version) satisfies Pi (≥ ${DOTS_PI_MIN_NODE})"
		return 0
	fi
	if declare -F dots_setup_fnm_node >/dev/null 2>&1; then
		echo "Note: Node $(dots_pi_node_version:-missing) < ${DOTS_PI_MIN_NODE}; ensuring fnm default..."
		dots_setup_fnm_node || true
		# Refresh PATH for current shell if fnm available
		if command -v fnm >/dev/null 2>&1; then
			eval "$(fnm env)" 2>/dev/null || true
		fi
	fi
	if dots_pi_node_ok; then
		echo "OK: Node $(dots_pi_node_version) satisfies Pi"
		return 0
	fi
	echo "Error: Pi requires Node.js ≥ ${DOTS_PI_MIN_NODE} (found: $(dots_pi_node_version:-none))" >&2
	echo "       Install via fnm / modern package group, then re-run setup." >&2
	return 1
}

dots_pi_install() {
	echo "=== Pi coding agent ==="
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] ensure Node ≥ ${DOTS_PI_MIN_NODE}"
		echo "[dry-run] npm install -g --ignore-scripts ${DOTS_PI_NPM_PKG}"
		echo "[dry-run] merge Pi MCP servers (dots-model-scout, dots-expert)"
		return 0
	fi
	if command -v pi >/dev/null 2>&1; then
		echo "OK: Pi already installed ($(pi --version 2>/dev/null || echo present))"
	else
		dots_pi_ensure_node || return 1
		if ! command -v npm >/dev/null 2>&1; then
			echo "Error: npm required to install ${DOTS_PI_NPM_PKG}" >&2
			return 1
		fi
		npm install -g --ignore-scripts "${DOTS_PI_NPM_PKG}" || {
			echo "Error: npm install failed for ${DOTS_PI_NPM_PKG}" >&2
			return 1
		}
		echo "OK: installed ${DOTS_PI_NPM_PKG}"
	fi
	if ! command -v pi >/dev/null 2>&1; then
		echo "Error: pi not on PATH after install" >&2
		return 1
	fi
	pi --version 2>/dev/null || true
	dots_pi_merge_mcp || true
	dots_agent_uv_sync || true
}

dots_agent_uv_sync() {
	local project="${DIR}/tools/dots_agent"
	[[ -f ${project}/pyproject.toml ]] || return 0
	if ! command -v uv >/dev/null 2>&1; then
		echo "Warn: uv missing — skip tools/dots_agent sync" >&2
		return 0
	fi
	uv sync --directory "${project}" --python-preference system || {
		echo "Warn: uv sync failed for tools/dots_agent" >&2
		return 0
	}
	ensure_dir "${HOME}/.local/bin"
	if [[ -f ${DIR}/scripts/dots-agent ]]; then
		chmod +x "${DIR}/scripts/dots-agent" 2>/dev/null || true
		ln -sfn "${DIR}/scripts/dots-agent" "${HOME}/.local/bin/dots-agent"
	fi
	if [[ -f ${DIR}/scripts/dots-model-scout ]]; then
		chmod +x "${DIR}/scripts/dots-model-scout" 2>/dev/null || true
		ln -sfn "${DIR}/scripts/dots-model-scout" "${HOME}/.local/bin/dots-model-scout"
	fi
	if [[ -f ${DIR}/scripts/dots-expert ]]; then
		chmod +x "${DIR}/scripts/dots-expert" 2>/dev/null || true
		ln -sfn "${DIR}/scripts/dots-expert" "${HOME}/.local/bin/dots-expert"
	fi
	echo "OK: tools/dots_agent synced"
}

dots_pi_merge_mcp() {
	# Structured merge into ~/.pi/agent/mcp.json without wiping unrelated servers.
	local py
	py="$(command -v python3 || true)"
	[[ -n ${py} ]] || return 0
	DOTS_DIR="${DIR}" "${py}" - <<'PY'
import json, os, pathlib, shutil, datetime

dots = pathlib.Path(os.environ["DOTS_DIR"])
home = pathlib.Path.home()
mcp_path = home / ".pi" / "agent" / "mcp.json"
mcp_path.parent.mkdir(parents=True, exist_ok=True)

scout = str(home / ".local" / "bin" / "dots-model-scout")
expert = str(home / ".local" / "bin" / "dots-expert")
# Fall back to repo scripts when not linked yet
if not pathlib.Path(scout).exists():
    scout = str(dots / "scripts" / "dots-model-scout")
if not pathlib.Path(expert).exists():
    expert = str(dots / "scripts" / "dots-expert")

desired = {
    "dots-model-scout": {
        "command": scout,
        "args": [],
        "env": {},
    },
    "dots-expert": {
        "command": expert,
        "args": [],
        "env": {},
    },
}

data = {"mcpServers": {}}
if mcp_path.is_file():
    try:
        data = json.loads(mcp_path.read_text(encoding="utf-8"))
    except Exception:
        bak = mcp_path.with_suffix(
            mcp_path.suffix + f".bak-{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}"
        )
        shutil.copy2(mcp_path, bak)
        data = {"mcpServers": {}}

servers = data.get("mcpServers")
if not isinstance(servers, dict):
    servers = {}
    data["mcpServers"] = servers

changed = False
for name, cfg in desired.items():
    existing = servers.get(name)
    if existing == cfg:
        continue
    servers[name] = cfg
    changed = True

if changed:
    if mcp_path.is_file():
        bak = mcp_path.with_suffix(
            mcp_path.suffix + f".bak-{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}"
        )
        shutil.copy2(mcp_path, bak)
    mcp_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"OK: merged DOTS MCP servers into {mcp_path}")
else:
    print(f"OK: Pi MCP configuration already converged ({mcp_path})")
PY
}
