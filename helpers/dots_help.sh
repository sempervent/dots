# shellcheck shell=bash
# helpers/dots_help.sh — install dots-help (uv project) + man pages

dots_help_project_dir() {
	printf '%s\n' "${DIR}/tools/dots_help"
}

dots_help_install() {
	local project dest man_src man_dest page
	project="$(dots_help_project_dir)"
	echo "=== dots-help (Textual) ==="
	if [[ ! -f ${project}/pyproject.toml ]]; then
		echo "Warn: missing ${project}/pyproject.toml" >&2
		return 0
	fi
	if ! command -v uv >/dev/null 2>&1; then
		echo "Warn: uv missing — skip dots-help install (core/modern provides uv)" >&2
		return 0
	fi
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] uv sync --directory ${project}"
		echo "[dry-run] link ~/.local/bin/dots-help"
		echo "[dry-run] install man pages → ~/.local/share/man/man1"
		return 0
	fi
	uv sync --directory "${project}" --python-preference system || {
		echo "Warn: uv sync failed for tools/dots_help (non-fatal)" >&2
		return 0
	}
	ensure_dir "${HOME}/.local/bin"
	if [[ -f ${DIR}/scripts/dots-help ]]; then
		chmod +x "${DIR}/scripts/dots-help" 2>/dev/null || true
		ln -sfn "${DIR}/scripts/dots-help" "${HOME}/.local/bin/dots-help"
		echo "OK: ${HOME}/.local/bin/dots-help"
	fi
	# Man pages
	man_src="${DIR}/docs/man/man1"
	man_dest="${HOME}/.local/share/man/man1"
	if [[ -d ${man_src} ]]; then
		ensure_dir "${man_dest}"
		for page in "${man_src}"/*.1; do
			[[ -f ${page} ]] || continue
			ln -sfn "${page}" "${man_dest}/$(basename "${page}")"
		done
		echo "OK: man pages → ${man_dest}"
	fi
}
