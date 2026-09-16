#!/usr/bin/env bash
# scripts/tests/link_manifest_test.sh — adversarial link deploy/check
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$ROOT"
pass=0; fail=0
ok() { echo "OK: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail+1)); }

# shellcheck source=../../helpers/toml.sh
source "$ROOT/helpers/toml.sh"
# shellcheck source=../../helpers/links.sh
source "$ROOT/helpers/links.sh"

TMP="$(mktemp -d)"
export HOME="$TMP"
DRY_RUN=0
PROFILE_NAME=base
ensure_dir() { mkdir -p "$1"; }
OLD_DOTS="$TMP/.old_dots"
backup_stamp() { date +%Y%m%d%H%M%S; }
move_sym() {
  local name="$1" dest="$2" source="${3:-}"
  mkdir -p "$(dirname "$dest")"
  if [[ -L "$dest" ]] && [[ "$(readlink "$dest")" == "$source" ]]; then
    echo "OK: $name (present)"; return 0
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    mkdir -p "$OLD_DOTS"
    mv "$dest" "$OLD_DOTS/${name}_$(backup_stamp)"
  fi
  ln -sfn "$source" "$dest"
  echo "Linked: $source → $dest"
}

echo "=== link manifest adversarial ==="

# dry-run no mutation — ensure_dir must respect DRY_RUN
ensure_dir() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[dry-run] mkdir -p $1"
  else
    mkdir -p "$1"
  fi
}
DRY_RUN=1
before=$(find "$TMP" | cksum)
dots_deploy_links >/dev/null
after=$(find "$TMP" | cksum)
[[ "$before" == "$after" ]] && ok "dry-run deploy no mutation" || bad "dry-run deploy mutated"

DRY_RUN=0
dots_deploy_links >/dev/null
[[ -L "$HOME/.bashrc" ]] && ok "bashrc linked" || bad "bashrc missing"
# second run no churn
mkdir -p "$OLD_DOTS"
count1=$(find "$OLD_DOTS" -type f 2>/dev/null | wc -l | tr -d ' ')
dots_deploy_links >/dev/null
count2=$(find "$OLD_DOTS" -type f 2>/dev/null | wc -l | tr -d ' ')
[[ "$count1" == "$count2" ]] && ok "second run no backup churn" || bad "second run created backups ($count1→$count2)"

# wrong symlink repaired
ln -sfn /nonexistent "$HOME/.bashrc"
dots_deploy_links >/dev/null
[[ "$(readlink "$HOME/.bashrc")" == "$ROOT/syms/bashrc" ]] && ok "wrong link repaired" || bad "wrong link not repaired"

# regular file backed up
rm -f "$HOME/.bashrc"
echo 'mine' >"$HOME/.bashrc"
dots_deploy_links >/dev/null
[[ -L "$HOME/.bashrc" ]] && ok "file replaced with link" || bad "file not linked"
if find "$OLD_DOTS" -name '.bashrc_*' -o -name '*bashrc*' 2>/dev/null | grep -q .; then
  ok "old file backed up"
else
  bad "no backup of regular file"
fi

# broken link
rm -f "$HOME/.zshrc"
ln -s /no/such/source "$HOME/.zshrc"
dots_deploy_links >/dev/null
[[ -L "$HOME/.zshrc" && -e "$HOME/.zshrc" ]] && ok "broken link repaired" || bad "broken link remains"

rm -rf "$TMP"
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
