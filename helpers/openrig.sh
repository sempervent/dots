# shellcheck shell=bash
# helpers/openrig.sh — OpenRig orchestration component (npm @openrig/cli)
#
# Official package: @openrig/cli  (docs: https://openrig.dev/docs/getting-started)
# Reviewed: 0.7.7 / 2026-11-03 — Node 22 or 24 (prefer 22; Apple silicon: 22).
# Do NOT use curl|sh installers from DOTS.
# Do NOT run `rig setup` — it may rewrite ~/.tmux.conf and install Herdr/providers.
# Do NOT use nvm — DOTS Node ownership is fnm only.
#
# Ownership (v1.6+):
#   DOTS: fnm, Node, npm, tmux, Herdr, Pi, Codex, LiteLLM, sandbox, routing, MCP, templates
#   OpenRig: daemon, kernel, queue, seat lifecycle, snapshots/restore, OpenRig views

DOTS_OPENRIG_NPM_PKG="${DOTS_OPENRIG_NPM_PKG:-@openrig/cli}"
DOTS_OPENRIG_NODE_MAJOR="${DOTS_OPENRIG_NODE_MAJOR:-22}"
DOTS_OPENRIG_NODE_ACCEPTED="${DOTS_OPENRIG_NODE_ACCEPTED:-22 24}"
DOTS_OPENRIG_REVIEWED_VERSION="${DOTS_OPENRIG_REVIEWED_VERSION:-0.7.7}"
DOTS_OPENRIG_REVIEWED_DATE="${DOTS_OPENRIG_REVIEWED_DATE:-2026-11-03}"
DOTS_OPENRIG_ABI_SCRIPT="${DOTS_OPENRIG_ABI_SCRIPT:-scripts/check-abi.mjs}"
DOTS_OPENRIG_MAX_ABI_REINSTALLS="${DOTS_OPENRIG_MAX_ABI_REINSTALLS:-1}"

dots_openrig_load_runtime_policy() {
	local policy="${DIR}/configs/agents/openrig/runtime.toml"
	[[ -f ${policy} ]] || return 0
	if ! declare -F dots_toml_query >/dev/null 2>&1; then
		return 0
	fi
	local pref accepted pkg reviewed date abi
	pref="$(
		dots_toml_query "${policy}" <<'PY'
n = data.get("node") or {}
print(str(n.get("preferred_major") or "22").strip())
PY
	)"
	accepted="$(
		dots_toml_query "${policy}" <<'PY'
n = data.get("node") or {}
vals = n.get("accepted_majors") or [22, 24]
print(" ".join(str(int(x)) for x in vals))
PY
	)"
	pkg="$(
		dots_toml_query "${policy}" <<'PY'
p = data.get("package") or {}
print(str(p.get("name") or "@openrig/cli").strip())
PY
	)"
	reviewed="$(
		dots_toml_query "${policy}" <<'PY'
p = data.get("package") or {}
print(str(p.get("reviewed_version") or "0.7.7").strip())
PY
	)"
	date="$(
		dots_toml_query "${policy}" <<'PY'
p = data.get("package") or {}
print(str(p.get("reviewed_date") or "").strip())
PY
	)"
	abi="$(
		dots_toml_query "${policy}" <<'PY'
p = data.get("package") or {}
print(str(p.get("abi_script") or "scripts/check-abi.mjs").strip())
PY
	)"
	[[ -n ${pref} ]] && DOTS_OPENRIG_NODE_MAJOR="${pref}"
	[[ -n ${accepted} ]] && DOTS_OPENRIG_NODE_ACCEPTED="${accepted}"
	[[ -n ${pkg} ]] && DOTS_OPENRIG_NPM_PKG="${pkg}"
	[[ -n ${reviewed} ]] && DOTS_OPENRIG_REVIEWED_VERSION="${reviewed}"
	[[ -n ${date} ]] && DOTS_OPENRIG_REVIEWED_DATE="${date}"
	[[ -n ${abi} ]] && DOTS_OPENRIG_ABI_SCRIPT="${abi}"
}

dots_openrig_node_version() {
	dots_node_version_raw 2>/dev/null || node -v 2>/dev/null | sed 's/^v//' || true
}

dots_openrig_node_major() {
	dots_node_major 2>/dev/null || true
}

dots_openrig_node_accepted() {
	local major want
	major="$(dots_openrig_node_major)"
	[[ -n ${major} ]] || return 1
	for want in ${DOTS_OPENRIG_NODE_ACCEPTED}; do
		[[ ${major} == "${want}" ]] && return 0
	done
	return 1
}

dots_openrig_node_ok() {
	dots_openrig_node_accepted
}

# Converge fnm + Node for OpenRig. Prefer preferred_major when installing;
# accept any accepted major that is already active with a matching npm.
dots_openrig_ensure_node() {
	dots_openrig_load_runtime_policy
	local major
	major="$(dots_openrig_node_major 2>/dev/null || true)"

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] ensure fnm"
		echo "[dry-run] ensure Node ${DOTS_OPENRIG_NODE_MAJOR} (accepted: ${DOTS_OPENRIG_NODE_ACCEPTED})"
		echo "[dry-run] verify npm belongs to active Node"
		echo "[dry-run] verify npm global prefix is user-owned (no sudo)"
		return 0
	fi

	if ! declare -F dots_fnm_converge_node >/dev/null 2>&1; then
		echo "Error: fnm helper missing (source helpers/fnm.sh)" >&2
		return 1
	fi

	if ! dots_fnm_available; then
		echo "Error: fnm missing — ./dots setup installs it via core packages before OpenRig" >&2
		echo "       Repair: ./dots setup --with openrig" >&2
		return 1
	fi

	# Already on an accepted major with matching npm → keep it.
	if dots_openrig_node_ok && dots_npm_belongs_to_active_node && dots_npm_prefix_user_owned; then
		echo "OK: Node $(dots_openrig_node_version) accepted for OpenRig (majors: ${DOTS_OPENRIG_NODE_ACCEPTED})"
		return 0
	fi

	# Otherwise converge preferred major (22).
	echo "Converging Node ${DOTS_OPENRIG_NODE_MAJOR} via fnm for OpenRig..."
	dots_fnm_converge_node "${DOTS_OPENRIG_NODE_MAJOR}" --require || return 1

	if ! dots_openrig_node_ok; then
		echo "Error: OpenRig requires Node major in (${DOTS_OPENRIG_NODE_ACCEPTED}); found $(dots_openrig_node_version:-none)" >&2
		return 1
	fi
	if ! dots_npm_belongs_to_active_node; then
		echo "Error: npm does not belong to active Node (node=$(dots_node_bin) npm=$(dots_npm_bin))" >&2
		return 1
	fi
	if ! dots_npm_prefix_user_owned; then
		echo "Error: npm global prefix not user-writable; refusing sudo npm" >&2
		return 1
	fi
	echo "OK: Node $(dots_openrig_node_version) ready for OpenRig (npm=$(dots_npm_bin))"
	return 0
}

dots_openrig_version() {
	local rig_bin
	rig_bin="$(dots_openrig_rig_bin 2>/dev/null || true)"
	[[ -n ${rig_bin} ]] || return 1
	"${rig_bin}" --version 2>/dev/null | head -1 || true
}

dots_openrig_home() {
	printf '%s\n' "${OPENRIG_HOME:-${HOME}/.openrig}"
}

dots_openrig_expected_rig_bin() {
	local prefix
	prefix="$(dots_npm_prefix_g 2>/dev/null || true)"
	[[ -n ${prefix} ]] || return 1
	printf '%s\n' "${prefix}/bin/rig"
}

# Prefer the rig that belongs to the active npm prefix; fall back to PATH only
# when it resolves to that same prefix (reject stale PATH hits).
dots_openrig_rig_bin() {
	local expected path
	expected="$(dots_openrig_expected_rig_bin 2>/dev/null || true)"
	if [[ -n ${expected} && -x ${expected} ]]; then
		printf '%s\n' "${expected}"
		return 0
	fi
	path="$(command -v rig 2>/dev/null || true)"
	[[ -n ${path} ]] || return 1
	if [[ -n ${expected} ]]; then
		local rp ep
		rp="$(cd "$(dirname "${path}")" && pwd -P)/$(basename "${path}")"
		ep="$(cd "$(dirname "${expected}")" && pwd -P)/$(basename "${expected}")"
		if [[ ${rp} != "${ep}" ]]; then
			# Stale PATH entry from another Node prefix
			return 1
		fi
	fi
	printf '%s\n' "${path}"
}

# Package state under the ACTIVE npm prefix.
# Prints one of: MISSING|INSTALLED_COMPATIBLE|INSTALLED_WRONG_PREFIX|INSTALLED_BROKEN|INSTALLED_VERSION_MISMATCH
dots_openrig_package_state() {
	local npm_bin root expected list_out path_rig
	npm_bin="$(dots_npm_bin)"
	[[ -n ${npm_bin} ]] || {
		echo "MISSING"
		return 0
	}
	root="$("${npm_bin}" root -g 2>/dev/null || true)"
	expected="$(dots_openrig_expected_rig_bin 2>/dev/null || true)"
	path_rig="$(command -v rig 2>/dev/null || true)"

	list_out="$("${npm_bin}" list -g --depth=0 "${DOTS_OPENRIG_NPM_PKG}" 2>/dev/null || true)"
	if ! printf '%s\n' "${list_out}" | grep -Fq "${DOTS_OPENRIG_NPM_PKG}@"; then
		if [[ -n ${path_rig} && -n ${expected} && ${path_rig} != "${expected}" && -x ${path_rig} ]]; then
			echo "INSTALLED_WRONG_PREFIX"
			return 0
		fi
		echo "MISSING"
		return 0
	fi

	if [[ -n ${expected} && ! -x ${expected} ]]; then
		echo "INSTALLED_BROKEN"
		return 0
	fi

	if [[ -n ${path_rig} && -n ${expected} ]]; then
		local rp ep
		rp="$(cd "$(dirname "${path_rig}")" 2>/dev/null && pwd -P)/$(basename "${path_rig}")"
		ep="$(cd "$(dirname "${expected}")" 2>/dev/null && pwd -P)/$(basename "${expected}")"
		if [[ -n ${rp} && -n ${ep} && ${rp} != "${ep}" ]]; then
			echo "INSTALLED_WRONG_PREFIX"
			return 0
		fi
	fi

	if ! dots_openrig_rig_bin >/dev/null 2>&1; then
		echo "INSTALLED_BROKEN"
		return 0
	fi
	if ! dots_openrig_version >/dev/null 2>&1; then
		echo "INSTALLED_BROKEN"
		return 0
	fi
	echo "INSTALLED_COMPATIBLE"
}

# Scoped package path: $(npm root -g)/@openrig/cli
dots_openrig_package_root() {
	local root
	root="$(dots_npm_root_g 2>/dev/null || true)"
	[[ -n ${root} ]] || return 1
	printf '%s\n' "${root}/${DOTS_OPENRIG_NPM_PKG}"
}

dots_openrig_abi_script() {
	local pkg_root
	pkg_root="$(dots_openrig_package_root)" || return 1
	printf '%s\n' "${pkg_root}/${DOTS_OPENRIG_ABI_SCRIPT}"
}

dots_openrig_check_abi() {
	local node_bin script
	node_bin="$(dots_node_bin)"
	[[ -n ${node_bin} ]] || {
		echo "Error: node missing for ABI check" >&2
		return 1
	}
	script="$(dots_openrig_abi_script)" || {
		echo "Error: cannot resolve OpenRig package root" >&2
		return 1
	}
	if [[ ! -f ${script} ]]; then
		echo "Error: ABI script absent: ${script}" >&2
		echo "       OpenRig package may be incomplete under $(dots_npm_root_g)" >&2
		return 1
	fi
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] ${node_bin} ${script}"
		return 0
	fi
	if ! "${node_bin}" "${script}"; then
		echo "Error: OpenRig Node/SQLite ABI check failed" >&2
		return 1
	fi
	echo "OK: OpenRig ABI check passed"
	return 0
}

dots_openrig_npm_install() {
	local npm_bin
	npm_bin="$(dots_npm_bin)"
	[[ -n ${npm_bin} ]] || {
		echo "Error: npm missing" >&2
		return 1
	}
	if ! dots_npm_belongs_to_active_node; then
		echo "Error: refusing to install with npm unbound to active Node" >&2
		return 1
	fi
	if ! dots_npm_prefix_user_owned; then
		echo "Error: refusing sudo npm — global prefix not user-owned" >&2
		return 1
	fi
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] ${npm_bin} install -g ${DOTS_OPENRIG_NPM_PKG}"
		return 0
	fi
	# Do not pass --ignore-scripts: postinstall may run ABI check.
	# npm 11+ may still skip scripts; we always re-run check-abi explicitly.
	echo "Installing ${DOTS_OPENRIG_NPM_PKG} with ${npm_bin} (prefix=$(dots_npm_prefix_g))..."
	"${npm_bin}" install -g "${DOTS_OPENRIG_NPM_PKG}" || {
		echo "Error: npm install failed for ${DOTS_OPENRIG_NPM_PKG}" >&2
		return 1
	}
	return 0
}

dots_openrig_verify_runtime() {
	local rig_bin
	rig_bin="$(dots_openrig_rig_bin)" || {
		echo "Error: rig not available under active npm prefix ($(dots_npm_prefix_g)/bin)" >&2
		return 1
	}
	if ! "${rig_bin}" --version >/dev/null 2>&1; then
		echo "Error: rig --version failed (${rig_bin})" >&2
		return 1
	fi
	"${rig_bin}" --help >/dev/null 2>&1 || true
	echo "OK: rig $(dots_openrig_version) @ ${rig_bin}"
	return 0
}

# Install/repair with at most one ABI-driven reinstall.
dots_openrig_install_cli() {
	local state reinstalls=0
	state="$(dots_openrig_package_state)"
	case "${state}" in
	INSTALLED_COMPATIBLE)
		echo "OK: OpenRig already installed ($(dots_openrig_version || echo present))"
		;;
	MISSING | INSTALLED_WRONG_PREFIX | INSTALLED_BROKEN | INSTALLED_VERSION_MISMATCH)
		echo "OpenRig package state: ${state}"
		dots_openrig_npm_install || return 1
		echo "OK: installed ${DOTS_OPENRIG_NPM_PKG}"
		;;
	*)
		echo "Error: unknown OpenRig package state: ${state}" >&2
		return 1
		;;
	esac

	dots_openrig_verify_runtime || return 1

	while true; do
		if dots_openrig_check_abi; then
			return 0
		fi
		if [[ ${reinstalls} -ge ${DOTS_OPENRIG_MAX_ABI_REINSTALLS} ]]; then
			echo "Error: ABI still failing after reinstall — see: dots agent team doctor" >&2
			return 1
		fi
		echo "ABI failed — reinstalling ${DOTS_OPENRIG_NPM_PKG} under active Node once..."
		dots_openrig_npm_install || return 1
		dots_openrig_verify_runtime || return 1
		reinstalls=$((reinstalls + 1))
	done
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
	dots_openrig_load_runtime_policy
	echo "=== OpenRig ==="
	echo "Reviewed: ${DOTS_OPENRIG_REVIEWED_VERSION} (${DOTS_OPENRIG_REVIEWED_DATE})"
	echo "Node policy: preferred=${DOTS_OPENRIG_NODE_MAJOR} accepted=${DOTS_OPENRIG_NODE_ACCEPTED} (fnm; never nvm)"

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		dots_openrig_ensure_node
		echo "[dry-run] inspect package state under active npm"
		echo "[dry-run] npm install -g ${DOTS_OPENRIG_NPM_PKG} (if needed)"
		echo "[dry-run] verify rig under npm prefix"
		echo "[dry-run] run ABI check: node \"\$(npm root -g)/${DOTS_OPENRIG_NPM_PKG}/${DOTS_OPENRIG_ABI_SCRIPT}\""
		echo "[dry-run] merge tmux fragment (not rig setup)"
		echo "[dry-run] skip Herdr/provider install (DOTS owns those)"
		return 0
	fi

	dots_openrig_ensure_node || return 1

	if ! command -v tmux >/dev/null 2>&1; then
		echo "Error: tmux required for OpenRig seats (install via herdr/modern packages)" >&2
		return 1
	fi

	dots_openrig_install_cli || return 1
	dots_openrig_merge_tmux_fragment || true
	echo "Note: DOTS does not run 'rig setup' (avoids rewriting tmux/Herdr/providers)."
	echo "      Use: dots agent team doctor"
	echo "OK: OpenRig desired state converged"
	return 0
}

dots_openrig_daemon_start() {
	local rig_bin
	rig_bin="$(dots_openrig_rig_bin)" || {
		echo "Error: rig not installed" >&2
		return 1
	}
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] rig daemon start"
		return 0
	fi
	"${rig_bin}" daemon start
}

dots_openrig_daemon_stop() {
	local rig_bin
	rig_bin="$(dots_openrig_rig_bin)" || {
		echo "Error: rig not installed" >&2
		return 1
	}
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] rig daemon stop"
		return 0
	fi
	"${rig_bin}" daemon stop
}

dots_openrig_status() {
	dots_openrig_load_runtime_policy
	echo "OpenRig status"
	echo "  package     ${DOTS_OPENRIG_NPM_PKG}"
	echo "  reviewed    ${DOTS_OPENRIG_REVIEWED_VERSION} (${DOTS_OPENRIG_REVIEWED_DATE})"
	echo "  node policy preferred=${DOTS_OPENRIG_NODE_MAJOR} accepted=${DOTS_OPENRIG_NODE_ACCEPTED}"
	if dots_openrig_rig_bin >/dev/null 2>&1; then
		echo "  installed   yes"
		echo "  version     $(dots_openrig_version || echo unknown)"
		echo "  executable  $(dots_openrig_rig_bin)"
		echo "  pkg state   $(dots_openrig_package_state)"
	else
		echo "  installed   no"
		echo "  pkg state   $(dots_openrig_package_state)"
	fi
	echo "  state root  $(dots_openrig_home)"
	echo "  node        $(dots_openrig_node_version:-missing) @ $(dots_node_bin 2>/dev/null || echo none)"
	echo "  npm         $(dots_npm_bin 2>/dev/null || echo none)"
	echo "  npm prefix  $(dots_npm_prefix_g 2>/dev/null || echo none)"
	echo "  tmux        $(command -v tmux >/dev/null 2>&1 && echo yes || echo no)"
	echo "  herdr       $(command -v herdr >/dev/null 2>&1 && herdr --version 2>/dev/null | head -1 || echo missing)"
	echo "  pi          $(command -v pi >/dev/null 2>&1 && echo yes || echo no)"
	if dots_openrig_rig_bin >/dev/null 2>&1; then
		local rig_bin
		rig_bin="$(dots_openrig_rig_bin)"
		"${rig_bin}" status 2>/dev/null || echo "  daemon      (rig status unavailable)"
		"${rig_bin}" terminal status 2>/dev/null || true
	fi
}

# Read-only doctor — never installs.
dots_openrig_doctor() {
	dots_openrig_load_runtime_policy
	local rc=0
	local state abi_note="n/a"

	echo "OpenRig Runtime"
	echo "────────────────────────────────────"
	echo ""
	echo "fnm"
	if dots_fnm_available; then
		echo "  status              OK ($(dots_fnm_bin))"
	else
		echo "  status              FAIL missing"
		rc=1
	fi
	echo ""
	echo "Node"
	echo "  policy              preferred ${DOTS_OPENRIG_NODE_MAJOR} (accepted: ${DOTS_OPENRIG_NODE_ACCEPTED})"
	if dots_openrig_node_ok; then
		echo "  version             $(dots_openrig_node_version)  OK"
		echo "  path                $(dots_node_bin)"
	else
		echo "  version             $(dots_openrig_node_version:-missing)  FAIL"
		echo "  path                $(dots_node_bin:-none)"
		rc=1
	fi
	echo ""
	echo "npm"
	if [[ -n $(dots_npm_bin) ]]; then
		echo "  version             $(dots_npm_version_raw)"
		echo "  path                $(dots_npm_bin)"
		echo "  global prefix       $(dots_npm_prefix_g)"
		echo "  global root         $(dots_npm_root_g)"
		if dots_npm_belongs_to_active_node; then
			echo "  belongs to Node     OK"
		else
			echo "  belongs to Node     FAIL"
			rc=1
		fi
		if dots_npm_prefix_user_owned; then
			echo "  prefix writable     OK"
		else
			echo "  prefix writable     FAIL (no sudo npm)"
			rc=1
		fi
	else
		echo "  status              FAIL missing"
		rc=1
	fi
	echo ""
	echo "OpenRig"
	echo "  package             ${DOTS_OPENRIG_NPM_PKG}"
	state="$(dots_openrig_package_state)"
	echo "  package state       ${state}"
	if dots_openrig_rig_bin >/dev/null 2>&1; then
		echo "  version             $(dots_openrig_version)"
		echo "  executable          $(dots_openrig_rig_bin)"
		echo "  npm prefix match    OK"
		local script
		script="$(dots_openrig_abi_script 2>/dev/null || true)"
		if [[ -f ${script:-} ]]; then
			if "$(dots_node_bin)" "${script}" >/dev/null 2>&1; then
				echo "  ABI                 OK"
				abi_note="OK"
			else
				echo "  ABI                 FAIL"
				abi_note="FAIL"
				rc=1
			fi
		else
			echo "  ABI                 FAIL script absent"
			abi_note="FAIL"
			rc=1
		fi
	else
		echo "  version             —"
		echo "  executable          MISSING"
		echo "  npm prefix match    FAIL"
		echo "  ABI                 FAIL"
		rc=1
	fi
	echo ""
	echo "Integration"
	if command -v tmux >/dev/null 2>&1; then
		echo "  tmux                OK"
	else
		echo "  tmux                FAIL"
		rc=1
	fi
	if command -v herdr >/dev/null 2>&1; then
		echo "  Herdr               OK"
	else
		echo "  Herdr               WARN (tmux fallback)"
	fi
	if command -v pi >/dev/null 2>&1; then
		echo "  Pi                  OK"
	else
		echo "  Pi                  WARN (default teams need Pi seats)"
	fi
	if [[ -f ${DIR}/configs/agents/openrig/rigs/dots-triad.yaml ]]; then
		echo "  team specs          OK"
	else
		echo "  team specs          FAIL"
		rc=1
	fi
	if [[ -f ${HOME}/.tmux.conf ]] && grep -q 'BEGIN DOTS-OPENRIG' "${HOME}/.tmux.conf" 2>/dev/null; then
		echo "  tmux fragment       OK"
	else
		echo "  tmux fragment       WARN not merged"
	fi
	if [[ -f ${HOME}/.tmux.conf ]] && grep -A5 'BEGIN DOTS-OPENRIG' "${HOME}/.tmux.conf" 2>/dev/null | grep -q 'prefix'; then
		echo "  tmux prefix safe    FAIL fragment sets prefix"
		rc=1
	else
		echo "  tmux prefix safe    OK"
	fi
	echo ""
	echo "Desired state"
	if [[ ${rc} -eq 0 ]]; then
		echo "  CONVERGED"
	else
		echo "  DIVERGED"
		echo ""
		echo "Repair:"
		echo "  ./dots setup --with openrig"
	fi
	return "${rc}"
}

dots_openrig_kernel_status() {
	local rig_bin
	rig_bin="$(dots_openrig_rig_bin)" || return 1
	"${rig_bin}" ps --nodes --rig kernel 2>/dev/null || "${rig_bin}" status 2>/dev/null || true
}

dots_openrig_terminal_status() {
	local rig_bin
	rig_bin="$(dots_openrig_rig_bin)" || return 1
	"${rig_bin}" terminal status 2>/dev/null || true
	if command -v herdr >/dev/null 2>&1; then
		echo "preferred_provider=herdr"
	else
		echo "preferred_provider=tmux"
	fi
}
