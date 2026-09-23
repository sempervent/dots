# Local models (discover, pull, image)

DOTS separates three ideas:

| Action | Command | Requires ai-server? |
|--------|---------|---------------------|
| **Inventory** (read-only) | `./dots models discover` | No |
| **Install / pull** | `./dots models` or `./scripts/pull_models.sh` | No |
| **Compose inference server** | `./setup.sh --with ai-server`, then `dots ai …` | Yes |

Registry and tiers: `configs/models.toml` in the repo and the
[generated models table](../reference/generated/models.md).

## Discover

Works on any machine with Python 3.11+ (same as other DOTS helpers). It scans
convention paths, Hugging Face cache, Ollama, llama.cpp cache listing, Draw
Things checkpoints, and—when configured—the ai-server `models_dir`.

```bash
./dots models discover
./dots models discover --verbose
./dots models discover --json
```

Managed GGUF for the Docker stack is listed separately:

```bash
dots ai models          # requires ai-server.toml
```

## Ollama and llama.cpp

Enable runtimes with setup, then pull from the registry:

```bash
./setup.sh --with ollama,llamacpp
./dots models
# or
./scripts/pull_models.sh --provider ollama --tier auto
./scripts/pull_models.sh --provider llamacpp --tier balanced --yes
```

Verify with `./dots models discover`.

## Draw Things and `img`

Image generation uses **Draw Things** via `draw-things-cli` (macOS-oriented).

1. Install the component:

   ```bash
   ./setup.sh --with drawthings
   ```

2. Confirm the CLI:

   ```bash
   command -v draw-things-cli
   draw-things-cli models list --downloaded-only --offline
   ```

3. **Download a checkpoint** (explicit opt-in; `img` does not pull for you):

   ```bash
   ./scripts/pull_models.sh --provider drawthings --tier balanced --yes
   # or
   draw-things-cli models ensure --model flux_2_klein_4b_q6p.ckpt
   ```

   Example ids live in [generated models](../reference/generated/models.md).

4. Discover or list:

   ```bash
   ./dots models discover
   ```

5. Generate:

   ```bash
   img -o /tmp/pic.png "An egg with legs"
   img --model flux_2_klein_4b_q6p.ckpt "prompt"
   ```

See also the [tools catalog](tools.md) and [Agents → Models](../agents/models.md).

## ai-server (optional)

For Open WebUI + llama-server in Docker, enable `ai-server`, adopt a GGUF into
`models_dir`, set default, then start the stack. Discovery is **not** limited
to that workflow—use `./dots models discover` first, then adopt when you want
a model managed for the server.

Full lifecycle: [AI inference server](ai-server.md).
