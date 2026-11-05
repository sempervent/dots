# Hardware tooling

```bash
./setup.sh --packages hardware
./dots check hardware
./dots check hardware examples
```

Storage/bus/serial CLIs (`smartctl`, `fio`, `lsusb`, `lspci`, `picocom`).
DOTS never runs SMART self-tests, fio benchmarks, or opens serial devices.

See `docs/using/hardware-tooling.md`.
