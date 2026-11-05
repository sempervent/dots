<!--
GENERATED — DO NOT EDIT.
Source: configs/components.toml
Generator: scripts/docs/generate_reference.py
-->

# Components (generated)

Authoritative registry: `configs/components.toml`.

| id | label | category | platforms | brewfile | omit_from_all | description |
| --- | --- | --- | --- | --- | --- | --- |
| herdr | Herdr | multiplexer | darwin, linux | brew/Brewfile.herdr | no | Terminal multiplexer (Brewfile.herdr) |
| hermes | Hermes | ai_client | darwin, linux | brew/Brewfile.hermes | no | Hermes agent CLI (+ macOS hermes-desktop) |
| ollama | Ollama | ai_runtime | darwin, linux | brew/Brewfile.ollama | no | Local LLM runtime (no models pulled) |
| llamacpp | llama.cpp | ai_runtime | darwin, linux | brew/Brewfile.llamacpp | no | llama.cpp runtime (Homebrew; models via pull_models.sh) |
| archify | Archify | skills | darwin, linux | brew/Brewfile.archify | yes | Archify skill only (also included in --with skills) |
| skills | Engineering skills | skills | darwin, linux | brew/Brewfile.archify | no | Curated engineering skill pack (includes Archify) |
| ai-skills | AI skills | skills | darwin, linux | brew/Brewfile.archify | no | Curated AI/agent engineering skill pack |
| drawthings | Draw Things | image_ai | darwin, linux | brew/Brewfile.drawthings | no | Draw Things CLI + MCP bridge + img (GUI/models are macOS-oriented) |
| opencode | OpenCode | ai_client | darwin, linux | brew/Brewfile.opencode | no | Local/general coding adapter |
| codex | Codex | ai_client | darwin | brew/Brewfile.codex | no | Frontier coding via Homebrew cask Codex |
| cursor | Cursor | ai_client | darwin | brew/Brewfile.cursor | no | Cursor Agent CLI (explicit opt-in) |
| fluidvoice | FluidVoice | voice_ai | darwin | brew/Brewfile.fluidvoice | no | Local voice-to-text dictation app with optional AI enhancement |
| images | Images toolkit | media | darwin, linux | brew/Brewfile.images | no | Deterministic image toolkit (Magick, etc.) |
| tex | TeX | docs | darwin, linux | brew/Brewfile.tex | no | Homebrew TeX Live (CLI) |
| mactools | macOS tools | workstation | darwin | brew/Brewfile.mactools | yes | Optional macOS workstation layer (Vorssaint, f.lux, automation/audio/CLI; Brewfile.mactools) |
| orbstack | OrbStack | containers | darwin | brew/Brewfile.orbstack | yes | Optional Darwin Docker-compatible runtime (install-only; never auto-start or remove Docker Desktop) |
| davinci-resolve | DaVinci Resolve | media | darwin | brew/Brewfile.davinci-resolve | yes | Optional professional NLE via Mac App Store (mas; install-only; never launch, scan media, or require App Store auth globally) |
| mitmproxy | mitmproxy | network | darwin | brew/Brewfile.mitmproxy | yes | Opt-in HTTP interception CLIs (install-only; never start proxy, trust CA, or change system proxy) |
| syncthing | Syncthing | backup | darwin, linux | brew/Brewfile.syncthing | yes | Opt-in peer sync client (install-only; never start daemon, pair devices, or create folders) |
| lsp | Language servers | developer_tooling | darwin, linux | brew/Brewfile.lsp | no | Language servers for DOTS development/editor workflows |
| ai-server | AI inference server | ai_runtime | darwin, linux | brew/Brewfile.ai-server | yes | Server stack: llama.cpp (llama-server) + Open WebUI via Docker Compose (opt-in models) |
| pi | Pi Coding Agent | ai_client | darwin, linux | brew/Brewfile.pi | no | Programmable coding-agent runtime for DOTS local-first agent orchestration (npm; Node ≥22.19) |
| litellm | LiteLLM Gateway | ai_gateway | darwin, linux | brew/Brewfile.litellm | no | Unified model gateway for local and remote agent inference (localhost Compose; OpenRouter via env) |
| agent-sandbox | Agent Sandbox | agent_security | darwin, linux | brew/Brewfile.agent-sandbox | no | Filesystem/network policy and OS-level command sandbox for DOTS agents (provider: pi-sandbox) |
| openrig | OpenRig | agent_orchestration | darwin, linux | brew/Brewfile.openrig | no | Persistent multi-agent orchestration for Pi, Codex and other coding runtimes (npm @openrig/cli; Node ≥22) |
