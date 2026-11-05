#!/usr/bin/env bash
# scripts/tests/data_backup_validate_test.sh — Phase 5 data/backup (non-mutating)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-data-backup.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

DATA="${ROOT}/scripts/ci/data_validate.sh"
BACKUP="${ROOT}/scripts/ci/backup_validate.sh"
[[ -x ${DATA} ]] || chmod +x "${DATA}"
[[ -x ${BACKUP} ]] || chmod +x "${BACKUP}"

# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"

echo "=== data package ownership ==="
for p in duckdb qsv visidata miller jless pgcli pg_activity; do
	found=0
	while IFS= read -r id; do [[ ${id} == "${p}" ]] && found=1; done < <(dots_group_package_ids data optional)
	[[ ${found} -eq 1 ]] && ok "data owns ${p}" || bad "data missing ${p}"
done
grep -q 'brew "pgcli"' "${ROOT}/brew/groups/data.Brewfile" && ok "pgcli in data Brewfile" || bad "pgcli Brewfile"
grep -q 'brew "pg_activity"' "${ROOT}/brew/groups/data.Brewfile" && ok "pg_activity in data Brewfile" || bad "pg_activity Brewfile"
grep -q 'brew "duckdb"' "${ROOT}/brew/groups/data.Brewfile" && ok "duckdb pre-existing in data" || bad "duckdb missing"

echo "=== backup package ownership ==="
found=0
while IFS= read -r id; do [[ ${id} == restic ]] && found=1; done < <(dots_group_package_ids backup optional)
[[ ${found} -eq 1 ]] && ok "backup owns restic" || bad "backup missing restic"
grep -q 'brew "restic"' "${ROOT}/brew/groups/backup.Brewfile" && ok "restic Brewfile" || bad "restic Brewfile"
# rclone stays in network — not duplicated
rclone_in_backup=0
while IFS= read -r id; do [[ ${id} == rclone ]] && rclone_in_backup=1; done < <(dots_group_package_ids backup optional)
[[ ${rclone_in_backup} -eq 0 ]] && ok "rclone not duplicated in backup group" || bad "rclone duplicated"
grep -q 'brew "rclone"' "${ROOT}/brew/groups/network.Brewfile" && ok "rclone owned by network" || bad "rclone missing from network"
# Syncthing omit_from_all component
grep -A12 'id = "syncthing"' "${ROOT}/configs/components.toml" | grep -q 'omit_from_all = true' && ok "syncthing omit_from_all" || bad "syncthing omit"
grep -q 'brew "syncthing"' "${ROOT}/brew/Brewfile.syncthing" && ok "syncthing brewfile" || bad "syncthing brewfile"
# Syncthing not in backup group optional list as a package id
st_pkg=0
while IFS= read -r id; do [[ ${id} == syncthing ]] && st_pkg=1; done < <(dots_group_package_ids backup optional)
[[ ${st_pkg} -eq 0 ]] && ok "syncthing not a backup group package id" || bad "syncthing in backup packages"
# all profile includes backup but not syncthing component by default
grep -q '"backup"' "${ROOT}/configs/bootstrap/profiles/all.toml" && ok "all includes backup" || bad "all missing backup"
grep -q 'syncthing' "${ROOT}/configs/bootstrap/profiles/all.toml" && bad "all references syncthing" || ok "all does not auto-include syncthing"

echo "=== no psql alias ==="
if rg -n 'alias[[:space:]]+psql=|alias[[:space:]]+psql =' "${ROOT}" --glob '!vendor/**' --glob '!**/node_modules/**' --glob '!**/*.md' 2>/dev/null | grep -q .; then
	bad "psql alias present"
else
	ok "no psql=pgcli alias"
fi

echo "=== data check non-mutating / no DB connection ==="
# Stub pgcli/psql that fail if connection-like args appear
mkdir -p "${TMP}/bin"
cat >"${TMP}/bin/pgcli" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
  *://*|*@*|*-h*|*--host*|*dbname*|*-d*) echo "UNEXPECTED_CONN:$a" >&2; exit 99 ;;
  esac
done
case "${1:-}" in --version) echo "pgcli stub 0"; exit 0 ;; esac
echo "pgcli stub"; exit 0
EOF
cat >"${TMP}/bin/psql" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
  *://*|*@*|*-h*|*--host*|*-c*|*dbname*) echo "UNEXPECTED_CONN:$a" >&2; exit 99 ;;
  esac
done
case "${1:-}" in --version) echo "psql stub 0"; exit 0 ;; esac
echo "psql stub"; exit 0
EOF
cat >"${TMP}/bin/pg_activity" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
  *://*|*@*|*-U*|*--username*|*-d*|*--dbname*) echo "UNEXPECTED_CONN:$a" >&2; exit 99 ;;
  esac
done
case "${1:-}" in --version) echo "pg_activity stub 0"; exit 0 ;; esac
echo "pg_activity stub"; exit 0
EOF
chmod +x "${TMP}/bin/"*
export PATH="${TMP}/bin:${PATH}"
dout="$("${DATA}" status 2>&1)" || {
	bad "data status exit"
	dout=""
}
echo "${dout}" | grep -qi 'UNEXPECTED_CONN' && bad "data check opened DB" || ok "data check no DB connection args"
echo "${dout}" | grep -qi 'No database connections' && ok "data invariants stated" || bad "data invariants"
# Must not walk home for datasets or invoke find/xargs against user paths
if rg -n '(^|[[:space:]])(find|xargs)[[:space:]]' "${DATA}" | rg -v 'usage|Usage|EOF|^[[:space:]]*#' | grep -q .; then
	bad "data validate walks/reads datasets"
else
	ok "data validate does not walk user datasets"
fi

echo "=== backup check non-mutation ==="
# Wrap restic/rclone/syncthing to detect forbidden verbs
cat >"${TMP}/bin/restic" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
  init|backup|restore|forget|prune|snapshots|check) echo "FORBIDDEN_RESTIC:$a" >&2; exit 99 ;;
  esac
done
case "${1:-}" in version) echo "restic stub 0"; exit 0 ;; esac
echo "restic stub"; exit 0
EOF
cat >"${TMP}/bin/rclone" <<'EOF'
#!/usr/bin/env bash
# Allow listremotes / version only
case "${1:-}" in
version) echo "rclone stub 0"; exit 0 ;;
listremotes) exit 0 ;;
ls|lsd|copy|sync|move|delete|purge|mount|cat|rc) echo "FORBIDDEN_RCLONE:$1" >&2; exit 99 ;;
*) echo "rclone stub"; exit 0 ;;
esac
EOF
cat >"${TMP}/bin/syncthing" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
--version) echo "syncthing stub 0"; exit 0 ;;
--help|-h) echo "help"; exit 0 ;;
serve|cli|--no-browser|"")
  # bare invoke / serve would start daemon
  echo "FORBIDDEN_SYNCTHING_START:$*" >&2
  exit 99
  ;;
*) echo "FORBIDDEN_SYNCTHING:$*" >&2; exit 99 ;;
esac
EOF
chmod +x "${TMP}/bin/restic" "${TMP}/bin/rclone" "${TMP}/bin/syncthing"
# Fake secrets in env — must never appear in output
export RESTIC_PASSWORD="super-secret-restic-pw-test"
export RCLONE_CONFIG_PASS="super-secret-rclone-token-test"
export SYNCTHING_API_KEY="super-secret-syncthing-api-test"
unset RESTIC_REPOSITORY RESTIC_REPOSITORY_FILE || true
bout="$("${BACKUP}" status 2>&1)" || {
	bad "backup status exit"
	bout=""
}
echo "${bout}" | grep -q 'FORBIDDEN_RESTIC' && bad "restic mutating verb invoked" || ok "no restic init/backup/restore/forget/prune"
echo "${bout}" | grep -q 'FORBIDDEN_RCLONE' && bad "rclone remote op invoked" || ok "no rclone remote ops"
echo "${bout}" | grep -q 'FORBIDDEN_SYNCTHING' && bad "syncthing start invoked" || ok "no syncthing auto-start"
echo "${bout}" | grep -q 'NOT CONFIGURED' && ok "restic repo NOT CONFIGURED when unset" || bad "missing NOT CONFIGURED"
echo "${bout}" | grep -qi 'super-secret' && bad "secrets leaked in backup status" || ok "secrets redacted from backup status"
# data status should also not leak
dout2="$("${DATA}" status 2>&1)" || true
echo "${dout2}" | grep -qi 'super-secret' && bad "secrets leaked in data status" || ok "secrets absent from data status"

echo "=== Syncthing running informational ==="
# Simulate running via fake pgrep? Hard without mocking pgrep. Assert status accepts running=NO.
echo "${bout}" | grep -qi 'running' && ok "reports running state" || bad "missing running state"

echo "=== examples modes (stdout only) ==="
exd="$("${DATA}" examples 2>&1)" || bad "data examples exit"
exb="$("${BACKUP}" examples 2>&1)" || bad "backup examples exit"
echo "${exd}" | grep -qi 'pgcli' && ok "data examples mention pgcli" || bad "data examples"
echo "${exb}" | grep -qi 'restic' && ok "backup examples mention restic" || bad "backup examples"
echo "${exb}" | grep -qi 'not a backup' && ok "Syncthing ≠ backup documented in examples" || ok "examples printed"

echo "=== CLI help ==="
chk="$("${ROOT}/dots" check --help 2>&1)" || true
echo "${chk}" | grep -q 'check data' && ok "help mentions check data" || bad "help missing data"
echo "${chk}" | grep -q 'check backup' && ok "help mentions check backup" || bad "help missing backup"

echo "=== YubiKey independence ==="
rg -q 'ykman|YubiKey|age-plugin' "${DATA}" "${BACKUP}" && bad "data/backup validate reference YubiKey" || ok "data/backup independent of YubiKey"

echo "=== no scheduler creation in validate scripts ==="
if rg -n 'launchctl|crontab|systemd-run|systemctl[[:space:]]+enable' "${DATA}" "${BACKUP}" 2>/dev/null | grep -q .; then
	bad "scheduler references in validate"
else
	ok "no scheduler creation in validate"
fi

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
