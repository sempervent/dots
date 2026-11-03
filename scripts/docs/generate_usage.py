#!/usr/bin/env python3
"""Generate scripts/generated/dots_usage.inc from configs/help/commands.toml.

Usage:
  python3 scripts/docs/generate_usage.py
  python3 scripts/docs/generate_usage.py --check
"""

from __future__ import annotations

import argparse
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "scripts" / "generated" / "dots_usage.inc"
COMMANDS = ROOT / "configs" / "help" / "commands.toml"
VERSION_FILE = ROOT / "VERSION"


def version() -> str:
    return VERSION_FILE.read_text(encoding="utf-8").strip() if VERSION_FILE.is_file() else "0"


def generate() -> str:
    with COMMANDS.open("rb") as fh:
        data = tomllib.load(fh)
    cmds = list(data.get("commands") or [])
    ver = version()
    lines = [
        f"# GENERATED — DO NOT EDIT. Source: configs/help/commands.toml",
        f"# Generator: scripts/docs/generate_usage.py",
        f"DOTS — machine environment manager  (v{ver})",
        "",
        "Usage:",
    ]
    for c in cmds:
        usage = str(c.get("usage") or f"dots {c.get('name')}")
        if usage.startswith("dots "):
            left = f"  ./{usage}"
        elif usage.startswith("dots"):
            left = f"  ./{usage}"
        else:
            left = f"  {usage}"
        desc = str(c.get("description") or "")
        # shorten long descriptions for synopsis
        if len(desc) > 56:
            desc = desc[:53] + "..."
        pad = max(1, 36 - len(left))
        lines.append(f"{left}{' ' * pad}{desc}")
    lines.extend(
        [
            "",
            "Interactive help:",
            "  ./dots help              Textual TUI (dots-help)",
            "  dots-help                same launcher",
            "  man dots                 Unix manual",
            "",
            "Optional components use profile with= or ./setup.sh --with <ids>",
            "(see ./dots components list). Docs:",
            "  https://sempervent.github.io/dots/using/components/",
            "",
            "Automation / expert scripts (still supported):",
            "  ./bootstrap.sh   ./setup.sh   ./configure.sh",
            "  ./scripts/pull_models.sh   ./scripts/check.sh",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    body = generate()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    if args.check:
        if not OUT.is_file() or OUT.read_text(encoding="utf-8") != body:
            print(f"drift: {OUT}", file=sys.stderr)
            return 1
        return 0
    OUT.write_text(body, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
