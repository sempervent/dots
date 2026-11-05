#!/usr/bin/env bash
# scripts/ci/backup_validate.sh — backup / sync diagnostics (Phase 5)
#
# Read-only: never restic init/backup/restore/forget/prune, never rclone
# remote operations, never starts Syncthing or pairs devices.
# Never prints RESTIC_PASSWORD, rclone tokens, or Syncthing API keys.
#
# Usage:
#   ./scripts/ci/backup_validate.sh              # status (default)
#   ./scripts/ci/backup_validate.sh status
#   ./scripts/ci/backup_validate.sh examples     # recovery-oriented examples only
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
Usage: ./scripts/ci/backup_validate.sh [status|examples]

  status    Report backup/sync tooling (local metadata only; no network)
  examples  Print recovery-oriented example commands (does not execute)

Never initializes repositories, runs backup/restore, contacts remotes,
starts Syncthing, or prints credentials.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

# Count rclone remotes from config without connecting.
# Prefer `rclone listremotes` (local config read). Fall back to "UNKNOWN".
rclone_remote_count() {
	if ! have rclone; then
		echo "n/a"
		return
	fi
	# listremotes reads local config only; do not pass remote: paths.
	local out
	if out="$(rclone listremotes 2>/dev/null)"; then
		# Count non-empty lines; never print remote names in status (names are OK,
		# but keep output minimal — report count only).
		local n=0
		while IFS= read -r line; do
			[[ -n ${line} ]] && n=$((n + 1))
		done <<<"${out}"
		echo "${n}"
	else
		echo "UNKNOWN"
	fi
}

rclone_config_state() {
	local cfg="${RCLONE_CONFIG:-${HOME}/.config/rclone/rclone.conf}"
	# Do not print path contents. Existence only.
	if [[ -f ${cfg} ]]; then
		echo "FOUND"
	else
		echo "NOT FOUND"
	fi
}

restic_repo_state() {
	# Explicit user configuration only — env var presence, not password.
	# Never read RESTIC_PASSWORD / RESTIC_PASSWORD_FILE contents.
	if [[ -n ${RESTIC_REPOSITORY:-} || -n ${RESTIC_REPOSITORY_FILE:-} ]]; then
		echo "CONFIGURED (env)"
	else
		echo "NOT CONFIGURED"
	fi
}

syncthing_running() {
	# Local process check only — no API, no config generation.
	if pgrep -x syncthing >/dev/null 2>&1; then
		echo "YES"
	else
		echo "NO"
	fi
}

syncthing_config_state() {
	local cfg="${HOME}/Library/Application Support/Syncthing/config.xml"
	local cfg_linux="${HOME}/.local/state/syncthing/config.xml"
	local cfg_alt="${HOME}/.config/syncthing/config.xml"
	if [[ -f ${cfg} || -f ${cfg_linux} || -f ${cfg_alt} ]]; then
		echo "FOUND"
	else
		echo "NOT FOUND"
	fi
}

run_status() {
	echo "${BLUE}Backup Tooling${NC}"
	echo "────────────────────────────────"
	echo ""

	echo "restic"
	if have restic; then
		local ver
		ver="$(restic version 2>/dev/null | head -n1 || true)"
		printf '  %-18s %s%s\n' "binary" "${GREEN}OK${NC}" "${ver:+ (${ver})}"
	else
		printf '  %-18s %s\n' "binary" "${YELLOW}missing${NC}"
	fi
	printf '  %-18s %s\n' "repository" "$(restic_repo_state)"
	echo ""

	echo "rclone (owned by network group)"
	if have rclone; then
		local ver
		ver="$(rclone version 2>/dev/null | head -n1 || true)"
		printf '  %-18s %s%s\n' "binary" "${GREEN}OK${NC}" "${ver:+ (${ver})}"
	else
		printf '  %-18s %s\n' "binary" "${YELLOW}missing${NC}"
	fi
	printf '  %-18s %s\n' "config" "$(rclone_config_state)"
	printf '  %-18s %s\n' "remotes" "$(rclone_remote_count)"
	echo ""

	echo "Syncthing (opt-in: ./setup.sh --with syncthing; omit_from_all)"
	if have syncthing; then
		# Prefer --help over bare invocation; avoid first-run config generation.
		# --version is documented as safe on current releases.
		local ver=""
		ver="$(syncthing --version 2>/dev/null | head -n1 || true)"
		printf '  %-18s %s%s\n' "binary" "${GREEN}INSTALLED${NC}" "${ver:+ (${ver})}"
	else
		printf '  %-18s %s\n' "binary" "OPTIONAL / not installed"
	fi
	printf '  %-18s %s\n' "config" "$(syncthing_config_state)"
	printf '  %-18s %s\n' "running" "$(syncthing_running)"
	echo ""

	echo "Invariants"
	echo "  Tool availability ≠ backup policy configured"
	echo "  repository NOT CONFIGURED is informational (not a failure)"
	echo "  Syncthing running=NO is informational (not a failure)"
	echo "  No restic init/backup/restore/forget/prune by this check"
	echo "  No rclone remote contact; no Syncthing start/pair/folder create"
	echo "  Credentials (RESTIC_PASSWORD, rclone tokens, API keys) never printed"
	return 0
}

run_examples() {
	cat <<'EOF'
Backup / recovery examples (copy/paste — not executed by DOTS)

  # restic — encrypted snapshot backup (user supplies repo + password)
  export RESTIC_REPOSITORY=/path/to/repo   # or s3:… / rest:…
  export RESTIC_PASSWORD_FILE=~/.config/restic/password   # user-managed
  restic init                  # once, explicitly
  restic backup ~/Documents
  restic snapshots
  restic restore latest --target /tmp/restore-dryrun

  # rclone — transport / remote filesystem (not a backup policy by itself)
  rclone listremotes           # local config only
  rclone ls remote:path        # contacts remote — user-directed only

  # Syncthing — peer sync (NOT a backup by itself)
  syncthing                    # user starts intentionally; DOTS never does

Philosophy
  tool availability  →  DOTS Phase 5
  configuration      →  user
  backup execution   →  user
  restore execution  →  user (explicit destination)
  scheduling         →  not created by DOTS Phase 5

DOTS config snapshots (./dots backup) are separate from restic repositories.
See docs/concepts/backup.md vs docs/using/backup-tooling.md.
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
