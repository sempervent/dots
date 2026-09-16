#!/usr/bin/env bash
# scripts/tests/python_runtime_test.sh — layered Python contract for skills
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$ROOT"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

# shellcheck source=../../helpers/toml.sh
source "$ROOT/helpers/toml.sh"
# shellcheck source=../../helpers/python_runtime.sh
source "$ROOT/helpers/python_runtime.sh"
# shellcheck source=../../helpers/packages.sh
source "$ROOT/helpers/packages.sh"

echo "=== layered Python contract ==="

# --show must work with bootstrap python (≥3.6), no 3.11 requirement
for p in base home work server; do
  if /bin/bash "$ROOT/bootstrap.sh" --profile "$p" --show >/tmp/py-show-"$p".out 2>&1; then
    ok "--show $p"
  else
    bad "--show $p failed"
    tail -15 /tmp/py-show-"$p".out >&2
  fi
  if rg -q 'Would provision Python|python@3\.|Install python3\.11' /tmp/py-show-"$p".out; then
    bad "--show $p must not provision/require Python 3.11"
  else
    ok "--show $p no 3.11 provisioning"
  fi
done

TMP="$(mktemp -d)"
export HOME="$TMP"
DRY_RUN=1

# Mock: hide 3.11+ binaries from find by overriding dots_find_python311
dots_find_python311() { return 1; }

reason_out="$(dots_ensure_python311_for "skills, ai-skills" 2>&1)" || true
if echo "$reason_out" | rg -q 'Would provision Python >=3.11 for: skills, ai-skills'; then
  ok "dry-run ensure announces provisioning"
else
  bad "dry-run ensure missing announce: $reason_out"
fi

# No HOME mutation from ensure dry-run
nfiles=$(find "$TMP" -type f 2>/dev/null | wc -l | tr -d ' ')
[[ "$nfiles" == "0" ]] && ok "ensure dry-run no HOME files" || bad "ensure dry-run wrote $nfiles files"

# Full home dry-run
before=$(find "$TMP" | cksum)
/bin/bash "$ROOT/bootstrap.sh" --profile home --dry-run >/tmp/py-home-dry.out 2>&1 || true
after=$(find "$TMP" | cksum)
[[ "$before" == "$after" ]] && ok "home dry-run non-mutating" || bad "home dry-run mutated HOME"
if rg -q 'Would provision Python >=3.11 for:' /tmp/py-home-dry.out; then
  ok "home dry-run reports Python >=3.11 provisioning"
else
  # Host may already have 3.11+ — then expect "using Python ≥3.11"
  if rg -q 'using Python ≥3.11 for|OK: using Python' /tmp/py-home-dry.out; then
    ok "home dry-run uses existing Python ≥3.11"
  else
    bad "home dry-run missing python 3.11 messaging"
    rg -n 'Python|skill' /tmp/py-home-dry.out | head -20 >&2
  fi
fi

# work/server must not mention provisioning
/bin/bash "$ROOT/bootstrap.sh" --profile work --dry-run >/tmp/py-work-dry.out 2>&1 || true
/bin/bash "$ROOT/bootstrap.sh" --profile server --dry-run >/tmp/py-server-dry.out 2>&1 || true
rg -q 'Would provision Python >=3.11' /tmp/py-work-dry.out && bad "work provisioned python" || ok "work no python 3.11 provision"
rg -q 'Would provision Python >=3.11' /tmp/py-server-dry.out && bad "server provisioned python" || ok "server no python 3.11 provision"

# Mocked real provision path: fake brew install that drops a tomllib python
unset -f dots_find_python311
FAKE="$(mktemp -d)"
cat >"$FAKE/python3.12" <<'EOF'
#!/bin/sh
# Minimal stub: claim tomllib for -c 'import tomllib'; otherwise succeed.
case "$*" in
  *import\ tomllib*) exit 0 ;;
  *-V*|*--version*) echo "Python 3.12.0"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$FAKE/python3.12"

_fake_installed=0
_prov_calls=0
dots_find_python311() {
  if [[ ${_fake_installed} -eq 1 ]] && dots_python_bin_has_tomllib "$FAKE/python3.12"; then
    printf '%s\n' "$FAKE/python3.12"
    return 0
  fi
  return 1
}
dots_provision_python311() {
  _prov_calls=$((_prov_calls + 1))
  _fake_installed=1
  echo "mock-provision python@3.12 for $*"
  return 0
}

DRY_RUN=0
DOTS_SKILLS_PYTHON=""
if dots_ensure_python311_for "skills"; then
  [[ "$DOTS_SKILLS_PYTHON" == "$FAKE/python3.12" ]] && ok "mocked install selects provisioned interpreter" || bad "got DOTS_SKILLS_PYTHON=$DOTS_SKILLS_PYTHON"
  [[ $_prov_calls -eq 1 ]] && ok "provision called once" || bad "prov_calls=$_prov_calls"
else
  bad "mocked ensure failed"
fi

# Idempotence: second ensure should not provision again
_prov_calls=0
DOTS_SKILLS_PYTHON=""
if dots_ensure_python311_for "skills"; then
  [[ $_prov_calls -eq 0 ]] && ok "second ensure skips provision" || bad "re-provisioned (calls=$_prov_calls)"
  [[ "$DOTS_SKILLS_PYTHON" == "$FAKE/python3.12" ]] && ok "second ensure reuses interpreter" || bad "lost interpreter"
else
  bad "second ensure failed"
fi

rm -rf "$TMP" "$FAKE"
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
