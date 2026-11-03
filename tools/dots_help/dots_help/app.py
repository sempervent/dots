"""Textual TUI for dots-help."""

from __future__ import annotations

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.command import Hit, Hits, Provider
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Footer, Header, Input, Label, ListItem, ListView, Markdown, Static

from .registry import Registry
from .state import gather_state
from .topics import render_topic, search


class TopicProvider(Provider):
    """Command palette: jump to topics / quit."""

    async def search(self, query: str) -> Hits:
        q = (query or "").strip().lower()
        app = self.app
        assert isinstance(app, DotsHelpApp)
        commands = [
            ("Quit", "quit", app.action_quit),
            ("Search", "search", app.action_search),
            ("Show Active Profile", "profiles", lambda: app._select_topic("profiles")),
            ("Open Backup Help", "backup", lambda: app._select_topic("backup")),
            ("Open Fuzzy Completion", "completion", lambda: app._select_topic("completion")),
            ("Open Components", "components", lambda: app._select_topic("components")),
        ]
        for title, needle, callback in commands:
            if not q or q in title.lower() or q in needle:
                yield Hit(1.0, title, callback, help=needle)
        for t in app.topics:
            tid = str(t.get("id") or "")
            title = str(t.get("title") or tid)
            blob = f"{tid} {title} {' '.join(t.get('keywords') or [])}".lower()
            if not q or q in blob:
                yield Hit(
                    0.9,
                    f"Open {title}",
                    lambda topic_id=tid: app._select_topic(topic_id),
                    help=tid,
                )


class SearchScreen(ModalScreen[str | None]):
    """Simple search modal; returns selected topic id."""

    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
    ]

    def __init__(self, reg: Registry) -> None:
        super().__init__()
        self.reg = reg
        self._hits: list = []

    def compose(self) -> ComposeResult:
        with Vertical(id="search-panel"):
            yield Label("Search topics / commands / components")
            yield Input(placeholder="Type to search…", id="search-input")
            yield ListView(id="search-results")

    def on_mount(self) -> None:
        self.query_one("#search-input", Input).focus()

    def on_input_changed(self, event: Input.Changed) -> None:
        q = event.value.strip()
        lv = self.query_one("#search-results", ListView)
        lv.clear()
        self._hits = search(self.reg, q) if q else []
        for h in self._hits:
            lv.append(ListItem(Label(f"[{h.category}] {h.title} → {h.topic_id}")))

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        idx = event.list_view.index
        if idx is None or idx < 0 or idx >= len(self._hits):
            return
        self.dismiss(self._hits[idx].topic_id)

    def action_cancel(self) -> None:
        self.dismiss(None)


class DotsHelpApp(App[None]):
    """Machine-aware DOTS help browser."""

    ENABLE_COMMAND_PALETTE = True
    COMMANDS = {TopicProvider}

    CSS = """
    Screen {
        background: #1e1e2e;
        color: #cdd6f4;
    }
    #sidebar {
        width: 28;
        border-right: solid #45475a;
        background: #181825;
    }
    #sidebar ListView {
        height: 1fr;
    }
    #body {
        height: 1fr;
        padding: 0 1;
    }
    #status {
        dock: bottom;
        height: 1;
        background: #313244;
        color: #a6adc8;
        padding: 0 1;
    }
    #search-panel {
        width: 70%;
        height: auto;
        max-height: 80%;
        border: round #cba6f7;
        background: #1e1e2e;
        padding: 1;
        margin: 2 4;
    }
    ListItem {
        padding: 0 1;
    }
    .list-item--highlighted {
        background: #45475a;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("slash", "search", "Search", key_display="/"),
        Binding("question_mark", "keys", "Keys", key_display="?"),
        Binding("c", "cheatsheet", "Cheat sheet"),
        Binding("ctrl+p", "palette", "Palette"),
        Binding("g", "top", "Top"),
        Binding("G", "bottom", "Bottom"),
    ]

    def __init__(self, topic: str | None = None) -> None:
        super().__init__()
        self.reg = Registry()
        self.state = gather_state(self.reg)
        self.topics = self.reg.topic_rows()
        self.current_id = topic or "overview"
        if not any(t.get("id") == self.current_id for t in self.topics):
            self.current_id = "overview"
        self.title = "DOTS Help"
        self.sub_title = f"v{self.state.version}"

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)
        with Horizontal():
            with Vertical(id="sidebar"):
                yield Label("Topics", id="sidebar-title")
                yield ListView(
                    *[ListItem(Label(str(t.get("title"))), id=f"topic-{t.get('id')}") for t in self.topics],
                    id="topic-list",
                )
            with Vertical(id="body"):
                yield Markdown(id="content")
        yield Static(self._status_line(), id="status")
        yield Footer()

    # status line already documents / ? q; Footer shows c for cheat sheet

    def on_mount(self) -> None:
        self._select_topic(self.current_id)
        # Highlight matching list item
        lv = self.query_one("#topic-list", ListView)
        for i, t in enumerate(self.topics):
            if t.get("id") == self.current_id:
                lv.index = i
                break

    def _status_line(self) -> str:
        st = self.state
        return (
            f"Profile: {st.profile or '—'}   Host: {st.host}   Shell: {st.shell}   "
            f"/ search   c cheat   ? keys   q quit"
        )

    def _select_topic(self, topic_id: str) -> None:
        self.current_id = topic_id
        md = self.query_one("#content", Markdown)
        body = render_topic(self.reg, topic_id, self.state)
        md.update(body)

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        if event.list_view.id != "topic-list":
            return
        idx = event.list_view.index
        if idx is None or idx < 0 or idx >= len(self.topics):
            return
        tid = str(self.topics[idx].get("id"))
        self._select_topic(tid)

    def action_search(self) -> None:
        def _done(topic_id: str | None) -> None:
            if topic_id:
                self._select_topic(topic_id)
                for i, t in enumerate(self.topics):
                    if t.get("id") == topic_id:
                        self.query_one("#topic-list", ListView).index = i
                        break

        self.push_screen(SearchScreen(self.reg), _done)

    def action_keys(self) -> None:
        self._select_topic("keybindings")

    def action_cheatsheet(self) -> None:
        from .cheatsheet import render_cheatsheet

        md = self.query_one("#content", Markdown)
        md.update(render_cheatsheet(self.state, self.reg, markdown=True))
        self.current_id = "cheatsheet"

    def action_palette(self) -> None:
        self.action_command_palette()

    def action_top(self) -> None:
        self.query_one("#topic-list", ListView).index = 0
        if self.topics:
            self._select_topic(str(self.topics[0].get("id")))

    def action_bottom(self) -> None:
        last = len(self.topics) - 1
        if last >= 0:
            self.query_one("#topic-list", ListView).index = last
            self._select_topic(str(self.topics[last].get("id")))


def run_tui(topic: str | None = None) -> int:
    DotsHelpApp(topic=topic).run()
    return 0
