# Shell & Prompt

| Shell | Role |
|-------|------|
| **Zsh** | Primary rich interactive shell (Oh My Zsh + Starship) |
| **Bash** | Servers, scripts, Zsh-less hosts |

Shared logic lives in `shell/`; shell-specific code in `zsh/` and `bash/`.

Vi editing mode is enabled in both shells. Starship owns the prompt when installed.

Reload:

```bash
# Zsh
source ~/.zshrc
# Bash
source ~/.bashrc
```
