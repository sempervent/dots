#!/usr/bin/env bash
# scripts/ci/distro_smoke_inner.sh — runs inside the container after prereqs
# Invoked by distro_smoke.sh via: exec bash /dots/scripts/ci/distro_smoke_inner.sh
set -euo pipefail

command -v python3
command -v bash

export DIR=/dots
# shellcheck disable=SC1091
source /dots/helpers/toml.sh
# shellcheck disable=SC1091
source /dots/helpers/packages.sh
# shellcheck disable=SC1091
source /dots/helpers/hardware.sh
# shellcheck disable=SC1091
source /dots/helpers/linux_distro.sh

echo ""
dots_linux_platform_report
echo ""

mgr="$(dots_linux_pkg_mgr)"
id="$(dots_linux_distro_id)"
family="$(dots_linux_distro_family)"
arch="$(dots_linux_arch)"

echo "Smoke metadata:"
echo "  label: ${DOTS_SMOKE_LABEL:-}"
echo "  expected family arg: ${DOTS_SMOKE_FAMILY:-"(none)"}"
echo "  detected id/family/pkgmgr/arch: ${id} / ${family} / ${mgr} / ${arch}"

if [[ -n ${DOTS_SMOKE_FAMILY:-} && ${DOTS_SMOKE_FAMILY} != "${mgr}" ]]; then
	echo "Error: expected package manager ${DOTS_SMOKE_FAMILY}, detected ${mgr}" >&2
	exit 1
fi

PROFILE_PACKAGES=(core modern server)
dots_resolve_package_groups
echo "  resolved groups: ${DOTS_RESOLVED_GROUPS[*]}"

case "${mgr}" in
apt) mapfile=/dots/configs/packages/apt.toml ;;
pacman) mapfile=/dots/configs/packages/pacman.toml ;;
dnf) mapfile=/dots/configs/packages/dnf.toml ;;
xbps) mapfile=/dots/configs/packages/xbps.toml ;;
*)
	echo "Error: no package map for mgr=${mgr}" >&2
	exit 1
	;;
esac
echo "  package map: $(basename "${mapfile}")"

_map_tool() {
	local tool="$1"
	TOOL="${tool}" MAPFILE="${mapfile}" python3 - <<'PY'
import os, tomllib
with open(os.environ["MAPFILE"], "rb") as f:
    data = tomllib.load(f)
t = os.environ["TOOL"]
pkgs = data.get("packages") or {}
val = pkgs.get(t)
if val is None:
    print("MISSING")
elif str(val).strip() == "":
    print("SKIP")
else:
    print(str(val).strip())
PY
}

pkg_exists() {
	local pkg="$1"
	case "${mgr}" in
	apt)
		apt-cache show "${pkg}" >/dev/null 2>&1
		;;
	pacman)
		pacman -Si "${pkg}" >/dev/null 2>&1
		;;
	dnf)
		dnf info -q "${pkg}" >/dev/null 2>&1
		;;
	xbps)
		xbps-query -R "${pkg}" >/dev/null 2>&1
		;;
	*) return 1 ;;
	esac
}

req_fail=0
opt_warn=0
echo ""
echo "=== Required package mappings (server groups) ==="
while IFS= read -r tool; do
	[[ -z ${tool} ]] && continue
	native="$(_map_tool "${tool}")"
	case "${native}" in
	MISSING)
		echo "ERROR: required tool ${tool} has no mapping in $(basename "${mapfile}")"
		req_fail=1
		;;
	SKIP)
		echo "NOTE: required tool ${tool} skipped on ${mgr} (empty map)"
		;;
	*)
		if pkg_exists "${native}"; then
			echo "OK: ${tool} → ${native}"
		else
			echo "ERROR: required ${tool} → ${native} not found in ${mgr} repositories"
			req_fail=1
		fi
		;;
	esac
done < <(dots_tools_for_groups required)

echo ""
echo "=== Optional package mappings (advisory) ==="
while IFS= read -r tool; do
	[[ -z ${tool} ]] && continue
	native="$(_map_tool "${tool}")"
	case "${native}" in
	MISSING | SKIP)
		echo "NOTE: optional ${tool} unavailable via ${mgr} map"
		;;
	*)
		if pkg_exists "${native}"; then
			echo "OK: optional ${tool} → ${native}"
		else
			echo "WARN: optional ${tool} → ${native} not in repositories"
			opt_warn=$((opt_warn + 1))
		fi
		;;
	esac
done < <(dots_tools_for_groups optional)

if [[ ${req_fail} -ne 0 ]]; then
	echo "Error: one or more REQUIRED package mappings failed" >&2
	exit 1
fi
echo "Optional advisories: ${opt_warn}"

echo ""
echo "=== bootstrap --profile server --show ==="
bash /dots/bootstrap.sh --profile server --show

echo ""
echo "=== bootstrap --profile server --dry-run ==="
bash /dots/bootstrap.sh --profile server --dry-run

echo ""
echo "OK: distro smoke passed (${DOTS_SMOKE_LABEL:-${mgr}})"
