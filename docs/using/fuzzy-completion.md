# Fuzzy completion

DOTS keeps Zsh’s completion intelligence and makes candidate selection fuzzy
and interactive via [fzf-tab](https://github.com/Aloxaf/fzf-tab).

These are three different layers:

| Layer | Role |
|-------|------|
| **Autosuggestion** | Ghost text from history (`zsh-autosuggestions`; accept with Ctrl-Space) |
| **Completion** | Valid candidates at the cursor (Zsh compsys + command-specific scripts) |
| **Fuzzy selection** | Interactive filtering of those candidates (fzf-tab on Tab) |

## Key bindings (Zsh)

| Key | Behavior |
|-----|----------|
| **Ctrl-R** | Fuzzy history (Atuin when installed; otherwise fzf) |
| **Ctrl-T** | Insert filesystem path(s) via fzf |
| **Alt-C** | Fuzzy directory jump via fzf (when the terminal delivers Meta-c) |
| **Tab** | Contextual fuzzy completion (fzf-tab over Zsh candidates) |
| **\*\*\<Tab\>** | Explicit recursive fzf filesystem completion |
| **Ctrl-Space** | Accept autosuggestion (not fzf-tab multi-select) |
| **Ctrl-Y** | Toggle multi-select inside the fzf-tab UI |

## Examples

```bash
git che<Tab>          # checkout / cherry-pick / check-ignore / …
git checkout <Tab>    # branches / tags from Git completion
vim conf<Tab>         # matching files
cd ~/dev/<Tab>        # directories
vim **<Tab>           # recursive fzf file pick
kubectl get <Tab>     # kubectl’s own candidates (when completion is installed)
docker compose <Tab>
ssh <Tab>             # known hosts
```

Ordinary Tab does **not** invent candidates. Zsh (and each command’s completion
script) still decides what is valid; fzf-tab only helps you pick.

## Bash

Bash does not use fzf-tab. It keeps the official fzf integration:

- Ctrl-R / Ctrl-T / Alt-C
- `**<Tab>` path completion (fd-backed when `fd` is available)

## Discoverability

```bash
dots-help                 # interactive help for this machine
dots-help completion      # this cheat-sheet, live capability state
man dots
```

| Discover | Search args | History | Files | Docs |
|----------|-------------|---------|-------|------|
| `dots-help` | Tab | Ctrl-R | Ctrl-T | `man dots` |

## Install / health

`./setup.sh` clones fzf-tab next to the other Oh My Zsh custom plugins (clone once;
startup never clones).

```bash
./dots check          # “Fuzzy completion” section
```

If fzf-tab is absent, Zsh still starts and Tab falls back to normal completion.
