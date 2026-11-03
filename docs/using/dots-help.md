# DOTS Help (`dots-help`)

After setup, DOTS is self-documenting for **this** machine:

```bash
dots-help                 # Textual TUI
./dots help               # same
./dots help completion    # jump to a topic
dots-help --plain lsp     # noninteractive / pipes / CI
man dots
man dots-help
```

`./dots --help` stays a **fast Bash synopsis** (no Python/Textual). Use it when you
only need the conventional CLI usage block.

## What it knows

Help reads authoritative registries and quick local state:

| Source | Content |
|--------|---------|
| `configs/components.toml` | Components / supergroups |
| `configs/packages/groups.toml` | Package groups |
| `configs/lsp/servers.toml` | Language servers |
| `configs/models.toml` | Model policy catalog |
| `configs/skills/manifest.toml` | Skill packs |
| `configs/help/commands.toml` | CLI command metadata |
| `configs/help/topics.toml` + `docs/help/*.md` | Narrative topics |
| `~/.config/dots/*` | Active profile / runtime |
| `~/.local/state/dots/backups/` | Snapshot inventory |

It does **not** run `brew outdated`, model downloads, or a full `./dots check` on
launch. Prefer:

```bash
./dots check
```

## Fuzzy completion + help

Together with [fuzzy completion](fuzzy-completion.md):

| Action | How |
|--------|-----|
| Discover commands | `dots-help` |
| Search valid arguments | Tab (fzf-tab on Zsh) |
| Search history | Ctrl-R |
| Search files | Ctrl-T |
| Traditional docs | `man dots` |

## Development

```bash
uv sync --directory tools/dots_help
uv run --directory tools/dots_help dots-help --plain
python3 scripts/docs/generate_manpages.py
python3 scripts/docs/generate_usage.py
```

Man pages install to `~/.local/share/man/man1/` during setup; shells prepend that
root to `MANPATH` when present.
