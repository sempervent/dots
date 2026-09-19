#!/usr/bin/env bash
# scripts/ci/distro_smoke.sh — Linux distro family smoke inside a container
#
# Usage:
#   ./scripts/ci/distro_smoke.sh <image> [--name LABEL] [--family apt|pacman|dnf|xbps]
#
# Validates:
#   - distro identity (/etc/os-release)
#   - package-manager detection
#   - required package-map entries exist in distro repositories (non-installing)
#   - bootstrap --profile server --show / --dry-run
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE=""
LABEL=""
FAMILY=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--name)
		shift
		LABEL="${1:-}"
		;;
	--family)
		shift
		FAMILY="${1:-}"
		;;
	-*)
		echo "Unknown option: $1" >&2
		exit 1
		;;
	*)
		if [[ -z ${IMAGE} ]]; then
			IMAGE="$1"
		else
			echo "Unexpected argument: $1" >&2
			exit 1
		fi
		;;
	esac
	shift || true
done

if [[ -z ${IMAGE} ]]; then
	echo "Usage: $0 <container-image> [--name LABEL] [--family apt|pacman|dnf|xbps]" >&2
	exit 1
fi
[[ -z ${LABEL} ]] && LABEL="${IMAGE}"

if ! command -v docker >/dev/null 2>&1; then
	echo "Error: docker required" >&2
	exit 1
fi

echo "=== Distro smoke: ${LABEL} (${IMAGE}) ==="

# Entry with sh so Void (no bash preinstalled) can bootstrap; then switch to bash.
docker run --rm \
	-e DOTS_SMOKE_FAMILY="${FAMILY}" \
	-e DOTS_SMOKE_LABEL="${LABEL}" \
	-v "${ROOT}:/dots:ro" -w /dots "${IMAGE}" \
	sh -c '
set -e
install_prereqs() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      python3 bash ca-certificates curl >/dev/null
  elif command -v pacman >/dev/null 2>&1; then
    if ! grep -q "^DisableSandbox" /etc/pacman.conf 2>/dev/null; then
      if grep -q "^\[options\]" /etc/pacman.conf 2>/dev/null; then
        sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf
      else
        printf "\n[options]\nDisableSandbox\n" >> /etc/pacman.conf
      fi
    fi
    pacman -Sy --noconfirm python bash ca-certificates curl >/dev/null
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install python3 bash ca-certificates curl >/dev/null
  elif command -v xbps-install >/dev/null 2>&1; then
    mkdir -p /etc/xbps.d
    printf "%s\n" "repository=https://repo-default.voidlinux.org/current" \
      > /etc/xbps.d/00-repository-main.conf
    xbps-install -Sy ca-certificates >/dev/null
    xbps-install -Sy python3 bash curl >/dev/null
  else
    echo "Error: unsupported package manager in image" >&2
    exit 1
  fi
}
install_prereqs
exec bash /dots/scripts/ci/distro_smoke_inner.sh
'
