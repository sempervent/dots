<!--
GENERATED — DO NOT EDIT.
Source: dots + bootstrap.sh + setup.sh + configure.sh (safe --help)
Generator: scripts/docs/generate_reference.py
-->

# CLI help (generated)

Captured from safe `--help` / `help` invocations. If a binary is missing or help fails, a source Usage excerpt may be used. Do not treat this page as inventing flags beyond what the scripts print.

## `./dots`

```text
DOTS — machine environment manager  (v1.3.1)

Usage:
  ./dots                     interactive setup
  ./dots setup               setup / reconfigure
  ./dots status              current state (read-only)
  ./dots packages            package ownership / drift
  ./dots packages status     full package audit
  ./dots packages outdated   outdated managed packages
  ./dots packages upgrade    upgrade DOTS-managed packages
  ./dots packages adopt …    suggest Brewfile declaration (no auto-edit)
  ./dots backup [--name N]   snapshot managed targets
  ./dots backups             list snapshots
  ./dots restore [ID]        restore a snapshot
  ./dots profile             profile management
  ./dots models              local model management
  ./dots check               verify machine
  ./dots update              update DOTS repo + reapply
  ./dots help                this help
  ./dots --version

Automation / expert scripts (still supported):
  ./bootstrap.sh   ./setup.sh   ./configure.sh
  ./scripts/pull_models.sh   ./scripts/check.sh
```

## `./bootstrap.sh`

```text
Usage: ./bootstrap.sh [options]

Onboard / refresh a machine using a declarative profile, then invoke setup.sh.

Options:
  --profile <name|path>  Builtin: base | home | work | server | all | current
                         Or a custom TOML path (absolute, relative, or ~/…)
  --with <list>          Add components/supergroups onto the profile baseline
  --without <list>       Remove components/supergroups from the effective set
  --show                 Print resolved components/packages/runtime and exit
  --dry-run              Preview (passed through to setup.sh; no mutations)
  --no-install           Resolve/verify only; do not install missing software
  --check-only           Run scripts/check.sh for the profile (no setup)
  --open-apps            After setup, open selected/installed apps (macOS GUI)
  --no-open              Never open apps (default)
  --pull-models          After setup, run scripts/pull_models.sh (explicit)
  --model-tier <tier>    Pass-through to pull_models when --pull-models is set
  -h, --help             Show this help

Selectors (--with / --without):
  Components:
    herdr        Herdr
    hermes       Hermes
    ollama       Ollama
    llamacpp     llama.cpp
    archify      Archify
    skills       Engineering skills
    ai-skills    AI skills
    drawthings   Draw Things
    opencode     OpenCode
    codex        Codex
    cursor       Cursor
    fluidvoice   FluidVoice
    images       Images toolkit
    tex          TeX
    mactools     macOS tools
  Supergroups:
    ai           AI applications — All supported AI applications for this platform

Happy paths:
  ./bootstrap.sh --profile home      # personal Mac (auto-provisions brew/python)
  ./bootstrap.sh --profile work      # employer Mac
  ./bootstrap.sh --profile server    # headless Linux
  ./bootstrap.sh --profile base      # minimal core
  ./bootstrap.sh --profile work --no-install   # managed hosts: fail if deps missing
  ./bootstrap.sh --profile work --with ai      # EXPLICIT opt-in: add AI apps
  ./bootstrap.sh --profile base --with ai --without cursor
  ./bootstrap.sh --profile home --with fluidvoice

Policy:
  Profiles are explicit authorization for THAT run.
  Binary presence alone never authorizes configuration.
  --with ai is explicit consent for every effective AI member on this platform.
  --without ai removes every AI-supergroup member (even if from the profile).
  Stage 0 auto-provisions Homebrew/Python via official channels when needed.
  --show / --dry-run never mutate.
  Large model downloads are never implied by ordinary bootstrap (use --pull-models
  or ./scripts/pull_models.sh explicitly).

See README.md for package groups, runtime policy, and local overrides.
```

## `./setup.sh`

```text
Usage: ./setup.sh [options]

Install / refresh dotfiles (idempotent). Safe to re-run.

Options:
  --with <list>     Comma-separated components and/or supergroups.
                    Components:
                      herdr        Herdr
                      hermes       Hermes
                      ollama       Ollama
                      llamacpp     llama.cpp
                      archify      Archify
                      skills       Engineering skills
                      ai-skills    AI skills
                      drawthings   Draw Things
                      opencode     OpenCode
                      codex        Codex
                      cursor       Cursor
                      fluidvoice   FluidVoice
                      images       Images toolkit
                      tex          TeX
                      mactools     macOS tools
                    Supergroups:
                      ai           AI applications — All supported AI applications for this platform
  --with=<list>     Same as --with <list>
  --dry-run         Preview actions without modifying the machine
  -h, --help        Show this help

Consent vs presence:
  A binary already on PATH does NOT authorize DOTS to configure it.
  AI client config runs only for components listed in --with this run.
  --with ai expands to every AI application supported on this machine and is
  explicit consent for those expanded members (same as listing each id).
  Prefer ./bootstrap.sh --profile {base,home,work,all|path.toml} for onboarding.
  Edit profiles with ./configure.sh (writes TOML only).

Examples:
  ./setup.sh
  ./setup.sh --with herdr
  ./setup.sh --with fluidvoice
  ./setup.sh --with mactools
  ./setup.sh --with herdr,hermes,mactools
  ./setup.sh --with ai
  ./setup.sh --with ai --without cursor
  ./setup.sh --with cursor
  ./setup.sh --with ai-skills
  ./setup.sh --with skills,ai-skills
  ./setup.sh --with hermes,skills,ai-skills
  ./setup.sh --with herdr,cursor
  ./setup.sh --with drawthings
  ./setup.sh --with hermes,drawthings
  ./setup.sh --with cursor,drawthings
  ./setup.sh --with skills
  ./setup.sh --with images,tex
  ./setup.sh --dry-run --with ai
  ./bootstrap.sh --profile home
  ./bootstrap.sh --profile work --with ai
  ./configure.sh --help

Default ./setup.sh installs core shell UX (fnm, Starship, Nerd Font, Neovim,
terminal-notifier) but does NOT install AI tools, agent skills, or models.

Environment (runtime shells, not installer):
  DOTS_MULTIPLEXER=tmux|herdr|none   (default: tmux)
  DOTS_AUTO_TMUX=0                   disable auto tmux (compat)
  DOTS_PROMPT_STATS=1                enable prompt dir stats (legacy)
  DOTS_GREETING=0                    silence fortune greeting
  DOTS_HERMES_NOTIFY_THRESHOLD=60    Hermes notify min session seconds
```

## `./configure.sh`

```text
Usage: ./configure.sh [options]

Create or edit a bootstrap profile TOML. Never installs packages or mutates AI configs.

Preferred customization: extend a builtin preset into ~/.config/dots/profiles/.

Options:
  --output <path>       Write profile TOML to this path
  --extends <name|path> Inherit from a builtin/custom profile (writes extends=)
  --from <name|path>    Clone resolved components from a profile (no extends=)
  --with <list>         Components to include (CSV)
  --without <list>      Components to exclude (CSV)
  --packages-add <list> Package groups to add (CSV)
  --packages-remove <l> Package groups to remove (CSV)
  --multiplexer <m>     Runtime multiplexer: tmux|herdr|none
  --name <name>         Profile name field (default: output basename)
  --description <t>     Profile description
  --force               Overwrite existing output without prompting
  --show <name|path>    Show resolved profile and exit
  -h, --help            Show this help

Examples:
  ./configure.sh --extends server --output ~/.config/dots/profiles/bertha.toml \
    --name bertha --packages-add infra --multiplexer herdr
  ./configure.sh --extends work --output ~/.config/dots/profiles/corp-work.toml \
    --with images --packages-add infra
  ./configure.sh --extends home --output ~/.config/dots/profiles/home-studio.toml \
    --without cursor --multiplexer tmux
  ./configure.sh --show ~/.config/dots/profiles/bertha.toml
```

## `./scripts/check.sh`

```text
Usage: /Users/joshuagrant/dots/scripts/check.sh [--profile base|home|work|server|all|current|/path/to/profile.toml]
```

## `./scripts/pull_models.sh`

```text
Usage: ./scripts/pull_models.sh [options]

Select and download local models according to hardware + configs/models.toml.
Bootstrap/setup do NOT pull large models by default.

Options:
  --list              Show hardware, tier, plan, and local status (no mutations)
  --dry-run           Print actions without downloading / starting services
  --yes               Skip confirmation prompts
  --tier <name>       minimal|balanced|large|max|auto (default: auto)
  --provider <name>   ollama|llamacpp|drawthings|fluidvoice|all (repeatable)
  --model <id>        Registry model id (repeatable)
  --update            Re-pull registry targets even if present
  --include-cleanup   Include optional Fluid-1 cleanup model
  -h, --help          Show this help

Examples:
  ./scripts/pull_models.sh --list
  ./scripts/pull_models.sh --dry-run
  ./scripts/pull_models.sh --provider ollama --tier balanced
  ./scripts/pull_models.sh --yes

User overrides: ~/.config/dots/models.toml
```

## `./dots packages`

```text
Usage:
  ./dots packages              interactive menu (TTY) or status
  ./dots packages status       full ownership report (read-only)
  ./dots packages outdated     outdated managed packages
  ./dots packages upgrade      upgrade packages in the resolved desired set
  ./dots packages upgrade --all
                               also upgrade undeclared Homebrew packages (opt-in)
  ./dots packages adopt NAME [--group G|--component C] [--cask]
                               print suggested Brewfile declaration (no auto-edit)

Ownership vocabulary:
  managed     declared by resolved DOTS config + package-manager owned
  missing     declared but absent
  outdated    declared, managed, update available
  external    declared; app exists outside Homebrew ownership
  undeclared  installed (leaves/casks) but not in resolved desired set

DOTS never runs brew bundle cleanup or uninstalls undeclared software.
```

## `./dots profile`

```text
════════════════════════════════════════
 Profiles
════════════════════════════════════════

Profiles:
  1) Show active
  2) Create (configure.sh)
  3) Preview resolved (--show)
  4) Switch / reapply (bootstrap)
  5) Back
Error: unknown profile 'n' (missing /Users/joshuagrant/dots/configs/bootstrap/profiles/n.toml)
Available builtins:
all
base
home
server
work
Or pass a custom TOML path: --profile /var/folders/p9/3qj56rnn6ns8gjh15jkzsg8h0000gn/T/tmp.FZertC1rSb/.config/dots/profiles/name.toml
```

## `./dots models`

```text
════════════════════════════════════════
 Models
════════════════════════════════════════
Machine:
  Apple M2
  OS: darwin  arch: arm64
  RAM: 24 GB
  free disk: 135 GB
=== DOTS local models ===
Machine:
  Apple M2
  OS: darwin  arch: arm64
  RAM: 24 GB
  free disk: 135 GB
  selected tier: balanced

Installed providers:
  ollama
  llamacpp
  drawthings
  fluidvoice

Plan:
  ollama       qwen2.5:7b                           ~4.7 GB  [general]

Expected catalog footprint: ~4.7 GB
Estimated additional download: ~4.7 GB
Free disk: 135 GB (reserve 20 GB)


Models:
  1) Show model plan (--list)
  2) Pull recommended missing models
  3) Choose provider
  4) Choose tier + pull
  5) Update to registry targets (--update)
  6) Edit model policy file
  7) Back

Provider:
  1) ollama
  2) llamacpp
  3) drawthings
  4) fluidvoice
  5) all
Enter a number 1-5
Enter a number 1-5
Enter a number 1-5
Enter a number 1-5
Enter a number 1-5
Enter a number 1-5
Enter a number 1-5
Enter a number 1-5
Enter a number 1-5
Enter a number 1-5
```

## `./dots backup`

```text
Usage: ./dots backup [--name NAME] | ./dots backup import-legacy
```

## `./dots restore`

```text
Usage: ./dots restore [snapshot-id] [--dry-run] [--yes]
```

