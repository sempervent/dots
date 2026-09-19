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
# Runtime helpers only — ShellCheck/shfmt come from pinned releases (not apt).
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
	ripgrep zsh ca-certificates curl xz-utils >/dev/null

# shellcheck source=ensure_lint_tools.sh
source "${ROOT}/scripts/ci/ensure_lint_tools.sh"
dots_ensure_lint_tools

# Prefer pinned tools for the remainder of the job
if [[ -n ${GITHUB_PATH:-} ]]; then
	echo "${BIN_DIR}" >>"${GITHUB_PATH}"
fi
export PATH="${BIN_DIR}:${PATH}"

command -v shellcheck
command -v shfmt
command -v rg
command -v zsh
echo "OK: CI runner prepared"
