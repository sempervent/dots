# Install and first run

## Clone

```bash
git clone https://github.com/sempervent/dots.git ~/dots
cd ~/dots
```

Use a stable path you will keep (profiles and links assume the repo stays put).

## Interactive setup

```bash
./dots
# equivalent:
./dots setup
```

The wizard walks machine role → profile → components → runtime → models →
review → bootstrap → verify. Interrupt with Ctrl-C: if apply had not started,
no changes; if interrupted mid-apply, re-run `./dots` (operations are idempotent).

## Non-interactive bootstrap

```bash
./bootstrap.sh --profile home
./bootstrap.sh --profile work
./bootstrap.sh --profile server
./bootstrap.sh --profile base
./bootstrap.sh --profile all
```

Custom profile file:

```bash
./bootstrap.sh --profile ~/.config/dots/profiles/my-box.toml --show
./bootstrap.sh --profile ~/.config/dots/profiles/my-box.toml --dry-run
./bootstrap.sh --profile ~/.config/dots/profiles/my-box.toml
```

Builtin short names (`home`, `work`, …) always resolve to **repository** presets —
they are never shadowed by files in `~/.config/dots/profiles/`.

## Stage 0 (prerequisites)

Before packages and links, bootstrap may install prerequisites as needed:

- Xcode Command Line Tools (macOS)
- Homebrew (official installer) when required
- Python ≥3.11 (stdlib `tomllib`) for TOML registries

Stage 0 is **conditional** — dry-run / show modes report what would happen without
mutating. Details live in `helpers/bootstrap_prereqs.sh` and
`scripts/tests/stage0_prereqs_test.sh`.

## Optional components on the command line

```bash
./setup.sh --with herdr,hermes,ollama
./setup.sh --with skills,ai-skills
./setup.sh --with ai                 # platform-aware AI supergroup
./setup.sh --with mactools           # Darwin only
./setup.sh --dry-run --with cursor
```

Ids and platforms: [generated components](../reference/generated/components.md).

## Consent vs presence

AI clients (Hermes, Codex, Cursor, …) are configured only when explicitly listed
in the profile or `--with` for that run. Binary presence alone does **not**
authorize configuration.

## After install

```bash
./dots status
./dots check
./dots packages status    # Homebrew ownership / drift (read-only)
```

Open a new shell (or `source` as appropriate) so linked configs take effect.
