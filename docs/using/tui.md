# Dynamic Desired-State TUI (`dots tui`)

DOTS provides a registry-driven Textual terminal interface (`./dots tui`) as a
front-end over the authoritative DOTS desired-state engine.

```bash
./dots tui                         # edit the active profile
./dots tui --profile work          # edit work; does not activate it
./dots tui --dry-run               # simulate saves and applies
./dots                     # opens TUI on already-bootstrapped TTY (or setup wizard)
./dots setup               # Bash setup / returning-machine wizard
./dots help                # documentation browser (dots-help); separate from this editor
```

## Profile editor workflow

`./dots help` and `./dots tui` stay separate. The lifecycle TUI is the profile editor.

```text
dots tui
Profiles
→ choose a profile
→ Edit Selected
→ Add Software
→ search
→ Add package only, or Enable the owner
→ Preview
→ Save Profile, or Save + Apply
```

**Active** is the profile this machine uses. **Editing** is the profile open in
Profile Editor. They can differ. The editor header shows both.

| Action | Effect |
|--------|--------|
| Edit Selected | Load that profile into the editor. Does not activate it. |
| Edit Active | Load the machine's active profile. |
| Save / Save Profile | One atomic overlay write. A non-active profile is saved with `--preserve-active`. |
| Save + Apply | Save the active profile and converge once. |
| Save + Activate + Apply | Confirm, then make the edited profile active and converge once. |

Individual Software is an explicit leaf package. Adding Raycast does not enable
the mactools component. Enabling the owner selects the whole component or group.
Search stages that choice immediately. Catalog names come from
`./dots packages leaves --json` and the other structured APIs.

Views cycle through All, Individual, Groups, Components, Bundles, Selected, and
Changes. Unavailable software is hidden until **Show unavailable**. Removing
desired state does not uninstall software.

Builtin profiles stay immutable. A save continues on the resulting `*-local`
overlay. Hand-written custom profiles are not rewritten; edits land in a sparse
overlay. Create profiles with `dots profile create`. The editor does not delete
profiles or edit arbitrary TOML.

Noninteractive CLI commands (`./dots install`, `./dots upgrade`,
`./dots profile`, `./dots setup`, `./dots status`, `./dots check`) remain fully
functional without Textual for servers, SSH sessions, scripts, and CI.

## Architecture

The TUI is strictly a presentation and controller layer:

```text
configs/{packages/groups,components}.toml
        ↓
./dots {profile show,components list,packages groups,packages leaves,profile plan} --json
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
  you choose **Preview (`p`)**, **Save (`s`)**, or **Save + Apply (`a`)**.
  Editing a profile that is not active shows **Save Profile** and
  **Save + Activate + Apply**.
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
descriptions, and packages. Search results and group detail panes consume
structured backend installability metadata (`./dots packages groups --json` and
`./dots profile resolve <pkg> --json`) directly without hard-coding package
rules in Python:

- Group rows show true platform support alongside installed counts.
- Package search hits show `Owner`, `Installable`, and `Installed` (or
  `Platform: unavailable through DOTS on this machine` when a known package such
  as `tflint` has no supported installer on the host platform).
- Selecting a package reveals its owning group or component and explains full
  capability impact. When a package has multiple owners (such as `taplo`), the
  TUI prompts you to choose rather than picking arbitrarily.

## Keyboard shortcuts

| Key | Action |
|-----|--------|
| `Up` / `Down` | Move selection |
| `Space` | Toggle capability |
| `Tab` / `Shift+Tab` | Next / previous pane |
| `/` | Add or manage software |
| `v` | Cycle catalog view |
| `p` | Preview plan (`dots profile plan --json`) |
| `s` | Save profile (non-active saves do not change the active pointer) |
| `a` | Save + Apply, or Save + Activate + Apply when editing another profile |
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
./dots profile plan [--profile NAME] [--add SEL] [--remove SEL] [--add-package PKG] [--remove-package PKG] --json
./dots packages leaves --json
./dots upgrade --dry-run --json
```

## Individual software

Profile Editor lists individual software first, then package groups, components,
and bundles. Names are not hard-coded. Search offers **Add this package only**
when `leaf_selectable` is true, or **Enable the owner**. Lifecycle-managed
packages do not offer package-only. The chosen action is staged immediately.
Staged edits are saved with groups and components in **one** `./dots profile mutate`.
Save + Apply performs one overlay write and at most one bootstrap convergence.
Preview text comes from the structured plan. Removing desired state does not uninstall.
