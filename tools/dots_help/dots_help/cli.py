"""CLI entry for dots-help."""

from __future__ import annotations

import argparse
import os
import sys


def _tty() -> bool:
    return sys.stdin.isatty() and sys.stdout.isatty()


def _can_textual() -> bool:
    if os.environ.get("TERM", "") == "dumb":
        return False
    if not _tty():
        return False
    try:
        import textual  # noqa: F401

        return True
    except Exception:
        return False


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="dots-help",
        description="Interactive DOTS help for the current machine.",
        add_help=True,
    )
    p.add_argument("topic", nargs="?", help="Topic id (e.g. completion, packages, backup)")
    p.add_argument("--plain", action="store_true", help="Plain text (no TUI)")
    p.add_argument("--search", metavar="QUERY", help="Search topics/commands/components")
    p.add_argument("--version", action="store_true", help="Print DOTS version")
    p.add_argument("--list-topics", action="store_true", help="List topic ids")
    return p


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    parser = build_parser()
    args = parser.parse_args(argv)

    from .registry import Registry
    from .render import render_plain
    from .state import gather_state

    reg = Registry()
    if args.version:
        print(f"dots-help (DOTS {reg.version()})")
        return 0

    if args.list_topics:
        for t in reg.topic_rows():
            print(f"{t.get('id')}\t{t.get('title')}")
        return 0

    force_plain = args.plain or args.search or (not _can_textual())
    if force_plain:
        if not args.plain and not args.search and not _tty():
            print("DOTS help TUI unavailable; showing plain help.", file=sys.stderr)
        elif not args.plain and not args.search and os.environ.get("TERM") == "dumb":
            print("DOTS help TUI unavailable; showing plain help.", file=sys.stderr)
        elif not args.plain and not args.search:
            try:
                import textual  # noqa: F401
            except Exception:
                print("DOTS help TUI unavailable; showing plain help.", file=sys.stderr)
        text = render_plain(topic_id=args.topic, query=args.search)
        sys.stdout.write(text)
        return 0

    try:
        from .app import run_tui

        return run_tui(topic=args.topic)
    except Exception as exc:  # noqa: BLE001 — always fall back
        print(f"DOTS help TUI unavailable ({exc}); showing plain help.", file=sys.stderr)
        sys.stdout.write(render_plain(topic_id=args.topic, query=args.search))
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
