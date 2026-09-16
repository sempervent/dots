#!/usr/bin/env python3
"""toml_min vs tomllib parity for bootstrap-critical DOTS TOML only.

Files that require full TOML (inline tables, dotted keys as nested tables,
quoted keys) are intentionally outside toml_min's subset and are listed as
UNSUPPORTED — bootstrap must not route them through toml_min.
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

try:
    import tomllib
except ImportError:
    print("SKIP: tomllib unavailable")
    raise SystemExit(0)

spec = importlib.util.spec_from_file_location("toml_min", ROOT / "tools" / "toml_min.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# Bootstrap / setup parse these with dots_toml_query (tomllib || toml_min)
CRITICAL = [
    "configs/components.toml",
    "configs/links.toml",
    "configs/packages/groups.toml",
    "configs/packages/apt.toml",
    "configs/packages/pacman.toml",
    "configs/packages/xbps.toml",
    "configs/packages/dnf.toml",
    "configs/node/default.toml",
    "configs/bootstrap/profiles/base.toml",
    "configs/bootstrap/profiles/home.toml",
    "configs/bootstrap/profiles/work.toml",
    "configs/bootstrap/profiles/server.toml",
    "configs/bootstrap/profiles/all.toml",
    "configs/agents/telemetry.toml",
    "configs/agents/router.toml",
    "configs/agents/execution.toml",
    "configs/notify/config.toml",
    "configs/drawthings/config.toml",
]

# Must NOT be silently misparsed by toml_min if ever fed to it
UNSUPPORTED = [
    "configs/skills/manifest.toml",  # dotted [packs.skills]
    "configs/herdr/config.toml",  # inline tables
    "configs/starship/starship.toml",  # quoted keys
]

fail = 0
okn = 0

for rel in CRITICAL:
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    a = tomllib.loads(text)
    try:
        b = mod.loads(text)
    except Exception as exc:
        print(f"FAIL toml_min rejected critical {rel}: {exc}")
        fail += 1
        continue
    if a != b:
        print(f"FAIL parity {rel}")
        fail += 1
    else:
        print(f"OK {rel}")
        okn += 1

for rel in UNSUPPORTED:
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    try:
        mod.loads(text)
        # If it "succeeds" but differs from tomllib, that's a silent misparse — fail
        try:
            a = tomllib.loads(text)
            b = mod.loads(text)
            if a != b:
                print(f"FAIL silent misparse of unsupported {rel}")
                fail += 1
            else:
                print(f"OK unsupported {rel} happens to match (acceptable)")
                okn += 1
        except Exception:
            print(f"OK unsupported {rel} rejected or unmatched")
            okn += 1
    except Exception:
        print(f"OK unsupported {rel} rejected by toml_min")
        okn += 1

# Explicit reject of inline tables
try:
    mod.loads('key = { inline = "table" }\n')
    print("FAIL: inline table should be rejected")
    fail += 1
except Exception:
    print("OK inline table rejected")
    okn += 1

print(f"Passed: {okn}  Failed: {fail}")
raise SystemExit(0 if fail == 0 else 1)
