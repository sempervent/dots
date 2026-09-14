---
name: agent-router
description: Explicit, readable routing/delegation policy for DOTS AI backends. Classify requests into hermes_direct, local (Ollama), archify, opencode, codex, drawthings, or images CLI — with user overrides and one-step OpenCode→Codex escalation. Use when choosing which backend should handle a task, or when the user asks how work should be delegated. No embeddings or learned classifiers.
license: MIT
metadata:
  version: "0.1.0"
  author: dots
---

# Agent router (explicit policy)

This skill is a **readable decision policy**, not an autonomous swarm.

Deterministic classifier (tests / tooling): `route.py` in this directory.

Config defaults: `configs/agents/router.toml` → `~/.config/dots/agents/router.toml`.

## Destinations

| Destination | Backend | Use for |
|-------------|---------|---------|
| `hermes_direct` | Hermes | conversation, explanations, planning, orchestration, synthesizing results |
| `local` | Hermes + Ollama | private/low-cost summarization, extraction, first-pass analysis |
| `archify` | Archify skill | architecture assessment, diagrams, structure mapping |
| `opencode` | OpenCode MCP/adapter | routine coding, repo inspection, tests, local refactors |
| `codex` | Codex MCP | difficult/frontier coding, hard debugging, high-consequence work |
| `drawthings` | Draw Things MCP | generative images / img2img |
| `images` | CLI toolkit (`magick`, `exiftool`, …) | resize, convert, optimize, EXIF — **not** generation |

## Precedence (highest first)

1. **Explicit user override** (“Use Codex…”, “Keep this local…”, “Use OpenCode…”, “Generate with Draw Things…”, “Analyze with Archify…”).
2. **Deterministic media ops** → `images` (never Draw Things).
3. **Generative imagery** → `drawthings`.
4. **Architecture analysis** → `archify` (analysis only; no code mutation).
5. **Difficult / high-consequence coding** → `codex`.
6. **Routine coding / repo inspection** → `opencode` (escalation target: Codex).
7. **Local/low-cost text work** → `local`.
8. **Everything else** → `hermes_direct`.

## Decision shape

When delegating, think in this structure (and say which backend you are using):

```text
destination: opencode
reason: repository implementation task
cwd: /path/to/repo          # required for coding; never invent $HOME/DOTS
escalation: codex           # optional single automatic step only
```

Do **not** fabricate tool results. If a backend was not invoked, say so.

## Coding cwd

Never invent a repository directory. Use an explicit user path, a trusted session cwd, or ask. Do not default coding agents to `$HOME` or the DOTS repo.

## Escalation (at most one automatic step)

```text
Hermes/local → (coding required) → OpenCode → (failure signals) → Codex
```

Escalate OpenCode → Codex only when:

- OpenCode exits nonzero
- OpenCode times out
- OpenCode reports inability
- tests still fail after a reasonable attempt
- task is high-consequence
- user explicitly requests Codex

Do **not** escalate merely because a response is long.

Forbidden unbounded loops: `OpenCode → Codex → OpenCode → reviewer → …` without a bounded reason. Further hops need Hermes judgment or an explicit user request.

## Architecture then implementation

```text
Archify → Hermes synthesis → OpenCode or Codex
```

Archify analyzes; it does not implement.

## Optional review (not mandatory for trivial changes)

- OpenCode implements → Codex reviews, or
- Codex implements → Hermes/local reviews

## Local-first + concurrency (24 GB)

Prefer local Hermes/Ollama and OpenCode when practical. Avoid starting OpenCode local inference + Hermes local model + Draw Things at the same time.

## Graceful degradation

| Missing | Behavior |
|---------|----------|
| Codex | Stay on OpenCode; explain no cloud escalation |
| Draw Things | Report generative backend unavailable |
| Archify | Hermes does normal analysis |
| OpenCode | Hermes advises only; do not pretend edits happened |
| images toolkit | Report missing CLI; do not send resize/convert to Draw Things |

Partial installs remain useful (`--with hermes,ollama` without Codex/Draw Things).

## Image routing examples

- “create a synthwave image” → Draw Things
- “resize foo.png to 512×512” → `magick` (images)
- “show EXIF” → `exiftool`
- “compress this PNG” → `pngquant` / Magick

## Hermes prompts (manual)

- “Use OpenCode to inspect this repository.”
- “Escalate this difficult refactor to Codex.”
- “Keep this local and inspect this repo.”
- “Analyze the architecture with Archify.”
- “Generate this with Draw Things.”
