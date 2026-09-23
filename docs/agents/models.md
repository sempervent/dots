# Models

Step-by-step discover / pull / Draw Things / `img`: [Local models](../using/local-models.md).

Authoritative registry: `configs/models.toml`
([generated table](../reference/generated/models.md)).

DOTS does **not** pull models during ordinary setup or CI. Use `./dots models`
or `./scripts/pull_models.sh` after the corresponding runtime components are
selected.

## Upstream interfaces (verified in registry comments)

| Provider | Interface |
|----------|-----------|
| Ollama | `ollama pull`, `ollama ls` |
| llama.cpp | `llama-cli -hf <repo>[:quant]`, `llama-cli --cache-list` |
| Draw Things | `draw-things-cli` — `models list`, `models ensure --model` |
| FluidVoice | App onboarding UI only — **no** stable CLI |

## Policy highlights

From `[policy]` in `models.toml`:

| Key | Meaning |
|-----|---------|
| `reserve_memory_gb` / `reserve_disk_gb` | Headroom before recommending pulls |
| Tier by **total** RAM | 8–15 minimal, 16–31 balanced, 32–63 large, 64+ max |
| `preferred_general_provider` | `ollama` |
| `preferred_coding_provider` | `llamacpp` |
| `include_cleanup_by_default` | Fluid-1 cleanup opt-in (`false`) |

Auto mode prefers Ollama for **general** and llama.cpp for **coding** so the same
weights are not double-downloaded. Explicit `--provider all` may still pull both
when the user asks.

## Roles

| Role | Typical provider |
|------|------------------|
| `general` | Ollama chat models |
| `coding` | llama.cpp GGUF (Hugging Face via `-hf`) |
| `image` | Draw Things checkpoints (darwin / arm64 oriented) |
| `speech` / `cleanup` | FluidVoice (manual automation) |

## CLI

```bash
./dots models discover
./dots models
./scripts/pull_models.sh --list
./scripts/pull_models.sh --help
```

### Draw Things (image)

After `./setup.sh --with drawthings`, pull a checkpoint (see registry `drawthings_model` ids), then use `img` or MCP. Details: [Local models → Draw Things](../using/local-models.md#draw-things-and-img).

User override file (optional): `~/.config/dots/models.toml` — see
`./dots status` Models section.

## Interactive progress (v1.4.0)

Wizard model pulls (models-only and Stage 4) run through `dots_wizard_run_models`
so interactive downloads keep a TTY. Piping `pull_models.sh` through `tee` solely
for logging broke CR progress from `ollama pull` / `llama-cli` / `draw-things-cli`
into permanent `>>>>` scrollback.

- Interactive: pull runs directly; durable setup log records `MODEL START` /
  `MODEL RESULT` only (not progress spam)
- `./dots models` still `exec`s `pull_models.sh` (TTY-preserving)
- Dry-run may capture plan lines; noninteractive does not fake a TTY

## Do not

- Invent model ids not present in `configs/models.toml`
- Assume Hermes template catalogs match this registry (they may differ)
- Pull models in CI or document CI as doing so
- Pipe interactive progress commands solely for logging

## Related

- [Agent harness](harness.md)
- [Generated models](../reference/generated/models.md)
- [Troubleshooting](../troubleshooting/index.md)
