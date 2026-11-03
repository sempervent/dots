#!/usr/bin/env python3
"""Generate docs/man/man1/*.1 from configs/help metadata.

Usage:
  python3 scripts/docs/generate_manpages.py
  python3 scripts/docs/generate_manpages.py --check
"""

from __future__ import annotations

import argparse
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAN1 = ROOT / "docs" / "man" / "man1"
COMMANDS = ROOT / "configs" / "help" / "commands.toml"
VERSION_FILE = ROOT / "VERSION"

HEADER = r""".\" GENERATED — DO NOT EDIT.
.\" Source: configs/help/commands.toml + scripts/docs/generate_manpages.py
."""


def load_commands() -> list[dict]:
    with COMMANDS.open("rb") as fh:
        data = tomllib.load(fh)
    return list(data.get("commands") or [])


def version() -> str:
    if VERSION_FILE.is_file():
        return VERSION_FILE.read_text(encoding="utf-8").strip() or "0"
    return "0"


def esc(text: str) -> str:
    return text.replace("\\", "\\\\").replace("-", "\\-")


def write_dots_1(cmds: list[dict], ver: str) -> str:
    lines = [
        HEADER,
        f'.TH DOTS 1 "2026-11-02" "DOTS {ver}" "User Commands"',
        ".SH NAME",
        "dots \\- desired\\-state environment manager",
        ".SH SYNOPSIS",
        ".B dots",
        "[command] [options]",
        ".SH DESCRIPTION",
        "DOTS converges a workstation toward a declarative desired state:",
        "profiles, package groups, optional components, skills, and models.",
        "Primary interactive shell UX includes fuzzy completion (fzf\\-tab) and",
        ".B dots\\-help",
        "for machine\\-aware documentation.",
        ".SH COMMANDS",
    ]
    for c in cmds:
        usage = esc(str(c.get("usage") or c.get("name")))
        desc = esc(str(c.get("description") or ""))
        lines.append(f".TP")
        lines.append(f".B {usage}")
        lines.append(desc)
    lines.extend(
        [
            ".SH FUZZY COMPLETION",
            "On Zsh, Tab uses fzf\\-tab over compsys candidates. Ctrl\\-R searches",
            "history, Ctrl\\-T inserts files, Alt\\-C jumps directories, and **Tab",
            "runs recursive fzf path completion. Ctrl\\-] accepts",
            "zsh\\-autosuggestions ghost text. Ctrl\\-Space is reserved for the",
            "tmux prefix; Ctrl\\-A is reserved for Herdr. See",
            ".BR dots\\-help (1)",
            "topic",
            ".B completion",
            ".",
            ".SH FILES",
            ".TP",
            ".I ~/.config/dots/",
            "Runtime state, active profile, models overlay.",
            ".TP",
            ".I ~/.local/state/dots/backups/",
            "Snapshots created by",
            ".BR dots\\-backup .",
            ".SH SEE ALSO",
            ".BR dots\\-help (1),",
            ".BR dots\\-packages (1),",
            ".BR dots\\-models (1),",
            ".BR dots\\-lsp (1),",
            ".BR dots\\-backup (1)",
            ".SH RECOVERY",
            "Use",
            ".B dots backup",
            "/",
            ".B dots restore",
            "for managed targets. Legacy trees may appear as",
            ".IR ~/.old_dots .",
        ]
    )
    return "\n".join(lines) + "\n"


def write_dots_help_1(ver: str) -> str:
    return "\n".join(
        [
            HEADER,
            f'.TH DOTS\\-HELP 1 "2026-11-02" "DOTS {ver}" "User Commands"',
            ".SH NAME",
            "dots\\-help \\- interactive DOTS help for the current machine",
            ".SH SYNOPSIS",
            ".B dots\\-help",
            "[topic] [--plain] [--search QUERY] [--version]",
            ".br",
            ".B dots help",
            "[topic] …",
            ".SH DESCRIPTION",
            "Opens a Textual TUI documenting commands, profiles, components,",
            "packages, AI, models, LSP, skills, keybindings, fuzzy completion,",
            "backup/restore, and configuration for",
            ".B this",
            "host. Falls back to plain text when the TUI cannot start.",
            ".SH KEYS",
            ".TP",
            ".B q",
            "Quit",
            ".TP",
            ".B /",
            "Search",
            ".TP",
            ".B ?",
            "Keybindings topic",
            ".TP",
            ".B Enter",
            "Open selected topic",
            ".SH TOPICS",
            "Use",
            ".B dots\\-help --list\\-topics",
            "or open e.g.",
            ".B dots\\-help completion",
            ".",
            ".SH PLAIN MODE",
            ".B dots\\-help --plain",
            "[topic] prints ANSI\\-free text under NO_COLOR / pipes.",
            ".SH FILES",
            ".I configs/help/commands.toml",
            ",",
            ".I configs/help/topics.toml",
            ",",
            ".I docs/help/*.md",
            ".SH SEE ALSO",
            ".BR dots (1)",
        ]
    ) + "\n"


def write_subcommand_1(name: str, cmd: dict, ver: str) -> str:
    usage = esc(str(cmd.get("usage") or f"dots {name}"))
    desc = esc(str(cmd.get("description") or ""))
    lines = [
        HEADER,
        f'.TH DOTS\\-{name.upper()} 1 "2026-11-02" "DOTS {ver}" "User Commands"',
        ".SH NAME",
        f"dots\\-{esc(name)} \\- {desc}",
        ".SH SYNOPSIS",
        f".B {usage}",
        ".SH DESCRIPTION",
        desc,
        ".SH EXAMPLES",
    ]
    examples = cmd.get("examples") or []
    if not examples:
        lines.append("See")
        lines.append(".BR dots\\-help (1)")
        lines.append(".")
    for ex in examples:
        lines.append(".TP")
        lines.append(f".B {esc(str(ex.get('command') or ''))}")
        lines.append(esc(str(ex.get("description") or "")))
    lines.extend(
        [
            ".SH SEE ALSO",
            ".BR dots (1),",
            ".BR dots\\-help (1)",
        ]
    )
    return "\n".join(lines) + "\n"


def generate() -> dict[str, str]:
    cmds = load_commands()
    ver = version()
    out: dict[str, str] = {
        "dots.1": write_dots_1(cmds, ver),
        "dots-help.1": write_dots_help_1(ver),
    }
    for c in cmds:
        name = str(c.get("name") or "")
        if name in {
            "setup",
            "packages",
            "components",
            "models",
            "lsp",
            "backup",
            "status",
            "check",
            "shell",
            "completion",
            "help",
        }:
            out[f"dots-{name}.1"] = write_subcommand_1(name, c, ver)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    pages = generate()
    MAN1.mkdir(parents=True, exist_ok=True)
    if args.check:
        drift = False
        for name, body in pages.items():
            path = MAN1 / name
            if not path.is_file() or path.read_text(encoding="utf-8") != body:
                print(f"drift: {path}", file=sys.stderr)
                drift = True
        return 1 if drift else 0
    for name, body in pages.items():
        path = MAN1 / name
        path.write_text(body, encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
