# shellcheck shell=bash
# helpers/fnm.sh — install and configure fnm-managed default Node (DOTS)
#
# Requires (from setup.sh): DIR, DRY_RUN, run_cmd, ensure_dir
# Policy file: configs/node/default.toml
#
# Ownership: DOTS uses fnm only. DOTS never installs or sources nvm.
# OpenRig (and other npm globals) must use the npm bundled with the active
# fnm-managed Node — never a stray Homebrew/system npm.

dots_node_default_version() {
	local policy="${DIR}/configs/node/default.toml"
	if [[ ! -f ${policy} ]]; then
		printf '%s\n' "24"
		return 0
	fi
	if declare -F dots_toml_query >/dev/null 2>&1; then
		dots_toml_query "${policy}" <<'PY'
print(str(data.get("version") or "24").strip() or "24")
PY
		return 0
	fi
	printf '%s\n' "24"
}

# --- diagnostics (read-only; no installs) ------------------------------------

dots_fnm_bin() {
	if command -v fnm >/dev/null 2>&1; then
		command -v fnm
		return 0
	fi
	if [[ -x /opt/homebrew/bin/fnm ]]; then
		printf '%s\n' /opt/homebrew/bin/fnm
		return 0
	fi
	if [[ -x /usr/local/bin/fnm ]]; then
		printf '%s\n' /usr/local/bin/fnm
		return 0
	fi
	return 1
}

dots_fnm_available() {
	dots_fnm_bin >/dev/null 2>&1
}

# Eval fnm env into the current shell (bash). No-op if fnm missing.
dots_fnm_eval_env() {
	local bin
	bin="$(dots_fnm_bin)" || return 1
	eval "$("${bin}" env --shell bash)"
}

dots_node_bin() {
	command -v node 2>/dev/null || true
}

dots_npm_bin() {
	command -v npm 2>/dev/null || true
}

dots_node_version_raw() {
	local bin
	bin="$(dots_node_bin)"
	[[ -n ${bin} ]] || return 1
	"${bin}" -v 2>/dev/null | sed 's/^v//' || true
}

dots_node_major() {
	local ver
	ver="$(dots_node_version_raw 2>/dev/null || true)"
	[[ -n ${ver} ]] || return 1
	printf '%s\n' "${ver%%.*}"
}

dots_npm_version_raw() {
	local bin
	bin="$(dots_npm_bin)"
	[[ -n ${bin} ]] || return 1
	"${bin}" --version 2>/dev/null || true
}

dots_npm_prefix_g() {
	local bin
	bin="$(dots_npm_bin)"
	[[ -n ${bin} ]] || return 1
	"${bin}" prefix -g 2>/dev/null || true
}

dots_npm_root_g() {
	local bin
	bin="$(dots_npm_bin)"
	[[ -n ${bin} ]] || return 1
	"${bin}" root -g 2>/dev/null || true
}

# True when node and npm share the same directory (fnm multishell / version root).
dots_npm_belongs_to_active_node() {
	local node_bin npm_bin node_dir npm_dir
	node_bin="$(dots_node_bin)"
	npm_bin="$(dots_npm_bin)"
	[[ -n ${node_bin} && -n ${npm_bin} ]] || return 1
	node_dir="$(cd "$(dirname "${node_bin}")" && pwd -P)"
	npm_dir="$(cd "$(dirname "${npm_bin}")" && pwd -P)"
	[[ ${node_dir} == "${npm_dir}" ]]
}

# True when global npm prefix is writable by the current user (no sudo needed).
dots_npm_prefix_user_owned() {
	local prefix
	prefix="$(dots_npm_prefix_g)"
	[[ -n ${prefix} ]] || return 1
	[[ -d ${prefix} ]] || return 1
	[[ -w ${prefix} ]]
}

# Reject known non-fnm system npm paths when fnm is the authority.
dots_npm_looks_fnm_managed() {
	local npm_bin node_bin
	npm_bin="$(dots_npm_bin)"
	node_bin="$(dots_node_bin)"
	[[ -n ${npm_bin} && -n ${node_bin} ]] || return 1
	case "${npm_bin}" in
	*/fnm_multishells/* | */.local/share/fnm/* | */fnm/node-versions/*)
		return 0
		;;
	esac
	case "${node_bin}" in
	*/fnm_multishells/* | */.local/share/fnm/* | */fnm/node-versions/*)
		# npm beside that node is acceptable even if path shape differs slightly
		dots_npm_belongs_to_active_node && return 0
		;;
	esac
	return 1
}

dots_node_runtime_report() {
	# Key=value lines for doctor / tests (read-only).
	local fnm_b node_b npm_b
	fnm_b="$(dots_fnm_bin 2>/dev/null || true)"
	node_b="$(dots_node_bin)"
	npm_b="$(dots_npm_bin)"
	echo "fnm_bin=${fnm_b:-}"
	if [[ -n ${fnm_b} ]]; then
		echo "fnm_version=$(${fnm_b} --version 2>/dev/null | head -1 || true)"
	else
		echo "fnm_version="
	fi
	echo "node_bin=${node_b:-}"
	echo "node_version=$(dots_node_version_raw 2>/dev/null || true)"
	echo "node_major=$(dots_node_major 2>/dev/null || true)"
	echo "npm_bin=${npm_b:-}"
	echo "npm_version=$(dots_npm_version_raw 2>/dev/null || true)"
	echo "npm_prefix_g=$(dots_npm_prefix_g 2>/dev/null || true)"
	echo "npm_root_g=$(dots_npm_root_g 2>/dev/null || true)"
	if dots_npm_belongs_to_active_node 2>/dev/null; then
		echo "npm_belongs_to_node=yes"
	else
		echo "npm_belongs_to_node=no"
	fi
	if dots_npm_prefix_user_owned 2>/dev/null; then
		echo "npm_prefix_writable=yes"
	else
		echo "npm_prefix_writable=no"
	fi
	if dots_npm_looks_fnm_managed 2>/dev/null; then
		echo "npm_fnm_managed=yes"
	else
		echo "npm_fnm_managed=no"
	fi
	echo "default_policy=$(dots_node_default_version)"
}

# --- convergence -------------------------------------------------------------

# Ensure fnm is on PATH. Does not brew-install here — callers that need packages
# must have applied Brewfile/core first. Returns 1 if still missing.
dots_fnm_ensure_on_path() {
	if dots_fnm_available; then
		dots_fnm_eval_env || true
		return 0
	fi
	return 1
}

# Install/activate a Node major (or exact version string) via fnm.
# Usage: dots_fnm_converge_node <version-or-major> [--require]
# --require: fail hard (default for OpenRig); without flag keeps historical soft warn
#            for general workstation setup.
dots_fnm_converge_node() {
	local ver="${1:-}"
	local require=0
	shift || true
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--require) require=1 ;;
		esac
		shift || true
	done
	[[ -n ${ver} ]] || ver="$(dots_node_default_version)"

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] ensure fnm; install Node ${ver} if absent; fnm default ${ver}; fnm use ${ver}"
		return 0
	fi

	if ! dots_fnm_ensure_on_path; then
		echo "Error: fnm missing — install via DOTS core/modern packages (brew fnm), then re-run setup" >&2
		[[ ${require} -eq 1 ]] && return 1
		return 0
	fi

	dots_fnm_eval_env || true
	local fnm_bin
	fnm_bin="$(dots_fnm_bin)" || return 1

	if "${fnm_bin}" list 2>/dev/null | rg -q "v?${ver}(\\.|$)|${ver} "; then
		echo "OK: fnm already has Node ${ver}"
	else
		echo "Installing Node ${ver} via fnm..."
		if ! "${fnm_bin}" install "${ver}"; then
			echo "Error: fnm install ${ver} failed" >&2
			[[ ${require} -eq 1 ]] && return 1
			return 0
		fi
	fi

	"${fnm_bin}" default "${ver}" >/dev/null 2>&1 || true
	"${fnm_bin}" use "${ver}" >/dev/null 2>&1 || true
	dots_fnm_eval_env || true

	local major got
	got="$(dots_node_version_raw 2>/dev/null || true)"
	major="$(dots_node_major 2>/dev/null || true)"
	if [[ -z ${got} ]]; then
		echo "Error: node missing after fnm converge (${ver})" >&2
		[[ ${require} -eq 1 ]] && return 1
		return 0
	fi

	# If ver is a major digit, require matching major; else prefix match.
	if [[ ${ver} =~ ^[0-9]+$ ]]; then
		if [[ ${major} != "${ver}" ]]; then
			echo "Error: active Node major is ${major}, expected ${ver} (path=$(dots_node_bin))" >&2
			[[ ${require} -eq 1 ]] && return 1
			return 0
		fi
	fi

	if ! dots_npm_belongs_to_active_node; then
		echo "Error: npm ($(dots_npm_bin)) does not belong to active node ($(dots_node_bin))" >&2
		[[ ${require} -eq 1 ]] && return 1
		return 0
	fi

	if ! dots_npm_prefix_user_owned; then
		echo "Error: npm global prefix not writable by this user ($(dots_npm_prefix_g))" >&2
		echo "       DOTS never uses sudo npm. Fix the conflicting Node/npm install." >&2
		[[ ${require} -eq 1 ]] && return 1
		return 0
	fi

	echo "OK: fnm $(${fnm_bin} --version 2>/dev/null) node=v${got} npm=$(dots_npm_version_raw) prefix=$(dots_npm_prefix_g)"
	return 0
}

# Historical workstation entrypoint (soft; used by setup.sh after Brewfile).
dots_setup_fnm_node() {
	echo "=== fnm / Node ==="
	local ver
	ver="$(dots_node_default_version)"
	dots_fnm_converge_node "${ver}" || true

	if [[ -L ${HOME}/.local/bin/node ]] && readlink "${HOME}/.local/bin/node" 2>/dev/null | rg -q '\.hermes/node'; then
		echo "Note: ~/.local/bin/node still points at Hermes private Node."
		echo "      PATH hygiene should retire it on the next setup run."
	fi
}
