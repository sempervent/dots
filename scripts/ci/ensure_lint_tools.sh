#!/usr/bin/env bash
# scripts/ci/ensure_lint_tools.sh — install/verify pinned ShellCheck + shfmt
#
# Downloads official release artifacts into <repo>/.tools/bin and verifies SHA-256.
# Used by prepare_runner.sh (CI) and lint.sh (local + CI).
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

_dots_tool_version_ok() {
	local bin="$1" expect="$2" got=""
	[[ -x ${bin} ]] || return 1
	case "$(basename "${bin}")" in
	shellcheck)
		got="$("${bin}" --version 2>/dev/null | awk '/version:/ {print $2; exit}')"
		;;
	shfmt)
		got="$("${bin}" --version 2>/dev/null | tr -d 'v' | head -1)"
		;;
	*) return 1 ;;
	esac
	[[ ${got} == "${expect}" ]]
}

_dots_install_shellcheck() {
	local arch="$1" expected="" url="" name="" platform="" tmp actual
	case "${arch}" in
	linux-amd64)
		platform="linux.x86_64"
		expected="${SHELLCHECK_SHA256_LINUX_AMD64}"
		;;
	linux-arm64)
		platform="linux.aarch64"
		expected="${SHELLCHECK_SHA256_LINUX_ARM64}"
		;;
	darwin-amd64)
		platform="darwin.x86_64"
		expected="${SHELLCHECK_SHA256_DARWIN_AMD64}"
		;;
	darwin-arm64)
		platform="darwin.aarch64"
		expected="${SHELLCHECK_SHA256_DARWIN_ARM64}"
		;;
	esac
	name="shellcheck-v${SHELLCHECK_VERSION}.${platform}.tar.xz"
	url="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${name}"

	tmp="$(mktemp -d)"
	echo "Fetching ShellCheck v${SHELLCHECK_VERSION} (${platform})..."
	curl -fsSL "${url}" -o "${tmp}/${name}"
	actual="$(_dots_sha256_file "${tmp}/${name}")"
	if [[ ${actual} != "${expected}" ]]; then
		rm -rf "${tmp}"
		echo "Error: ShellCheck checksum mismatch" >&2
		echo "  expected: ${expected}" >&2
		echo "  actual:   ${actual}" >&2
		return 1
	fi
	tar -xJf "${tmp}/${name}" -C "${tmp}"
	install -m 0755 "${tmp}/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "${BIN_DIR}/shellcheck"
	rm -rf "${tmp}"
}

_dots_install_shfmt() {
	local arch="$1" expected="" url="" name="" goarch="" tmp actual
	case "${arch}" in
	linux-amd64)
		goarch="linux_amd64"
		expected="${SHFMT_SHA256_LINUX_AMD64}"
		;;
	linux-arm64)
		goarch="linux_arm64"
		expected="${SHFMT_SHA256_LINUX_ARM64}"
		;;
	darwin-amd64)
		goarch="darwin_amd64"
		expected="${SHFMT_SHA256_DARWIN_AMD64}"
		;;
	darwin-arm64)
		goarch="darwin_arm64"
		expected="${SHFMT_SHA256_DARWIN_ARM64}"
		;;
	esac
	name="shfmt_v${SHFMT_VERSION}_${goarch}"
	url="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/${name}"

	tmp="$(mktemp -d)"
	echo "Fetching shfmt v${SHFMT_VERSION} (${goarch})..."
	curl -fsSL "${url}" -o "${tmp}/${name}"
	actual="$(_dots_sha256_file "${tmp}/${name}")"
	if [[ ${actual} != "${expected}" ]]; then
		rm -rf "${tmp}"
		echo "Error: shfmt checksum mismatch" >&2
		echo "  expected: ${expected}" >&2
		echo "  actual:   ${actual}" >&2
		return 1
	fi
	install -m 0755 "${tmp}/${name}" "${BIN_DIR}/shfmt"
	rm -rf "${tmp}"
}

dots_ensure_lint_tools() {
	local arch
	arch="$(_dots_ci_arch)"

	export PATH="${BIN_DIR}:${PATH}"

	if ! _dots_tool_version_ok "${BIN_DIR}/shellcheck" "${SHELLCHECK_VERSION}"; then
		_dots_install_shellcheck "${arch}"
	fi
	if ! _dots_tool_version_ok "${BIN_DIR}/shfmt" "${SHFMT_VERSION}"; then
		_dots_install_shfmt "${arch}"
	fi

	if ! _dots_tool_version_ok "${BIN_DIR}/shellcheck" "${SHELLCHECK_VERSION}"; then
		echo "Error: ShellCheck ${SHELLCHECK_VERSION} not available after install" >&2
		return 1
	fi
	if ! _dots_tool_version_ok "${BIN_DIR}/shfmt" "${SHFMT_VERSION}"; then
		echo "Error: shfmt ${SHFMT_VERSION} not available after install" >&2
		return 1
	fi

	echo "Lint toolchain (pinned):"
	shellcheck --version | head -2
	echo "shfmt $(shfmt --version)"
}

# When executed directly (not sourced), install and exit.
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
	dots_ensure_lint_tools
fi
