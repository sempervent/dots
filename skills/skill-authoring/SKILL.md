---
name: skill-authoring
description: Create, review, and register DOTS skills that follow the Agent Skills specification and DOTS supply-chain policy.
---

# Skill authoring

Use this skill when adding or changing a skill that DOTS will install.

Keep this file short. Put procedures in `references/`.

## Do this

1. Write `SKILL.md` with YAML frontmatter. `name` and `description` are required.
2. Name the skill in lowercase with hyphens. The directory name matches `name`.
3. Put long procedures in `references/`, scripts in `scripts/`, and static files in `assets/`.
4. Review the skill without executing its scripts. See `references/security.md`.
5. Register it in `configs/skills/manifest.toml` with a reviewed source ref.
6. Run `dots skills audit NAME` before enabling it.

## Do not

- Install an entire upstream catalog.
- Pin a skill to a moving `main` branch when a reviewed commit exists.
- Put secrets, tokens, or machine-local paths in the skill or the manifest.
- Execute bundled scripts during review.

## References

- `references/structure.md` — frontmatter, progressive disclosure, and path rules
- `references/security.md` — static review and manifest registration
