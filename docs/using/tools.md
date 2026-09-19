# Tools catalog

Conceptual tools DOTS cares about — not every transitive package. Upstream links
are documentation only; CI does **not** fetch them.

| Tool | Role in DOTS | Installed by | Platforms | Upstream |
|------|--------------|--------------|-----------|----------|
| Homebrew | Primary package manager on macOS / Linuxbrew | Stage 0 official installer | darwin, linux | https://brew.sh |
| fnm | Node version manager (Node policy) | group Brewfiles / `configs/node/default.toml` | darwin, linux | https://github.com/Schniz/fnm |
| Neovim | Default editor (`EDITOR`/`VISUAL`) | package groups | darwin, linux | https://neovim.io |
| Starship | Cross-shell prompt | package groups | darwin, linux | https://starship.rs |
| Herdr | Terminal multiplexer / session orchestrator | `--with herdr` / profiles | darwin, linux | https://herdr.dev |
| Hermes | Local/cloud agent CLI (+ macOS desktop) | `--with hermes` | darwin, linux | https://github.com/NousResearch/hermes-agent |
| Ollama | Local LLM runtime (no auto model pull) | `--with ollama` | darwin, linux | https://ollama.com |
| llama.cpp | Local GGUF runtime via Homebrew | `--with llamacpp` | darwin, linux | https://github.com/ggml-org/llama.cpp |
| Archify | Architecture diagram skill | `--with archify` / skills pack | darwin, linux | https://github.com/tt-a1i/archify |
| OpenCode | Local/general coding adapter | `--with opencode` | darwin, linux | https://github.com/sst/opencode |
| Codex | Frontier coding (Homebrew cask) | `--with codex` | darwin | https://github.com/openai/codex |
| Cursor | Cursor Agent CLI (`agent`) | `--with cursor` | darwin | https://cursor.com |
| Draw Things | Local image generation CLI + MCP | `--with drawthings` | darwin, linux | https://drawthings.ai |
| FluidVoice | Local voice-to-text (macOS 15+) | `--with fluidvoice` | darwin | https://github.com/altic-dev/FluidVoice |
| Vorssaint | macOS control-plane companion | `--with mactools` | darwin | https://vorssaint.com |
| Raycast | Launcher / automation | `--with mactools` | darwin | https://www.raycast.com |
| Keyboard Maestro | macOS macro automation | `--with mactools` | darwin | https://www.keyboardmaestro.com |
| Hazel | Folder automation | `--with mactools` | darwin | https://www.noodlesoft.com |
| Little Snitch | Network connection alert / firewall | `--with mactools` | darwin | https://www.obdev.at/products/littlesnitch/ |
| OrbStack | Containers / VMs (additive to Docker) | `--with mactools` | darwin | https://orbstack.dev |
| Hookmark | Link notes to anything | `--with mactools` | darwin | https://hookproductivity.com |
| DEVONthink | Personal knowledge base | `--with mactools` | darwin | https://www.devontechnologies.com/apps/devonthink |
| Ghostty | Terminal emulator config linked | `--with mactools` / links | darwin | https://ghostty.org |
| Zed | Editor cask | `--with mactools` | darwin | https://zed.dev |
| Loopback | Virtual audio devices | `--with mactools` | darwin | https://rogueamoeba.com/loopback/ |
| Audio Hijack | Audio capture / routing | `--with mactools` | darwin | https://rogueamoeba.com/audiohijack/ |
| BlackHole | Virtual audio loopback | `--with mactools` | darwin | https://existential.audio/blackhole/ |
| VCV Rack | Modular synthesis | `--with mactools` | darwin | https://vcvrack.com |
| OBS | Streaming / recording | `--with mactools` | darwin | https://obsproject.com |
| TouchDesigner | Visual programming / media | `--with mactools` | darwin | https://derivative.ca |
| Processing | Creative coding IDE | `--with mactools` | darwin | https://processing.org |
| Sonic Pi | Live coding music | `--with mactools` | darwin | https://sonic-pi.net |
| SuperCollider | Audio synthesis platform | `--with mactools` | darwin | https://supercollider.github.io |
| Yazi | Terminal file manager (additive) | links + mactools tooling | darwin, linux | https://yazi-rs.github.io |
| Ranger | Terminal file manager | workstation group | darwin, linux | https://ranger.github.io |
| mise | Polyglot runtime manager (migration path) | linked config; see MISE migration | darwin, linux | https://mise.jdx.dev |
| lazygit | TUI for git | modern group / mactools notes | darwin, linux | https://github.com/jesseduffield/lazygit |
| atuin | Shell history sync | modern group | darwin, linux | https://atuin.sh |
| direnv | Per-directory env | modern group | darwin, linux | https://direnv.net |
| fzf | Fuzzy finder | core group | darwin, linux | https://github.com/junegunn/fzf |
| ripgrep | Fast search | core group | darwin, linux | https://github.com/BurntSushi/ripgrep |
| bat | Syntax-aware `cat` | modern group | darwin, linux | https://github.com/sharkdp/bat |
| zoxide | Smarter `cd` | modern group | darwin, linux | https://github.com/ajeetdsouza/zoxide |
| uv | Python packaging / tooling | modern group | darwin, linux | https://github.com/astral-sh/uv |
| jq | JSON CLI | core group | darwin, linux | https://jqlang.github.io/jq/ |
| tmux | Terminal multiplexer (baseline) | core group / profiles | darwin, linux | https://github.com/tmux/tmux |

Ownership paths: [Architecture](../concepts/architecture.md). How to extend:
[Extending](extending.md). macOS layer detail: [mactools](../macos/mactools.md).
Agent stack: [Agent harness](../agents/harness.md).
