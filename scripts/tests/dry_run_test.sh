#!/usr/bin/env bash
# scripts/tests/dry_run_test.sh — dry-run must not mutate HOME
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0; fail=0
ok() { echo "OK: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail+1)); }

snap() {
  # Ignore nothing — full tree checksum of paths+types (not brew host caches outside HOME)
  (cd "$1" && find . -print | LC_ALL=C sort | cksum)
}

echo "=== dry-run non-mutation ==="
TMP="$(mktemp -d)"
export HOME="$TMP"
# Isolate brew from writing into test HOME
export HOMEBREW_CACHE="/tmp/dots-brew-cache-unused-$$"
export HOMEBREW_NO_AUTO_UPDATE=1

before="$(snap "$TMP")"
/bin/bash "$ROOT/bootstrap.sh" --profile base --dry-run >/tmp/dots-dry-base.out 2>&1 || {
  bad "bootstrap base dry-run exited nonzero"
  cat /tmp/dots-dry-base.out | tail -30
}
after="$(snap "$TMP")"
if [[ "$before" == "$after" ]]; then
  ok "bootstrap --profile base --dry-run no HOME mutation"
else
  bad "bootstrap base dry-run mutated HOME"
  find "$TMP" -print | head -50
fi

before="$(snap "$TMP")"
/bin/bash "$ROOT/bootstrap.sh" --profile home --dry-run >/tmp/dots-dry-home.out 2>&1 || true
after="$(snap "$TMP")"
if [[ "$before" == "$after" ]]; then
  ok "bootstrap --profile home --dry-run no HOME mutation"
else
  bad "bootstrap home dry-run mutated HOME"
  find "$TMP" -print | head -50
fi

before="$(snap "$TMP")"
/bin/bash "$ROOT/bootstrap.sh" --profile server --dry-run >/tmp/dots-dry-server.out 2>&1 || true
after="$(snap "$TMP")"
if [[ "$before" == "$after" ]]; then
  ok "bootstrap --profile server --dry-run no HOME mutation"
else
  bad "bootstrap server dry-run mutated HOME"
fi

before="$(snap "$TMP")"
/bin/bash "$ROOT/setup.sh" --dry-run --profile base --packages core,modern >/tmp/dots-dry-setup.out 2>&1 || true
after="$(snap "$TMP")"
if [[ "$before" == "$after" ]]; then
  ok "setup.sh --dry-run no HOME mutation"
else
  bad "setup.sh --dry-run mutated HOME"
  find "$TMP" -print | head -40
fi

# Must not create dots config
if [[ -e "$TMP/.config/dots" ]]; then
  bad "dry-run created ~/.config/dots"
else
  ok "no ~/.config/dots after dry-run"
fi

rm -rf "$TMP"
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
