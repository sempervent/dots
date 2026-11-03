#!/usr/bin/env bash
# scripts/ci/ensure_uv.sh — install/verify pinned uv for CI (dots-help, Python tools)
#
# Downloads official release artifacts into <repo>/.tools/bin and verifies SHA-256.
# Used by prepare_runner.sh and macos_smoke.sh.
#
# Never pipes curl to a shell.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tool-versions.env
source "${ROOT}/scripts/ci/tool-versions.env"

TOOLS_DIR="${DOTS_TOOLS_DIR:-${ROOT}/.tools}"
BIN_DIR="${TOOLS_DIR}/bin"
mkdir -p "${BIN_DIR}"

_dots_ci_arch() {
	case "$(uname -s)-$(uname -m)" in
	Linux-x86_64 | Linux-amd64) printf 'linux-amd64\n' ;;
	Linux-aarch64 | Linux-arm64) printf 'linux-arm64\n' ;;
	Darwin-x86_64) printf 'darwin-amd64\n' ;;
	Darwin-arm64) printf 'darwin-arm64\n' ;;
	*)
		echo "Error: unsupported OS/arch: $(uname -s) $(uname -m)" >&2
		return 1
		;;
	esac
}

_dots_sha256_file() {
	local f="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "${f}" | awk '{print $1}'
	else
		shasum -a 256 "${f}" | awk '{print $1}'
	fi
}

_dots_uv_version_ok() {
	local bin="$1" expect="$2" got=""
	[[ -x ${bin} ]] || return 1
	got="$("${bin}" --version 2>/dev/null | awk '{print $2; exit}')"
	[[ ${got} == "${expect}" ]]
}

_dots_install_uv() {
	local arch="$1" expected="" url="" name="" triple="" tmp actual
	case "${arch}" in
	linux-amd64)
		triple="x86_64-unknown-linux-gnu"
		expected="${UV_SHA256_LINUX_AMD64}"
		;;
	linux-arm64)
		triple="aarch64-unknown-linux-gnu"
		expected="${UV_SHA256_LINUX_ARM64}"
		;;
	darwin-amd64)
		triple="x86_64-apple-darwin"
		expected="${UV_SHA256_DARWIN_AMD64}"
		;;
	darwin-arm64)
		triple="aarch64-apple-darwin"
		expected="${UV_SHA256_DARWIN_ARM64}"
		;;
	esac
	name="uv-${triple}.tar.gz"
	url="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${name}"

	tmp="$(mktemp -d)"
	echo "Fetching uv ${UV_VERSION} (${triple})..."
	curl -fsSL "${url}" -o "${tmp}/${name}"
	actual="$(_dots_sha256_file "${tmp}/${name}")"
	if [[ ${actual} != "${expected}" ]]; then
		rm -rf "${tmp}"
		echo "Error: uv checksum mismatch" >&2
		echo "  expected: ${expected}" >&2
		echo "  actual:   ${actual}" >&2
		return 1
	fi
	tar -xzf "${tmp}/${name}" -C "${tmp}"
	install -m 0755 "${tmp}/uv-${triple}/uv" "${BIN_DIR}/uv"
	rm -rf "${tmp}"
}

dots_ensure_uv() {
	local arch
	arch="$(_dots_ci_arch)"

	export PATH="${BIN_DIR}:${PATH}"

	# Prefer an already-correct system/Homebrew uv when present.
	if command -v uv >/dev/null 2>&1; then
		if _dots_uv_version_ok "$(command -v uv)" "${UV_VERSION}"; then
			echo "uv $(uv --version)"
			return 0
		fi
	fi

	if ! _dots_uv_version_ok "${BIN_DIR}/uv" "${UV_VERSION}"; then
		_dots_install_uv "${arch}"
	fi

	if ! _dots_uv_version_ok "${BIN_DIR}/uv" "${UV_VERSION}"; then
		echo "Error: uv ${UV_VERSION} not available after install" >&2
		return 1
	fi

	echo "uv $(uv --version)"
}

# When executed directly (not sourced), install and exit.
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
	dots_ensure_uv
fi
