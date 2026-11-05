#!/usr/bin/env bash
# scripts/ci/hardware_validate.sh — hardware diagnostics (Phase 6)
#
# Read-only: never runs SMART self-tests, never runs fio workloads,
# never opens serial devices, never requires sudo.
#
# Usage:
#   ./scripts/ci/hardware_validate.sh           # status (default)
#   ./scripts/ci/hardware_validate.sh status
#   ./scripts/ci/hardware_validate.sh examples
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

MODE="${1:-status}"
OS="$(uname -s)"

usage() {
	cat <<'EOF'
Usage: ./scripts/ci/hardware_validate.sh [status|examples]

  status    Report hardware tooling (no device I/O / no sudo)
  examples  Print example commands (does not execute)

Never runs SMART tests, fio benchmarks, or opens serial devices.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

tool_line() {
	local label="$1"
	local bin="$2"
	local unsupported="${3:-}"
	if have "${bin}"; then
		local ver=""
		case "${bin}" in
		smartctl) ver="$(smartctl --version 2>/dev/null | head -n1 || true)" ;;
		fio) ver="$(fio --version 2>/dev/null | head -n1 || true)" ;;
		lsusb) ver="present" ;;
		lspci) ver="present" ;;
		picocom) ver="$(picocom --help 2>&1 | head -n1 || true)" ;;
		*) ver="present" ;;
		esac
		printf '  %-18s %s%s\n' "${label}" "${GREEN}OK${NC}" "${ver:+ (${ver})}"
	elif [[ -n ${unsupported} && ${OS} == Darwin ]]; then
		printf '  %-18s %s\n' "${label}" "UNSUPPORTED / limited on macOS"
	else
		printf '  %-18s %s\n' "${label}" "${YELLOW}missing${NC}"
	fi
}

run_status() {
	echo "${BLUE}Hardware Tooling${NC}"
	echo "────────────────────────────────"
	echo ""
	echo "Storage"
	tool_line "smartctl" smartctl
	tool_line "fio" fio
	echo ""
	echo "Buses"
	# Linux-strong; Darwin may have brew formulae but still limited
	tool_line "lsusb" lsusb linuxish
	tool_line "lspci" lspci linuxish
	echo ""
	echo "Serial"
	tool_line "picocom" picocom
	echo ""
	echo "Invariants"
	echo "  smartctl installed ≠ device health readable (no raw disk access here)"
	echo "  No SMART self-tests; no fio workloads; no serial device open"
	echo "  No sudo/doas/pkexec required for this check"
	echo "  Missing USB/PCI/serial hardware is healthy, not a failure"
	return 0
}

run_examples() {
	cat <<'EOF'
Hardware tooling examples (copy/paste — not executed by DOTS)

  smartctl --version
  # Privileged / disruptive — user-directed only (may need elevation):
  #   smartctl -a /dev/disk0
  #   smartctl -t short /dev/disk0          # self-test — not run by DOTS

  fio --version
  # Destructive risk — user-directed only; never point at production disks casually:
  #   fio --name=randread --rw=randread --bs=4k --size=1g --filename=/path/to/file

  lsusb                    # Linux (and some brew installs)
  lspci                    # Linux (and some brew installs)
  picocom -b 115200 /dev/ttyUSB0   # opens serial — user-directed only

SSH/screen/minicom may also exist on the machine; picocom is additive.
EOF
}

case "${MODE}" in
-h | --help)
	usage
	exit 0
	;;
"" | status)
	run_status
	exit $?
	;;
examples)
	run_examples
	exit 0
	;;
*)
	echo "Unknown mode: ${MODE}" >&2
	usage >&2
	exit 1
	;;
esac
