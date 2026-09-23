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
./dots packages status     # package ownership / drift (read-only)
./dots packages outdated   # outdated DOTS-managed packages
./dots packages upgrade    # upgrade resolved desired set only
./dots backup              # snapshot managed targets
./dots backups             # list recoverable snapshots
./dots restore             # restore a snapshot (creates a safety snapshot first)
./dots profile             # create / preview / switch profiles
./dots models              # local model plan & pull
./dots lsp                 # language-server install / status / checks
./dots check               # health verification
./dots update              # git pull + optional reapply
./dots --version
```

Preview without mutating:

```bash
./dots setup --dry-run
```

Automation / advanced:

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

## Package ownership

Installed software must never fail setup merely because DOTS did not install it.

| Term | Meaning |
|------|---------|
| **managed** | Declared by the *resolved* DOTS package/component set **and** owned by Homebrew |
| **missing** | Declared by DOTS but absent |
| **outdated** | Declared, Homebrew-owned, update available |
| **external** | Declared by DOTS; app exists but Homebrew does not own it |
| **undeclared** | Top-level Homebrew install not in the resolved desired set |

```text
installed ≠ managed
managed = declared by resolved DOTS configuration
```

Desired state is the **union** of active profile package-group Brewfiles plus
selected optional components — never every Brewfile on disk.

Homebrew package ownership is split across:

```text
brew/groups/*.Brewfile          # profile package groups (canonical)
brew/Brewfile.<component>       # optional --with components (canonical)
brew/Brewfile                   # convenience / backward-compatible aggregate only
```

There is no `packages.txt`. Do not treat top-level `brew/Brewfile` as the sole
authority. Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```bash
./dots packages status              # full audit (advisories only)
./dots packages upgrade             # upgrade managed outdated only
./dots packages upgrade --all       # opt-in: also upgrade undeclared Homebrew pkgs
./dots packages adopt glow --group modern   # prints suggested Brewfile lines
```

DOTS **never** runs `brew bundle cleanup` or uninstalls undeclared software.
External casks: warn → try `brew install --cask --adopt` → leave untouched on
failure (never `--force`).

## Recovery (snapshots)

Before DOTS replaces unmanaged targets, it creates one coherent snapshot.

```bash
./dots backups
./dots restore
# or: ./dots restore <snapshot-id> --dry-run
```

Snapshots live under `~/.local/state/dots/backups/`. Existing `~/.old_dots`
content can be imported with `./dots backup import-legacy`.

## Profiles

```text
I am a normal home user          →  home   (via ./dots or --profile home)
I am configuring a work machine  →  work
I am configuring a Linux server  →  server
My machine differs slightly      →  ~/.config/dots/profiles/<name>.toml
                                    with extends = "<base>"
```

| Profile | Package groups | Optional components | Multiplexer | GUI |
|---------|----------------|---------------------|-------------|-----|
| `base` | core, modern | none | tmux | minimal |
| `home` | core…gui + infra/media + dev/network/data/geo/security | personal stack (incl. Herdr) | herdr | yes |
| `work` | core, modern, workstation, dev, data, geo, security, gui | **none** unless `--with` / custom | tmux | yes (font) |
| `server` | core, modern, server | **Herdr** (no AI providers) | tmux | no |
| `all` | full workstation (incl. new tool groups) | all optional | tmux | yes |

Custom profiles: [`examples/profiles/`](examples/profiles/). Authority for
optional component ids: `configs/components.toml`. Package groups:
`brew/groups/*.Brewfile` + `configs/packages/`. Managed links: `configs/links.toml`.

**Irreducible bootstrap seed:** supported OS, `/bin/bash`, network for official
installers, and OS elevation when system packages require it.

## Machine-local overrides

```text
~/.config/dots/runtime.env   # generated from profile (non-secret)
~/.config/dots/local.sh      # your host overrides (never overwritten)
~/.config/dots/profiles/     # user-owned custom profiles (extends builtins)
```

Provisioning precedence: repository defaults < built-in profile < custom profile
< CLI `--with` / `--without` / `--packages`.  
Runtime precedence: `shell/exports.sh` < `runtime.env` < `local.sh` < process env.

**Consent vs presence:** AI clients are configured only when explicitly listed in
the profile / `--with` for that run.

## Platforms

- **macOS** — Homebrew + optional mactools layer ([docs/MACTOOLS.md](docs/MACTOOLS.md))
- **Linux** — native `apt` / `pacman` / `xbps` / `dnf` (Homebrew not required on
  servers). Distro matrix: [docs/LINUX.md](docs/LINUX.md)

## Optional components (quick reference)

```bash
./setup.sh --with herdr,hermes,ollama
./setup.sh --with skills,ai-skills
./setup.sh --with ai                 # platform-aware AI applications supergroup
./setup.sh --with mactools           # Darwin workstation layer
./setup.sh --with lsp                # local language-server toolchain
./setup.sh --dry-run --with cursor
```

| Component | Role |
|-----------|------|
| `herdr` | Terminal multiplexer |
| `hermes` | Agent CLI (+ macOS desktop) |
| `ollama` / `llamacpp` | Local LLM runtimes |
| `archify` / `skills` / `ai-skills` | Skills (see [docs/SKILLS.md](docs/SKILLS.md)) |
| `drawthings` | Local image generation CLI + MCP |
| `opencode` / `codex` / `cursor` | Coding agents |
| `fluidvoice` | Voice dictation (macOS 15+) |
| `images` / `tex` | Media / TeX toolkits |
| `mactools` | macOS workstation casks |
| `lsp` | PATH-visible language servers for Neovim and other clients |

## Language servers

```bash
./dots lsp
./dots lsp status
./dots lsp install --yes
./dots lsp check
./dots setup --with lsp
./setup.sh --with lsp
./setup.sh --with ai
```

The `lsp` component covers Rust, Python, Go, Bash, Markdown, TOML,
Terraform/HCL, Dockerfile, Docker Compose, R, YAML, JSON, and Lua. The `ai`
supergroup includes this local code-intelligence layer. Selecting `lsp` alone
does **not** authorize or configure Hermes, Codex, Cursor, OpenCode, Ollama, or
any cloud provider. DOTS owns PATH-visible binaries; Neovim configures clients
without downloading duplicate Mason copies. See the
[language-server guide](docs/using/language-servers.md).

Full subsystem detail lives under `docs/` — not in this README.

## Verify

```bash
./scripts/check.sh --profile home
./bootstrap.sh --profile home --show
```

Required check failures make bootstrap **fail**. Warnings do not.

## Documentation

**Site:** [https://sempervent.github.io/dots/](https://sempervent.github.io/dots/)

| Doc | Purpose |
|-----|---------|
| [docs site](https://sempervent.github.io/dots/) | Full MkDocs product (Getting Started → Reference) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Stub → architecture deep dive |
| [docs/EXTENDING.md](docs/EXTENDING.md) | Stub → extending cookbook |
| [docs/SKILLS.md](docs/SKILLS.md) | Stub → skills |
| [docs/TOOLS.md](docs/TOOLS.md) | Stub → tools catalog |
| [docs/LINUX.md](docs/LINUX.md) | Stub → Linux / Pi |
| [docs/MACTOOLS.md](docs/MACTOOLS.md) | Stub → macOS workstation layer |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Branch / PR / CI workflow |
| [SKILL.md](SKILL.md) | Canonical maintainer operating manual |
| [AGENTS.md](AGENTS.md) | Thin shim → `SKILL.md` |
