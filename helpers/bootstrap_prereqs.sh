# shellcheck shell=bash
# helpers/bootstrap_prereqs.sh — Stage 0: bootstrap the bootstrap (no Python/TOML)
#
# Ensures DOTS has enough infrastructure to run Stage 1 (TOML/profile/packages).
# Compatible with macOS /bin/bash 3.2.
#
# Irreducible seed (DOTS cannot create these):
#   - supported OS (Darwin / Linux)
#   - /bin/bash able to start this script
#   - network connectivity for official installers/packages
#   - OS elevation (root or sudo) when system packages require it
#
# Globals honored: DRY_RUN, SHOW_ONLY, NO_INSTALL, CI, NONINTERACTIVE, DIR
# Optional: dots_detect_linux_pkg_mgr, dots_find_python311, dots_provision_python311

DOTS_HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
DOTS_HERDR_INSTALL_URL="https://herdr.dev/install.sh"

# --- platform / elevation ----------------------------------------------------

dots_os_family() {
	case "$(uname -s)" in
	Darwin) printf '%s\n' darwin ;;
	Linux) printf '%s\n' linux ;;
	*) printf '%s\n' unsupported ;;
	esac
}

dots_require_elevation() {
	# Success if already root or sudo works non-interactively enough to -n.
	if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
		return 0
	fi
	if command -v sudo >/dev/null 2>&1; then
		if sudo -n true 2>/dev/null; then
			return 0
		fi
		# Interactive sudo may still work later; report that elevation binary exists.
		return 0
	fi
	echo "Error: privilege elevation required but neither root nor sudo is available." >&2
	echo "Required: root session or a working 'sudo' for system package installation." >&2
	return 1
}

dots_run_elevated() {
	if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

# --- Homebrew discovery / activation -----------------------------------------

dots_find_brew() {
	local p
	if command -v brew >/dev/null 2>&1; then
		command -v brew
		return 0
	fi
	for p in \
		/opt/homebrew/bin/brew \
		/usr/local/bin/brew \
		/home/linuxbrew/.linuxbrew/bin/brew; do
		if [[ -x ${p} ]]; then
			printf '%s\n' "${p}"
			return 0
		fi
	done
	return 1
}

dots_activate_brew() {
	local brew_bin brew_dir
	brew_bin="$(dots_find_brew)" || return 1
	# shellcheck disable=SC2046
	eval "$("${brew_bin}" shellenv)"
	if ! command -v brew >/dev/null 2>&1; then
		brew_dir="$(dirname "${brew_bin}")"
		export PATH="${brew_dir}:${PATH}"
	fi
	command -v brew >/dev/null 2>&1 || [[ -x ${brew_bin} ]]
}

# --- Apple CLT ---------------------------------------------------------------

dots_apple_clt_present() {
	[[ "$(uname -s)" == "Darwin" ]] || return 0
	# xcode-select -p succeeds when CLT or Xcode is installed
	xcode-select -p >/dev/null 2>&1
}

dots_ensure_apple_clt() {
	[[ "$(uname -s)" == "Darwin" ]] || return 0
	if dots_apple_clt_present; then
		echo "OK: Apple Command Line Tools → $(xcode-select -p 2>/dev/null || echo present)"
		return 0
	fi

	if [[ ${SHOW_ONLY:-0} -eq 1 ]] || [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "Would install Apple Command Line Tools"
		return 0
	fi

	if [[ ${NO_INSTALL:-0} -eq 1 ]]; then
		echo "Error: Apple Command Line Tools missing and --no-install set." >&2
		return 1
	fi

	echo "=== Installing Apple Command Line Tools (official xcode-select) ==="
	echo "An Apple installation UI may appear — approve it to continue."
	# Triggers GUI installer; may return immediately while install continues.
	if ! xcode-select --install 2>/dev/null; then
		# Already triggered or partial state — fall through to wait loop
		true
	fi

	# Prefer /usr/bin/seq if available; Bash 3.2 may lack seq — use while loop instead
	local i=0
	while [[ ${i} -lt 120 ]]; do
		i=$((i + 1))
		if dots_apple_clt_present; then
			echo "OK: Apple Command Line Tools installed"
			return 0
		fi
		sleep 5
		if [[ $((i % 6)) -eq 0 ]]; then
			echo "Waiting for Command Line Tools installation… (${i}/120)"
		fi
	done

	echo "Error: Apple Command Line Tools not available after waiting." >&2
	echo "Required: CLT via xcode-select --install" >&2
	echo "Provider attempted: Apple xcode-select" >&2
	echo "Remaining: complete the Apple GUI installer, then re-run DOTS." >&2
	return 1
}

# --- Homebrew install (official upstream only) -------------------------------

dots_download_official() {
	# Download URL to dest with HTTPS curl, fail on HTTP errors. No TLS disable.
	local url="$1" dest="$2"
	if ! command -v curl >/dev/null 2>&1; then
		echo "Error: curl required to download official installer: ${url}" >&2
		return 1
	fi
	curl -fsSL --proto '=https' --tlsv1.2 -o "${dest}" "${url}" || {
		echo "Error: failed to download official installer from ${url}" >&2
		return 1
	}
	[[ -s ${dest} ]] || {
		echo "Error: downloaded installer is empty: ${url}" >&2
		return 1
	}
}

dots_ensure_homebrew() {
	local brew_bin
	if brew_bin="$(dots_find_brew)"; then
		dots_activate_brew || true
		echo "OK: Homebrew → $(command -v brew 2>/dev/null || echo "${brew_bin}")"
		return 0
	fi

	if [[ ${SHOW_ONLY:-0} -eq 1 ]] || [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "Would install Homebrew from official Homebrew installer"
		echo "Would activate brew shellenv for this process (/opt/homebrew or /usr/local)"
		return 0
	fi

	if [[ ${NO_INSTALL:-0} -eq 1 ]]; then
		echo "Error: Homebrew missing and --no-install set." >&2
		return 1
	fi

	# Linux: Homebrew is optional when a native package manager exists.
	if [[ "$(uname -s)" == "Linux" ]]; then
		local mgr="unknown"
		if declare -F dots_detect_linux_pkg_mgr >/dev/null 2>&1; then
			mgr="$(dots_detect_linux_pkg_mgr)"
		fi
		if [[ ${mgr} != "unknown" ]]; then
			echo "OK: using native Linux package manager (${mgr}); Homebrew not required"
			return 0
		fi
		echo "Error: unsupported package-management environment" >&2
		echo "No Homebrew and no apt/pacman/xbps/dnf detected." >&2
		return 1
	fi

	# macOS: install official Homebrew
	if [[ "$(uname -s)" != "Darwin" ]]; then
		echo "Error: unsupported OS for Homebrew auto-install: $(uname -s)" >&2
		return 1
	fi

	echo "=== Installing Homebrew (official upstream installer) ==="
	echo "URL: ${DOTS_HOMEBREW_INSTALL_URL}"
	echo "DOTS does not fork this installer. Upstream confirmation prompts are preserved"
	echo "unless CI/NONINTERACTIVE is explicitly set."

	local tmp
	tmp="$(mktemp "${TMPDIR:-/tmp}/dots-brew-install.XXXXXX")"
	if ! dots_download_official "${DOTS_HOMEBREW_INSTALL_URL}" "${tmp}"; then
		rm -f "${tmp}"
		return 1
	fi

	# Unattended only when explicitly in CI / NONINTERACTIVE context.
	local env_prefix=()
	if [[ ${CI:-} == "true" ]] || [[ -n ${GITHUB_ACTIONS:-} ]] || [[ ${NONINTERACTIVE:-0} == "1" ]]; then
		env_prefix=(env NONINTERACTIVE=1)
		echo "Note: NONINTERACTIVE=1 (CI/unattended mode)"
	fi

	# Run installer as current user (Homebrew installer elevates itself as needed).
	# Never: sudo curl | sh
	if ! "${env_prefix[@]+"${env_prefix[@]}"}" /bin/bash "${tmp}"; then
		rm -f "${tmp}"
		echo "Error: official Homebrew installer failed." >&2
		echo "Required: Homebrew package manager" >&2
		echo "Provider attempted: ${DOTS_HOMEBREW_INSTALL_URL}" >&2
		echo "Remaining: fix upstream installer errors, then re-run DOTS." >&2
		return 1
	fi
	rm -f "${tmp}"

	if ! dots_activate_brew; then
		echo "Error: Homebrew installed but not discoverable in this process." >&2
		echo "Expected: /opt/homebrew/bin/brew or /usr/local/bin/brew" >&2
		return 1
	fi
	echo "OK: Homebrew installed and activated → $(command -v brew)"
	return 0
}

# --- Python ≥3.11 (after package manager) ------------------------------------

dots_stage0_python_present() {
	if declare -F dots_find_python311 >/dev/null 2>&1; then
		dots_find_python311 >/dev/null 2>&1 && return 0
	fi
	local c
	for c in python3.14 python3.13 python3.12 python3.11 python3; do
		command -v "${c}" >/dev/null 2>&1 || continue
		if "${c}" -c 'import tomllib' 2>/dev/null; then
			return 0
		fi
	done
	# Absolute Homebrew paths
	for c in \
		/opt/homebrew/opt/python@3.13/bin/python3.13 \
		/opt/homebrew/opt/python@3.12/bin/python3.12 \
		/opt/homebrew/opt/python@3.11/bin/python3.11 \
		/usr/local/opt/python@3.12/bin/python3.12; do
		[[ -x ${c} ]] || continue
		if "${c}" -c 'import tomllib' 2>/dev/null; then
			return 0
		fi
	done
	return 1
}

dots_ensure_supported_python() {
	if dots_stage0_python_present; then
		local py=""
		if declare -F dots_find_python311 >/dev/null 2>&1; then
			py="$(dots_find_python311 2>/dev/null || true)"
		fi
		echo "OK: Python ≥3.11 → ${py:-available}"
		return 0
	fi

	if [[ ${SHOW_ONLY:-0} -eq 1 ]] || [[ ${DRY_RUN:-0} -eq 1 ]]; then
		if command -v brew >/dev/null 2>&1 || dots_find_brew >/dev/null 2>&1; then
			echo "Would install Python 3.12 via Homebrew (brew install python@3.12)"
		elif [[ "$(uname -s)" == "Linux" ]]; then
			echo "Would install Python >=3.11 via the platform package manager"
		else
			echo "Would install Python 3.12 after Homebrew is available"
		fi
		return 0
	fi

	if [[ ${NO_INSTALL:-0} -eq 1 ]]; then
		echo "Error: Python >=3.11 missing and --no-install set." >&2
		return 1
	fi

	# Prefer shared provisioner when available
	if declare -F dots_provision_python311 >/dev/null 2>&1; then
		dots_provision_python311 "DOTS Stage 0 / tomllib" || return 1
	elif command -v brew >/dev/null 2>&1; then
		brew install python@3.12 || brew install python@3.11 || return 1
	elif [[ "$(uname -s)" == "Linux" ]]; then
		local mgr
		mgr="$(dots_detect_linux_pkg_mgr 2>/dev/null || echo unknown)"
		dots_require_elevation || return 1
		case "${mgr}" in
		apt)
			dots_run_elevated apt-get update -qq || true
			dots_run_elevated env DEBIAN_FRONTEND=noninteractive apt-get install -y python3.12 python3 ||
				dots_run_elevated env DEBIAN_FRONTEND=noninteractive apt-get install -y python3.11 python3 ||
				dots_run_elevated env DEBIAN_FRONTEND=noninteractive apt-get install -y python3 ||
				return 1
			;;
		pacman)
			dots_run_elevated pacman -Sy --noconfirm --needed python || return 1
			;;
		xbps)
			dots_run_elevated xbps-install -Sy python3 || return 1
			;;
		dnf)
			dots_run_elevated dnf install -y python3.12 || dots_run_elevated dnf install -y python3.11 || return 1
			;;
		*)
			echo "Error: unsupported package-management environment" >&2
			return 1
			;;
		esac
	else
		echo "Error: cannot provision Python >=3.11" >&2
		return 1
	fi

	if ! dots_stage0_python_present; then
		echo "Error: Python >=3.11 provisioned but still not discoverable." >&2
		return 1
	fi
	echo "OK: Python ≥3.11 provisioned"
	return 0
}

# git + curl are required before setup.sh can clone plugins / fetch installers
dots_ensure_bootstrap_tools() {
	local need=()
	command -v curl >/dev/null 2>&1 || need+=(curl)
	command -v git >/dev/null 2>&1 || need+=(git)

	if [[ ${#need[@]} -eq 0 ]]; then
		echo "OK: bootstrap tools → git curl"
		return 0
	fi

	if [[ ${SHOW_ONLY:-0} -eq 1 ]] || [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "Would install bootstrap tools: ${need[*]}"
		return 0
	fi
	if [[ ${NO_INSTALL:-0} -eq 1 ]]; then
		echo "Error: missing bootstrap tools (${need[*]}) and --no-install set." >&2
		return 1
	fi

	echo "=== Installing bootstrap tools: ${need[*]} ==="
	if command -v brew >/dev/null 2>&1 || dots_activate_brew 2>/dev/null; then
		brew install "${need[@]}" || return 1
	elif [[ "$(uname -s)" == "Linux" ]]; then
		local mgr
		mgr="$(dots_detect_linux_pkg_mgr 2>/dev/null || echo unknown)"
		dots_require_elevation || return 1
		case "${mgr}" in
		apt)
			dots_run_elevated apt-get update -qq || true
			dots_run_elevated env DEBIAN_FRONTEND=noninteractive apt-get install -y "${need[@]}" || return 1
			;;
		pacman)
			dots_run_elevated pacman -Sy --noconfirm --needed "${need[@]}" || return 1
			;;
		xbps)
			dots_run_elevated xbps-install -Sy "${need[@]}" || return 1
			;;
		dnf)
			dots_run_elevated dnf install -y "${need[@]}" || return 1
			;;
		*)
			echo "Error: cannot install ${need[*]} — unsupported package manager" >&2
			return 1
			;;
		esac
	else
		echo "Error: cannot install ${need[*]}" >&2
		return 1
	fi
	if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
		echo "Error: git/curl still missing after install attempt" >&2
		return 1
	fi
	echo "OK: bootstrap tools → git curl"
	return 0
}

# --- Herdr (official provider) -----------------------------------------------

dots_ensure_herdr() {
	if command -v herdr >/dev/null 2>&1; then
		echo "OK: herdr → $(command -v herdr)"
		return 0
	fi

	if [[ ${SHOW_ONLY:-0} -eq 1 ]] || [[ ${DRY_RUN:-0} -eq 1 ]]; then
		if command -v brew >/dev/null 2>&1 || dots_find_brew >/dev/null 2>&1; then
			echo "Would install herdr via Homebrew (brew install herdr)"
		else
			echo "Would install herdr via official installer (${DOTS_HERDR_INSTALL_URL})"
		fi
		return 0
	fi

	if [[ ${NO_INSTALL:-0} -eq 1 ]]; then
		echo "Error: herdr missing and --no-install set." >&2
		return 1
	fi

	# Prefer Homebrew formula when brew is available (macOS or Linuxbrew)
	if command -v brew >/dev/null 2>&1 || dots_activate_brew 2>/dev/null; then
		echo "=== Installing herdr via Homebrew ==="
		if brew install herdr; then
			echo "OK: herdr → $(command -v herdr)"
			return 0
		fi
		echo "Warn: brew install herdr failed; trying official Herdr installer" >&2
	fi

	# Official vendor installer (isolated here — not scattered curl|sh)
	echo "=== Installing herdr via official installer ==="
	echo "URL: ${DOTS_HERDR_INSTALL_URL}"
	local tmp
	tmp="$(mktemp "${TMPDIR:-/tmp}/dots-herdr-install.XXXXXX")"
	if ! dots_download_official "${DOTS_HERDR_INSTALL_URL}" "${tmp}"; then
		rm -f "${tmp}"
		echo "Error: could not download Herdr installer." >&2
		echo "Required: herdr" >&2
		echo "Providers attempted: Homebrew formula herdr; ${DOTS_HERDR_INSTALL_URL}" >&2
		return 1
	fi
	if ! /bin/bash "${tmp}"; then
		rm -f "${tmp}"
		echo "Error: official Herdr installer failed." >&2
		echo "Required: herdr" >&2
		echo "Provider attempted: ${DOTS_HERDR_INSTALL_URL}" >&2
		return 1
	fi
	rm -f "${tmp}"

	# Common install locations
	export PATH="${HOME}/.local/bin:${PATH}"
	if command -v herdr >/dev/null 2>&1; then
		echo "OK: herdr → $(command -v herdr)"
		return 0
	fi
	echo "Error: herdr installer finished but herdr not on PATH." >&2
	echo "Remaining: ensure ~/.local/bin (or vendor prefix) is on PATH, then re-run." >&2
	return 1
}

# --- Stage 0 orchestration ---------------------------------------------------

dots_stage0_report() {
	echo "=== Bootstrap prerequisites (Stage 0) ==="
	echo "OS: $(uname -s)  arch: $(uname -m)"

	if [[ "$(uname -s)" == "Darwin" ]]; then
		if dots_apple_clt_present; then
			echo "  Apple Command Line Tools    present"
		else
			echo "  Apple Command Line Tools    would install"
		fi
		if dots_find_brew >/dev/null 2>&1; then
			echo "  Homebrew                    present ($(dots_find_brew))"
		else
			echo "  Homebrew                    would install"
		fi
	else
		local mgr="unknown"
		if declare -F dots_detect_linux_pkg_mgr >/dev/null 2>&1; then
			mgr="$(dots_detect_linux_pkg_mgr)"
		fi
		if [[ ${mgr} != "unknown" ]]; then
			echo "  Package manager             present (${mgr})"
		elif dots_find_brew >/dev/null 2>&1; then
			echo "  Package manager             Homebrew/Linuxbrew present"
		else
			echo "  Package manager             MISSING (unsupported)"
		fi
	fi

	if dots_stage0_python_present; then
		echo "  Python >=3.11               present"
	else
		echo "  Python 3.12                 would install"
	fi
	local tools_missing=()
	command -v curl >/dev/null 2>&1 || tools_missing+=(curl)
	command -v git >/dev/null 2>&1 || tools_missing+=(git)
	if [[ ${#tools_missing[@]} -eq 0 ]]; then
		echo "  git curl                    present"
	else
		echo "  bootstrap tools             would install (${tools_missing[*]})"
	fi
}

# Ensure Stage 0 infrastructure. soft=1 → report-only (show/dry-run).
dots_stage0_ensure() {
	local soft="${1:-0}"
	local os
	os="$(dots_os_family)"
	if [[ ${os} == "unsupported" ]]; then
		echo "Error: unsupported OS: $(uname -s)" >&2
		return 1
	fi

	if [[ ${soft} -eq 1 ]] || [[ ${SHOW_ONLY:-0} -eq 1 ]] || [[ ${DRY_RUN:-0} -eq 1 ]]; then
		dots_stage0_report
		# Still activate brew if present-but-not-PATH so show can use it later
		dots_activate_brew 2>/dev/null || true
		return 0
	fi

	echo "=== Stage 0: bootstrap the bootstrap ==="
	if [[ ${os} == "darwin" ]]; then
		dots_ensure_apple_clt || return 1
		dots_ensure_homebrew || return 1
		dots_activate_brew || return 1
	else
		local mgr
		mgr="$(dots_detect_linux_pkg_mgr 2>/dev/null || echo unknown)"
		if [[ ${mgr} == "unknown" ]]; then
			if dots_find_brew >/dev/null 2>&1; then
				dots_activate_brew || true
			else
				echo "Error: unsupported package-management environment" >&2
				echo "Need apt, pacman, xbps, dnf, or Homebrew/Linuxbrew." >&2
				return 1
			fi
		else
			echo "OK: Linux package manager → ${mgr}"
			dots_require_elevation || return 1
		fi
	fi

	dots_ensure_supported_python || return 1
	# Export interpreter for Stage 1 helpers in this process
	if declare -F dots_require_python >/dev/null 2>&1; then
		dots_require_python 0 || true
	fi
	dots_ensure_bootstrap_tools || return 1
	echo "OK: Stage 0 complete"
	return 0
}

# Builtin profile fallback for --show when Python/TOML unavailable (no cycle).
dots_show_builtin_profile_fallback() {
	local name="$1"
	echo ""
	echo "profile: ${name} (Stage-0 fallback — full TOML resolve needs Python >=3.11)"
	case "${name}" in
	base)
		echo "package groups:"
		echo "  core"
		echo "  modern"
		echo "components:"
		echo "  (none)"
		echo "runtime:"
		echo "  multiplexer = tmux"
		;;
	work)
		echo "package groups:"
		echo "  core"
		echo "  modern"
		echo "  workstation"
		echo "components:"
		echo "  (none)"
		echo "runtime:"
		echo "  multiplexer = tmux"
		;;
	server)
		echo "package groups:"
		echo "  core"
		echo "  modern"
		echo "  server"
		echo "components:"
		echo "  herdr"
		echo "runtime:"
		echo "  multiplexer = tmux"
		;;
	home)
		echo "package groups:"
		echo "  core"
		echo "  modern"
		echo "  workstation"
		echo "  infra"
		echo "  media"
		echo "  gui"
		echo "components:"
		echo "  hermes herdr ollama skills ai-skills drawthings opencode codex cursor images tex"
		echo "runtime:"
		echo "  multiplexer = herdr"
		;;
	all)
		echo "package groups:"
		echo "  core … gui (full)"
		echo "components:"
		echo "  (all optional except omit_from_all)"
		echo "runtime:"
		echo "  multiplexer = tmux"
		;;
	*)
		echo "Note: custom profile full resolve requires Python >=3.11"
		;;
	esac
}
