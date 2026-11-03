# Keybindings

Authoritative intended map (see `configs/help/keybindings.toml`). Runtime
ownership is verified by `./dots shell status`.

| Key | Context | Action |
|-----|---------|--------|
| Ctrl-Space | tmux | Prefix (**reserved** — never shell) |
| Ctrl-A | Herdr | Prefix (**reserved** — never a global shell shortcut) |
| Ctrl-R | shell | Fuzzy history (Atuin when installed, else fzf) |
| Ctrl-T | shell | Fuzzy file insertion |
| Alt-C | shell | Fuzzy directory jump |
| Tab | Zsh | Contextual fuzzy completion (fzf-tab) |
| **\<Tab\> | shell | Recursive fzf filesystem completion |
| Ctrl-] | Zsh vi insert | Accept autosuggestion |
| Ctrl-Y | fzf-tab UI | Toggle multi-select |

## Invariants

- **Ctrl-Space** belongs exclusively to tmux.
- **Ctrl-A** belongs exclusively to Herdr.
- Shell features must not compete with those prefixes.

Diagnose:

```bash
./dots shell status
./dots shell keys
```
