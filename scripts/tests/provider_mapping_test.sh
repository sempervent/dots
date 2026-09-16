#!/usr/bin/env bash
# scripts/tests/provider_mapping_test.sh — every REQUIRED package has a provider
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

echo "=== required package provider mapping ==="

# shellcheck source=../../helpers/toml.sh
source "$ROOT/helpers/toml.sh"
dots_require_python 0 || {
	echo "SKIP: need Python >=3.11 for provider mapping parse"
	exit 0
}

export DOTS_ROOT="$ROOT"
result="$(
	"$DOTS_PYTHON" - <<'PY'
import os, tomllib
from pathlib import Path
root = Path(os.environ["DOTS_ROOT"])
groups = tomllib.loads((root / "configs/packages/groups.toml").read_text())
required = set()
for g in groups.get("groups") or []:
    for t in g.get("required") or []:
        required.add(str(t).strip())

maps = {}
for name in ("apt", "pacman", "xbps", "dnf"):
    p = root / f"configs/packages/{name}.toml"
    if p.is_file():
        maps[name] = tomllib.loads(p.read_text()).get("packages") or {}

brew_tools = set()
for bf in (root / "brew/groups").glob("*.Brewfile"):
    for line in bf.read_text().splitlines():
        line = line.strip()
        if line.startswith('brew "') or line.startswith('cask "'):
            brew_tools.add(line.split('"')[1])

aliases = {
    "ripgrep": ["ripgrep"],
    "fd": ["fd"],
    "neovim": ["neovim"],
    "font-jetbrains-mono-nerd-font": ["font-jetbrains-mono-nerd-font"],
}

core_linux = {
    "bash", "zsh", "tmux", "git", "curl", "wget", "jq", "ripgrep", "fd", "fzf",
    "neovim", "rsync", "bat", "zoxide", "direnv", "htop", "tree",
}

missing = []
for tool in sorted(required):
    has_linux = any(bool(m.get(tool)) for m in maps.values())
    has_brew = tool in brew_tools or any(a in brew_tools for a in aliases.get(tool, []))
    if tool.startswith("font-") or tool == "terminal-notifier":
        if not has_brew:
            missing.append(f"{tool}: no brew provider for macOS-oriented required tool")
        continue
    if tool in core_linux and not has_linux:
        missing.append(f"{tool}: REQUIRED core/modern tool lacks Linux native mapping")
        continue
    if not has_linux and not has_brew:
        missing.append(f"{tool}: no apt/pacman/xbps/dnf mapping and not in brew groups")

herdr_helper = (root / "helpers/bootstrap_prereqs.sh").read_text()
if "dots_ensure_herdr" not in herdr_helper or "herdr.dev/install" not in herdr_helper:
    missing.append("herdr: missing official install provider in bootstrap_prereqs.sh")
if not (root / "brew/Brewfile.herdr").is_file():
    missing.append("herdr: missing brew/Brewfile.herdr")

if missing:
    print("MISSING")
    for m in missing:
        print(m)
else:
    print("OK")
    print("required_count=%d" % len(required))
PY
)"

if echo "$result" | head -1 | grep -qx OK; then
	ok "all required packages have providers ($(echo "$result" | tail -1))"
else
	bad "REQUIRED_PACKAGE_WITHOUT_PROVIDER"
	echo "$result" >&2
fi

# Regression: bash special GROUPS must not be used for package group CSV
export DOTS_ROOT="$ROOT"
if "$DOTS_PYTHON" - <<'PY'
from pathlib import Path
import os, re
text = Path(os.environ["DOTS_ROOT"], "helpers/packages.sh").read_text()
for i, line in enumerate(text.splitlines(), 1):
    if re.search(r'(?<![A-Za-z0-9_])GROUPS=', line) or 'os.environ.get("GROUPS"' in line:
        raise SystemExit(f"{i}:{line}")
print("ok")
PY
then
	ok "package group env uses DOTS_PKG_GROUPS not GROUPS"
else
	bad "helpers/packages.sh must not use env GROUPS (bash special var)"
fi

if grep -q 'with = \["herdr"\]' "$ROOT/configs/bootstrap/profiles/server.toml"; then
	ok "server profile requires herdr"
else
	bad "server profile missing herdr"
fi

echo "Passed: $pass  Failed: $fail"
[[ $fail -eq 0 ]]
