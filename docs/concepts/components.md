# Components and supergroups

Optional components are selected via profile `with` / `without` or
`./setup.sh --with <ids>`.

Authority: `configs/components.toml`
([generated components](../reference/generated/components.md),
[generated supergroups](../reference/generated/supergroups.md)).

## Component fields (registry)

| Field | Meaning |
|-------|---------|
| `id` | CLI / profile selector |
| `platforms` | `darwin` and/or `linux` |
| `brewfile` | Optional path to `brew/Brewfile.<id>` |
| `omit_from_all` | Skip when profile `all` expands the registry |
| `min_darwin` | e.g. FluidVoice requires macOS 15+ |
| `category` / `cloud` / `local_ai` | Metadata for documentation and policy |

Unsupported **explicit** `--with` on the wrong platform is an error.
Unsupported members of a **supergroup** are reported and omitted.

## Current components

| id | Role | Platforms |
|----|------|-----------|
| `herdr` | Terminal multiplexer | darwin, linux |
| `hermes` | Agent CLI (+ macOS desktop) | darwin, linux |
| `ollama` | Local LLM runtime (no auto model pull) | darwin, linux |
| `llamacpp` | llama.cpp via Homebrew | darwin, linux |
| `archify` | Archify skill only (`omit_from_all`) | darwin, linux |
| `skills` | Engineering skill pack (includes Archify) | darwin, linux |
| `ai-skills` | AI/agent harness skill pack | darwin, linux |
| `drawthings` | Draw Things CLI + MCP | darwin, linux |
| `opencode` | Local/general coding adapter | darwin, linux |
| `codex` | Frontier coding (Homebrew cask) | darwin |
| `cursor` | Cursor Agent CLI | darwin |
| `fluidvoice` | Voice dictation (macOS 15+) | darwin |
| `images` | Deterministic image toolkit | darwin, linux |
| `tex` | TeX Live (CLI) | darwin, linux |
| `mactools` | macOS workstation layer (`omit_from_all`) | darwin |

## Supergroups

| id | Members (expand before install) |
|----|----------------------------------|
| `ai` | hermes, ollama, llamacpp, drawthings, opencode, codex, cursor, fluidvoice |

```bash
./setup.sh --with ai
./setup.sh --dry-run --with ai
```

Nested groups are not supported (v1).

## Specialized side effects

Some components need post-Brewfile helpers (Herdr Linux installer, hermes-desktop,
FluidVoice cask presence, Codex npm→cask migration). Those live in
`helpers/optional_components.sh` — not a second registry.

## Adding a component

See [Extending](../using/extending.md). Register in `components.toml` first;
`SUPPORTED_WITH` is **loaded from** that file.
