# Network tooling

Package group **`network`** installs diagnostic and remote-access CLIs.
Installation does **not** authorize scanning, capture packets, join a VPN,
open remote sessions, start tunnels, or change routes.

## Install

```bash
./setup.sh --packages network
# home / all profiles already include network
```

## Tool roles

| Tool | Role |
|------|------|
| `ssh` | Universal baseline connection (system OpenSSH; not installed by DOTS) |
| `sshs` | Interactive host picker over your existing SSH config |
| `mosh` | Resilient interactive remote shell |
| `autossh` | Supervised restart for SSH sessions/tunnels you start |
| `sshuttle` | Routed/subnet access over SSH (user-directed; may need root) |
| `tailscale` | Optional private overlay network client |
| `mtr` | Path + loss/latency |
| `nmap` | Host/service discovery |
| `iperf3` | Throughput measurement |
| `gping` | Latency visualization |
| `bandwhich` | Per-process bandwidth (often needs elevated privileges) |
| `termshark` | Terminal packet analysis (needs `tshark`) |
| `tshark` | Wireshark CLI capture engine |
| `rclone` | Remote/object storage transport (also xref’d from backup docs) |

DOTS does **not** install Homebrew `openssh`, alias `ssh` to another tool, or
manage `~/.ssh/config`, `known_hosts`, or keys.

### sshuttle

When **you** run `sshuttle`, it can change local routing/firewall state,
forward broad subnets, proxy DNS, and commonly requires `sudo` or root. DOTS only
installs and inventories `sshuttle` — installation does not join a remote network.

Distro packages may ship an older upstream line (e.g. 1.x on Debian/Ubuntu) than
Homebrew (2.x). DOTS does not bypass package managers to chase version numbers.

### autossh

`autossh` restarts SSH processes when they exit — useful for supervised tunnels.
Prefer ordinary OpenSSH `ServerAliveInterval` / `ServerAliveCountMax` when that
solves keepalive; use `autossh` when you need automatic tunnel restart behavior.
DOTS never starts `autossh`, sets `AUTOSSH_*`, or creates launchd/systemd units.

### sshs

`sshs` is a TUI that reads **your** `~/.ssh/config`. DOTS does not create SSH
host entries or run `sshs` during setup or checks.

### termshark / Homebrew note

The Homebrew `termshark` formula is **deprecated and disabled** (2026-01-03).
DOTS does **not** list it in the Darwin Brewfile. Linux native maps may still
provide `termshark`. `tshark` is declared separately; DOTS does **not**
auto-install Wireshark on Darwin (capture privilege prompts).

## SSH vs mosh vs sshs

| Tool | Role |
|------|------|
| `ssh` | Universal baseline remote shell (unchanged) |
| `mosh` | Resilient interactive alternative |
| `sshs` | Pick hosts from existing SSH configuration |

DOTS does not alias `ssh`→`mosh` or `ssh`→`sshs`.

## Tailscale

Tailscale remains a **`network` package** (install-only; never auto-`up`).

```text
DOTS installation does not authenticate Tailscale.
DOTS installation does not run `tailscale up`.
DOTS does not choose routes, DNS, exit nodes, or subnet routers.
```

`./dots check network` may report installed / logged-in / connected as
informational state. Unconfigured Tailscale is valid (`OPTIONAL` / not FAIL).

## Diagnostics

```bash
./dots check network
./dots check network examples
```

Default check performs **zero** remote probes, port scans, packet captures,
throughput tests, SSH connections, tunnels, or `sshuttle` routes.

## Warnings

- **Scanning (`nmap` / broad `mtr`/`gping`)** may be restricted by organizational
  policy. Installation does not imply authorization to scan.
- **Packet capture** (`termshark` / `tshark` / `bandwhich`) may expose sensitive
  traffic. DOTS never enables capture or modifies BPF / wireshark group
  privileges.