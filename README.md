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
./setup.sh --with archify
./setup.sh --with drawthings
./setup.sh --with herdr,hermes,ollama,archify,drawthings
./setup.sh --with=herdr,hermes
./setup.sh --dry-run --with drawthings
./setup.sh --help
```

| Component | Installs |
|-----------|----------|
| `herdr` | `brew/Brewfile.herdr` → `herdr` |
| `hermes` | `hermes-agent` (+ macOS cask `hermes-desktop`) |
| `ollama` | `ollama` (no models, service not started) |
| `archify` | `brew/Brewfile.archify` → Node 18+, then `npx skills add tt-a1i/archify -g` |
| `drawthings` | `Brewfile.drawthings` → `draw-things-cli` + Hermes MCP bridge |

## Package management

**Homebrew truth is `brew/Brewfile` only.** There is no `packages.txt`.

Optional packages are declared in:

- `brew/Brewfile.herdr`
- `brew/Brewfile.hermes`
- `brew/Brewfile.ollama`
- `brew/Brewfile.archify` (Node for agent skills)
- `brew/Brewfile.drawthings` (`draw-things-cli`; does **not** install the GUI)

and applied only when selected via `--with`.

## Agent skills

Reusable agent skills install through the same `--with` mechanism. The first
skill is **Archify** (architecture / workflow / sequence / data-flow /
lifecycle diagrams → validated HTML).

```bash
./setup.sh --with archify
```

What happens:

1. Homebrew installs Node (`Brewfile.archify`) if needed.
2. Setup verifies Node ≥ 18 and `npx`.
3. If Archify is not already present, runs:
   `npx -y skills add tt-a1i/archify -g -y`
4. Skill lives globally at `~/.agents/skills/archify` (shared across agents).

**Hermes** discovers Archify via the symlink the `skills` CLI creates at
`~/.hermes/skills/archify` → `~/.agents/skills/archify`. No extra Hermes
config or dots-managed copy is required.

**Herdr** does not embed Archify. It orchestrates agents (e.g. Hermes); Hermes
loads the skill. Boundary: Herdr → Hermes → Archify skill → JSON IR →
validate/deliver → HTML.

To add another skill later: map it in `helpers/agent_skills.sh`
(`agent_skill_package`), add the name to `SUPPORTED_WITH` in `setup.sh`, and
add a `brew/Brewfile.<name>` only if Homebrew deps are required.

## Draw Things (image tool)

Draw Things is a **local image-generation tool**, not a Hermes reasoning model.

```text
Hermes  --reasoning-->  Ollama / qwen-hermes
   |
   | MCP stdio
   v
~/.local/bin/drawthings-mcp  -->  draw-things-cli  -->  ~/Pictures/AI/DrawThings/
```

### One-line install

```bash
./setup.sh --with drawthings
# or with the rest of the local AI stack:
./setup.sh --with hermes,herdr,ollama,archify,drawthings
```

### What setup installs/configures

1. Homebrew: tap `drawthingsai/draw-things` + `draw-things-cli` (`Brewfile.drawthings`).
2. `uv` project env for the bridge (`tools/drawthings_mcp/` — `mcp>=1.2,<2`, locked).
3. Live config → `~/.config/drawthings-mcp/config.toml` (first install; existing live file kept).
4. Stable launcher → `~/.local/bin/drawthings-mcp` → `$DOTS/scripts/drawthings-mcp`.
5. Output dir → `~/Pictures/AI/DrawThings/` (writable).
6. If Hermes is present: register MCP server `drawthings` (idempotent).
7. Probe: tool discovery + `status` + `list_models` (no image generation).

Does **not**: install Draw Things.app, download image models, or bind any network port.

### Draw Things.app policy

`draw-things-cli` does **not** require the GUI process at runtime. The Mac App Store /
drawthings.ai GUI install is still the usual way to obtain the default models
directory (app container). You may instead set `DRAWTHINGS_MODELS_DIR`. Setup never
fails solely because the GUI is absent.

### Manual Hermes registration

```bash
hermes mcp add drawthings --command ~/.local/bin/drawthings-mcp
hermes mcp list
hermes mcp test drawthings
```

Hermes prefixes MCP tools with the server name after discovery. Example prompts:

- “Use Draw Things to list my installed image models.”
- “Generate an image of a red cube on a black background using Draw Things.”
- “Generate this image using flux_2_klein_4b_q8p.ckpt.”

MCP tools: `status`, `list_models`, `generate`, `img2img`.

### Validation vs smoke

```bash
./scripts/check.sh                      # cheap checks
./scripts/drawthings_mcp_probe.sh       # MCP initialize/status/list_models
./scripts/drawthings_smoke.sh           # optional tiny PNG (GPU/time)
```

Memory: default `memory.policy = "manual"`. Optional `unload_ollama` stops loaded
Ollama models before generation (not the Ollama daemon; no auto-reload).

Reusable client snippet (OpenCode/Codex later): `~/.config/dots/drawthings-mcp.client.json`
(and template `configs/drawthings/mcp.client.json` using `~/.local/bin/drawthings-mcp`).

## Layout

```
shell/     shared aliases, exports, functions, paths, tools, multiplexer, theme
bash/      Bash-only
zsh/       Zsh-only + Oh My Zsh
distro/    platform hooks
syms/      $HOME symlink sources
ranger/    Ranger overrides + Catppuccin colorscheme
configs/   bat, btop, herdr, drawthings, templates
brew/      Brewfile (+ optional fragments)
helpers/   setup helpers (herdr_config, agent_skills, optional_components, drawthings)
tools/     MCP bridges (drawthings_mcp)
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

Aligned to this repo’s tmux muscle memory where Herdr has an equivalent. tmux stays on Ctrl-Space; Herdr is not changed to match tmux’s prefix.

| Key | Action | vs tmux |
|-----|--------|---------|
| h/j/k/l | focus panes | identical |
| **&** | side-by-side split (`split_vertical`) | Herdr-specific (tmux uses `v`) |
| **"** | top/bottom split (`split_horizontal`) | Herdr-specific; matches classic tmux `"` |
| **b** | **sidebar** | intentional exception (tmux `b` = top/bottom split) |
| c / n / p / 1–9 | tabs | identical to tmux windows |
| z / x | zoom / close pane | identical |
| Shift-K | close tab | mirrors tmux `K` (kill-window) |
| d | detach | mirrors tmux default detach |
| w / g | workspace picker / goto | Herdr-native |
| r | resize mode | intentional (tmux `r` = reload) |
| Shift-R | reload config | Herdr default; tmux reload is `r` |
| `[` | edit scrollback | closest to tmux copy-mode `[` |

Split naming: Herdr `split_vertical` = side-by-side (tmux `-h`); `split_horizontal` = top/bottom (tmux `-v`).

Not mirrored (no faithful Herdr equivalent): tmux man (`/`), process viewer (`~`), paste (`P`), copy-mode vi chords.

Deploy: `setup.sh` merges managed `[theme]`/`[keys]` into `~/.config/herdr/config.toml` (regular file — Herdr rewrites local UI/onboarding; symlink is unsafe).

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

Agent skills such as Archify are installed with `--with archify` (see **Agent
skills** above); Hermes picks them up from `~/.hermes/skills/`.

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
