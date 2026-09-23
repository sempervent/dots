# Recipes

Task-oriented paths grounded in real CLI entrypoints.

## Preview a profile without changing anything

```bash
./bootstrap.sh --profile home --show
./bootstrap.sh --profile home --dry-run
./setup.sh --dry-run --with ai
```

## First-time home Mac

```bash
./dots
# or
./bootstrap.sh --profile home
./dots check
```

Optional macOS workstation layer:

```bash
./dots backup --name before-mactools
./setup.sh --with mactools
```

## Work Mac (no AI by default)

```bash
./bootstrap.sh --profile work --show
./bootstrap.sh --profile work
```

Employer-approved extras only via custom profile or explicit `--with`.

## Headless Debian / Ubuntu server

```bash
./bootstrap.sh --profile server --dry-run
./bootstrap.sh --profile server
```

With infra tools (template: `examples/profiles/bertha.toml`):

```bash
cp examples/profiles/bertha.toml ~/.config/dots/profiles/bertha.toml
# edit, then:
./bootstrap.sh --profile ~/.config/dots/profiles/bertha.toml --show
./bootstrap.sh --profile ~/.config/dots/profiles/bertha.toml
```

## Raspberry Pi

See [Raspberry Pi](../platforms/raspberry-pi.md). Typical:

```bash
./bootstrap.sh --profile server
```

## Home without Cursor

```bash
cp examples/profiles/home-studio.toml ~/.config/dots/profiles/home-studio.toml
./bootstrap.sh --profile ~/.config/dots/profiles/home-studio.toml
```

## Package drift audit

```bash
./dots packages status
./dots packages outdated
./dots packages upgrade          # managed only
```

## Snapshot and restore

```bash
./dots backup --name manual
./dots backups
./dots restore <id> --dry-run
./dots restore <id>
```

## Local models (after opting into runtimes)

```bash
./setup.sh --with ollama,llamacpp
./dots models discover
./scripts/pull_models.sh --list
./dots models
```

## Skill packs

```bash
./setup.sh --with skills
./setup.sh --with ai-skills
./setup.sh --with skills,ai-skills
./scripts/update-skills.sh
```

## Docs site locally

```bash
./scripts/docs/generate.sh
./scripts/docs/serve.sh
./scripts/docs/check.sh
```
