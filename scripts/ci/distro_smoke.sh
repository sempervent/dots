#!/usr/bin/env bash
# scripts/ci/distro_smoke.sh — run server profile smoke inside a Linux container
# Usage: ./scripts/ci/distro_smoke.sh <image>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${1:-}"
if [[ -z ${IMAGE} ]]; then
	echo "Usage: $0 <container-image>" >&2
	exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
	echo "Error: docker required" >&2
	exit 1
fi

docker run --rm -v "${ROOT}:/dots:ro" -w /dots "${IMAGE}" sh -c '
set -e
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 bash ca-certificates >/dev/null
elif command -v pacman >/dev/null 2>&1; then
  # Nested virt: alpm sandbox can fail in GitHub Actions
  grep -q "^DisableSandbox" /etc/pacman.conf || echo DisableSandbox >> /etc/pacman.conf
  pacman -Sy --noconfirm python bash ca-certificates >/dev/null
elif command -v xbps-install >/dev/null 2>&1; then
  # Use current official Void mirror (valid TLS). Never disable verification.
  mkdir -p /etc/xbps.d
  printf "%s\n" "repository=https://repo-default.voidlinux.org/current" \
    > /etc/xbps.d/00-repository-main.conf
  # Refresh CA store with normal TLS; fail if the mirror is untrustworthy.
  xbps-install -Sy ca-certificates >/dev/null
  xbps-install -Sy python3 bash >/dev/null
else
  echo "Error: unsupported package manager in image" >&2
  exit 1
fi
command -v python3
command -v bash
bash ./bootstrap.sh --profile server --show
bash ./bootstrap.sh --profile server --dry-run
'
