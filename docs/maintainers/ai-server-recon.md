# AI server (`ai-server`) — reconnaissance (2026-03)

Starting point for the `feat/ai-server` work.

## Repository snapshot (start)

| Item | Value |
|------|--------|
| Branch | `feat/ai-server` (from `feat/lsp-toolchain` @ `41f134c`) |
| Working tree | clean at branch creation |

## Where `ai-server` belongs

```text
configs/components.toml          optional component id + brewfile
configs/ai-server/               declarative defaults, compose template, backend registry
brew/Brewfile.ai-server          Docker CLI (Homebrew path)
helpers/ai_server.sh             validate, render compose, lifecycle, models, doctor
~/.config/dots/ai-server.toml    machine config (seeded once on setup)
~/.config/dots/ai-server/        generated compose + .env (outside git)
/srv/ai/ (Linux default)         mutable runtime root (models, WebUI data, state)
./dots ai …                      user-facing lifecycle (not the `ai` supergroup)
setup.sh --with ai-server        idempotent provisioning hook
```

The **`ai` supergroup** remains workstation-oriented (Hermes, Ollama, LSP, …).  
**`ai-server`** is a separate optional component for headless/server inference (Compose + Open WebUI + llama.cpp). It is **not** a member of `--with ai` unless explicitly added later.

## Declarative vs runtime state

| Kind | Location | Git |
|------|----------|-----|
| Component registry | `configs/components.toml` | tracked |
| Backend/image defaults | `configs/ai-server/backends.toml` | tracked |
| Compose template | `configs/ai-server/compose.template.yml` | tracked |
| Shipped defaults | `configs/ai-server/defaults.toml` | tracked |
| Machine config | `~/.config/dots/ai-server.toml` | **never** |
| Generated compose/env | `~/.config/dots/ai-server/` | **never** |
| GGUF models | `{runtime_root}/models/` | **never** |
| Open WebUI DB/state | `{runtime_root}/open-webui/` | **never** |
| Docker engine volumes | engine-managed | **never** |

Contract: **known** (registry) ≠ **selected** (`--with`) ≠ **installed** (packages) ≠ **configured** (toml on disk) ≠ **running** (containers).

## Root cause: `dots ai models` visibility (2026-03 follow-up)

Initial v1 listed only `find models_dir -maxdepth 1 '*.gguf'`. DOTS model pulls (`scripts/pull_models.sh`) install into **Ollama blob storage**, **Hugging Face / llama.cpp caches**, and other provider-specific paths—not necessarily `{runtime_root}/models`. Hence previously installed models were **discovered nowhere** by `dots ai models`.

Fix: unified read-only inventory in `scripts/ai_model_inventory.py` (`dots ai discover`); `dots ai models` shows **managed** GGUF under `models_dir` and points to discover/adopt for elsewhere.

## Deliberately outside DOTS

- Automatic multi‑GB model downloads during `./setup` or `./bootstrap`
- Public exposure of `llama-server` (internal Compose network by default)
- Host firewall / TLS / reverse proxy / Tailscale auth
- Kubernetes, multi-node scheduling, RAG/vector DBs
- Replacing or conflating Ollama/Hermes workstation flows

## Existing patterns reused

- Optional components: `lsp` (registry + helper + setup phase + `dots lsp`)
- TOML: `helpers/toml.sh` + Python `tomllib`
- State paths: `helpers/state.sh` (`~/.config/dots`, `~/.local/state/dots`)
- Tests: `scripts/tests/*_test.sh`, registered in `scripts/ci/test.sh`
- ShellCheck: `scripts/ci/lint.sh`

## CLI entrypoints

- Human CLI: `./dots` → `dots_cmd_*` dispatch
- Setup: `./setup.sh` / `./bootstrap.sh --profile server --with ai-server`
- No in-repo Compose projects before this feature; `shell/functions.sh` wraps `docker compose` for interactive use only
