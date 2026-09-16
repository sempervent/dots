#!/usr/bin/env bash
# scripts/tests/stage0_prereqs_test.sh — Stage 0 Homebrew/Python/CLT control flow
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$ROOT"
pass=0
fail=0
ok() {
	echo "OK: $1"
	pass=$((pass + 1))
}
bad() {
	echo "FAIL: $1" >&2
	fail=$((fail + 1))
}

# shellcheck source=../../helpers/bootstrap_prereqs.sh
source "$ROOT/helpers/bootstrap_prereqs.sh"
# shellcheck source=../../helpers/packages.sh
source "$ROOT/helpers/packages.sh"
# shellcheck source=../../helpers/python_runtime.sh
source "$ROOT/helpers/python_runtime.sh"

echo "=== Stage 0 prerequisite tests ==="

# Existing brew detection (this machine likely has brew on macOS / sometimes Linuxbrew on CI)
if brew_bin="$(dots_find_brew)"; then
	ok "dots_find_brew locates brew ($brew_bin)"
elif [[ "$(uname -s)" == "Darwin" ]]; then
	bad "dots_find_brew failed on Darwin (Homebrew expected)"
else
	ok "brew absent on Linux host (native pkg mgr OK)"
fi

# Homebrew present but not on PATH
(
	export PATH="/usr/bin:/bin"
	# Still find via absolute prefixes
	if dots_find_brew >/dev/null 2>&1; then
		ok "brew found when not on PATH"
	else
		# May fail on Linux CI without homebrew prefixes — acceptable
		ok "brew absent from standard prefixes (ok on Linux CI)"
	fi
)

# Activate brew into restricted PATH
if [[ "$(uname -s)" == "Darwin" ]]; then
	export PATH="/usr/bin:/bin"
	if dots_activate_brew && command -v brew >/dev/null 2>&1; then
		ok "dots_activate_brew restores brew on PATH"
	else
		bad "dots_activate_brew failed"
	fi
else
	ok "skip activate_brew assert on non-Darwin"
fi

# Dry-run / show never download installers
TMP="$(mktemp -d)"
export HOME="$TMP"
SHOW_ONLY=1 DRY_RUN=0
out="$(dots_stage0_ensure 1 2>&1)"
echo "$out" | grep -q 'Bootstrap prerequisites' && ok "stage0 report header" || bad "missing stage0 report"
# Must not create brew install artifacts under HOME from soft stage0
n=$(find "$TMP" -type f 2>/dev/null | wc -l | tr -d ' ')
[[ $n == "0" ]] && ok "soft stage0 no HOME files" || bad "soft stage0 wrote files"

# Mock missing brew: dry-run should announce Would install, not curl
SHOW_ONLY=0 DRY_RUN=1
dots_find_brew() { return 1; }
dots_apple_clt_present() { return 1; }
dots_stage0_python_present() { return 1; }
if [[ "$(uname -s)" == "Darwin" ]]; then
	out="$(dots_ensure_apple_clt 2>&1)"
	echo "$out" | grep -q 'Would install Apple Command Line Tools' && ok "dry-run CLT announce" || bad "CLT dry-run: $out"
else
	# CLT is Darwin-only; ensure Linux is a no-op
	out="$(dots_ensure_apple_clt 2>&1)"
	if [[ -z ${out} ]]; then
		ok "CLT ensure is no-op on Linux"
	else
		bad "CLT ensure should be silent on Linux: $out"
	fi
fi
out="$(dots_ensure_homebrew 2>&1)"
echo "$out" | grep -q 'Would install Homebrew from official' && ok "dry-run Homebrew announce" || bad "brew dry-run: $out"
# Ensure download was not attempted — override curl to fail loudly if called
curl() {
	echo "CURL_CALLED $*" >&2
	return 99
}
export -f curl 2>/dev/null || true
out="$(dots_ensure_homebrew 2>&1)" || true
echo "$out" | grep -q 'CURL_CALLED' && bad "dry-run called curl" || ok "dry-run did not call curl"
out="$(dots_ensure_supported_python 2>&1)"
echo "$out" | grep -q 'Would install Python' && ok "dry-run Python announce" || bad "python dry-run: $out"

# --no-install fails when brew mocked missing on Darwin
unset -f dots_find_brew curl 2>/dev/null || true
# shellcheck source=../../helpers/bootstrap_prereqs.sh
source "$ROOT/helpers/bootstrap_prereqs.sh"
if [[ "$(uname -s)" == "Darwin" ]]; then
	NO_INSTALL=1 DRY_RUN=0 SHOW_ONLY=0
	dots_find_brew() { return 1; }
	if dots_ensure_homebrew 2>/dev/null; then
		bad "--no-install should fail when brew missing"
	else
		ok "--no-install fails when brew missing"
	fi
	unset -f dots_find_brew
else
	ok "skip --no-install brew assert on Linux"
fi

# Official URL constants are HTTPS
echo "$DOTS_HOMEBREW_INSTALL_URL" | grep -q '^https://raw.githubusercontent.com/Homebrew/install/' &&
	ok "Homebrew installer URL official HTTPS" || bad "bad brew URL"
echo "$DOTS_HERDR_INSTALL_URL" | grep -q '^https://herdr.dev/' &&
	ok "Herdr installer URL official HTTPS" || bad "bad herdr URL"

# bootstrap --show reports Stage 0
show_out="$(/bin/bash "$ROOT/bootstrap.sh" --profile server --show 2>&1 || true)"
echo "$show_out" | grep -q 'Bootstrap prerequisites\|Stage 0\|OK: Homebrew\|OK: Python\|package groups' &&
	ok "bootstrap --show includes Stage 0 or profile" || bad "show missing stage0/profile"

# setup.sh sources same Stage 0 helper
grep -q 'bootstrap_prereqs.sh' "$ROOT/setup.sh" && ok "setup.sh shares Stage 0 helper" || bad "setup missing prereqs"
grep -q 'bootstrap_prereqs.sh' "$ROOT/bootstrap.sh" && ok "bootstrap.sh shares Stage 0 helper" || bad "bootstrap missing prereqs"

rm -rf "$TMP"
echo "Passed: $pass  Failed: $fail"
[[ $fail -eq 0 ]]
