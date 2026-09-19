# Skills

DOTS installs agent skills via the upstream `skills` CLI into a global store.
This document is the authority for *how* skills are declared. Do not confuse it
with per-skill `SKILL.md` files inside a skill directory.

## Concepts

### Skill pack

Selectable via:

```bash
./setup.sh --with skills      # engineering pack (includes Archify)
./setup.sh --with ai-skills   # AI/agent harness pack
./setup.sh --with skills,ai-skills   # union (set semantics, deduped)
```

Declared in **`configs/skills/manifest.toml`**:

```text
[packs.skills] / [packs.ai-skills]
  → groups[]
    → [[skills]] with matching group
```

Pack install does **not** normally require a new optional component.

### Standalone selectable skill

Example: `--with archify`.

Unusual — only when the skill must be selectable alone. Requires:

1. A `[[components]]` entry in `configs/components.toml` (platforms, optional
   `brewfile`, `omit_from_all` as needed).
2. A mapping in `helpers/agent_skills.sh` → `agent_skill_package` (owner/repo).
3. Homebrew deps only if needed (`brewfile = "brew/Brewfile.<id>"` on the
   component; Archify/skills/ai-skills share `brew/Brewfile.archify`).

`SUPPORTED_WITH` in `setup.sh` is **loaded from** `configs/components.toml` —
do not edit a hard-coded list in `setup.sh`.

### Installed skill (runtime)

| Location | Role |
|----------|------|
| `~/.agents/skills/<name>` | Canonical global store |
| `~/.hermes/skills/<name>` | Hermes discovery (often a symlink created by the skills CLI) |

DOTS verifies a valid `SKILL.md` at either path. It does **not** require a
duplicate tree under both. When Hermes is co-selected, landing only under
`~/.hermes/skills` can still satisfy verification.

Provenance lock: `~/.agents/.skill-lock.json` (copied under
`~/.config/dots/skills/` after pack install). Content-hash via skills CLI — not
git SHA pinning.

In-repo skill sources (e.g. `skills/agent-router/`) are separate from pack
install; packs pull remote `owner/repo` specs from the manifest.

## How to add

### Skill to an existing pack

1. Add `[[skills]]` to `configs/skills/manifest.toml` (`name`, `source`, `group`,
   `enabled = true`).
2. Ensure `group` is listed under the pack’s `groups`.
3. Run skill tests + `./scripts/ci/test.sh`.

No new component.

### New skill group

1. Add the group name to the relevant `[packs.*] groups = [...]`.
2. Add `[[skills]]` rows with that `group`.

### Standalone selectable skill

1. Register component in `configs/components.toml`.
2. Map `agent_skill_package` in `helpers/agent_skills.sh`.
3. Optional `brewfile` if Homebrew deps are required.
4. Document in README skill table / [TOOLS.md](TOOLS.md) if notable.

### Skill with Homebrew dependencies

Prefer `brewfile =` on the component (shared file allowed, e.g. Archify). Apply
path is resolved by `dots_component_brewfile` — see [EXTENDING.md](EXTENDING.md).

## Updates

```bash
./scripts/update-skills.sh   # opt-in; not every setup
```

Security review of installed skills is **advisory by default**. Set
`DOTS_SKILLS_STRICT_REVIEW=1` to fail on findings (does not delete skills).

## Validation

```bash
bash scripts/tests/skills_location_test.sh
bash scripts/tests/skills_desired_state_test.sh
bash scripts/tests/repository_contract_test.sh
./scripts/ci/lint.sh
./scripts/ci/test.sh
```
