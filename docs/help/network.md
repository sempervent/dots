# Network tooling

```bash
./setup.sh --packages network
./dots check network
./dots check network examples
```

Install-only diagnostics and remote CLIs (`mtr`, `nmap`, `iperf3`, `gping`,
`bandwhich`, `mosh`, `rclone`, `tailscale`, …). DOTS never scans networks,
captures packets, runs iperf, or executes `tailscale up`.

See `docs/using/network-tooling.md`.
