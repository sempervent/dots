# shellcheck shell=bash
# helpers/mapshaper.sh — Mapshaper CLI via npm (Phase 9)
#
# Official package: mapshaper (https://github.com/mbloch/mapshaper)
# No Homebrew formula. Reuses existing fnm/Node ownership — never introduces nvm.
# Install-only: never processes user geospatial files during setup.

DOTS_MAPSHAPER_NPM_PKG="${DOTS_MAPSHAPER_NPM_PKG:-mapshaper}"

dots_mapshaper_have() {
	command -v mapshaper >/dev/null 2>&1
}

# Ensure npm is available via existing Node/fnm policy (no alternate bootstrap).
dots_mapshaper_ensure_npm() {
	if command -v npm >/dev/null 2>&1; then
		return 0
	fi
	if declare -F dots_setup_fnm_node >/dev/null 2>&1; then
		dots_setup_fnm_node || true
		if command -v fnm >/dev/null 2>&1; then
			eval "$(fnm env)" 2>/dev/null || true
		fi
	fi
	command -v npm >/dev/null 2>&1
}

# Install mapshaper when package group `geo` is selected.
# Safe: version probe only after install; no dataset processing.
dots_mapshaper_install() {
	echo "=== Mapshaper (npm) ==="
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] npm install -g --ignore-scripts ${DOTS_MAPSHAPER_NPM_PKG}"
		return 0
	fi
	if dots_mapshaper_have; then
		echo "OK: mapshaper already installed ($(mapshaper --version 2>/dev/null | head -n1 || echo present))"
		return 0
	fi
	if ! dots_mapshaper_ensure_npm; then
		echo "Warn: npm not available — skip mapshaper (install Node via fnm / modern group, then re-run)" >&2
		return 0
	fi
	# Prefer user-local global when possible; never sudo npm.
	npm install -g --ignore-scripts "${DOTS_MAPSHAPER_NPM_PKG}" || {
		echo "Warn: npm install failed for ${DOTS_MAPSHAPER_NPM_PKG} (continuing; geo CLI otherwise OK)" >&2
		return 0
	}
	if dots_mapshaper_have; then
		echo "OK: installed ${DOTS_MAPSHAPER_NPM_PKG} ($(mapshaper --version 2>/dev/null | head -n1 || echo present))"
	else
		echo "Warn: mapshaper not on PATH after npm install" >&2
	fi
	return 0
}

# Called from package provisioning when geo is in the resolved set.
dots_geo_npm_tools_install() {
	local g
	DOTS_RESOLVED_GROUPS=("${DOTS_RESOLVED_GROUPS[@]+"${DOTS_RESOLVED_GROUPS[@]}"}")
	for g in "${DOTS_RESOLVED_GROUPS[@]+"${DOTS_RESOLVED_GROUPS[@]}"}"; do
		if [[ ${g} == geo ]]; then
			dots_mapshaper_install
			return $?
		fi
	done
	return 0
}
