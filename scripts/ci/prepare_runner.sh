#!/usr/bin/env bash
# scripts/ci/prepare_runner.sh — install CI harness tools on ubuntu-latest
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

if [[ "$(uname -s)" != "Linux" ]]; then
	echo "prepare_runner.sh targets Linux CI runners (skipping on $(uname -s))"
	exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
	echo "Error: apt-get required on this runner" >&2
	exit 1
fi

sudo apt-get update -qq
# Tools: shellcheck (lint), ripgrep (tests), zsh (runtime_precedence), curl + CAs (shfmt fetch)
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
	shellcheck ripgrep zsh ca-certificates curl >/dev/null

# shfmt from official GitHub release with checksum verification
SHFMT_VER="3.12.0"
SHFMT_ARCH="linux_amd64"
case "$(uname -m)" in
aarch64 | arm64) SHFMT_ARCH="linux_arm64" ;;
x86_64 | amd64) SHFMT_ARCH="linux_amd64" ;;
*)
	echo "Error: unsupported arch for shfmt: $(uname -m)" >&2
	exit 1
	;;
esac

SHFMT_NAME="shfmt_v${SHFMT_VER}_${SHFMT_ARCH}"
SHFMT_URL="https://github.com/mvdan/sh/releases/download/v${SHFMT_VER}/${SHFMT_NAME}"
SUMS_URL="https://github.com/mvdan/sh/releases/download/v${SHFMT_VER}/sha256sums.txt"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
curl -fsSL "${SUMS_URL}" -o "${TMP}/sha256sums.txt"
curl -fsSL "${SHFMT_URL}" -o "${TMP}/${SHFMT_NAME}"
EXPECTED="$(awk -v f="${SHFMT_NAME}" '$2 == f {print $1; exit}' "${TMP}/sha256sums.txt")"
if [[ -z ${EXPECTED} ]]; then
	echo "Error: checksum not found for ${SHFMT_NAME}" >&2
	exit 1
fi
ACTUAL="$(sha256sum "${TMP}/${SHFMT_NAME}" | awk '{print $1}')"
if [[ ${ACTUAL} != "${EXPECTED}" ]]; then
	echo "Error: shfmt checksum mismatch" >&2
	echo "  expected: ${EXPECTED}" >&2
	echo "  actual:   ${ACTUAL}" >&2
	exit 1
fi
chmod +x "${TMP}/${SHFMT_NAME}"
sudo mv "${TMP}/${SHFMT_NAME}" /usr/local/bin/shfmt

command -v shellcheck
command -v shfmt
command -v rg
command -v zsh
echo "OK: CI runner prepared"
