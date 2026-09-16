#!/usr/bin/env bash
# scripts/tests/provider_transition_test.sh — profile switch must not imply AI consent
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0; fail=0
ok() { echo "OK: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail+1)); }

echo "=== provider transition / consent ==="
# home dry-run must mention cursor brewfile when selected
out="$(/bin/bash "$ROOT/bootstrap.sh" --profile home --dry-run 2>&1 || true)"
echo "$out" | rg -q 'Brewfile.cursor|cursor' && ok "home dry-run includes cursor" || bad "home missing cursor"
echo "$out" | rg -q 'Brewfile.hermes|hermes' && ok "home dry-run includes hermes" || bad "home missing hermes"

# work dry-run must NOT configure cursor/hermes
out="$(/bin/bash "$ROOT/bootstrap.sh" --profile work --dry-run 2>&1 || true)"
if echo "$out" | rg -q 'Brewfile.cursor'; then
  bad "work dry-run still applies Brewfile.cursor"
else
  ok "work dry-run omits Brewfile.cursor"
fi
if echo "$out" | rg -q 'Brewfile.hermes'; then
  bad "work dry-run still applies Brewfile.hermes"
else
  ok "work dry-run omits Brewfile.hermes"
fi

# bare setup.sh dry-run omits AI
out="$(/bin/bash "$ROOT/setup.sh" --dry-run 2>&1 || true)"
if echo "$out" | rg -q 'Brewfile.cursor|Brewfile.hermes|Brewfile.codex'; then
  bad "bare setup.sh dry-run applies AI brewfiles"
else
  ok "bare setup.sh dry-run has no AI brewfiles"
fi

# active-profile must not be treated as consent: work --show still empty with
out="$(/bin/bash "$ROOT/bootstrap.sh" --profile work --show 2>&1)"
echo "$out" | rg -q 'components:' && ok "work --show has components section" || bad "work --show broken"
# ensure none listed
if echo "$out" | rg -A5 '^components:' | rg -q 'hermes|cursor|codex'; then
  bad "work --show lists AI components"
else
  ok "work --show has no AI components"
fi

echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
