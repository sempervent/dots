"""Machine-specific DOTS cheat sheet (read-only, no network)."""

from __future__ import annotations

from .registry import Registry
from .state import MachineState, gather_state


def render_cheatsheet(st: MachineState | None = None, reg: Registry | None = None, *, markdown: bool = False) -> str:
    reg = reg or Registry()
    st = st or gather_state(reg)
    sep = "══════════════════════════════════════════════════════"
    lines: list[str] = []
    if markdown:
        lines.append("# DOTS cheat sheet")
        lines.append("")
        lines.append(f"_DOTS {st.version} — {st.host}_")
        lines.append("")
    else:
        lines.append("DOTS CHEAT SHEET")
        lines.append(sep)
        lines.append("")

    def h(title: str) -> None:
        if markdown:
            lines.append(f"## {title}")
            lines.append("")
        else:
            lines.append(title)
            lines.append("")

    def bullet(text: str) -> None:
        lines.append(f"  {text}" if not markdown else f"- {text}")

    h("Machine")
    bullet(f"Profile       {st.profile or '(none)'}")
    bullet(f"Shell         {st.shell}")
    bullet(f"Multiplexer   {st.multiplexer or '(unset)'}")
    lines.append("")

    h("Navigation")
    bullet("z <query>       zoxide jump" if _has("zoxide") else "zoxide          (not installed)")
    bullet("Ctrl-R          fuzzy history")
    bullet("Ctrl-T          fuzzy files")
    bullet("Alt-C           fuzzy directories")
    if st.shell == "zsh":
        bullet("Tab             contextual fuzzy completion")
        bullet("**<Tab>         recursive fuzzy file completion")
        bullet("Ctrl-Space      accept autosuggestion")
    else:
        bullet("**<Tab>         recursive fuzzy file completion (Bash fzf)")
    lines.append("")

    h("DOTS")
    bullet("dots            setup/reconfigure")
    bullet("dots status     machine state")
    bullet("dots check      verify environment")
    bullet("dots shell status  inspect bindings")
    bullet("dots-help       full interactive help")
    bullet("dots-help --cheatsheet")
    lines.append("")

    h("Packages")
    bullet("dots packages status")
    bullet("dots packages explain NAME")
    lines.append("")

    ai_ids = {
        "hermes",
        "ollama",
        "llamacpp",
        "drawthings",
        "opencode",
        "codex",
        "cursor",
        "fluidvoice",
        "ai-server",
    }
    ai_active = any(c in st.active_components for c in ai_ids)
    if ai_active:
        h("AI")
        bullet("dots models")
        bullet("dots models discover")
        lines.append("")
    elif any(True for _ in reg.component_rows()):
        h("AI (inactive)")
        bullet("Enable: ./dots setup --with ai")
        lines.append("")

    if "lsp" in st.active_components:
        h("LSP")
        bullet("dots lsp status")
        lines.append("")

    h("Recovery")
    bullet("dots backup --name NAME")
    bullet("dots backups")
    bullet("dots restore ID")
    if st.backup_latest:
        bullet(f"latest          {st.backup_latest}")
    lines.append("")

    h("Docs")
    bullet("dots-help")
    bullet("man dots")
    lines.append("")
    return "\n".join(lines)


def _has(cmd: str) -> bool:
    import shutil

    return shutil.which(cmd) is not None
