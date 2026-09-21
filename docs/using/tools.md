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
| act | Run GitHub Actions locally | `dev` group | darwin, linux | https://github.com/nektos/act |
| difftastic | Syntax-aware diff (`difft`) | `dev` group (opt-in Git config) | darwin, linux | https://difftastic.wilfred.me.uk |
| mergiraf | Syntax-aware merge driver | `dev` group (opt-in Git config) | darwin, linux | https://mergiraf.org |
| gitleaks | Secrets scanning | `security` group | darwin, linux | https://github.com/gitleaks/gitleaks |
| trivy | Vulnerability / misconfig scanner | `security` group | darwin, linux | https://trivy.dev |
| age / sops | File encryption / secrets editor | `security` group | darwin, linux | https://age-encryption.org |
| cosign | Sigstore signing / verify | `security` group | darwin, linux | https://github.com/sigstore/cosign |
| tailscale | Mesh VPN CLI (install-only; no `up`) | `network` group | darwin, linux | https://tailscale.com |
| mosh | Roaming remote shell | `network` group | darwin, linux | https://mosh.org |
| rclone | Cloud storage sync | `network` group | darwin, linux | https://rclone.org |
| doggo | Human-friendly DNS client | `network` group | darwin, linux | https://github.com/mr-karan/doggo |
| duckdb | In-process analytical SQL | `data` group | darwin, linux | https://duckdb.org |
| miller | Name-indexed CSV/TSV/JSON CLI | `data` group | darwin, linux | https://miller.readthedocs.io |
| visidata | Terminal spreadsheet multitool | `data` group | darwin, linux | https://www.visidata.org |
| gdal | Geospatial data library / CLIs | `geo` group | darwin, linux | https://gdal.org |
| tippecanoe | Vector tile builder | `geo` group | darwin, linux | https://github.com/felt/tippecanoe |
| pmtiles | PMTiles archive CLI | `geo` group | darwin, linux | https://github.com/protomaps/go-pmtiles |
| QGIS | Desktop GIS | `--with mactools` | darwin | https://qgis.org |
| GrandPerspective | Disk usage treemap | `--with mactools` | darwin | https://grandperspectiv.sourceforge.net |
| MIDI Monitor | MIDI signal inspector | `--with mactools` | darwin | https://www.snoize.com/MIDIMonitor/ |

### Opt-in notes (not configured by DOTS)

```bash
# difftastic as Git external diff (per-repo)
git config diff.external difft

# mergiraf as a merge driver (per-repo; see mergiraf docs for full driver line)
git config merge.mergiraf.name mergiraf

# example CLIs after install
act -l
gitleaks detect --source .
trivy fs .
age-keygen -o key.txt
duckdb -c "SELECT 42"
mlr --csv head -n 5 data.csv
doggo example.com
gdalinfo --version
pmtiles show map.pmtiles
```

`mitmproxy` is known but **not** in default `network` membership (opt-in later).

Ownership paths: [Architecture](../concepts/architecture.md). How to extend:
[Extending](extending.md). macOS layer detail: [mactools](../macos/mactools.md).
Agent stack: [Agent harness](../agents/harness.md).
