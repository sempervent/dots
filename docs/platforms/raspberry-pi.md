# Raspberry Pi

DOTS treats Raspberry Pi OS as a **Debian-family** host: same `apt` map as
Ubuntu/Debian (`configs/packages/apt.toml`).

## What CI proves today

| Check | What it means |
|-------|----------------|
| Distro smoke (Debian/Ubuntu) | Shared apt mappings resolve |
| **ARM64 smoke (Debian 13)** | Native `ubuntu-24.04-arm` runner + apt + aarch64 detection |

This is an **architecture proxy**, not a full Raspberry Pi OS hardware boot test.

## Recommended profile

```bash
./bootstrap.sh --profile server --show
./bootstrap.sh --profile server --dry-run
./bootstrap.sh --profile server
```

`server` installs Herdr but defaults the multiplexer to tmux and does **not**
enable AI providers. Add components only with explicit consent:

```bash
./bootstrap.sh --profile server --with hermes,ollama
```

## Practical notes

- Prefer **64-bit** Raspberry Pi OS when possible (matches ARM64 CI lane).
- Storage and RAM constrain local models — see [Models](../agents/models.md)
  tiers (`minimal` for ≤15 GB RAM class hosts).
- GUI / mactools components are Darwin-only; do not pass `--with mactools`.
- Platform detection: `./dots status` → Platform section.

## Future work (explicit)

- Real Raspberry Pi OS userspace image in CI
- armhf (32-bit) scheduled coverage
- Pi-specific hardware tooling (GPIO, etc.) — **not** in scope today

## Related

- [Linux](linux.md)
- [Profiles](../concepts/profiles.md)
