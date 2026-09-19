#!/usr/bin/env bash
# scripts/mactools/export-configs.sh — ingest vendor-supported exports into dots
#
# Does NOT scrape ~/Library or reverse-engineer app databases.
# Usage:
#   ./scripts/mactools/export-configs.sh
#   ./scripts/mactools/export-configs.sh all
#   ./scripts/mactools/export-configs.sh vorssaint ~/Desktop/Vorssaint\ Settings.plist
#   ./scripts/mactools/export-configs.sh keyboard-maestro ~/Desktop/Macros.kmmacros
#   ./scripts/mactools/export-configs.sh hazel ~/Desktop/HazelExport/
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST_ROOT="${ROOT}/configs/mactools"

usage() {
	cat <<'EOF'
Usage: ./scripts/mactools/export-configs.sh [TOOL] [EXPORT_PATH]

TOOLS:
  vorssaint          Ingest Vorssaint Settings.plist (after in-app Export)
  keyboard-maestro   Ingest .kmmacros / export folder (after File → Export)
  hazel              Ingest Hazel Export All directory or rule file
  raycast            Print manual guidance only
  all                Print status + guidance for every tool

With no EXPORT_PATH, prints the official manual export steps for TOOL.
With EXPORT_PATH, validates (where possible) and copies into configs/mactools/<tool>/.

Never commits secrets automatically — review before git add.
EOF
}

_status_line() {
	local tool="$1" status="$2" note="$3"
	printf '%-18s %-12s %s\n' "${tool}" "${status}" "${note}"
}

print_status_table() {
	echo "=== mactools config portability ==="
	_status_line "vorssaint" "manual→ingest" "in-app Export/Import plist"
	_status_line "keyboard-maestro" "manual" "File → Export Macros"
	_status_line "hazel" "manual" "Action → Export All"
	_status_line "raycast" "unsupported" "account sync only; no offline export"
	echo ""
	echo "Docs: ${DEST_ROOT}/<tool>/README.md  and  docs/MACTOOLS.md"
}

_scan_secrets_hint() {
	local path="$1"
	if command -v rg >/dev/null 2>&1; then
		if rg -n -i 'password|api[_-]?key|secret|token|bearer |sk-|BEGIN (RSA |OPENSSH )?PRIVATE' "${path}" 2>/dev/null | head -5; then
			echo "Warn: possible secret-like strings detected — review before committing." >&2
			return 1
		fi
	fi
	return 0
}

ingest_vorssaint() {
	local src="$1"
	local dest_dir="${DEST_ROOT}/vorssaint"
	local dest="${dest_dir}/settings.plist"
	[[ -f ${src} ]] || {
		echo "Error: plist not found: ${src}" >&2
		return 1
	}
	# Validate portable backup markers when present
	if ! grep -q 'vorssaintBackupVersion\|vorssaintBackupAppVersion\|Vorssaint' "${src}" 2>/dev/null; then
		echo "Warn: file does not look like a Vorssaint settings export (continuing)." >&2
	fi
	mkdir -p "${dest_dir}"
	cp "${src}" "${dest}"
	chmod 600 "${dest}" 2>/dev/null || true
	_scan_secrets_hint "${dest}" || true
	echo "OK: ingested → ${dest}"
	echo "Note: plist is gitignored by default; review then force-add only if intentional."
}

ingest_km() {
	local src="$1"
	local dest_dir="${DEST_ROOT}/keyboard-maestro"
	mkdir -p "${dest_dir}"
	if [[ -d ${src} ]]; then
		local name
		name="$(basename "${src}")"
		rm -rf "${dest_dir:?}/${name:?}"
		cp -R "${src}" "${dest_dir}/${name}"
		echo "OK: copied export folder → ${dest_dir}/${name}"
	elif [[ -f ${src} ]]; then
		cp "${src}" "${dest_dir}/$(basename "${src}")"
		echo "OK: copied → ${dest_dir}/$(basename "${src}")"
	else
		echo "Error: missing export: ${src}" >&2
		return 1
	fi
	_scan_secrets_hint "${dest_dir}" || true
	echo "Note: KM exports are gitignored by default."
}

ingest_hazel() {
	local src="$1"
	local dest_dir="${DEST_ROOT}/hazel"
	mkdir -p "${dest_dir}"
	if [[ -d ${src} ]]; then
		local name
		name="$(basename "${src}")"
		rm -rf "${dest_dir:?}/${name:?}"
		cp -R "${src}" "${dest_dir}/${name}"
		echo "OK: copied Hazel export dir → ${dest_dir}/${name}"
	elif [[ -f ${src} ]]; then
		cp "${src}" "${dest_dir}/$(basename "${src}")"
		echo "OK: copied → ${dest_dir}/$(basename "${src}")"
	else
		echo "Error: missing Hazel export: ${src}" >&2
		return 1
	fi
	echo "Note: Hazel exports often contain absolute paths — review before commit."
}

guide_vorssaint() {
	cat <<'EOF'
Vorssaint (manual):
  1. Open Vorssaint → Settings → Export settings to a .plist
  2. ./scripts/mactools/export-configs.sh vorssaint /path/to/Vorssaint\ Settings.plist
EOF
}

guide_km() {
	cat <<'EOF'
Keyboard Maestro (manual):
  1. Open Keyboard Maestro editor
  2. File → Export → Export Macros… (or Export as Folder…)
  3. ./scripts/mactools/export-configs.sh keyboard-maestro /path/to/export
  Do not copy ~/Library/Application Support/Keyboard Maestro into Git.
EOF
}

guide_hazel() {
	cat <<'EOF'
Hazel (manual):
  1. Open Hazel
  2. Action → Export All (or Export Rules for one folder)
  3. ./scripts/mactools/export-configs.sh hazel /path/to/export-dir
  Do not commit ~/Library/Application Support/Hazel wholesale.
EOF
}

guide_raycast() {
	cat <<'EOF'
Raycast (unsupported for offline Git sync):
  Use Raycast account sync if available. Do not scrape Application Support.
EOF
}

tool="${1:-all}"
path="${2:-}"

case "${tool}" in
-h | --help) usage; exit 0 ;;
all)
	print_status_table
	echo ""
	guide_vorssaint
	echo ""
	guide_km
	echo ""
	guide_hazel
	echo ""
	guide_raycast
	;;
vorssaint)
	if [[ -n ${path} ]]; then
		ingest_vorssaint "${path}"
	else
		guide_vorssaint
	fi
	;;
keyboard-maestro | km)
	if [[ -n ${path} ]]; then
		ingest_km "${path}"
	else
		guide_km
	fi
	;;
hazel)
	if [[ -n ${path} ]]; then
		ingest_hazel "${path}"
	else
		guide_hazel
	fi
	;;
raycast)
	guide_raycast
	;;
*)
	echo "Unknown tool: ${tool}" >&2
	usage >&2
	exit 1
	;;
esac
