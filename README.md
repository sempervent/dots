# Sempervent's Dotfiles

Author: Joshua N. Grant  
Email: jngrant@live.com

A personal workstation operating layer: shared muscle memory across home Mac,
work Mac, and headless Linux — not identical software everywhere.

Bash remains fully supported. Zsh + Oh My Zsh is the primary rich interactive
shell. Shared logic lives in `shell/`; shell-specific behavior in `bash/` and
`zsh/`.

## First run (happy path)

```bash
git clone https://github.com/sempervent/dots.git ~/dots
cd ~/dots
./dots
```

`./dots` is the primary human interface: machine role → profile → components →
runtime → models → review → bootstrap → verify. Expert scripts remain available
underneath for automation.

```bash
./dots                     # interactive setup (same as ./dots setup)
./dots status              # read-only dashboard
./dots backup              # snapshot managed targets
./dots backups             # list recoverable snapshots
./dots restore             # restore a snapshot (creates a safety snapshot first)
./dots profile             # create / preview / switch profiles
./dots models              # local model plan & pull
./dots check               # health verification
./dots update              # git pull + optional reapply
./dots --version
```

### Prompt (Bash + Starship)

Bash and Starship deliberately share the same semantic layout:

```text
┌──┤joshuagrant@poster_nutbag├─┤19:55:55├─┤Wed Sep 16├─┤origin/master->master│
├───┤jobs (0)├─┤.venv│
└─┤~/dots│
```

Set `DOTS_PROMPT=off` to disable the custom Bash PS1. Legacy directory
stats remain available via `DOTS_PROMPT_STATS=1` but are no longer part of
the default prompt.

### Recovery (snapshots)

Before DOTS replaces unmanaged targets, it creates one coherent snapshot.
Recover with:

```bash
./dots backups
./dots restore
# or: ./dots restore <snapshot-id> --dry-run
```

Snapshots live under `~/.local/state/dots/backups/`. Existing
`~/.old_dots` content is detected and can be imported with
`./dots backup import-legacy`.

Preview without mutating the machine:

```bash
./dots setup --dry-run
```

Automation / advanced use (unchanged):

```bash
./bootstrap.sh --profile home
./bootstrap.sh --profile work
./bootstrap.sh --profile server
./bootstrap.sh --profile home --show
./bootstrap.sh --profile home --dry-run
./setup.sh --dry-run --with ai
./configure.sh
./scripts/pull_models.sh --list
./scripts/check.sh
```

### Which profile?

```text
I am a normal home user          →  home   (via ./dots or --profile home)
I am configuring a work machine  →  work
I am configuring a Linux server  →  server
My machine differs slightly      →  ~/.config/dots/profiles/<name>.toml
                                    with extends = "<base>"
```

Short example (custom server host — or just answer the wizard):

```bash
mkdir -p ~/.config/dots/profiles
cp examples/profiles/bertha.toml ~/.config/dots/profiles/bertha.toml
./bootstrap.sh --profile ~/.config/dots/profiles/bertha.toml --show
./bootstrap.sh --profile ~/.config/dots/profiles/bertha.toml
```

More templates: [`examples/profiles/`](examples/profiles/).

| Profile | Package groups | Optional components | Multiplexer | GUI |
|---------|----------------|---------------------|-------------|-----|
| `base` | core, modern | none | tmux | minimal |
| `home` | core…gui + infra/media | personal stack (incl. Herdr) | herdr | yes |
| `work` | core, modern, workstation | **none** unless `--with` / custom | tmux | limited |
| `server` | core, modern, server | **Herdr** (no AI providers) | tmux | no |
| `all` | full workstation | all optional | tmux | yes |

**Irreducible bootstrap seed** (DOTS cannot create these for you):

```text
a supported OS (macOS or Linux)
/bin/bash able to start bootstrap.sh / setup.sh
network connectivity for official installers/packages
OS elevation (root or sudo) when system packages require it
```

Everything else declared by the selected profile is provisioned automatically:

| Requirement | How DOTS installs it |
|-------------|----------------------|
| Apple CLT (macOS) | official `xcode-select --install` |
| Homebrew (macOS) | official Homebrew installer (HTTPS) |
| Python ≥3.11 | Homebrew `python@3.12` or apt/pacman/xbps/dnf |
| Profile packages | brew groups or native Linux maps |
| Herdr | `brew install herdr` or official `https://herdr.dev/install.sh` |

`--show` / `--dry-run` never mutate — they report Stage 0 actions such as
`Would install Homebrew` / `Would install Python 3.12`.

Managed hosts that prohibit package installs:

```bash
./bootstrap.sh --profile work --no-install
```

**Linux servers:** native `apt` / `pacman` / `xbps` / `dnf` (Homebrew not required).
`tmux` and `herdr` are both first-class on the server profile; Herdr does **not**
authorize Hermes, Codex, Cursor, Ollama, or any other provider.

## Machine-local overrides

```text
~/.config/dots/runtime.env   # generated from profile (non-secret)
~/.config/dots/local.sh      # your host overrides (never overwritten)
~/.config/dots/profiles/     # user-owned custom profiles (extends builtins)
```

### Provisioning vs runtime precedence

**Provisioning / profile configuration** (install-time):

```text
repository defaults
  < built-in profile
  < custom profile / inheritance (extends)
  < CLI --with / --without / --packages
```

**Runtime shell configuration** (after bootstrap):

```text
repository defaults (shell/exports.sh)
  < ~/.config/dots/runtime.env
  < ~/.config/dots/local.sh
  < explicit process environment (DOTS_MULTIPLEXER, …)
```

`local.sh` does not change package installation after bootstrap — it is runtime/shell
policy only. Do not store secrets in `local.sh`.

### Custom profiles (extends)

Built-in `home` / `work` / `server` are presets, not prisons. Prefer a user-owned
overlay instead of editing repository TOML. Start from
[`examples/profiles/`](examples/profiles/) or generate with `./configure.sh`.

```toml
# ~/.config/dots/profiles/bertha.toml

[profile]
name = "bertha"
extends = "server"

[runtime]
multiplexer = "tmux"   # or "herdr" — both valid; Herdr is installed either way

[packages]
add = ["infra"]
```

```bash
./bootstrap.sh --profile ~/.config/dots/profiles/bertha.toml --show
./bootstrap.sh --profile ~/.config/dots/profiles/bertha.toml
```

Work customization without weakening default AI safety (still no providers unless listed):

```toml
# ~/.config/dots/profiles/corp-work.toml
[profile]
name = "corp-work"
extends = "work"

[components]
with = ["images"]

[packages]
add = ["infra"]
```

Home without Cursor, keep Herdr as automatic multiplexer:

```toml
# ~/.config/dots/profiles/home-studio.toml
[profile]
name = "home-studio"
extends = "home"
without = ["cursor"]

[runtime]
multiplexer = "herdr"
```

Builtin names (`home`, `work`, …) always resolve to repository presets — never
silently shadowed by `~/.config/dots/profiles/home.toml`. Pass an explicit path
for user files. Non-builtin short names may resolve under `~/.config/dots/profiles/`.

Or generate with configure (writes TOML only):

```bash
./configure.sh --extends server --output ~/.config/dots/profiles/bertha.toml \
  --name bertha --packages-add infra --multiplexer herdr
```

## Git identity

DOTS manages `~/.config/git/common` (aliases, editor, rerere).  
Personal/work `user.name` / `user.email` live in:

```text
~/.config/git/personal
~/.config/git/work
```

created once from templates — never overwritten. See `configs/git/README.md`.

## Verify

After bootstrap (or anytime):

```bash
# Health check for the profile you just applied (or omit --profile for defaults)
./scripts/check.sh --profile home
./scripts/check.sh --profile server

# Inspect resolved config without mutating the machine
./bootstrap.sh --profile home --show
./bootstrap.sh --profile ~/.config/dots/profiles/bertha.toml --show
```

Required check failures make bootstrap **fail**. Warnings do not.
Success looks like a zero-failure summary from `./scripts/check.sh` and
`Bootstrap complete: profile contract satisfied` from a real bootstrap.

## Consent vs presence

**Binary presence ≠ configuration authorization.** AI clients are configured only
when explicitly listed in the profile / `--with` for that run.

---

## Install (legacy / direct)

```bash
./setup.sh                         # core refresh (no AI)
./setup.sh --with herdr,hermes     # explicit components
./configure.sh                     # edit profiles (TOML only)
```

### Skill options

| Flag | Meaning |
|------|---------|
| `--with archify` | Archify only |
| `--with skills` | Engineering pack (includes Archify + security-review) |
| `--with ai-skills` | AI/agent harness pack |
| `--with skills,ai-skills` | Union of both packs |

Skill packs are declared in `configs/skills/manifest.toml`.

### Separation of concerns

| Script | Role |
|--------|------|
| `dots` | Unified human entrypoint (wizard + status/models/check) |
| `setup.sh` | Install / refresh mechanism |
| `bootstrap.sh` | Profile orchestration → setup + health gate |
| `configure.sh` | Profile creation/editing (writes TOML only) |

Authority for optional component ids: `configs/components.toml`.  
Package groups: `brew/groups/*.Brewfile` + `configs/packages/`.  
Managed links: `configs/links.toml`.

### Local agent telemetry (private)

DOTS records **local observational** metadata about routing and adapter
executions so you can measure the harness before changing it.

| | |
|--|--|
| **Stored** | backend, model, duration, success/timeout, route reason/category, escalation flags, optional resource/Ollama snapshots, token/cost *if exposed* |
| **Not stored (default)** | prompts, responses, secrets, source code, full paths, env dumps |
| **Database** | `~/.local/share/dots/telemetry/agents.sqlite3` (SQLite WAL) |
| **Config** | `configs/agents/telemetry.toml` → `~/.config/dots/agents/telemetry.toml` |
| **Opt-out** | `DOTS_TELEMETRY=0` or `enabled = false` in telemetry.toml |

```bash
agent-stats
agent-stats --week
agent-telemetry doctor
```

Telemetry failures never abort agent work.

### Optional components (`--with`)

```bash
./setup.sh --with herdr
./setup.sh --with hermes
./setup.sh --with ollama
./setup.sh --with archify
./setup.sh --with skills
./setup.sh --with ai-skills
./setup.sh --with skills,ai-skills
./setup.sh --with drawthings
./setup.sh --with opencode
./setup.sh --with codex
./setup.sh --with cursor
./setup.sh --with fluidvoice
./setup.sh --with images
./setup.sh --with tex
./setup.sh --with ai
./setup.sh --with ai --without cursor
./setup.sh --with herdr,cursor
./setup.sh --with hermes,drawthings
./setup.sh --with cursor,drawthings
./setup.sh --with images,drawthings
./setup.sh --with images,tex
./setup.sh --with=herdr,hermes
./setup.sh --dry-run --with cursor
./setup.sh --dry-run --with ai
./setup.sh --help
```

| Component | Installs |
|-----------|----------|
| `herdr` | `brew/Brewfile.herdr` → `herdr` |
| `hermes` | `hermes-agent` (+ macOS cask `hermes-desktop`) |
| `ollama` | `ollama` (no models, service not started) |
| `llamacpp` | `Brewfile.llamacpp` → Homebrew `llama.cpp` (models via `pull_models.sh`) |
| `archify` | Archify skill only (`npx skills add tt-a1i/archify -g`) |
| `skills` | Curated Engineering Pack from `configs/skills/manifest.toml` (includes Archify + security-review) |
| `ai-skills` | Curated AI/agent pack (evals, production ops, litellm, ml-engineering, …) |
| `drawthings` | `Brewfile.drawthings` → `draw-things-cli` + MCP launcher + `img` |
| `opencode` | `Brewfile.opencode` → OpenCode CLI + DOTS adapter/MCP |
| `codex` | `Brewfile.codex` → **Homebrew cask** `codex` (+ Hermes MCP if hermes co-selected) |
| `cursor` | `Brewfile.cursor` → cask `cursor-cli` (`agent`) + opt-in `~/.cursor` merge |
| `fluidvoice` | `Brewfile.fluidvoice` → cask `fluidvoice` (macOS 15+; no models/permissions automated) |
| `images` | `Brewfile.images` → Magick/gs/rsvg/exiftool/pngquant/webp/oxipng |
| `tex` | `Brewfile.tex` → Homebrew `texlive` (CLI) |

### Supergroups

`--with` accepts declarative **supergroups** from `configs/components.toml`. Groups expand to ordinary component ids before install (no second installation path).

| Supergroup | Meaning |
|------------|---------|
| `ai` | All **AI applications** supported on this platform |

```bash
./setup.sh --with ai
./setup.sh --with ai --without cursor
./bootstrap.sh --profile work --with ai   # explicit opt-in on work
```

`--with ai` expands to every supported AI application for the current machine:

```text
hermes, ollama, llamacpp, drawthings, opencode, codex, cursor, fluidvoice
```

Platform-incompatible members are **reported and omitted** from the group (for example FluidVoice on Linux). Explicitly requesting an unsupported component (for example `./setup.sh --with fluidvoice` on Linux) remains an **error**.

`ai` does **not** include skill packs (`skills`, `ai-skills`), Herdr, images, or TeX.

Custom profiles may use the same selectors:

```toml
[components]
with = ["ai"]
without = ["cursor"]
```

`--without ai` removes every member of the AI supergroup (even if those components came from the profile). Individual `--without` entries still win over `--with`.

Prefer `--profile home` or `--profile all` (lab) for broader aggregates; `all` ≠ `ai`.

## Local models

DOTS installs AI **applications** separately from AI **models**.

`bootstrap` / `setup` do **not** pull multi-gigabyte models by default.

```bash
./scripts/pull_models.sh --list
./scripts/pull_models.sh --dry-run
./scripts/pull_models.sh
```

`pull_models.sh` chooses defaults from `configs/models.toml` according to hardware (tier) and which runtimes are installed. Overrides live in `~/.config/dots/models.toml` (never overwritten by updates).

```bash
./scripts/pull_models.sh --provider ollama
./scripts/pull_models.sh --provider drawthings
./scripts/pull_models.sh --tier balanced
./bootstrap.sh --profile home --pull-models   # optional convenience; same script
```

### Example: 24 GB Apple Silicon

```text
Detected: Apple Silicon, 24 GB → tier balanced
```

Typical plan when Ollama, llama.cpp, Draw Things, and FluidVoice are present:

```text
Ollama        qwen2.5:7b                              ~4.7 GB   (general)
llama.cpp     Qwen2.5-Coder-7B-Instruct Q4_K_M        ~4.7 GB   (coding)
Draw Things   flux_2_klein_4b_q6p.ckpt                ~6 GB     (image)
FluidVoice    Parakeet TDT v3                         ~0.5 GB   (speech — MANUAL)
```

Ollama and llama.cpp intentionally cover **different roles** so auto mode does not duplicate the same weights into two caches.

### FluidVoice models

FluidVoice has **no supported noninteractive model CLI** today. `pull_models.sh` reports `MANUAL` and recommends Parakeet TDT v3 (speech) plus optional Fluid-1 (cleanup). Models are downloaded inside the FluidVoice app. DOTS does **not** write into undocumented cache paths.

### llama.cpp

```bash
./setup.sh --with llamacpp
./scripts/pull_models.sh --provider llamacpp
```

Installs via Homebrew (`brew install llama.cpp`). Models use `llama-cli -hf <repo>[:quant]`.

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
./setup.sh --with skills    # curated Engineering Pack (includes Archify)
./setup.sh --with ai-skills # curated AI/agent harness pack
./setup.sh --with skills,ai-skills  # union (deduped)
./scripts/update-skills.sh  # opt-in update (not on every setup)
```

Manifest: `configs/skills/manifest.toml` (`[packs.skills]`, `[packs.ai-skills]`, groups).
Provenance: `~/.agents/.skill-lock.json` (content-hash via skills CLI; not git SHA pinning)
copied to `~/.config/dots/skills/skills-lock.json` after pack install.

Verification accepts a valid `SKILL.md` under either:

```text
~/.agents/skills/<name>
~/.hermes/skills/<name>
```

When Hermes is co-selected (`--with hermes,skills`), an install that lands only
under `~/.hermes/skills` is success — DOTS does not require a duplicate copy
under `~/.agents/skills`. Static security review runs against the resolved path.

What `--with archify` does:

1. Verifies Node ≥ 18 via fnm-managed Node and `npx`.
2. If Archify is not already present, runs:
   `npx -y skills add tt-a1i/archify -g -y`
3. Skill is verified at its actual install location (global store and/or Hermes).

**Hermes** may receive skills via `-a hermes-agent` when Hermes is selected.
Presence of `~/.hermes` alone does not grant configuration consent.

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

