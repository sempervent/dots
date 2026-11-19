"""Embedded DOTS Help documentation browser pane."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widgets import Label, ListItem, ListView, Markdown

from ..registry import Registry
from ..state import gather_state
from ..topics import render_topic


class HelpPane(Horizontal):
    """Browse DOTS help topics inside the lifecycle TUI."""

    def __init__(self, reg: Registry, **kwargs) -> None:
        super().__init__(**kwargs)
        self.reg = reg
        self.topics = self.reg.topic_rows()

    def compose(self) -> ComposeResult:
        with Vertical(id="help-sidebar"):
            yield Label("Help Topics", classes="pane-title")
            yield ListView(
                *[ListItem(Label(str(t.get("title")))) for t in self.topics],
                id="help-topic-list",
            )
        with Vertical(id="help-body"):
            yield Markdown(id="help-markdown")

    def on_mount(self) -> None:
        if self.topics:
            lv = self.query_one("#help-topic-list", ListView)
            lv.index = 0
            self._open_topic(str(self.topics[0].get("id")))

    def _open_topic(self, topic_id: str) -> None:
        st = gather_state(self.reg)
        body = render_topic(self.reg, topic_id, st)
        self.query_one("#help-markdown", Markdown).update(body)

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        if event.list_view.id != "help-topic-list":
            return
        idx = event.list_view.index
        if idx is None or idx < 0 or idx >= len(self.topics):
            return
        self._open_topic(str(self.topics[idx].get("id")))
