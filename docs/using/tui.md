# Dynamic Desired-State TUI (`dots tui`)

DOTS provides a registry-driven Textual terminal interface (`./dots tui`) as a
front-end over the authoritative DOTS desired-state engine.

```bash
./dots tui                 # open dynamic desired-state dashboard (interactive TTY)
./dots                     # opens TUI on already-bootstrapped TTY (or setup wizard)
./dots setup               # Bash setup / returning-machine wizard
./dots help                # documentation browser (dots-help)
```

Noninteractive CLI commands (`./dots install`, `./dots upgrade`,
`./dots profile`, `./dots setup`, `./dots status`, `./dots check`) remain fully
functional without Textual for servers, SSH sessions, scripts, and CI.

## Architecture

The TUI is strictly a presentation and controller layer:

```text
configs/{packages/groups,components}.toml
        ↓
./dots {profile show,components list,packages groups,profile plan} --json
        ↓
Textual TUI (tools/dots_help)
        ↓
./dots profile mutate / ./dots upgrade --yes
        ↓
helpers/profile_edit.sh (atomic sparse overlay) → bootstrap.sh
```

Python never edits profile TOML directly and never invokes `brew`, `apt`, `dnf`,
`pacman`, or `xbps` directly.

## Dynamic registry population

Every **package group** (`configs/packages/groups.toml`), **component**
(`configs/components.toml` grouped by `category`), and **supergroup**
(`[[supergroups]]`) is loaded dynamically from the structured backend JSON APIs.
Adding a group or component to the registry makes it appear in the TUI
automatically without code changes.

## Selection state glyphs

Capability rows distinguish inheritance, local edits, exclusions, and platform
availability using both glyphs and text tags (accessible without color):

| Glyph | State tag | Meaning |
|-------|-----------|---------|
| `●` | `[inherited]` | Inherited from the parent/base profile |
| `✓` | `[local]` | Explicitly selected in the local sparse overlay |
| `□` | `[absent]` | Not selected |
| `⊘` | `[excluded]` | Inherited capability explicitly excluded locally |
| `!` | `[unsupported]` | Unavailable on this OS or macOS version (disabled) |

Set `DOTS_TUI_ASCII=1` to use ASCII-only glyphs (`*`, `+`, ` `, `-`, `!`).

## Persistence and safety

- **Staged changes:** Toggling items updates only the in-memory working set until
  you choose **Preview (`p`)**, **Save Only (`s`)**, or **Save + Apply (`a`)**.
- **Built-in presets protected:** Built-in profiles under
  `configs/bootstrap/profiles/` are never edited; changes persist into sparse
  DOTS-managed overlays (`~/.config/dots/profiles/<name>-local.toml`).
- **Custom profiles preserved:** Hand-written custom profiles remain untouched;
  TUI edits layer a sparse `<name>-local.toml` overlay on top.
- **Unchecking inherited items:** Toggling off an inherited capability adds an
  exclusion (`packages.remove` / `components.without`) in the local overlay.
- **No automatic uninstall:** Unchecking a group or component updates desired
  state only — installed packages are never automatically uninstalled.
- **Batch transaction:** Multiple checkbox changes persist in one atomic
  `dots profile mutate` write and apply via at most one `bootstrap.sh` pass.

## Package search and owner resolution

Press `/` to search across groups, bundles (supergroups), components,
descriptions, and packages. Selecting a package uses the DOTS owner resolver
(`dots profile resolve <pkg> --json`) to highlight its owning group or component
and explain the full capability impact. When a package has multiple owners (such
as `taplo`), the TUI prompts you to choose rather than picking arbitrarily.

## Keyboard shortcuts

| Key | Action |
|-----|--------|
| `Up` / `Down` | Move selection |
| `Space` | Toggle capability |
| `Tab` / `Shift+Tab` | Next / previous pane |
| `/` | Search groups, components, bundles, packages |
| `p` | Preview plan (`dots profile plan --json`) |
| `s` | Save Only (persist sparse overlay without bootstrap) |
| `a` | Save + Apply (persist once + converge once) |
| `r` | Refresh state from backend |
| `?` | Keyboard help and glyph legend |
| `q` | Quit (prompts Save / Discard / Cancel if unsaved) |

## Structured JSON interfaces

```bash
./dots profile show [PROFILE] --json
./dots profile list --json
./dots components list --json
./dots packages groups --json
./dots profile resolve <selector> --json
./dots profile plan [--profile NAME] [--add SEL] [--remove SEL] --json
./dots upgrade --dry-run --json
```
