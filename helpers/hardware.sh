# shellcheck shell=bash
# helpers/hardware.sh — host hardware detection for model policy
#
# Overrides for tests (export before calling):
#   DOTS_FORCE_OS=darwin|linux
#   DOTS_FORCE_ARCH=arm64|x86_64|aarch64|amd64
#   DOTS_FORCE_RAM_GB=<int>
#   DOTS_FORCE_DISK_FREE_GB=<int>
#   DOTS_FORCE_CHIP="Apple M2"|Intel|...

dots_hw_os() {
	if [[ -n ${DOTS_FORCE_OS:-} ]]; then
		printf '%s\n' "${DOTS_FORCE_OS}"
		return 0
	fi
	case "$(uname -s)" in
	Darwin) printf 'darwin\n' ;;
	Linux) printf 'linux\n' ;;
	*) printf 'unknown\n' ;;
	esac
}

dots_hw_arch() {
	if [[ -n ${DOTS_FORCE_ARCH:-} ]]; then
		printf '%s\n' "${DOTS_FORCE_ARCH}"
		return 0
	fi
	local m
	m="$(uname -m)"
	case "${m}" in
	arm64 | aarch64) printf 'arm64\n' ;;
	x86_64 | amd64) printf 'x86_64\n' ;;
	*) printf '%s\n' "${m}" ;;
	esac
}

# Total physical RAM in whole GiB (floor).
dots_hw_ram_gb() {
	if [[ -n ${DOTS_FORCE_RAM_GB:-} ]]; then
		printf '%s\n' "${DOTS_FORCE_RAM_GB}"
		return 0
	fi
	local os bytes kb
	os="$(dots_hw_os)"
	if [[ ${os} == darwin ]]; then
		bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
		# Bash 3.2 integer division
		printf '%s\n' "$((bytes / 1024 / 1024 / 1024))"
		return 0
	fi
	if [[ -r /proc/meminfo ]]; then
		kb="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
		printf '%s\n' "$((kb / 1024 / 1024))"
		return 0
	fi
	printf '0\n'
}

# Free disk space on $HOME filesystem in whole GiB (floor).
dots_hw_disk_free_gb() {
	if [[ -n ${DOTS_FORCE_DISK_FREE_GB:-} ]]; then
		printf '%s\n' "${DOTS_FORCE_DISK_FREE_GB}"
		return 0
	fi
	local avail
	# df -k portable; take available blocks for $HOME
	avail="$(df -k "${HOME}" 2>/dev/null | awk 'NR==2 {print $4; exit}')"
	[[ -z ${avail} ]] && avail=0
	printf '%s\n' "$((avail / 1024 / 1024))"
}

# Human chip / CPU label.
dots_hw_chip() {
	if [[ -n ${DOTS_FORCE_CHIP:-} ]]; then
		printf '%s\n' "${DOTS_FORCE_CHIP}"
		return 0
	fi
	local os brand
	os="$(dots_hw_os)"
	if [[ ${os} == darwin ]]; then
		brand="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
		if [[ -z ${brand} ]] || [[ ${brand} == *Apple* ]]; then
			# Prefer marketing name when present (e.g. Apple M2)
			local chip
			chip="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip:/{print $2; exit}')"
			if [[ -n ${chip} ]]; then
				printf '%s\n' "${chip}"
				return 0
			fi
		fi
		if [[ -n ${brand} ]]; then
			printf '%s\n' "${brand}"
			return 0
		fi
		printf 'Apple Silicon\n'
		return 0
	fi
	if [[ -r /proc/cpuinfo ]]; then
		brand="$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
		[[ -n ${brand} ]] && {
			printf '%s\n' "${brand}"
			return 0
		}
	fi
	printf '%s\n' "$(dots_hw_arch)"
}

# True on Apple Silicon (arm64 Darwin).
dots_hw_is_apple_silicon() {
	[[ "$(dots_hw_os)" == darwin && "$(dots_hw_arch)" == arm64 ]]
}

# Print a short multi-line machine summary.
dots_hw_summary() {
	echo "Machine:"
	echo "  $(dots_hw_chip)"
	echo "  OS: $(dots_hw_os)  arch: $(dots_hw_arch)"
	echo "  RAM: $(dots_hw_ram_gb) GB"
	echo "  free disk: $(dots_hw_disk_free_gb) GB"
}
