#!/usr/bin/env bash
# shellcheck shell=bash
# helpers/linux_distro.sh — Linux distro identity from /etc/os-release
#
# Distro identity is diagnostic context. Package-manager detection
# (helpers/packages.sh → dots_detect_linux_pkg_mgr) remains authoritative
# for install mechanics.
#
# Test override: DOTS_OS_RELEASE_FILE=/path/to/fixture
# Optional: DIR for sourcing packages.sh when present

dots_linux_os_release_file() {
	printf '%s\n' "${DOTS_OS_RELEASE_FILE:-/etc/os-release}"
}

# Print VALUE for KEY= from os-release (unquoted). Empty if missing.
dots_linux_os_release_get() {
	local key="$1" file line val
	file="$(dots_linux_os_release_file)"
	[[ -r ${file} ]] || return 0
	while IFS= read -r line || [[ -n ${line} ]]; do
		[[ ${line} == \#* || -z ${line} ]] && continue
		case "${line}" in
		"${key}="*)
			val="${line#*=}"
			val="${val#\"}"
			val="${val%\"}"
			val="${val#\'}"
			val="${val%\'}"
			printf '%s\n' "${val}"
			return 0
			;;
		esac
	done <"${file}"
	return 0
}

# Normalized distribution ID (lowercase). Empty on non-Linux / missing file.
dots_linux_distro_id() {
	local id
	id="$(dots_linux_os_release_get ID | tr '[:upper:]' '[:lower:]')"
	# Raspberry Pi OS variants
	if [[ -z ${id} ]]; then
		printf '\n'
		return 0
	fi
	case "${id}" in
	raspbian | raspberrypi | raspberrypios) printf 'raspbian\n' ;;
	*) printf '%s\n' "${id}" ;;
	esac
}

# Space-separated ID_LIKE tokens (lowercase).
dots_linux_distro_like() {
	local like
	like="$(dots_linux_os_release_get ID_LIKE | tr '[:upper:]' '[:lower:]')"
	printf '%s\n' "${like}"
}

# Human-facing name (PRETTY_NAME or NAME or ID).
dots_linux_distro_pretty() {
	local n
	n="$(dots_linux_os_release_get PRETTY_NAME)"
	[[ -n ${n} ]] && {
		printf '%s\n' "${n}"
		return 0
	}
	n="$(dots_linux_os_release_get NAME)"
	[[ -n ${n} ]] && {
		printf '%s\n' "${n}"
		return 0
	}
	dots_linux_distro_id
}

# Coarse OS family for diagnostics: debian|arch|fedora|void|unknown
# Based on ID / ID_LIKE — not package-manager probes.
dots_linux_distro_family() {
	local id like
	id="$(dots_linux_distro_id)"
	like="$(dots_linux_distro_like)"
	case "${id}" in
	debian | ubuntu | raspbian | linuxmint | pop | elementary)
		printf 'debian\n'
		return 0
		;;
	arch | manjaro | endeavouros | garuda | artix)
		printf 'arch\n'
		return 0
		;;
	fedora | rhel | centos | rocky | almalinux | ol)
		printf 'fedora\n'
		return 0
		;;
	void)
		printf 'void\n'
		return 0
		;;
	esac
	case " ${like} " in
	*\ debian\ * | *\ ubuntu\ *)
		printf 'debian\n'
		return 0
		;;
	*\ arch\ * | *\ archlinux\ *)
		printf 'arch\n'
		return 0
		;;
	*\ fedora\ * | *\ rhel\ *)
		printf 'fedora\n'
		return 0
		;;
	esac
	# Raspberry Pi OS often ships ID=debian; detect via pretty name / rpi markers
	if [[ ${id} == debian ]]; then
		local pretty
		pretty="$(dots_linux_distro_pretty | tr '[:upper:]' '[:lower:]')"
		if [[ ${pretty} == *raspberry* ]] || [[ -f /etc/rpi-issue ]]; then
			printf 'debian\n'
			return 0
		fi
	fi
	printf 'unknown\n'
}

# True when this host is Raspberry Pi OS / Raspbian family (still apt).
dots_linux_is_raspbian() {
	local id pretty
	id="$(dots_linux_distro_id)"
	[[ ${id} == raspbian ]] && return 0
	pretty="$(dots_linux_distro_pretty | tr '[:upper:]' '[:lower:]')"
	[[ ${pretty} == *raspberry*pi*os* || ${pretty} == *raspbian* ]] && return 0
	[[ -f /etc/rpi-issue ]] && return 0
	return 1
}

# Architecture: prefer helpers/hardware.sh when available; always normalize aliases.
dots_linux_arch() {
	local m
	if declare -F dots_hw_arch >/dev/null 2>&1; then
		m="$(dots_hw_arch)"
	else
		m="$(uname -m)"
	fi
	case "${m}" in
	arm64 | aarch64) printf 'arm64\n' ;;
	x86_64 | amd64) printf 'x86_64\n' ;;
	*) printf '%s\n' "${m}" ;;
	esac
}

# Package-manager family for install (authoritative probe).
dots_linux_pkg_mgr() {
	if declare -F dots_detect_linux_pkg_mgr >/dev/null 2>&1; then
		dots_detect_linux_pkg_mgr
		return 0
	fi
	if command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
		printf 'apt\n'
	elif command -v pacman >/dev/null 2>&1; then
		printf 'pacman\n'
	elif command -v xbps-install >/dev/null 2>&1; then
		printf 'xbps\n'
	elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
		printf 'dnf\n'
	else
		printf 'unknown\n'
	fi
}

# Expected pkgmgr family hint from distro ID (for tests / diagnostics).
# Does not replace dots_linux_pkg_mgr.
dots_linux_expected_pkg_mgr() {
	case "$(dots_linux_distro_family)" in
	debian) printf 'apt\n' ;;
	arch) printf 'pacman\n' ;;
	fedora) printf 'dnf\n' ;;
	void) printf 'xbps\n' ;;
	*) printf 'unknown\n' ;;
	esac
}

# Multi-line platform report for status / Stage 0 / CI.
dots_linux_platform_report() {
	local os
	if declare -F dots_hw_os >/dev/null 2>&1; then
		case "$(dots_hw_os)" in
		linux) os=Linux ;;
		darwin) os=Darwin ;;
		*) os="$(dots_hw_os)" ;;
		esac
	else
		os="$(uname -s 2>/dev/null || echo unknown)"
	fi
	if [[ ${os} != Linux ]]; then
		echo "Platform:"
		echo "  OS: ${os}"
		if declare -F dots_hw_arch >/dev/null 2>&1; then
			echo "  architecture: $(dots_hw_arch)"
		else
			echo "  architecture: $(uname -m)"
		fi
		return 0
	fi
	local id family mgr arch pretty
	id="$(dots_linux_distro_id)"
	family="$(dots_linux_distro_family)"
	mgr="$(dots_linux_pkg_mgr)"
	arch="$(dots_linux_arch)"
	pretty="$(dots_linux_distro_pretty)"
	echo "Platform:"
	echo "  OS: Linux"
	echo "  distro: ${pretty:-${id:-unknown}}"
	echo "  id: ${id:-unknown}"
	echo "  family: ${family}"
	if dots_linux_is_raspbian; then
		echo "  raspbian: yes (Debian-family / apt)"
	fi
	echo "  package manager: ${mgr}"
	echo "  architecture: ${arch}"
	local like
	like="$(dots_linux_distro_like)"
	if [[ -n ${like} ]]; then
		echo "  like: ${like}"
	fi
}
