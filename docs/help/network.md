# Network tooling

```bash
./setup.sh --packages network
./dots check network
./dots check network examples
```

Install-only diagnostics and remote CLIs (`mtr`, `nmap`, `iperf3`, `gping`,
`bandwhich`, `mosh`, `sshs`, `autossh`, `sshuttle`, `rclone`, `tailscale`, …).
System OpenSSH remains the baseline transport. DOTS never scans networks,
captures packets, runs iperf, opens SSH sessions, starts tunnels, or executes
`tailscale up`.

See `docs/using/network-tooling.md`.
