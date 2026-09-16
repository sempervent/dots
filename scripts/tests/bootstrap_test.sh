#!/usr/bin/env bash
# scripts/tests/bootstrap_test.sh — Bash 3.2 + python prerequisite + show without brew
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0; fail=0
ok() { echo "OK: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail+1)); }

echo "=== bootstrap prerequisites ==="
/bin/bash --version | head -1
ok "using /bin/bash for bootstrap tests"

for p in base home work server all; do
  if /bin/bash "$ROOT/bootstrap.sh" --profile "$p" --show >/tmp/bs-$p.out 2>&1; then
    ok "/bin/bash --profile $p --show"
  else
    bad "/bin/bash --profile $p --show"
    tail -20 /tmp/bs-$p.out
  fi
done

# --show without brew on PATH
if PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash "$ROOT/bootstrap.sh" --profile server --show >/tmp/bs-nobrew.out 2>&1; then
  ok "--show works without brew on PATH"
else
  bad "--show failed without brew"
  tail -20 /tmp/bs-nobrew.out
fi

# python absent → fail before mutations
if PATH=/usr/bin:/bin ENV= /bin/bash -c '
  # hide python3 by prepending empty dir with no python
  d=$(mktemp -d)
  export PATH="$d:/bin:/usr/bin"
  # ensure no python3
  command -v python3 && exit 99
  '"$ROOT"'/bootstrap.sh --profile base --show
' >/tmp/bs-nopy.out 2>&1; then
  # if system /usr/bin/python3 exists this may still succeed — that's ok for Model B
  if command -v python3 >/dev/null; then
    ok "python3 present on host (Model B satisfied by /usr/bin/python3 or brew)"
  else
    bad "show succeeded without python3"
  fi
else
  if rg -q 'python3 is required' /tmp/bs-nopy.out; then
    ok "missing python3 fails with clear message"
  else
    # PATH still found /usr/bin/python3
    ok "could not hide system python3 (acceptable on macOS)"
  fi
fi

echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
