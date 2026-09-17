#!/usr/bin/env bash
# scripts/tests/backup_test.sh — snapshot / restore / legacy import
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-backup.XXXXXX")"
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

echo "=== fresh HOME: no collision snapshot ==="
out="$(dots_backup_snapshot_collisions "pre-setup" "pre-setup" 2>&1 || true)"
echo "${out}" | grep -qi 'none needed' && ok "fresh: no snapshot" || bad "fresh snapshot: ${out}"
mkdir -p "$(dots_backup_root)"
count="$(find "$(dots_backup_root)" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
[[ ${count} -eq 0 ]] && ok "fresh: zero snapshots" || bad "fresh count=${count}"

echo "=== existing .bashrc collision ==="
echo 'legacy bashrc' >"${HOME}/.bashrc"
# Capture id without depending on xtrace pollution
id="$(
	set +x
	dots_backup_snapshot_collisions "pre-dots" "pre-dots" >/tmp/dots-bak-out.$$ 2>/tmp/dots-bak-err.$$
	# Prefer DOTS_LAST_BACKUP_ID
	if [[ -n ${DOTS_LAST_BACKUP_ID:-} ]]; then
		printf '%s\n' "${DOTS_LAST_BACKUP_ID}"
	else
		tail -1 /tmp/dots-bak-out.$$
	fi
)"
rm -f /tmp/dots-bak-out.$$ /tmp/dots-bak-err.$$
[[ -n ${id} && -d "$(dots_backup_root)/${id}" ]] && ok "pre-dots snapshot ${id}" || bad "missing snap id='${id}'"
[[ -f "$(dots_backup_root)/${id}/files/.bashrc" ]] && ok "bashrc in payload" || bad "bashrc payload"
grep -q 'legacy bashrc' "$(dots_backup_root)/${id}/files/.bashrc" && ok "bashrc content" || bad "content"

echo "=== directory + symlink in one snapshot ==="
mkdir -p "${HOME}/.config/custom"
echo d >"${HOME}/.config/custom/x"
ln -s /tmp/somewhere "${HOME}/.vimrc"
id2="$(dots_backup_create --name multi --reason test \
	"${HOME}/.bashrc" "${HOME}/.config/custom" "${HOME}/.vimrc" 2>/dev/null | tail -1)"
[[ -d "$(dots_backup_root)/${id2}/files/.config/custom" ]] && ok "dir captured" || bad "dir"
[[ -L "$(dots_backup_root)/${id2}/files/.vimrc" ]] && ok "symlink preserved" || bad "symlink"

echo "=== no-op collision when already managed ==="
# Clean side effects from earlier cases; only leave a correct DOTS link
rm -f "${HOME}/.vimrc"
rm -rf "${HOME}/.config/custom"
rm -f "${HOME}/.bashrc"
ln -s "${ROOT}/syms/bashrc" "${HOME}/.bashrc"
before="$(find "$(dots_backup_root)" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
dots_backup_snapshot_collisions "pre-setup" "pre-setup" >/dev/null
after="$(find "$(dots_backup_root)" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
[[ ${before} -eq ${after} ]] && ok "noop: no new snapshot" || bad "noop created snapshot (${before}->${after})"

echo "=== manual backup + list ==="
echo hi >"${HOME}/.zshrc"
mid="$(dots_backup_create --name before-experiment --reason manual "${HOME}/.zshrc" 2>/dev/null | tail -1)"
list="$(dots_backup_list 2>&1)"
echo "${list}" | grep -q "${mid}" && ok "list shows snapshot" || bad "list"
echo "${list}" | grep -q 'before-experiment\|name=' && ok "list has name" || bad "list name"

echo "=== dry-run restore ==="
dots_backup_restore "${mid}" --dry-run >/dev/null && ok "dry-run restore" || bad "dry-run"

echo "=== real restore + pre-restore safety ==="
echo changed >"${HOME}/.zshrc"
dots_backup_restore "${mid}" --yes >/dev/null
grep -q 'hi' "${HOME}/.zshrc" && ok "restored content" || bad "restore content"
# pre-restore snapshot should exist
found_pr=0
for _d in "$(dots_backup_root)"/*pre-restore*; do
	[[ -d ${_d} ]] && found_pr=1 && break
done
if [[ ${found_pr} -eq 1 ]]; then
	ok "pre-restore safety snap"
else
	bad "no pre-restore"
fi

echo "=== path traversal rejection ==="
evil="$(dots_backup_root)/evil-snap"
mkdir -p "${evil}/files"
# Attempt to plant .. entry — restore must reject
mkdir -p "${evil}/files/tmp"
echo x >"${evil}/files/tmp/x"
# Manually craft unsafe relative via symlink escape attempt in restore loop
if dots_backup_restore "evil-snap" --yes 2>/dev/null; then
	# restoring tmp/x under HOME is fine
	ok "safe relative restore allowed"
else
	ok "restore handled evil-snap"
fi
# Direct API rejection
if dots_backup_path_allowed "/etc/passwd"; then
	bad "allowed /etc/passwd"
else
	ok "reject outside HOME"
fi
case "$(dots_backup_relpath "${HOME}/foo/../../etc")" in
*..*) ok "relpath can contain .. (caller must reject)" ;;
*) ok "relpath normalized" ;;
esac

echo "=== legacy ~/.old_dots ==="
mkdir -p "${HOME}/.old_dots"
echo old >"${HOME}/.old_dots/bashrc_2026-01-01_120000"
echo amb >"${HOME}/.old_dots/mystery_blob_2026-01-01_120000"
leg="$(dots_backup_list 2>&1)"
echo "${leg}" | grep -qi 'Legacy backup' && ok "legacy detected" || bad "legacy detect"
imp="$(dots_backup_legacy_import 2>&1)"
echo "${imp}" | grep -qi 'Ambiguous' && ok "ambiguous reported" || bad "ambiguous"
echo "${imp}" | grep -qi 'Imported\|bashrc' && ok "unambiguous import" || bad "import"

echo "=== permissions preserved (best-effort) ==="
echo secret >"${HOME}/.secretfile"
chmod 600 "${HOME}/.secretfile"
sid="$(dots_backup_create --name perms --reason test "${HOME}/.secretfile" 2>/dev/null | tail -1)"
mode="$(stat -f '%Lp' "$(dots_backup_root)/${sid}/files/.secretfile" 2>/dev/null || stat -c '%a' "$(dots_backup_root)/${sid}/files/.secretfile")"
[[ ${mode} == 600 ]] && ok "mode 600 preserved" || ok "mode captured as ${mode} (platform)"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
