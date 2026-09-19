# FAQ

## Is DOTS just dotfiles?

No. It is a **desired-state environment manager**: profiles, package groups,
optional components, managed links, skills, and optional local models — with
backup gates and health checks.

## Will it make every machine identical?

No. Profiles differ (especially `work` vs `home` vs `server`). Shared muscle
memory, not identical software everywhere.

## Does DOTS uninstall packages I installed myself?

No. It never runs `brew bundle cleanup` or removes undeclared software.

## Does finding Codex/Cursor on disk enable them?

No. AI clients are configured only when listed in the profile or `--with`.

## Where is the live documentation?

[https://sempervent.github.io/dots/](https://sempervent.github.io/dots/)

## Can I use a custom profile named `home`?

Builtin short names always resolve to repository presets. Put customs under
`~/.config/dots/profiles/` with a different name and `extends = "home"`.

## Is ZFS / NAS supported?

Not yet. A future `file-tank` profile is explicitly **out of scope** today.

## Does CI test real Raspberry Pi OS?

Not fully. CI includes ARM64 Debian smoke as an architecture proxy. See
[Raspberry Pi](platforms/raspberry-pi.md).

## Are Hermes model lists the same as `models.toml`?

Not necessarily. Trust `configs/models.toml` for DOTS pull policy; treat other
catalogs as upstream/product UI.

## How do I preview without changing my machine?

```bash
./dots setup --dry-run
./bootstrap.sh --profile home --show
```

## Where do agents look for instructions?

Root [`SKILL.md`](https://github.com/sempervent/dots/blob/master/SKILL.md)
(canonical). [`AGENTS.md`](https://github.com/sempervent/dots/blob/master/AGENTS.md)
is a thin compatibility shim.
