# Linux compatibility

DOTS installs via **package-manager families**, not one package list per distro.

| Distribution | Family | Package manager | Map | CI |
|--------------|--------|-----------------|-----|----|
| Ubuntu 24.04 | Debian | apt | `configs/packages/apt.toml` | required (`Distro smoke (Ubuntu 24.04)`) |
| Debian 13 | Debian | apt | same | required (`Distro smoke (Debian 13)`) |
| Raspberry Pi OS | Debian | apt | same | ARM64 proxy + detection tests |
| Arch | Arch | pacman | `configs/packages/pacman.toml` | required |
| Manjaro | Arch | pacman | same | required |
| Fedora | Fedora | dnf | `configs/packages/dnf.toml` | required |
| Void | Void | xbps | `configs/packages/xbps.toml` | required |

## Model

```text
apt    → Debian, Ubuntu, Raspberry Pi OS
pacman → Arch, Manjaro
dnf    → Fedora (and RHEL-ish when present)
xbps   → Void
```

Shared maps are authoritative. Distro-specific overrides are added **only** when a
real package-name difference is confirmed — not as speculative duplicate maps.

## Detection

`helpers/linux_distro.sh` reads `/etc/os-release` for ID / ID_LIKE / pretty name.
Package installation still uses `dots_detect_linux_pkg_mgr` (command probes).

```bash
./dots status   # Platform: section on Linux
```

## ARM64 / Raspberry Pi

PR CI includes **ARM64 smoke (Debian 13)** on a native `ubuntu-24.04-arm` runner.
That proves architecture detection and the shared apt map on aarch64.

It is **not** identical to booting Raspberry Pi OS on Pi hardware. Future optional
coverage could add a real Raspberry Pi OS userspace image or armhf nightlies.

## Server profile

`./bootstrap.sh --profile server` (groups `core modern server`) is the headless
smoke target across all Linux families. Distro smoke validates required package
mappings against live repositories without installing the full workstation.

## Future (out of scope here)

- `file-tank` profile extending `server` (ZFS / SMART / nvme tooling)
- Raspberry Pi OS armhf scheduled coverage
- Debian 12 LTS lane if still needed on older hosts
