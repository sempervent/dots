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

For a new machine, prefer profiles:

```bash
./bootstrap.sh --profile base    # core shell UX only — zero AI
./bootstrap.sh --profile work    # conservative allowlist (edit work.toml)
./bootstrap.sh --profile home    # editable home stack template
./bootstrap.sh --profile work --with hermes   # profile + explicit add
./bootstrap.sh --profile home --without cursor
```

`setup.sh` is idempotent. Default install includes shell UX (fnm, Starship,
JetBrainsMono Nerd Font, Neovim, terminal-notifier) but does **not** install AI
tooling or download models.

### Consent vs presence

**DOTS distinguishes software presence from configuration consent.**

A binary already on the machine (Cursor, Hermes, Codex, …) does **not** authorize
DOTS to configure it. Configuration, MCP registration, and Herdr integrations run
only for components explicitly listed in `--with` / the selected bootstrap profile
for **that** invocation.

| Component | Allowed config when selected |
|-----------|------------------------------|
| `hermes` | `~/.hermes/*` (MCP, notify hooks) |
| `herdr` | Herdr config + integrations **only** for co-selected agents |
| `ollama` | local Ollama notes/wiring when selected |
| `opencode` | OpenCode config; Hermes MCP only if `hermes` also selected |
| `codex` | Codex adapter; Hermes MCP only if `hermes` also selected |
| `cursor` | `~/.cursor/*` merge; Herdr cursor integration if `herdr` also selected |
| `drawthings` | bridge/launcher/`img`; MCP into a client only if that client is co-selected |
| `skills` | `~/.agents/skills` global store; Hermes links only if `hermes` selected |

### Optional components (`--with`)

```bash
./setup.sh --with herdr
./setup.sh --with hermes
./setup.sh --with ollama
./setup.sh --with archify
./setup.sh --with skills
./setup.sh --with drawthings
./setup.sh --with opencode
./setup.sh --with codex
./setup.sh --with cursor
./setup.sh --with images
./setup.sh --with tex
./setup.sh --with herdr,cursor
./setup.sh --with hermes,drawthings
./setup.sh --with cursor,drawthings
./setup.sh --with images,drawthings
./setup.sh --with images,tex
./setup.sh --with herdr,hermes,ollama,skills,drawthings,opencode,codex,cursor,images,tex
./setup.sh --with=herdr,hermes
./setup.sh --dry-run --with cursor
./setup.sh --help
```

| Component | Installs |
|-----------|----------|
| `herdr` | `brew/Brewfile.herdr` → `herdr` |
| `hermes` | `hermes-agent` (+ macOS cask `hermes-desktop`) |
| `ollama` | `ollama` (no models, service not started) |
| `archify` | Archify skill only (`npx skills add tt-a1i/archify -g`) |
| `skills` | Curated Engineering Pack from `configs/skills/manifest.toml` (includes Archify + security-review) |
| `drawthings` | `Brewfile.drawthings` → `draw-things-cli` + MCP launcher + `img` |
| `opencode` | `Brewfile.opencode` → OpenCode CLI + DOTS adapter/MCP |
| `codex` | `Brewfile.codex` → **Homebrew cask** `codex` (+ Hermes MCP if hermes co-selected) |
| `cursor` | `Brewfile.cursor` → cask `cursor-cli` (`agent`) + opt-in `~/.cursor` merge |
| `images` | `Brewfile.images` → Magick/gs/rsvg/exiftool/pngquant/webp/oxipng |
| `tex` | `Brewfile.tex` → Homebrew `texlive` (CLI) |

**Do not add `--with ai`.** Prefer `--profile home` for a full personal stack.
## Package management

**Homebrew truth is `brew/Brewfile` only.** There is no `packages.txt`.

Default Brewfile now includes: `fnm`, `starship`, `neovim`, `terminal-notifier`,
and cask `font-jetbrains-mono-nerd-font`. Node runtime is managed by **fnm**
(policy: `configs/node/default.toml`), not NVM and not raw `brew node`.

**PATH hygiene:** Homebrew precedes `~/.local/bin`. Setup retires Hermes git-install
shims (`~/.local/bin/{node,npm,npx,hermes}`) into `~/.local/bin/.dots-retired/`
when Homebrew `hermes-agent` / fnm are present. Hermes keeps its private Node at
`~/.hermes/node/` (not on PATH). Optional leftover cleanup: `brew uninstall nvm`
(does **not** delete `~/.nvm` data).

**Editor:** default `EDITOR`/`VISUAL`/`git core.editor` = `nvim`. Interactive
`vim`/`vi` aliases map to Neovim; `/usr/bin/vim` is never overwritten.

**Notifications:** `~/.local/bin/notify` wraps `terminal-notifier`. Hermes
session hooks notify after long tasks (default ≥60s). Smoke:
`./scripts/notify-smoke.sh`.

Optional packages are declared in:

- `brew/Brewfile.herdr`
- `brew/Brewfile.hermes`
- `brew/Brewfile.ollama`
- `brew/Brewfile.archify` (reserved; Node via fnm)
- `brew/Brewfile.drawthings` (`draw-things-cli`; does **not** install the GUI)
- `brew/Brewfile.opencode` (`opencode`)
- `brew/Brewfile.codex` (cask `codex` — preferred over npm `@openai/codex`)
- `brew/Brewfile.cursor` (cask `cursor-cli` — preferred over `curl … \| bash`)
- `brew/Brewfile.images` (deterministic image toolkit)
- `brew/Brewfile.tex` (`texlive`)

and applied only when selected via `--with`.

## Cursor Agent (`--with cursor`)

Install path: Homebrew cask `cursor-cli` (inspectable). Upstream also documents
`curl https://cursor.com/install -fsS | bash`; DOTS prefers the cask to avoid
pipe-to-shell. Official command is `agent` (also `cursor-agent`).

Config is touched **only** when `cursor` is selected:

- `~/.cursor/cli-config.json` — merge conservative defaults (no wildcard MCP/Shell)
- `~/.cursor/mcp.json` — Draw Things only when `drawthings` co-selected
- OpenCode/Codex are **not** registered as Cursor MCP tools

Thin runner: `cursor-agent-run run --dir <repo> --prompt "…"` → `agent -p …`.

Router: destination `cursor` only on explicit “use Cursor”. If unavailable, report
unavailable — no silent Codex/OpenCode substitute.

## Draw Things `img`

```bash
img "a PCB-shelled cosmic turtle"
img -w 1536 -h 1024 "retro-futurist synthesizer laboratory"
img-square "…"
img-wide "…"
pfl-icon "experimental electronic music laboratory, bold icon"
```

Defaults (width/height/steps) are CLI flags; model + output dir come from the same
`configs/drawthings/config.toml` / live `~/.config/drawthings-mcp/config.toml` as MCP
(`DRAWTHINGS_MODEL` / `DRAWTHINGS_OUTPUT_DIR` override). Deployed with `--with drawthings`.

## Agent skills

```bash
./setup.sh --with archify   # Archify only
./setup.sh --with skills    # curated Hermes Engineering Pack (includes Archify)
./scripts/update-skills.sh  # opt-in update (not on every setup)
```

Manifest: `configs/skills/manifest.toml`. Provenance: `~/.agents/.skill-lock.json`
(copied to `~/.config/dots/skills/skills-lock.json` after pack install).

What `--with archify` does:

1. Verifies Node ≥ 18 via fnm-managed Node and `npx`.
2. If Archify is not already present, runs:
   `npx -y skills add tt-a1i/archify -g -y`
3. Skill lives globally at `~/.agents/skills/archify` (shared across agents).

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
6. MCP registration into Hermes/Cursor **only** when that client is co-selected.
7. Probe: tool discovery + `status` + `list_models` (no image generation).
8. `img` / `img-square` / `img-wide` / `pfl-icon` → `~/.local/bin/`.

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

Reusable client snippet: `~/.config/dots/drawthings-mcp.client.json`
(and template `configs/drawthings/mcp.client.json` using `~/.local/bin/drawthings-mcp`).

## Coding backends (OpenCode + Codex)

Hermes follows the **agent-router** skill for explicit delegation (no embeddings).

```text
User → Hermes conductor (+ agent-router policy)
         ├── local reasoning     → Ollama
         ├── architecture        → Archify skill
         ├── image generation    → Draw Things MCP
         ├── image manipulation  → images CLI (Magick/…)
         ├── local/general code  → OpenCode adapter (MCP / CLI)
         └── frontier/escalated  → Codex native MCP (codex mcp-server)
Herdr supervises interactive sessions; it does not choose the coding backend.
```

### Install

```bash
./setup.sh --with opencode,codex
# full local AI stack + media/TeX:
./setup.sh --with hermes,herdr,ollama,archify,drawthings,opencode,codex,images,tex
```

### OpenCode (local/general coding)

Stable launchers:

- `~/.local/bin/opencode-agent` — CLI adapter over `opencode run`
- `~/.local/bin/opencode-mcp` — thin Hermes MCP (`status`, `list_models`, `list_agents`, `run`)

Config: `~/.config/dots/agents/execution.toml` (template `configs/agents/execution.toml`).

Defaults (inspect with `opencode models` / `opencode agent list`):

| Setting | Value |
|---------|-------|
| mode | `standalone` (no persistent `opencode serve` by default) |
| default_model | `ollama/qwen-hermes:latest` |
| default_agent | `build` (implementation; may modify files) |
| timeout | 600s |

Override agent for inspect/review: `--agent plan` (edit denied by OpenCode).

```bash
opencode-agent run \
  --dir ~/dev/project \
  --prompt "Inspect this repository and identify the cause of the failing tests."

opencode-agent run \
  --dir ~/dev/project \
  --agent build \
  --prompt "Implement the fix and run tests." \
  --auto
```

`--dir` is required and must exist. The adapter does not default to DOTS or `$HOME`.

Optional server mode: set `mode = "server"` and `server_url = "http://127.0.0.1:4096"` in
execution.toml, start `opencode serve --hostname 127.0.0.1 --port 4096` yourself, then
`opencode-agent run --attach http://127.0.0.1:4096 ...`. DOTS does not auto-daemonize serve.

Hermes prompts (manual):

- “Use OpenCode to inspect this repository.”
- “Delegate this implementation to OpenCode.”

Concurrency: avoid running OpenCode local inference + Hermes local model + Draw Things
simultaneously on a 24 GB MacBook Air. They may share one Ollama server.

```bash
./scripts/opencode_smoke.sh   # temp dir; plan agent; opt-in
```

### Codex (frontier / escalated coding)

Install source: **Homebrew cask** (`brew install --cask codex`), not global npm.

Codex ≥0.154 removed `codex mcp-server`. When that subcommand is missing, DOTS
registers a thin stdio MCP bridge (`~/.local/bin/codex-mcp` → `codex exec`) so
Hermes can still delegate. Auth stays in `~/.codex/`.

Hermes also ships a builtin **codex** skill that drives `codex exec` via the
terminal — complementary to MCP.

If an old npm `@openai/codex` is blocking `/opt/homebrew/bin/codex`, setup migrates the
Homebrew-prefix npm package when safe, then installs the cask. Manual cleanup:

```bash
/opt/homebrew/bin/npm uninstall -g --prefix /opt/homebrew @openai/codex
brew install --cask codex
```

```bash
hermes mcp list
hermes mcp test codex
./scripts/codex_mcp_smoke.sh   # connection/discovery only
```

Hermes prompts (manual):

- “Use Codex to review this architecture.”
- “Escalate this difficult refactor to Codex.”

Hermes↔Codex tool-callback / app-server bidirectionality is **deferred** unless Hermes
creates it naturally; this pass only requires Hermes → Codex as a coding specialist.

## Images toolkit (`--with images`)

Deterministic conversion / optimization / metadata — **not** generative.

```bash
./setup.sh --with images
./setup.sh --with images,drawthings   # toolkit + generative backend
```

| Tool | Role |
|------|------|
| `magick` | convert / trim / resize |
| `gs` | Ghostscript / PDF |
| `rsvg-convert` | SVG → raster |
| `exiftool` | metadata |
| `pngquant` | lossy PNG optimize |
| `cwebp` / `dwebp` | WebP |
| `oxipng` | lossless PNG |

Examples:

```bash
magick input.webp output.png
magick input.png -background none -trim output.png
exiftool image.png
pngquant image.png
rsvg-convert input.svg > output.png
```

## TeX Live (`--with tex`)

```bash
./setup.sh --with tex
pdflatex --version
xelatex --version
kpsewhich article.cls
```

Homebrew formula `texlive` (CLI). No MacTeX / BasicTeX GUI bundle.

## Agent router (explicit policy)

Version-controlled skill: `skills/agent-router/` (linked into `~/.agents/skills` and
`~/.hermes/skills` when an AI stack component is requested).

| Kind | Destination |
|------|-------------|
| general reasoning | Hermes / Ollama |
| architecture | Archify |
| routine coding | OpenCode |
| difficult coding | Codex |
| generative imagery | Draw Things |
| image manipulation | images CLI |
| TeX/LaTeX | TeX Live |

User overrides always win (“Use Codex…”, “Keep this local…”). At most one automatic
coding escalation: OpenCode → Codex. Policy tests (no model calls):

```bash
./scripts/router_policy_test.sh
```

## Layout

```
shell/     shared aliases, exports, functions, paths, tools, multiplexer, theme
bash/      Bash-only
zsh/       Zsh-only + Oh My Zsh
distro/    platform hooks
syms/      $HOME symlink sources
ranger/    Ranger overrides + Catppuccin colorscheme
configs/   bat, btop, herdr, drawthings, opencode, agents, templates
brew/      Brewfile (+ optional fragments)
helpers/   setup helpers (…, drawthings, opencode, codex, agent_router)
skills/    DOTS-local Hermes skills (agent-router)
tools/     MCP bridges (drawthings_mcp, opencode_mcp)
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
