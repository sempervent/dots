#!/usr/bin/env bash
# scripts/tests/python_runtime_test.sh — Python ≥3.11 / tomllib contract
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

echo "=== Python ≥3.11 / tomllib contract ==="

# --show works when a ≥3.11 interpreter is discoverable (this host / CI)
for p in base home work server; do
	if /bin/bash "$ROOT/bootstrap.sh" --profile "$p" --show >/tmp/py-show-"$p".out 2>&1; then
		ok "--show $p"
	else
		bad "--show $p failed"
		tail -15 /tmp/py-show-"$p".out >&2
	fi
	# Must not actually install during --show
	if rg -q 'brew install python|apt-get install.*python|pacman -S.*python' /tmp/py-show-"$p".out; then
		bad "--show $p must not run package installs"
	else
		ok "--show $p non-mutating for Python"
	fi
done

# Soft require: missing ≥3.11 → report Would provision, do not install
TMP="$(mktemp -d)"
export HOME="$TMP"
FAKEPY="$(mktemp -d)"
cat >"${FAKEPY}/python3" <<'EOF'
#!/bin/sh
# Pretend to be Python 3.9 without tomllib
case "$*" in
  *import\ tomllib*) exit 1 ;;
  *version_info*) echo "3.9.18"; exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${FAKEPY}/python3"
# Hide real interpreters from find; force soft path through fake python3
dots_find_python311() { return 1; }
_saved_path="${PATH}"
PATH="${FAKEPY}:/usr/bin:/bin"
SHOW_ONLY=1
out="$(dots_require_python 1 2>&1)" && soft_rc=0 || soft_rc=$?
PATH="${_saved_path}"
unset SHOW_ONLY
if [[ ${soft_rc} -ne 0 ]] && echo "${out}" | rg -q 'Python >=3.11 required'; then
	ok "soft require reports Python >=3.11 required"
else
	bad "soft require unexpected: rc=${soft_rc} out=${out}"
fi
if echo "${out}" | rg -q 'Would provision Python'; then
	ok "soft require announces Would provision"
else
	bad "soft require missing Would provision: ${out}"
fi
if echo "${out}" | rg -q 'Found: Python 3.9'; then
	ok "soft require reports found version"
else
	ok "soft require version line optional"
fi
rm -rf "${FAKEPY}"

# No HOME mutation from soft require
nfiles=$(find "$TMP" -type f 2>/dev/null | wc -l | tr -d ' ')
[[ "$nfiles" == "0" ]] && ok "soft require no HOME files" || bad "soft require wrote $nfiles files"

DRY_RUN=1

# Mock: hide 3.11+ binaries from find by overriding dots_find_python311
dots_find_python311() { return 1; }

reason_out="$(dots_ensure_python311_for "skills, ai-skills" 2>&1)" || true
if echo "$reason_out" | rg -q 'Would provision Python >=3.11 for: skills, ai-skills'; then
	ok "dry-run ensure announces provisioning"
else
	bad "dry-run ensure missing announce: $reason_out"
fi

# Full home dry-run
before=$(find "$TMP" | cksum)
/bin/bash "$ROOT/bootstrap.sh" --profile home --dry-run >/tmp/py-home-dry.out 2>&1 || true
after=$(find "$TMP" | cksum)
[[ "$before" == "$after" ]] && ok "home dry-run non-mutating" || bad "home dry-run mutated HOME"

# work/server dry-run must not provision for skills (no skills selected)
/bin/bash "$ROOT/bootstrap.sh" --profile work --dry-run >/tmp/py-work-dry.out 2>&1 || true
/bin/bash "$ROOT/bootstrap.sh" --profile server --dry-run >/tmp/py-server-dry.out 2>&1 || true
# Soft bootstrap python message is OK; mutating brew install is not
rg -q 'brew install python@' /tmp/py-work-dry.out && bad "work ran brew install python" || ok "work dry-run no brew python install"
rg -q 'brew install python@' /tmp/py-server-dry.out && bad "server ran brew install python" || ok "server dry-run no brew python install"

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
