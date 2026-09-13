# Sempervent's Dotfiles

Author: Joshua N. Grant
Email: jngrant@live.com

Bash remains fully supported for servers and scripts. Zsh + Oh My Zsh is the
primary rich interactive shell (especially on macOS). Shared logic lives in
`shell/`; shell-specific behavior in `bash/` and `zsh/`. `.zshrc` does **not**
source Bash configs.

## Install

```bash
git clone https://github.com/sempervent/dots.git ~/dots
cd ~/dots
./setup.sh
```

`setup.sh` is idempotent: unique timestamped backups under `~/.old_dots/`,
skips existing Oh My Zsh / TPM / Vundle / plugin clones, and does not change
your login shell.

Packages: prefer `brew bundle --file=brew/Brewfile` (also invoked by setup when
`brew` is available). `brew/packages.txt` is a lighter fallback list.

## Layout

```
shell/     shared aliases, exports, functions, PATH/Homebrew, tools, tmux helper
bash/      Bash-only options, history, completion, prompt, ffs/so
zsh/       Zsh-only options, history, keybindings, prompt, Oh My Zsh
distro/    macOS / Linux hooks
syms/      files linked into $HOME (.bashrc, .zshrc, .zprofile, …)
brew/      Brewfile + packages.txt
```

## Oh My Zsh

Installed to `~/.oh-my-zsh` if missing. Third-party plugins are cloned once under
`$ZSH_CUSTOM/plugins`:

- zsh-autosuggestions
- zsh-syntax-highlighting (loaded last)
- zsh-history-substring-search

Not enabled: OMZ `extract` (custom `extract()`), OMZ `z` (zoxide).

Update plugins: `omz update` and `git -C ~/.oh-my-zsh/custom/plugins/<name> pull`.

## Useful toggles

| Variable | Effect |
|----------|--------|
| `DOTS_AUTO_TMUX=0` | disable interactive auto-tmux |
| `DOTS_PROMPT_STATS=1` | enable dir file count/size in prompt |
| `DOTS_GREETING=0` | silence fortune greeting |

## Default shell

```bash
chsh -s "$(command -v zsh)"   # prefer Zsh
chsh -s "$(command -v bash)"  # revert to Bash
```

## Testing / startup timing

```bash
DOTS_AUTO_TMUX=0 DOTS_GREETING=0 bash -lic 'echo bash-ok'
DOTS_AUTO_TMUX=0 DOTS_GREETING=0 zsh  -lic 'echo zsh-ok'
time DOTS_AUTO_TMUX=0 DOTS_GREETING=0 bash -i -c exit
time DOTS_AUTO_TMUX=0 DOTS_GREETING=0 zsh  -i -c exit
```

## Migration notes

- `dco` prefers `docker compose`, falls back to `docker-compose`
- `ffs` is Bash-only; Zsh: OMZ `sudo` plugin (Esc Esc)
- No global `TERM=xterm-256color`; tmux prefers `tmux-256color`
- Homebrew typo `/opt/hombrew` removed; use `brew shellenv`
- History is configured separately for Bash and Zsh
- Use `bash-completion@2` (not `bash-completion` v1)

## Homebrew troubleshooting

If `brew bundle` warns about stale keg metadata (`libtiff` / `webp`), that is a
local Homebrew repair — **not** something `setup.sh` will auto-uninstall. See
`brew doctor` and Homebrew’s guidance before removing kegs.

## License

Personal dotfiles — use as you wish.
