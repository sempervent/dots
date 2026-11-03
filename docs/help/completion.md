# Fuzzy Completion

Zsh keeps compsys intelligence; fzf-tab makes candidate selection fuzzy.

| Key | Behavior |
|-----|----------|
| Ctrl-R | Fuzzy history (Atuin when installed; else fzf) |
| Ctrl-T | Insert filesystem path(s) via fzf |
| Alt-C | Fuzzy directory jump via fzf |
| Tab | Contextual fuzzy completion (fzf-tab) |
| **\<Tab\> | Explicit recursive fzf filesystem completion |
| Ctrl-] | Accept autosuggestion (Zsh vi insert) |
| Ctrl-Y | Toggle multi-select inside fzf-tab |

> **Ctrl-Space is reserved for the tmux prefix.** It is never used for
> autosuggestion acceptance or fzf-tab multi-select.

## Examples

```bash
git che<Tab>
git checkout <Tab>
vim src/<Tab>
vim **<Tab>
cd ~/dev/<Tab>
ssh <Tab>
kubectl get <Tab>
docker compose <Tab>
terraform <Tab>
```

Ordinary Tab does not invent candidates — Zsh decides what is valid; fzf-tab helps you pick.

Bash uses official fzf only (Ctrl-R/T, Alt-C, **\<Tab\>), not fzf-tab.
