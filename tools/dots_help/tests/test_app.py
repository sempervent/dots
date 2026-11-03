"""Textual pilot + unit tests for dots-help (no physical TTY required)."""

from __future__ import annotations

import asyncio
import os
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
os.environ.setdefault("DOTS_DIR", str(ROOT))


@pytest.fixture
def isolated_home(tmp_path, monkeypatch):
    home = tmp_path / "home"
    (home / ".config" / "dots").mkdir(parents=True)
    (home / ".local" / "state" / "dots" / "backups" / "snap1").mkdir(parents=True)
    (home / ".config" / "dots" / "active-profile").write_text(
        "DOTS_PROFILE=home\nDOTS_PACKAGE_GROUPS=core modern\n"
        "DOTS_ACTIVE_COMPONENTS=lsp hermes\nDOTS_MULTIPLEXER=tmux\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("DOTS_DIR", str(ROOT))
    monkeypatch.setenv("NO_COLOR", "1")
    for key in (
        "DOTS_PROFILE",
        "DOTS_ACTIVE_COMPONENTS",
        "DOTS_PACKAGE_GROUPS",
        "DOTS_MULTIPLEXER",
        "DOTS_PROFILE_FILE",
    ):
        monkeypatch.delenv(key, raising=False)
    return home


def test_registry_commands_and_topics():
    from dots_help.registry import Registry

    reg = Registry(ROOT)
    names = {c["name"] for c in reg.command_rows()}
    assert "help" in names
    assert "status" in names
    ids = {t["id"] for t in reg.topic_rows()}
    assert "completion" in ids
    assert "backup" in ids
    assert reg.supergroup_rows()
    assert any(r.get("id") == "ai" for r in reg.supergroup_rows())


def test_plain_render_and_search(isolated_home):
    from dots_help.render import render_plain
    from dots_help.registry import Registry
    from dots_help.topics import search

    text = render_plain("overview")
    assert "DOTS" in text
    assert "\x1b[" not in text
    comp = render_plain("completion")
    assert "fzf" in comp.lower() or "Tab" in comp
    hits = search(Registry(ROOT), "completion")
    assert hits
    assert any(h.topic_id == "completion" for h in hits)


def test_state_from_home(isolated_home):
    from dots_help.registry import Registry
    from dots_help.state import gather_state

    st = gather_state(Registry(ROOT))
    assert st.profile == "home"
    assert "lsp" in st.active_components
    assert st.backup_count >= 1


def test_app_starts_navigates_search_quits(isolated_home):
    from dots_help.app import DotsHelpApp

    async def _run() -> None:
        app = DotsHelpApp(topic="overview")
        async with app.run_test() as pilot:
            assert app.query_one("#topic-list")
            assert app.query_one("#content")
            await pilot.press("j")
            await pilot.press("/")
            await pilot.press("escape")
            await pilot.press("c")
            assert app.current_id == "cheatsheet"
            await pilot.press("q")

    asyncio.run(_run())


def test_cheatsheet_plain(isolated_home):
    from dots_help.cheatsheet import render_cheatsheet
    from dots_help.registry import Registry
    from dots_help.state import gather_state

    text = render_cheatsheet(gather_state(Registry(ROOT)), Registry(ROOT))
    assert "CHEAT SHEET" in text or "cheat" in text.lower()
    assert "\x1b[" not in text
    assert "dots" in text.lower()


def test_search_synonyms(isolated_home):
    from dots_help.registry import Registry
    from dots_help.topics import search

    reg = Registry(ROOT)
    assert any(h.topic_id == "completion" for h in search(reg, "autocomplete"))
    assert any(h.topic_id == "keybindings" for h in search(reg, "keyboard"))
    assert any(h.topic_id in {"diagnostics", "shell"} for h in search(reg, "doctor"))
