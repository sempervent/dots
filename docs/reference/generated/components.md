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
| mactools | macOS tools | workstation | darwin | brew/Brewfile.mactools | yes | Optional macOS workstation layer (Vorssaint + automation/audio/CLI; Brewfile.mactools) |
| lsp | Language servers | developer_tooling | darwin, linux | brew/Brewfile.lsp | no | Language servers for DOTS development/editor workflows |
