# AI inference server (`ai-server`)

For local inventory and Draw Things / Ollama / llama.cpp workflows that do **not**
require this stack, see [Local models](local-models.md).

Opt-in server stack: **Open WebUI** (browser) → **llama-server** (OpenAI-compatible API) → **GGUF models**.

Workstation tools (`ollama`, `hermes`, …) stay separate. Enable with:

```bash
./bootstrap.sh --profile server --with ai-server
# or
./setup.sh --with ai-server
```

Setup installs Docker CLI packages (Homebrew path), seeds `~/.config/dots/ai-server.toml`, creates runtime directories, and renders a Compose project under `~/.config/dots/ai-server/`. It does **not** download models or container images beyond normal Docker behavior on `dots ai up`.

## Architecture

```text
Browser
   |
   |  host :webui_port (default 3000)
   v
Open WebUI (container)
   |
   |  http://llama:8080/v1  (internal network)
   v
llama-server (container)
   |
   v
{runtime_root}/models/*.gguf
```

Defaults:

| Item | Linux | macOS |
|------|-------|-------|
| Runtime root | `/srv/ai` | `~/srv/ai` |
| Models | `{runtime_root}/models` | same |
| WebUI data | `{runtime_root}/open-webui` | same |
| Machine config | `~/.config/dots/ai-server.toml` | same |

Backends (`ai_server.backend`): `cpu`, `cuda`, `rocm`, `vulkan`, `intel`, `native` (native is diagnostic-only in v1; use Docker backends for `dots ai up`).

## CLI

```bash
dots ai --help
./dots models discover
./dots models discover --verbose
./dots models discover --json
dots ai doctor
dots ai models          # managed GGUF in models_dir only
dots ai model adopt ~/path/to/model.gguf
dots ai model adopt --copy ~/path/to/model.gguf
dots ai model add ./MyModel.gguf
dots ai model add hf://owner/repo/model-Q4_K_M.gguf
dots ai model default model-Q4_K_M.gguf
dots ai up
dots ai status
dots ai logs
dots ai logs llama
dots ai down
```

### Managed vs discovered

| Command | Meaning |
|---------|---------|
| `./dots models discover` | Read-only scan of known stores (models_dir when ai-server enabled, configured paths, HF cache, Ollama, Draw Things, conventions). |
| `dots ai models` | GGUF files **managed** under `models_dir` (including adopted symlinks). |

`default_model` must be a **basename present in `models_dir`**. Adopt compatible GGUF from elsewhere before setting default:

```bash
./dots models discover
dots ai model adopt ~/somewhere/Qwen3-14B-Q4_K_M.gguf
dots ai model default Qwen3-14B-Q4_K_M.gguf
dots ai doctor
dots ai up
```

Ollama models appear in `discover` as backend `ollama` and are **not** directly usable by llama-server unless you have a separate GGUF file to adopt.

Custom discovery roots:

```toml
[ai_server.discovery]
paths = ["/mnt/models", "/data/gguf"]
```

`dots ai down` stops containers and does **not** delete models or WebUI volumes/data directories.

## Configuration example

`~/.config/dots/ai-server.toml` (seeded from `configs/ai-server/defaults.toml`):

```toml
[ai_server]
backend = "cpu"
runtime_root = "/srv/ai"
default_model = "qwen3-14b-q4_k_m.gguf"
webui_port = 3000
context_size = 8192
gpu_layers = 0

[ai_server.llama]
extra_args = []
```

## Security and networking

- Open WebUI publishes the configured host port.
- llama-server is **not** host-published by default (`publish_llama = false`).
- No firewall or TLS changes; use a reverse proxy and authentication on untrusted networks.
- First Open WebUI launch creates the admin account in local application data under `{runtime_root}/open-webui`.

## CUDA (outline)

1. Install NVIDIA drivers and [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html).
2. Set `backend = "cuda"` in `ai-server.toml`.
3. `dots ai doctor` should report NVIDIA runtime visibility.
4. `dots ai up` uses the CUDA llama.cpp image with GPU reservations.

## Persistence and removal

| Action | Models | WebUI state | Config |
|--------|--------|-------------|--------|
| `dots ai down` | kept | kept | kept |
| Re-run setup `--with ai-server` | kept | kept | kept (config not overwritten) |
| Delete models | manual `dots ai model remove` | — | — |
| Remove stack config | remove `~/.config/dots/ai-server/` | — | remove `ai-server.toml` |

## Troubleshooting

- **No default model**: `dots ai model default <file.gguf>` after adding a GGUF.
- **Docker missing on Linux**: install `docker.io` / Compose v2; re-run doctor.
- **Health vs running**: `dots ai status` distinguishes container state and HTTP health.

See also: [maintainers recon](../maintainers/ai-server-recon.md).
