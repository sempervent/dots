# Skill structure

Agent Skills use a directory with `SKILL.md` at the root.

## Frontmatter

```yaml
---
name: example-skill
description: One sentence that says when to use the skill.
---
```

Constraints:

- `name` is lowercase letters, digits, and single hyphens. No leading, trailing, or repeated hyphens. At most 64 characters.
- `description` is required and at most 1024 characters.
- The directory name equals `name`.

## Progressive disclosure

`SKILL.md` states the task and the rules that must not be skipped. Move command lists, examples, and background into `references/` and link them with relative paths.

Relative links and symlinks must stay inside the skill directory.

## DOTS registration

Curated skills are declared in `configs/skills/manifest.toml`. A profile may include only those names. A profile cannot select an arbitrary URL.

Machine-local install state belongs in `~/.config/dots/skills/`, not in the git manifest.
