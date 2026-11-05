# Hardware tooling

Package group **`hardware`** installs storage, bus, and serial diagnostic CLIs.
Linux support is strongest; macOS is partial.

## Install

```bash
./setup.sh --packages hardware
# home / all include hardware; see examples/profiles/server-hardware.toml
```

## Tool roles

| Tool / binary | Package id | Role |
|---------------|------------|------|
| `smartctl` | `smartmontools` | Storage health inspection |
| `fio` | `fio` | Storage benchmarking |
| `lsusb` | `usbutils` | USB enumeration (Linux-strong) |
| `lspci` | `pciutils` | PCI enumeration (Linux-strong) |
| `picocom` | `picocom` | Serial terminal |

`screen` / `minicom` may already exist on a machine; picocom is **additive**.

## Destructive-risk warnings

Advanced use of these tools can be disruptive or privileged:

| Tool | Risk |
|------|------|
| `smartctl -t …` | SMART self-tests (not run by DOTS) |
| `fio` against disks/files | Can destroy data or saturate I/O |
| `picocom` / serial | Opens devices; can send data to hardware |
| raw `lsusb`/`lspci` | Usually read-only; still environment-specific |

DOTS setup/check only verifies binaries (e.g. `smartctl --version`).

## Diagnostics

```bash
./dots check hardware
./dots check hardware examples
```

No sudo. No SMART tests. No fio workloads. No serial device open.
Missing USB/PCI/serial hardware is healthy, not a failure.

## Platform notes

- **Linux:** native maps for smartmontools, fio, usbutils, pciutils, picocom.
- **macOS:** brew formulae available for the group; `lsusb`/`lspci` may be
  limited or report UNSUPPORTED when absent — that is expected.
