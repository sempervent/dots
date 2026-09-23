# shellcheck shell=bash
# helpers/lsp.sh — registry-driven language-server install/status/check
#
# Authority: configs/lsp/servers.toml. DOTS owns PATH-visible binaries;
# editors only configure and attach clients.

dots_lsp_registry_path() {
	printf '%s\n' "${DOTS_LSP_REGISTRY:-${DIR}/configs/lsp/servers.toml}"
}

# Pipe-delimited rows. Registry values may not contain literal `|`.
dots_lsp_rows() {
	dots_toml_query "$(dots_lsp_registry_path)" <<'PY'
def csv(value):
    return ",".join(str(x) for x in (value or []))

for s in data.get("servers") or []:
    values = [
        s.get("id", ""), s.get("label", ""), csv(s.get("domains")),
        s.get("binary", ""), s.get("brew", ""), s.get("apt", ""),
        s.get("fallback", ""), s.get("fallback_package", ""),
        s.get("fallback_repo", ""), s.get("fallback_asset_amd64", ""),
        s.get("fallback_asset_arm64", ""), s.get("fallback_binary_path", ""),
        "true" if s.get("required") else "false", s.get("nvim", ""),
        s.get("health", ""), csv(s.get("version_args")),
        csv(s.get("filetypes")), csv(s.get("extensions")),
    ]
    print("|".join(str(v).replace("|", "") for v in values))
PY
}

dots_lsp_validate_registry() {
	dots_toml_query "$(dots_lsp_registry_path)" <<'PY'
servers = data.get("servers") or []
if data.get("version") != 1:
    raise SystemExit("Error: unsupported LSP registry version")
if not servers:
    raise SystemExit("Error: LSP registry has no servers")
seen = set()
roles = {}
allowed_health = {"executable", "r_package"}
allowed_fallback = {"npm", "python_venv", "go", "github_binary", "github_gzip", "github_tar", "cran"}
for s in servers:
    sid = str(s.get("id") or "").strip()
    if not sid or sid in seen:
        raise SystemExit("Error: missing/duplicate LSP id '%s'" % sid)
    seen.add(sid)
    for key in ("label", "binary", "nvim", "health"):
        if not str(s.get(key) or "").strip():
            raise SystemExit("Error: LSP '%s' missing %s" % (sid, key))
    for key in ("domains", "filetypes", "extensions", "platforms"):
        if not isinstance(s.get(key), list) or not s.get(key):
            raise SystemExit("Error: LSP '%s' missing %s mapping" % (sid, key))
    if s.get("health") not in allowed_health:
        raise SystemExit("Error: LSP '%s' has invalid health policy" % sid)
    fallback = str(s.get("fallback") or "").strip()
    if fallback not in allowed_fallback:
        raise SystemExit("Error: LSP '%s' has invalid fallback '%s'" % (sid, fallback))
    if not str(s.get("brew") or "").strip() and not str(s.get("apt") or "").strip() and not fallback:
        raise SystemExit("Error: LSP '%s' has no install provider" % sid)
    if fallback.startswith("github_"):
        for key in ("fallback_repo", "fallback_asset_amd64", "fallback_asset_arm64"):
            if not str(s.get(key) or "").strip():
                raise SystemExit("Error: LSP '%s' missing %s" % (sid, key))
    for role in s.get("extensions") or []:
        role = str(role)
        owner = roles.get(role)
        if owner and not s.get("allow_role_overlap"):
            raise SystemExit("Error: LSP role '%s' claimed by %s and %s" % (role, owner, sid))
        roles[role] = sid
print("OK")
PY
}

_dots_lsp_r_package_ok() {
	command -v Rscript >/dev/null 2>&1 || return 1
	Rscript -e 'quit(status=if(requireNamespace("languageserver", quietly=TRUE)) 0 else 1)' >/dev/null 2>&1
}

dots_lsp_server_satisfied() {
	local binary="$1" health="$2"
	case "${health}" in
	r_package) _dots_lsp_r_package_ok ;;
	*) command -v "${binary}" >/dev/null 2>&1 ;;
	esac
}

dots_lsp_probe_version() {
	local binary="$1" args_csv="$2" output
	local -a args=()
	[[ -n ${args_csv} ]] || return 0
	IFS=',' read -r -a args <<<"${args_csv}"
	output="$("${binary}" "${args[@]}" 2>&1 | head -1 || true)"
	[[ -n ${output} ]] && printf '%s\n' "${output}"
}

dots_lsp_status() {
	local detailed="${1:-1}" id label domains binary brew apt fallback package repo asset_x64 asset_arm archive_path required nvim health version_args filetypes extensions
	local available=0 required_missing=0 optional_missing=0 total=0 state
	if [[ ${detailed} -eq 1 ]]; then
		printf '%-20s %-34s %s\n' "Domain" "Server / binary" "State"
		printf '%-20s %-34s %s\n' "--------------------" "----------------------------------" "-------"
	fi
	while IFS='|' read -r id label domains binary brew apt fallback package repo asset_x64 asset_arm archive_path required nvim health version_args filetypes extensions; do
		[[ -n ${id} ]] || continue
		total=$((total + 1))
		if dots_lsp_server_satisfied "${binary}" "${health}"; then
			available=$((available + 1))
			state="OK"
			if [[ ${detailed} -eq 1 && -n ${version_args} ]]; then
				local version_line
				version_line="$(dots_lsp_probe_version "${binary}" "${version_args}")"
				[[ -n ${version_line} ]] && state="OK (${version_line})"
			fi
		else
			state="MISSING"
			if [[ ${required} == true ]]; then
				required_missing=$((required_missing + 1))
			else
				optional_missing=$((optional_missing + 1))
			fi
		fi
		if [[ ${detailed} -eq 1 ]]; then
			printf '%-20s %-34s %s\n' "${label}" "${binary}" "${state}"
		fi
	done < <(dots_lsp_rows)
	DOTS_LSP_TOTAL=${total}
	DOTS_LSP_AVAILABLE=${available}
	DOTS_LSP_REQUIRED_MISSING=${required_missing}
	DOTS_LSP_OPTIONAL_MISSING=${optional_missing}
	if [[ ${detailed} -eq 1 ]]; then
		echo ""
		echo "Available: ${available}/${total}; required missing: ${required_missing}; optional missing: ${optional_missing}"
	fi
	return 0
}

dots_lsp_summary() {
	dots_lsp_status 0
	echo "LSP:"
	echo "  ${DOTS_LSP_AVAILABLE}/${DOTS_LSP_TOTAL} available"
	echo "  ${DOTS_LSP_REQUIRED_MISSING} required missing, ${DOTS_LSP_OPTIONAL_MISSING} optional missing"
}

dots_lsp_check() {
	dots_lsp_status 1
	[[ ${DOTS_LSP_REQUIRED_MISSING} -eq 0 ]]
}

_dots_lsp_install_dir() {
	mkdir -p "${HOME}/.local/bin" "${HOME}/.local/share/dots/lsp"
	export PATH="${HOME}/.local/bin:${PATH}"
}

_dots_lsp_download() {
	local url="$1" dest="$2"
	if declare -F dots_download_official >/dev/null 2>&1; then
		dots_download_official "${url}" "${dest}"
	else
		curl -fsSL --proto '=https' --tlsv1.2 -o "${dest}" "${url}"
	fi
}

_dots_lsp_native_install() {
	local package="$1" mgr
	[[ -n ${package} ]] || return 1
	mgr="$(dots_detect_linux_pkg_mgr 2>/dev/null || echo unknown)"
	case "${mgr}" in
	apt)
		dots_run_elevated apt-get update -qq
		dots_run_elevated env DEBIAN_FRONTEND=noninteractive apt-get install -y "${package}"
		;;
	pacman) dots_run_elevated pacman -Sy --noconfirm --needed "${package}" ;;
	dnf) dots_run_elevated dnf install -y "${package}" ;;
	xbps) dots_run_elevated xbps-install -Sy "${package}" ;;
	*) return 1 ;;
	esac
}

_dots_lsp_try_apt() {
	local package="$1"
	[[ -n ${package} ]] || return 1
	[[ "$(dots_detect_linux_pkg_mgr 2>/dev/null || true)" == apt ]] || return 1
	if ! apt-cache show "${package}" >/dev/null 2>&1; then
		if [[ ${DOTS_LSP_APT_REFRESHED:-0} -eq 0 ]]; then
			dots_run_elevated apt-get update -qq || return 1
			DOTS_LSP_APT_REFRESHED=1
		fi
	fi
	apt-cache show "${package}" >/dev/null 2>&1 || return 1
	dots_run_elevated env DEBIAN_FRONTEND=noninteractive apt-get install -y "${package}"
}

_dots_lsp_ensure_node() {
	local major="" asset tmp fnm_bin ver
	if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
		major="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
		if [[ ${major:-0} -ge 20 ]]; then
			return 0
		fi
	fi
	if command -v fnm >/dev/null 2>&1; then
		fnm_bin="$(command -v fnm)"
	else
		case "$(uname -m)" in
		aarch64 | arm64) asset="fnm-arm64.zip" ;;
		x86_64 | amd64) asset="fnm-linux.zip" ;;
		*)
			echo "Error: unsupported architecture for fnm: $(uname -m)" >&2
			return 1
			;;
		esac
		tmp="$(mktemp -d "${TMPDIR:-/tmp}/dots-fnm.XXXXXX")"
		_dots_lsp_download "https://github.com/Schniz/fnm/releases/latest/download/${asset}" "${tmp}/fnm.zip" || {
			rm -rf "${tmp}"
			return 1
		}
		python3 -m zipfile -e "${tmp}/fnm.zip" "${tmp}/out" || {
			rm -rf "${tmp}"
			return 1
		}
		install -m 755 "${tmp}/out/fnm" "${HOME}/.local/bin/fnm"
		rm -rf "${tmp}"
		fnm_bin="${HOME}/.local/bin/fnm"
	fi
	eval "$("${fnm_bin}" env --shell bash)"
	ver="24"
	if declare -F dots_node_default_version >/dev/null 2>&1; then
		ver="$(dots_node_default_version)"
	fi
	"${fnm_bin}" install "${ver}" || return 1
	"${fnm_bin}" default "${ver}" >/dev/null 2>&1 || true
	eval "$("${fnm_bin}" env --shell bash)"
	command -v npm >/dev/null 2>&1
}

_dots_lsp_install_python_venv() {
	local package="$1" binary="$2" py dest
	py="$(dots_find_python311 2>/dev/null || command -v python3)"
	[[ -n ${py} ]] || return 1
	dest="${HOME}/.local/share/dots/lsp/${package}"
	if ! "${py}" -m venv "${dest}" >/dev/null 2>&1; then
		if [[ "$(dots_detect_linux_pkg_mgr 2>/dev/null || true)" == apt ]]; then
			_dots_lsp_native_install python3-venv || return 1
		fi
		"${py}" -m venv "${dest}" || return 1
	fi
	"${dest}/bin/python" -m pip install --upgrade "${package}" || return 1
	ln -sfn "${dest}/bin/${binary}" "${HOME}/.local/bin/${binary}"
}

_dots_lsp_github_release() {
	local kind="$1" id="$2" binary="$3" repo="$4" asset_template="$5" archive_path="$6"
	local tmp tag version asset url install_root
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/dots-lsp-release.XXXXXX")"
	_dots_lsp_download "https://api.github.com/repos/${repo}/releases/latest" "${tmp}/release.json" || {
		rm -rf "${tmp}"
		return 1
	}
	tag="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag_name"])' "${tmp}/release.json")"
	version="${tag#v}"
	asset="${asset_template//\{version\}/${version}}"
	url="https://github.com/${repo}/releases/download/${tag}/${asset}"
	case "${kind}" in
	github_binary)
		_dots_lsp_download "${url}" "${tmp}/${binary}" || {
			rm -rf "${tmp}"
			return 1
		}
		install -m 755 "${tmp}/${binary}" "${HOME}/.local/bin/${binary}"
		;;
	github_gzip)
		_dots_lsp_download "${url}" "${tmp}/${binary}.gz" || {
			rm -rf "${tmp}"
			return 1
		}
		gzip -dc "${tmp}/${binary}.gz" >"${tmp}/${binary}" || {
			rm -rf "${tmp}"
			return 1
		}
		install -m 755 "${tmp}/${binary}" "${HOME}/.local/bin/${binary}"
		;;
	github_tar)
		_dots_lsp_download "${url}" "${tmp}/archive.tar.gz" || {
			rm -rf "${tmp}"
			return 1
		}
		install_root="${HOME}/.local/share/dots/lsp/${id}/${version}"
		mkdir -p "${install_root}"
		tar -xzf "${tmp}/archive.tar.gz" -C "${install_root}" || {
			rm -rf "${tmp}"
			return 1
		}
		[[ -x ${install_root}/${archive_path} ]] || {
			echo "Error: ${archive_path} absent from ${asset}" >&2
			rm -rf "${tmp}"
			return 1
		}
		ln -sfn "${install_root}/${archive_path}" "${HOME}/.local/bin/${binary}"
		;;
	*)
		rm -rf "${tmp}"
		return 1
		;;
	esac
	rm -rf "${tmp}"
}

_dots_lsp_install_cran() {
	local package="$1"
	if ! command -v Rscript >/dev/null 2>&1; then
		if command -v brew >/dev/null 2>&1; then
			brew install r || return 1
		else
			case "$(dots_detect_linux_pkg_mgr 2>/dev/null || true)" in
			apt) _dots_lsp_native_install r-base || return 1 ;;
			pacman) _dots_lsp_native_install r || return 1 ;;
			dnf) _dots_lsp_native_install R || return 1 ;;
			xbps) _dots_lsp_native_install R || return 1 ;;
			*) return 1 ;;
			esac
		fi
	fi
	Rscript -e "p <- path.expand(Sys.getenv('R_LIBS_USER')); dir.create(p, recursive=TRUE, showWarnings=FALSE); .libPaths(c(p, .libPaths())); if (!requireNamespace('${package}', quietly=TRUE)) install.packages('${package}', repos='https://cloud.r-project.org', lib=p)"
}

_dots_lsp_install_fallback() {
	local fallback="$1" id="$2" binary="$3" package="$4" repo="$5" asset="$6" archive_path="$7"
	case "${fallback}" in
	npm)
		_dots_lsp_ensure_node || return 1
		npm install -g "${package}"
		;;
	python_venv) _dots_lsp_install_python_venv "${package}" "${binary}" ;;
	go)
		if ! command -v go >/dev/null 2>&1; then
			case "$(dots_detect_linux_pkg_mgr 2>/dev/null || true)" in
			apt) _dots_lsp_native_install golang-go || return 1 ;;
			pacman) _dots_lsp_native_install go || return 1 ;;
			dnf) _dots_lsp_native_install golang || return 1 ;;
			xbps) _dots_lsp_native_install go || return 1 ;;
			*) return 1 ;;
			esac
		fi
		env GOBIN="${HOME}/.local/bin" go install "${package}"
		;;
	github_binary | github_gzip | github_tar) _dots_lsp_github_release "${fallback}" "${id}" "${binary}" "${repo}" "${asset}" "${archive_path}" ;;
	cran) _dots_lsp_install_cran "${package}" ;;
	*)
		echo "Error: unsupported LSP fallback '${fallback}' for ${id}" >&2
		return 1
		;;
	esac
}

dots_lsp_install() {
	local id label domains binary brew apt fallback package repo asset_x64 asset_arm archive_path required nvim health version_args filetypes extensions asset
	local failures=0
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] reconcile language servers from $(dots_lsp_registry_path)"
		dots_lsp_rows | while IFS='|' read -r id label domains binary brew apt fallback package repo asset_x64 asset_arm archive_path required nvim health version_args filetypes extensions; do
			echo "[dry-run] ${id}: existing binary → skip; else native package → ${fallback} fallback"
		done
		return 0
	fi
	_dots_lsp_install_dir
	DOTS_LSP_APT_REFRESHED=0
	while IFS='|' read -r id label domains binary brew apt fallback package repo asset_x64 asset_arm archive_path required nvim health version_args filetypes extensions; do
		[[ -n ${id} ]] || continue
		if dots_lsp_server_satisfied "${binary}" "${health}"; then
			echo "OK: ${id} already installed"
			continue
		fi
		echo "Installing ${id}..."
		if command -v brew >/dev/null 2>&1 && [[ -n ${brew} ]]; then
			brew install "${brew}" || true
		elif [[ -n ${apt} ]]; then
			_dots_lsp_try_apt "${apt}" || true
		fi
		if dots_lsp_server_satisfied "${binary}" "${health}"; then
			echo "OK: ${id} installed via native package manager"
			continue
		fi
		case "$(uname -m)" in
		aarch64 | arm64) asset="${asset_arm}" ;;
		*) asset="${asset_x64}" ;;
		esac
		if ! _dots_lsp_install_fallback "${fallback}" "${id}" "${binary}" "${package}" "${repo}" "${asset}" "${archive_path}"; then
			echo "Error: trusted fallback '${fallback}' failed for ${id}" >&2
			failures=$((failures + 1))
			continue
		fi
		if dots_lsp_server_satisfied "${binary}" "${health}"; then
			echo "OK: ${id} installed via ${fallback}"
		else
			echo "Error: ${id} provider completed but health check still fails" >&2
			failures=$((failures + 1))
		fi
	done < <(dots_lsp_rows)
	[[ ${failures} -eq 0 ]]
}
