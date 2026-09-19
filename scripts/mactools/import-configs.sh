#!/usr/bin/env bash
# scripts/mactools/import-configs.sh — guide restoring vendor-supported exports
#
# Does not force-quit apps or write into ~/Library preference databases.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_ROOT="${ROOT}/configs/mactools"

usage() {
	cat <<'EOF'
Usage: ./scripts/mactools/import-configs.sh <TOOL>

TOOLS: vorssaint | keyboard-maestro | hazel | raycast | all

Opens Finder on the export directory when files exist, and prints the
official in-app Import steps. Never scrapes or overwrites live app databases.
EOF
}

_open_dir() {
	local d="$1"
	if [[ -d ${d} ]] && [[ "$(uname -s)" == "Darwin" ]]; then
		open "${d}" 2>/dev/null || true
		echo "Opened: ${d}"
	fi
}

import_vorssaint() {
	local d="${SRC_ROOT}/vorssaint"
	local plist="${d}/settings.plist"
	echo "=== Vorssaint import ==="
	if [[ -f ${plist} ]]; then
		echo "Found: ${plist}"
		_open_dir "${d}"
		echo "In Vorssaint: Settings → Import → select settings.plist"
		if [[ "$(uname -s)" == "Darwin" ]]; then
			open "${plist}" 2>/dev/null || true
		fi
	else
		echo "No ingested plist at ${plist}"
		echo "Export first: ./scripts/mactools/export-configs.sh vorssaint <file>"
		_open_dir "${d}"
	fi
}

import_km() {
	local d="${SRC_ROOT}/keyboard-maestro"
	echo "=== Keyboard Maestro import ==="
	_open_dir "${d}"
	echo "In Keyboard Maestro: File → Import Macros… → select .kmmacros / folder"
	ls -la "${d}" 2>/dev/null | sed -n '1,20p' || true
}

import_hazel() {
	local d="${SRC_ROOT}/hazel"
	echo "=== Hazel import ==="
	_open_dir "${d}"
	echo "In Hazel: Action → Import Rules → select exported rule files"
	ls -la "${d}" 2>/dev/null | sed -n '1,20p' || true
}

import_raycast() {
	echo "=== Raycast ==="
	echo "No offline import path in DOTS. Use Raycast account sync if available."
}

tool="${1:-}"
case "${tool}" in
"" | -h | --help) usage; exit 0 ;;
all)
	import_vorssaint
	echo ""
	import_km
	echo ""
	import_hazel
	echo ""
	import_raycast
	;;
vorssaint) import_vorssaint ;;
keyboard-maestro | km) import_km ;;
hazel) import_hazel ;;
raycast) import_raycast ;;
*)
	echo "Unknown tool: ${tool}" >&2
	usage >&2
	exit 1
	;;
esac
