# Skills

Packs are declared in `configs/skills/manifest.toml`.

```bash
./dots setup --with skills
./dots setup --with ai-skills
./dots setup --with archify
```

Installed under `~/.agents/skills/` (Hermes discovers separately when co-selected).

```bash
./dots skills list
./dots skills status
./dots skills audit
./dots skills update NAME --plan
```

Profiles may add `skills.include` / `skills.exclude` for curated names only.
Removing a skill from desired state does not delete installed files.
See `docs/agents/capabilities.md`.
