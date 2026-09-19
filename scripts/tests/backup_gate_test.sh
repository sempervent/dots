#!/usr/bin/env bash
# scripts/tests/backup_gate_test.sh — backup failure must block symlink mutation
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-bak-gate.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT
export HOME="${TMP}/home"
mkdir -p "${HOME}"
DIR="${ROOT}"
export DIR
DRY_RUN=0
PROFILE_NAME=home

# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/links.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/state.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/backup.sh"

echo "=== collision backup succeeds before mutate ==="
echo 'legacy' >"${HOME}/.bashrc"
if dots_backup_snapshot_collisions "pre-setup" "pre-setup" >/tmp/gate-ok.$$ 2>&1; then
	ok "snapshot ok"
else
	bad "snapshot should succeed"
	cat /tmp/gate-ok.$$
fi
[[ -n ${DOTS_LAST_BACKUP_ID:-} ]] && ok "DOTS_LAST_BACKUP_ID set" || bad "no backup id"
[[ -f "$(dots_backup_root)/${DOTS_LAST_BACKUP_ID}/files/.bashrc" ]] && ok "bashrc captured" || bad "payload"

echo "=== forced backup failure aborts (return 1) ==="
# Shadow dots_backup_create to simulate failure while collisions exist
dots_backup_create() {
	echo "simulated backup failure" >&2
	return 1
}
unset DOTS_LAST_BACKUP_ID
echo 'another' >"${HOME}/.zshrc"
# Re-source collision helper body is already loaded; override create only
if dots_backup_snapshot_collisions "pre-setup" "pre-setup" >/tmp/gate-fail.$$ 2>&1; then
	bad "should fail when create fails"
else
	ok "backup failure returns nonzero"
fi
grep -qi 'refusing to mutate\|backup failed' /tmp/gate-fail.$$ && ok "failure message" || bad "message: $(cat /tmp/gate-fail.$$)"

echo "=== setup dry-run still reaches backup before symlinks ==="
# Use real helpers in a throwaway HOME; dry-run must not mutate
export HOME="${TMP}/home2"
mkdir -p "${HOME}"
echo 'x' >"${HOME}/.bashrc"
out="$("${ROOT}/setup.sh" --dry-run --profile base 2>&1)" || true
# Ordering: Backup section before Symlinks / Managed links
bak_line="$(echo "${out}" | grep -n 'Backup (before\|=== Backup' | head -1 | cut -d: -f1)"
sym_line="$(echo "${out}" | grep -n '=== Symlinks\|Managed links' | head -1 | cut -d: -f1)"
if [[ -n ${bak_line} && -n ${sym_line} && ${bak_line} -lt ${sym_line} ]]; then
	ok "backup before symlinks (${bak_line}<${sym_line})"
else
	bad "ordering bak=${bak_line} sym=${sym_line}"
fi
echo "${out}" | grep -qi 'would snapshot\|none needed\|Backup' && ok "backup stage invoked" || bad "no backup in dry-run"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
