<!--
GENERATED — DO NOT EDIT.
Source: configs/bootstrap/profiles/*.toml
Generator: scripts/docs/generate_reference.py
-->

# Built-in profiles (generated)

Repository presets under `configs/bootstrap/profiles/`. Custom overlays live in `~/.config/dots/profiles/` (not generated).

## `all`

ALL optional DOTS components (lab convenience — may include cloud AI)

- **Source:** `configs/bootstrap/profiles/all.toml`
- **include_all_optional:** yes
- **packages:** `core`, `modern`, `workstation`, `infra`, `media`, `gui`, `dev`, `security`, `network`, `data`, `geo`
- **with:** (none)
- **runtime.multiplexer:** `tmux`

## `base`

Core shell UX only — safe on any machine

- **Source:** `configs/bootstrap/profiles/base.toml`
- **packages:** `core`, `modern`
- **with:** (none)
- **runtime.multiplexer:** `tmux`

## `home`

Personal workstation — edit before relying on it

- **Source:** `configs/bootstrap/profiles/home.toml`
- **packages:** `core`, `modern`, `workstation`, `infra`, `media`, `gui`, `dev`, `network`, `data`, `geo`, `security`
- **with:** `ai`, `herdr`, `skills`, `ai-skills`, `images`, `tex`
- **without:** `fluidvoice`
- **runtime.multiplexer:** `herdr`

## `server`

Headless server — tmux + Herdr available, no GUI/AI providers by default

- **Source:** `configs/bootstrap/profiles/server.toml`
- **packages:** `core`, `modern`, `server`
- **with:** `herdr`
- **runtime.multiplexer:** `tmux`

## `work`

Conservative allowlist — no AI clients by default

- **Source:** `configs/bootstrap/profiles/work.toml`
- **packages:** `core`, `modern`, `workstation`, `dev`, `data`, `security`
- **with:** (none)
- **runtime.multiplexer:** `tmux`

## Example templates

Not applied automatically. Copy from `examples/profiles/`:

| file | name | extends | description |
| --- | --- | --- | --- |
| bertha.toml | bertha | server | Headless server with infra package group |
| home-studio.toml | home-studio | home | Home workstation without Cursor Agent CLI |
| work-custom.toml | corp-work | work | Work machine with infra tools + images toolkit (no AI) |
