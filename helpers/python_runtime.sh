# shellcheck shell=bash
# helpers/python_runtime.sh — locate / provision Python ≥3.11 (stdlib tomllib)
#
# DOTS minimum supported Python is 3.11. Preferred provisioned version is 3.12+.
# Does not replace system Python or change interactive PATH/aliases.
#
# Requires: DIR, DRY_RUN (optional)
# Optional: dots_detect_linux_pkg_mgr from helpers/packages.sh

# True if interpreter at $1 can import tomllib (Python ≥3.11).
dots_python_bin_has_tomllib() {
	local bin="$1"
	[[ -n ${bin} ]] || return 1
	command -v "${bin}" >/dev/null 2>&1 || [[ -x ${bin} ]] || return 1
	local pyhome
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pyhome.XXXXXX")"
	if HOME="${pyhome}" PYTHONDONTWRITEBYTECODE=1 "${bin}" -B -c 'import tomllib' 2>/dev/null; then
		rm -rf "${pyhome}"
		return 0
	fi
	rm -rf "${pyhome}"
	return 1
}

# Print absolute path to a Python ≥3.11 with tomllib, or return 1.
dots_find_python311() {
	local c cand
	# Prefer versioned Homebrew/opt paths, then versioned names, then python3.
	for cand in \
		"${HOMEBREW_PREFIX:-/opt/homebrew}/opt/python@3.13/bin/python3.13" \
		"${HOMEBREW_PREFIX:-/opt/homebrew}/opt/python@3.12/bin/python3.12" \
		"${HOMEBREW_PREFIX:-/opt/homebrew}/opt/python@3.11/bin/python3.11" \
		/usr/local/opt/python@3.13/bin/python3.13 \
		/usr/local/opt/python@3.12/bin/python3.12 \
		/usr/local/opt/python@3.11/bin/python3.11 \
		python3.13 python3.12 python3.11 python3; do
		c="$(command -v "${cand}" 2>/dev/null || true)"
		[[ -z ${c} && -x ${cand} ]] && c="${cand}"
		[[ -z ${c} ]] && continue
		if dots_python_bin_has_tomllib "${c}"; then
			printf '%s\n' "${c}"
			return 0
		fi
	done
	return 1
}

# Run a specific Python binary with HOME isolation (no Apple cache pollution).
# Usage: dots_run_python_bin /path/to/python [args...]
dots_run_python_bin() {
	local bin="$1"
	shift
	local pyhome rc=0
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pyhome.XXXXXX")"
	HOME="${pyhome}" PYTHONDONTWRITEBYTECODE=1 PYTHONNOUSERSITE=1 "${bin}" -B "$@" || rc=$?
	rm -rf "${pyhome}"
	return "${rc}"
}

# Provision Python ≥3.11 via canonical package managers. Does not mutate PATH.
dots_provision_python311() {
	local reason="${1:-components needing tomllib}"
	echo "=== Provisioning Python ≥3.11 (for: ${reason}) ==="

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "Would provision Python >=3.11 for: ${reason}"
		return 0
	fi

	if command -v brew >/dev/null 2>&1; then
		# Homebrew python@3.12 is the stable modern formula on current macOS/Linuxbrew.
		if brew list --versions python@3.12 >/dev/null 2>&1 ||
			brew list --versions python@3.11 >/dev/null 2>&1 ||
			brew list --versions python@3.13 >/dev/null 2>&1; then
			echo "OK: Homebrew Python ≥3.11 already installed"
			return 0
		fi
		echo "brew install python@3.12"
		if brew install python@3.12; then
			return 0
		fi
		echo "Warn: brew install python@3.12 failed; trying python@3.11" >&2
		brew install python@3.11 || return 1
		return 0
	fi

	local mgr=""
	if declare -F dots_detect_linux_pkg_mgr >/dev/null 2>&1; then
		mgr="$(dots_detect_linux_pkg_mgr)"
	fi
	case "${mgr}" in
	apt)
		sudo apt-get update -qq || true
		# Prefer python3 metapackage (provides /usr/bin/python3) plus 3.12 when available
		if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3.12 python3; then
			return 0
		fi
		if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3.11 python3; then
			return 0
		fi
		if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3; then
			return 0
		fi
		echo "Error: apt could not install python3.12/python3.11/python3" >&2
		return 1
		;;
	pacman)
		sudo pacman -Sy --noconfirm --needed python || return 1
		return 0
		;;
	xbps)
		sudo xbps-install -Sy python3 || return 1
		return 0
		;;
	dnf)
		if sudo dnf install -y python3.12; then
			return 0
		fi
		sudo dnf install -y python3.11 || return 1
		return 0
		;;
	*)
		echo "Error: cannot provision Python ≥3.11 (no brew and unsupported Linux package manager)." >&2
		echo "Install python3.11+ manually, then re-run with the same --with / profile." >&2
		return 1
		;;
	esac
}

# Ensure DOTS_SKILLS_PYTHON points at a tomllib-capable interpreter when needed.
# Args: comma/space separated reason labels (e.g. "skills, ai-skills")
# Sets global DOTS_SKILLS_PYTHON on success.
dots_ensure_python311_for() {
	local reason="${*:-skills}"
	reason="$(echo "${reason}" | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	[[ -z ${reason} ]] && reason="skills"

	local found
	if found="$(dots_find_python311)"; then
		DOTS_SKILLS_PYTHON="${found}"
		echo "OK: using Python ≥3.11 for ${reason} → ${DOTS_SKILLS_PYTHON}"
		return 0
	fi

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "Would provision Python >=3.11 for: ${reason}"
		DOTS_SKILLS_PYTHON=""
		return 0
	fi

	if ! dots_provision_python311 "${reason}"; then
		echo "Error: failed to provision Python ≥3.11 required for: ${reason}" >&2
		return 1
	fi

	if found="$(dots_find_python311)"; then
		DOTS_SKILLS_PYTHON="${found}"
		echo "OK: provisioned Python ≥3.11 for ${reason} → ${DOTS_SKILLS_PYTHON}"
		return 0
	fi

	echo "Error: Python ≥3.11 package installed but tomllib interpreter not found on PATH." >&2
	echo "On Apple Silicon Homebrew, ensure brew is on PATH for this process, then re-run." >&2
	return 1
}
