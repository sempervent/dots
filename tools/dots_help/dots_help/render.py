"""Plain-text rendering for non-TTY / --plain / fallbacks."""

from __future__ import annotations

import os
import re
import sys

from .registry import Registry
from .state import MachineState, gather_state
from .topics import render_topic, search


_ANSI_RE = re.compile(r"\x1b\[[0-9;]*[mK]")


def wants_color() -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("TERM", "") == "dumb":
        return False
    return sys.stdout.isatty()


def strip_ansi(text: str) -> str:
    return _ANSI_RE.sub("", text)


def md_to_plain(md: str) -> str:
    """Very small Markdown → plain transform (headers, fences, bold)."""
    out: list[str] = []
    in_fence = False
    for line in md.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
            out.append("")
            continue
        if in_fence:
            out.append(line)
            continue
        if line.startswith("# "):
            out.append(line[2:].upper())
            out.append("=" * min(60, max(8, len(line) - 2)))
            continue
        if line.startswith("## "):
            out.append("")
            out.append(line[3:])
            out.append("-" * min(40, max(4, len(line) - 3)))
            continue
        if line.startswith("### "):
            out.append(line[4:])
            continue
        line = re.sub(r"\*\*([^*]+)\*\*", r"\1", line)
        line = re.sub(r"`([^`]+)`", r"\1", line)
        out.append(line)
    text = "\n".join(out)
    return text if wants_color() else strip_ansi(text)


def render_plain(topic_id: str | None = None, query: str | None = None) -> str:
    reg = Registry()
    st = gather_state(reg)
    chunks: list[str] = []
    if query:
        hits = search(reg, query, st)
        chunks.append(f"DOTS help search: {query}")
        chunks.append("")
        if not hits:
            chunks.append("(no matches)")
        for h in hits:
            chunks.append(f"[{h.category}] {h.title} → {h.topic_id}  {h.detail}")
        return "\n".join(chunks) + "\n"

    tid = topic_id or "overview"
    body = render_topic(reg, tid, st)
    header = f"dots-help (DOTS {st.version}) — {tid}\n"
    return header + md_to_plain(body) + "\n"


def synopsis_lines(reg: Registry | None = None) -> list[str]:
    """Concise CLI synopsis lines from commands.toml (for generators / --help)."""
    reg = reg or Registry()
    ver = reg.version()
    lines = [
        f"DOTS — machine environment manager  (v{ver})",
        "",
        "Usage:",
    ]
    for cmd in reg.command_rows():
        usage = cmd.get("usage") or f"dots {cmd.get('name')}"
        desc = cmd.get("description") or ""
        # Align roughly like existing dots_usage
        left = f"  ./{usage}" if not str(usage).startswith("dots ") else f"  ./{usage}"
        # normalize dots X → ./dots X
        left = left.replace("./dots ", "./dots ")
        if left.startswith("./dots "):
            pass
        elif left.startswith("  ./dots"):
            pass
        else:
            left = f"  ./{usage}" if usage.startswith("dots") else f"  {usage}"
        left = f"  ./{usage}" if str(usage).startswith("dots") else f"  {usage}"
        pad = max(2, 34 - len(left))
        lines.append(f"{left}{' ' * pad}{desc}")
    lines.extend(
        [
            "",
            "Interactive help:",
            "  ./dots help              Textual TUI (dots-help)",
            "  dots-help                same",
            "  man dots                 Unix manual",
            "",
            "Optional components use profile with= or ./setup.sh --with <ids>",
            "(see ./dots components list). Docs:",
            "  https://sempervent.github.io/dots/using/components/",
            "",
            "Automation / expert scripts (still supported):",
            "  ./bootstrap.sh   ./setup.sh   ./configure.sh",
            "  ./scripts/pull_models.sh   ./scripts/check.sh",
        ]
    )
    return lines
