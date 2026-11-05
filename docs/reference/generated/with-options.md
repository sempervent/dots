<!--
GENERATED — DO NOT EDIT.
Source: configs/components.toml + brew/Brewfile.* + configs/skills/manifest.toml
Generator: scripts/docs/generate_reference.py
-->

# `--with` options (generated)

Registry-driven reference for optional components and supergroups. Do not invent ids beyond `configs/components.toml`. Human guide: [Components and `--with`](../../using/components.md).

## Supergroups

| id | label | members | description |
| --- | --- | --- | --- |
| `ai` | AI applications | `hermes`, `ollama`, `llamacpp`, `drawthings`, `opencode`, `codex`, `cursor`, `fluidvoice`, `lsp`, `pi`, `litellm`, `agent-sandbox`, `openrig` | Local runtimes, coding agents, and the LSP toolchain for this platform |

## Components

### `herdr`

Terminal multiplexer (Brewfile.herdr)

- **label:** Herdr
- **category:** multiplexer
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.herdr`
- **formulae:** `herdr`
- **activate:** `./dots setup --with herdr`

### `hermes`

Hermes agent CLI (+ macOS hermes-desktop)

- **label:** Hermes
- **category:** ai_client
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.hermes`
- **formulae:** `hermes-agent`
- **activate:** `./dots setup --with hermes`

### `ollama`

Local LLM runtime (no models pulled)

- **label:** Ollama
- **category:** ai_runtime
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.ollama`
- **formulae:** `ollama`
- **activate:** `./dots setup --with ollama`

### `llamacpp`

llama.cpp runtime (Homebrew; models via pull_models.sh)

- **label:** llama.cpp
- **category:** ai_runtime
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.llamacpp`
- **formulae:** `llama.cpp`
- **activate:** `./dots setup --with llamacpp`

### `archify`

Archify skill only (also included in --with skills)

- **label:** Archify
- **category:** skills
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.archify`
- **omit_from_all:** yes
- **note:** Archify skill only; shared `brew/Brewfile.archify` with `skills` / `ai-skills`
- **activate:** `./dots setup --with archify`

### `skills`

Curated engineering skill pack (includes Archify)

- **label:** Engineering skills
- **category:** skills
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.archify`
- **skills:** `skill-security-review`, `systematic-debugging`, `verification-methodology`, `implementation-planning`, `spec-driven-development`, `software-architecture`, `software-architecture-analysis`, `secure-software-engineering`, `technical-documentation`, `adr-authoring`, `cli-builder`, `docker-compose`, `kubernetes`, `terraform`, `release-engineering`, `playwright`, `archify`
- **pack:** Engineering pack (reproducible, security-reviewed)
- **activate:** `./dots setup --with skills`

### `ai-skills`

Curated AI/agent engineering skill pack

- **label:** AI skills
- **category:** skills
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.archify`
- **skills:** `skill-security-review`, `agent-evals-and-observability`, `agent-production-operations`, `litellm`, `ml-engineering`, `workflow-architect`, `capacity-and-cost-engineering`, `privacy-engineering`, `product-analytics-and-measurement`, `telemetry`
- **pack:** AI/agent engineering pack for operating and evaluating the harness
- **activate:** `./dots setup --with ai-skills`

### `drawthings`

Draw Things CLI + MCP bridge + img (GUI/models are macOS-oriented)

- **label:** Draw Things
- **category:** image_ai
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.drawthings`
- **formulae:** `drawthingsai/draw-things/draw-things-cli`
- **activate:** `./dots setup --with drawthings`

### `opencode`

Local/general coding adapter

- **label:** OpenCode
- **category:** ai_client
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.opencode`
- **formulae:** `opencode`
- **activate:** `./dots setup --with opencode`

### `codex`

Frontier coding via Homebrew cask Codex

- **label:** Codex
- **category:** ai_client
- **platforms:** darwin
- **brewfile:** `brew/Brewfile.codex`
- **casks:** `codex`
- **activate:** `./dots setup --with codex`

### `cursor`

Cursor Agent CLI (explicit opt-in)

- **label:** Cursor
- **category:** ai_client
- **platforms:** darwin
- **brewfile:** `brew/Brewfile.cursor`
- **casks:** `cursor-cli`
- **activate:** `./dots setup --with cursor`

### `fluidvoice`

Local voice-to-text dictation app with optional AI enhancement

- **label:** FluidVoice
- **category:** voice_ai
- **platforms:** darwin
- **brewfile:** `brew/Brewfile.fluidvoice`
- **casks:** `fluidvoice`
- **activate:** `./dots setup --with fluidvoice`

### `images`

Deterministic image toolkit (Magick, etc.)

- **label:** Images toolkit
- **category:** media
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.images`
- **formulae:** `imagemagick`, `ghostscript`, `librsvg`, `exiftool`, `pngquant`, `webp`, `oxipng`
- **activate:** `./dots setup --with images`

### `tex`

Homebrew TeX Live (CLI)

- **label:** TeX
- **category:** docs
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.tex`
- **formulae:** `texlive`
- **activate:** `./dots setup --with tex`

### `mactools`

Optional macOS workstation layer (Vorssaint + automation/audio/CLI; Brewfile.mactools)

- **label:** macOS tools
- **category:** workstation
- **platforms:** darwin
- **brewfile:** `brew/Brewfile.mactools`
- **omit_from_all:** yes
- **formulae:** `mise`, `yazi`, `watchexec`, `hyperfine`, `mprocs`, `xh`, `dust`, `duf`, `diskbloom`
- **casks:** `vorssaint`, `raycast`, `keyboard-maestro`, `hazel`, `little-snitch`, `hookmark`, `devonthink`, `ghostty`, `zed`, `loopback`, `audio-hijack`, `blackhole-2ch`, `vcv-rack`, `obs`, `touchdesigner`, `processing`, `sonic-pi`, `supercollider`, `qgis`, `grandperspective`, `midi-monitor`, `secretive`, `bruno`, `proxyman`
- **activate:** `./dots setup --with mactools`

### `orbstack`

Optional Darwin Docker-compatible runtime (install-only; never auto-start or remove Docker Desktop)

- **label:** OrbStack
- **category:** containers
- **platforms:** darwin
- **brewfile:** `brew/Brewfile.orbstack`
- **omit_from_all:** yes
- **casks:** `orbstack`
- **activate:** `./dots setup --with orbstack`

### `mitmproxy`

Opt-in HTTP interception CLIs (install-only; never start proxy, trust CA, or change system proxy)

- **label:** mitmproxy
- **category:** network
- **platforms:** darwin
- **brewfile:** `brew/Brewfile.mitmproxy`
- **omit_from_all:** yes
- **casks:** `mitmproxy`
- **activate:** `./dots setup --with mitmproxy`

### `syncthing`

Opt-in peer sync client (install-only; never start daemon, pair devices, or create folders)

- **label:** Syncthing
- **category:** backup
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.syncthing`
- **omit_from_all:** yes
- **formulae:** `syncthing`
- **activate:** `./dots setup --with syncthing`

### `lsp`

Language servers for DOTS development/editor workflows

- **label:** Language servers
- **category:** developer_tooling
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.lsp`
- **formulae:** `rust-analyzer`, `basedpyright`, `gopls`, `bash-language-server`, `yaml-language-server`, `vscode-langservers-extracted`, `lua-language-server`, `markdown-oxide`, `taplo`, `terraform-ls`, `dockerfile-language-server`, `r`
- **activate:** `./dots setup --with lsp`

### `ai-server`

Server stack: llama.cpp (llama-server) + Open WebUI via Docker Compose (opt-in models)

- **label:** AI inference server
- **category:** ai_runtime
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.ai-server`
- **omit_from_all:** yes
- **formulae:** `docker`, `docker-compose`
- **activate:** `./dots setup --with ai-server`

### `pi`

Programmable coding-agent runtime for DOTS local-first agent orchestration (npm; Node ≥22.19)

- **label:** Pi Coding Agent
- **category:** ai_client
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.pi`
- **activate:** `./dots setup --with pi`

### `litellm`

Unified model gateway for local and remote agent inference (localhost Compose; OpenRouter via env)

- **label:** LiteLLM Gateway
- **category:** ai_gateway
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.litellm`
- **activate:** `./dots setup --with litellm`

### `agent-sandbox`

Filesystem/network policy and OS-level command sandbox for DOTS agents (provider: pi-sandbox)

- **label:** Agent Sandbox
- **category:** agent_security
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.agent-sandbox`
- **formulae:** `ripgrep`
- **activate:** `./dots setup --with agent-sandbox`

### `openrig`

Persistent multi-agent orchestration for Pi, Codex and other coding runtimes (npm @openrig/cli; Node ≥22)

- **label:** OpenRig
- **category:** agent_orchestration
- **platforms:** darwin, linux
- **brewfile:** `brew/Brewfile.openrig`
- **formulae:** `fnm`, `tmux`
- **activate:** `./dots setup --with openrig`

