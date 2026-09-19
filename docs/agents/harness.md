# Agent harness

DOTS wires optional AI **clients**, local **runtimes**, skills, an explicit
**router policy**, and optional **telemetry**. Nothing here invents backends that
are not declared in `configs/components.toml`, `configs/agents/*.toml`, or
`skills/agent-router/SKILL.md`.

Consent: configure AI only when the profile / `--with` lists the component.

## Components (install selectors)

| Component | Role | Platforms |
|-----------|------|-----------|
| `herdr` | Terminal multiplexer / session orchestrator | darwin, linux |
| `hermes` | Agent CLI (+ macOS hermes-desktop) | darwin, linux |
| `ollama` | Local LLM runtime (no models auto-pulled) | darwin, linux |
| `llamacpp` | llama.cpp via Homebrew; models via `pull_models.sh` | darwin, linux |
| `opencode` | Local/general coding adapter | darwin, linux |
| `codex` | Frontier coding (Homebrew cask) | darwin |
| `cursor` | Cursor Agent CLI (`agent`) — explicit opt-in | darwin |
| `drawthings` | Image generation CLI + MCP | darwin, linux |
| `archify` | Architecture skill (also in `skills` pack) | darwin, linux |
| `skills` / `ai-skills` | Curated skill packs | darwin, linux |
| `fluidvoice` | Voice dictation (macOS 15+) | darwin |
| `images` | Deterministic image toolkit (Magick, etc.) | darwin, linux |

Supergroup `ai` expands to the AI application ids listed in
[generated supergroups](../reference/generated/supergroups.md).

## Herdr

Config template: `configs/herdr/config.toml` → merged into
`~/.config/herdr/config.toml` (not a pure symlink — Herdr rewrites local UI
state). Prefix defaults to Ctrl-A with tmux-oriented pane keys; see comments in
that file. Profile `home` defaults `runtime.multiplexer = "herdr"`;
`server`/`work`/`base` default to tmux.

## Hermes

Optional component `hermes`. Co-selecting Hermes enables skill discovery under
`~/.hermes/skills/` (often symlinks from the skills CLI). Hermes is the usual
conversation / orchestration front-end in the router policy.

## OpenCode / Codex / Cursor

Templates: `configs/agents/execution.toml`.

| Adapter | Default role in policy |
|---------|------------------------|
| OpenCode | Routine coding / repo inspection |
| Codex | Difficult / frontier / escalated coding (MCP) |
| Cursor | **Never** auto-selected — only when the user says “use Cursor” |

Concurrency note (from execution.toml / router): on ~24 GB hosts, avoid stacking
OpenCode local inference + Hermes local model + Draw Things simultaneously.

## Ollama / llama.cpp

Runtimes only — models are planned/pulled separately
([Models](models.md)). Policy in `configs/models.toml`: Ollama prefers
**general**; llama.cpp prefers **coding** in auto mode so weights are not
double-downloaded.

## Draw Things / images

- Generative imagery → Draw Things (`drawthings`)
- Resize / convert / EXIF → `images` toolkit (`magick`, `exiftool`, …) — **not**
  Draw Things

## Archify

Architecture assessment / diagrams. Analyzes; does not implement. Also installed
via `--with skills`.

## Router (explicit policy)

**Sources of truth:**

- `configs/agents/router.toml` → live copy `~/.config/dots/agents/router.toml`
- Behavioral policy: `skills/agent-router/SKILL.md`
- Deterministic classifier for tests: `skills/agent-router/route.py`

Defaults from `router.toml`:

| Key | Value |
|-----|-------|
| `local_first` | `true` |
| `max_auto_escalation` | `1` (OpenCode → Codex) |
| `require_coding_cwd` | `true` |
| Escalation on nonzero / timeout / inability / tests failing / high-consequence | `true` |
| Escalation on long response | `false` |
| Avoid parallel local inference | `true` |

### Destinations (from agent-router skill)

| Destination | Backend | Use for |
|-------------|---------|---------|
| `hermes_direct` | Hermes | conversation, planning, synthesis |
| `local` | Hermes + Ollama | private/low-cost text work |
| `archify` | Archify | architecture / diagrams |
| `opencode` | OpenCode | routine coding |
| `codex` | Codex | frontier / escalated coding |
| `cursor` | Cursor Agent CLI | explicit “use Cursor” only |
| `drawthings` | Draw Things | generative images |
| `images` | CLI toolkit | deterministic media ops |

### Precedence (highest first)

1. Explicit user override
2. Deterministic media ops → `images`
3. Generative imagery → `drawthings`
4. Architecture → `archify`
5. Difficult / high-consequence coding → `codex`
6. Routine coding → `opencode`
7. Local/low-cost text → `local`
8. Everything else → `hermes_direct`

Coding cwd: never invent a repository path; do not default agents to `$HOME` or
the DOTS repo.

## Telemetry

`configs/agents/telemetry.toml` — observational only, **not** adaptive routing.

| Setting | Default |
|---------|---------|
| `enabled` | `true` |
| `capture_text` | `false` |
| Store prompts / responses / full paths | `false` |
| Retention | 90 days |
| DB | `~/.local/share/dots/telemetry/agents.sqlite3` |

Opt out: `enabled = false` in the live telemetry.toml **or** `DOTS_TELEMETRY=0`.

## Related

- [Models](models.md)
- [Skills](../using/skills.md)
- [Components](../concepts/components.md)
