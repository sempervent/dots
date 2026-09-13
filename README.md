# Sempervent's Dotfiles

Author: Joshua N. Grant
Email: jngrant@live.com

Bash remains fully supported. Zsh + Oh My Zsh is the primary rich interactive
shell. Shared logic lives in `shell/`; shell-specific behavior in `bash/` and
`zsh/`.

## Install

```bash
git clone https://github.com/sempervent/dots.git ~/dots
cd ~/dots
./setup.sh
```

`setup.sh` is idempotent. Default install does **not** install AI tooling or
download models.

### Optional components (`--with`)

```bash
./setup.sh --with herdr
./setup.sh --with hermes
./setup.sh --with ollama
./setup.sh --with herdr,hermes,ollama
./setup.sh --with=herdr,hermes
./setup.sh --dry-run --with herdr
./setup.sh --help
```

| Component | Installs |
|-----------|----------|
| `herdr` | `brew/Brewfile.herdr` → `herdr` |
| `hermes` | `hermes-agent` (+ macOS cask `hermes-desktop`) |
| `ollama` | `ollama` (no models, service not started) |

## Package management

**Homebrew truth is `brew/Brewfile` only.** There is no `packages.txt`.

Optional AI packages are declared in:

- `brew/Brewfile.herdr`
- `brew/Brewfile.hermes`
- `brew/Brewfile.ollama`

and applied only when selected via `--with`.

## Layout

```
shell/     shared aliases, exports, functions, paths, tools, multiplexer, theme
bash/      Bash-only
zsh/       Zsh-only + Oh My Zsh
distro/    platform hooks
syms/      $HOME symlink sources
ranger/    Ranger overrides + Catppuccin colorscheme
configs/   bat, btop, herdr, templates
brew/      Brewfile (+ optional fragments)
```

## Multiplexers

| Tool | Prefix | Auto via |
|------|--------|----------|
| tmux | **Ctrl-Space** | `DOTS_MULTIPLEXER=tmux` (default) |
| Herdr | **Ctrl-A** | `DOTS_MULTIPLEXER=herdr` |
| none | — | `DOTS_MULTIPLEXER=none` or `DOTS_AUTO_TMUX=0` |

Suggested iTerm profiles (set env in the profile — not hard-coded):

- general: `DOTS_MULTIPLEXER=tmux`
- agents: `DOTS_MULTIPLEXER=herdr`
- plain: `DOTS_MULTIPLEXER=none`

Never nests tmux inside Herdr (detects `HERDR_*` env).

### Herdr keys (Ctrl-A)

| Key | Action |
|-----|--------|
| h/j/k/l | focus panes |
| v | side-by-side split |
| `-` | top/bottom split |
| **b** | **sidebar** (kept on b) |
| c / n / p / 1–9 | tabs |
| z / x / q | zoom / close pane / detach |
| w / g | workspace picker / goto |
| r | resize mode |
| Shift-R | reload config |
| `[` | edit scrollback |

Theme: Catppuccin (Mocha dark / Latte light with auto_switch).

## Ranger

Managed overrides under `ranger/` (not a full upstream dump). Setup deploys
file-level links into `~/.config/ranger/` without wiping bookmarks/history.

Previews: bat, jq, yq, chafa, pdftotext, mediainfo/ffprobe, exiftool, sqlite3.
Explicit trash: `dt` (normal Ranger delete unchanged).

## Hermes

Install via Homebrew when opted in (`--with hermes`). Existing `~/.hermes/`
config and secrets remain **user-owned** and are never overwritten.

If `~/.local/bin/hermes` still wins PATH after Brew install, rename/remove that
shim manually after verifying `brew`'s `hermes-agent`.

Non-secret example notes: `configs/templates/hermes/config.yaml.example`.

## Ollama

```bash
./setup.sh --with ollama
brew services start ollama   # manual
brew services stop ollama
ollama list
```

No model downloads from setup.

## Catppuccin

| Tool | Flavor |
|------|--------|
| Herdr | built-in catppuccin + latte auto |
| tmux | catppuccin/tmux `#v2.1.3` Mocha |
| Ranger | `colorschemes/catppuccin.py` |
| bat | Catppuccin Mocha theme (setup builds cache) |
| btop | catppuccin_mocha.theme |
| fzf | Mocha colors via `shell/theme.sh` |

Shell prompts stay custom (no Starship / Powerlevel10k).

## Troubleshooting

- Old Hermes PATH: `type -a hermes`
- Herdr integrations: `herdr integration status`
- tmux plugins: Prefix `Ctrl-Space` then `I`
- bat theme: `bat cache --build` (setup does this when themes present)
- Health: `./scripts/check.sh`

## License

Personal dotfiles — use as you wish.
