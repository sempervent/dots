# Fuzzy Completion

Zsh keeps compsys intelligence; **fzf-tab** makes candidate selection fuzzy.

| Key | Behavior |
|-----|----------|
| **Ctrl-R** | Fuzzy history (Atuin when installed; else fzf) |
| **Ctrl-T** | Insert filesystem path(s) via fzf |
| **Alt-C** | Fuzzy directory jump via fzf |
| **Tab** | Contextual fuzzy completion (fzf-tab) |
| **\*\*\<Tab\>** | Explicit recursive fzf filesystem completion |
| **Ctrl-Space** | Accept autosuggestion (not fzf-tab multi-select) |
| **Ctrl-Y** | Toggle multi-select inside fzf-tab |

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

Ordinary Tab does **not** invent candidates — Zsh decides what is valid; fzf-tab helps you pick.

Bash uses official fzf only (Ctrl-R/T, Alt-C, `**<Tab>`), not fzf-tab.

See also: [docs/using/fuzzy-completion.md](../using/fuzzy-completion.md)
