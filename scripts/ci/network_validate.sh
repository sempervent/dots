#!/usr/bin/env bash
# scripts/ci/network_validate.sh — network diagnostics (Phase 6)
#
# Read-only: never scans hosts/subnets, never starts iperf, never captures
# packets, never runs `tailscale up` / login / set, never opens mosh/ssh.
#
# Usage:
#   ./scripts/ci/network_validate.sh           # status (default)
#   ./scripts/ci/network_validate.sh status
#   ./scripts/ci/network_validate.sh examples
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

MODE="${1:-status}"

usage() {
	cat <<'EOF'
Usage: ./scripts/ci/network_validate.sh [status|examples]

  status    Report network tooling (local only; no probes/captures)
  examples  Print example commands (does not execute)

Never scans networks, captures packets, starts iperf, or runs tailscale up.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

tool_line() {
	local label="$1"
	local bin="$2"
	local note="${3:-}"
	if have "${bin}"; then
		local ver=""
		case "${bin}" in
		mtr) ver="$(mtr --version 2>/dev/null | head -n1 || true)" ;;
		nmap) ver="$(nmap --version 2>/dev/null | head -n1 || true)" ;;
		iperf3) ver="$(iperf3 --version 2>/dev/null | head -n1 || true)" ;;
		gping) ver="$(gping --version 2>/dev/null | head -n1 || true)" ;;
		bandwhich) ver="$(bandwhich --version 2>/dev/null | head -n1 || true)" ;;
		termshark) ver="$(termshark --version 2>/dev/null | head -n1 || true)" ;;
		tshark) ver="$(tshark --version 2>/dev/null | head -n1 || true)" ;;
		mosh) ver="$(mosh --version 2>/dev/null | head -n1 || true)" ;;
		rclone) ver="$(rclone version 2>/dev/null | head -n1 || true)" ;;
		*) ver="present" ;;
		esac
		printf '  %-18s %s%s%s\n' "${label}" "${GREEN}OK${NC}" "${ver:+ (${ver})}" "${note:+ ${note}}"
	else
		# termshark often missing on Darwin (Homebrew formula disabled)
		if [[ ${label} == termshark || ${label} == tshark ]]; then
			printf '  %-18s %s\n' "${label}" "OPTIONAL / not installed"
		else
			printf '  %-18s %s\n' "${label}" "${YELLOW}missing${NC}"
		fi
	fi
}

# Safe Tailscale status — never up/login/set. Prefer `tailscale status --json`
# only if non-mutating; fall back to version + presence.
tailscale_block() {
	echo "Tailscale"
	if ! have tailscale; then
		printf '  %-18s %s\n' "installed" "OPTIONAL / not installed"
		printf '  %-18s %s\n' "connected" "NO"
		return 0
	fi
	local ver=""
	ver="$(tailscale version 2>/dev/null | head -n1 || true)"
	printf '  %-18s %s%s\n' "installed" "${GREEN}YES${NC}" "${ver:+ (${ver})}"

	# Read-only status. Never pass up/login/set/switch.
	# Prefer JSON BackendState so we never print auth/node keys.
	local connected="NO"
	local logged_in="NO"
	local backend=""
	if backend="$(tailscale status --json --peers=false 2>/dev/null |
		python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)
  print(d.get("BackendState") or "")
except Exception:
  print("")' 2>/dev/null)"; then
		case "${backend}" in
		Running)
			logged_in="YES"
			connected="YES"
			;;
		NeedsLogin | NeedsMachineAuth)
			logged_in="NO"
			connected="NO"
			;;
		Stopped | "" )
			logged_in="NO"
			connected="NO"
			;;
		*)
			logged_in="UNKNOWN"
			connected="UNKNOWN"
			;;
		esac
		[[ -n ${backend} ]] && printf '  %-18s %s\n' "daemon state" "${backend}"
	else
		printf '  %-18s %s\n' "daemon" "NOT REACHABLE"
	fi
	printf '  %-18s %s\n' "logged in" "${logged_in}"
	printf '  %-18s %s\n' "connected" "${connected}"
}

run_status() {
	echo "${BLUE}Network Tooling${NC}"
	echo "────────────────────────────────"
	echo ""
	echo "Diagnostics"
	tool_line "mtr" mtr
	tool_line "nmap" nmap
	tool_line "iperf3" iperf3
	tool_line "gping" gping
	tool_line "bandwhich" bandwhich
	echo ""
	echo "Packet analysis"
	tool_line "termshark" termshark "(Homebrew formula disabled; Linux/native may provide)"
	tool_line "tshark" tshark
	echo ""
	echo "Remote / transfer"
	tool_line "mosh" mosh
	tool_line "rclone" rclone "(owned by network)"
	echo ""
	tailscale_block
	echo ""
	echo "Invariants"
	echo "  No host/subnet scans; no iperf client/server; no packet capture"
	echo "  No tailscale up/login/set; no mosh/ssh connections"
	echo "  SSH remains the default remote shell (mosh is optional)"
	echo "  Capture privileges / BPF / wireshark group never modified by this check"
	return 0
}

run_examples() {
	cat <<'EOF'
Network tooling examples (copy/paste — not executed by DOTS)

  mtr example.com
  nmap -sV host.example          # may be restricted by org policy
  iperf3 -c host.example         # user-directed throughput test
  gping example.com
  bandwhich                      # often needs elevated privileges (user-run)
  termshark -i en0               # packet capture may expose sensitive traffic
  mosh user@host                 # resilient remote shell (SSH remains default)
  tailscale status               # read-only
  # DOTS never runs: tailscale up | login | set

Warnings
  nmap / scanning may be unauthorized on networks you do not own.
  Packet capture (termshark/tshark/bandwhich) may expose credentials/traffic.
  Tailscale installation does not authenticate or join a tailnet.
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
