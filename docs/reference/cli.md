# CLI reference

Primary human interface: **`./dots`**. Expert scripts remain supported.

## Quick map

| Command | Role |
|---------|------|
| `./dots` / `./dots setup` | Interactive setup / reconfigure |
| `./dots status` | Read-only dashboard |
| `./dots packages …` | Ownership / drift / upgrade / adopt |
| `./dots backup` / `backups` / `restore` | Snapshots |
| `./dots profile` | Profile management |
| `./dots models` | Local model plan & pull UX |
| `./dots check` | Health verification |
| `./dots update` | Repo update + optional reapply |
| `./dots help` / `./dots --version` | Help / version |
| `./bootstrap.sh` | Profile → Stage 0 → setup → check |
| `./setup.sh` | Packages / links / components |
| `./configure.sh` | Profile TOML only |
| `./scripts/check.sh` | Health script |
| `./scripts/pull_models.sh` | Model pull helper |

## Generated help text

Full captured `--help` / usage output (regenerated; do not invent flags beyond it):

→ [CLI help (generated)](generated/cli-help.md)

## Safe preview flags

```bash
./dots setup --dry-run
./bootstrap.sh --profile home --show
./bootstrap.sh --profile home --dry-run
./setup.sh --dry-run --with ai
```

## Related

- [Getting Started](../getting-started/index.md)
- [Recipes](../using/recipes.md)
- [Packages](../concepts/packages.md)
