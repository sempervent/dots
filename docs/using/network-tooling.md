# Network tooling

Package group **`network`** installs diagnostic and remote-access CLIs.
Installation does **not** authorize scanning, capture packets, join a VPN, or
open remote sessions.

## Install

```bash
./setup.sh --packages network
# home / all profiles already include network
```

## Tool roles

| Tool | Role |
|------|------|
| `mtr` | Path + loss/latency |
| `nmap` | Host/service discovery |
| `iperf3` | Throughput measurement |
| `gping` | Latency visualization |
| `bandwhich` | Per-process bandwidth (often needs elevated privileges) |
| `termshark` | Terminal packet analysis (needs `tshark`) |
| `tshark` | Wireshark CLI capture engine |
| `mosh` | Resilient interactive remote shell |
| `rclone` | Remote/object storage transport (also xref’d from backup docs) |
| `tailscale` | Optional private overlay network client |

### termshark / Homebrew note

The Homebrew `termshark` formula is **deprecated and disabled** (2026-01-03).
DOTS does **not** list it in the Darwin Brewfile. Linux native maps may still
provide `termshark`. `tshark` is declared separately; DOTS does **not**
auto-install Wireshark on Darwin (capture privilege prompts).

## SSH vs mosh

| Tool | Role |
|------|------|
| `ssh` | Universal baseline remote shell (unchanged) |
| `mosh` | Resilient interactive alternative |

DOTS does not alias `ssh`→`mosh`.

## Tailscale

Tailscale remains a **`network` package** (Phase 0: install OK; never auto-`up`).

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

Default check performs **zero** remote probes, port scans, packet captures, or
throughput tests.

## Warnings

- **Scanning (`nmap` / broad `mtr`/`gping`)** may be restricted by organizational
  policy. Installation does not imply authorization to scan.
- **Packet capture** (`termshark` / `tshark` / `bandwhich`) may expose sensitive
  traffic. DOTS never enables capture or modifies BPF / wireshark group
  privileges.
