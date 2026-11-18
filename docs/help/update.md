# Update / Maintenance

`dots update` updates the **DOTS repository**. `dots upgrade` upgrades
**installed Homebrew software** in the active desired scope (`update != upgrade`).

| Command | Role |
|---------|------|
| `dots update` | Update DOTS itself (`git pull` + optional reapply) |
| `dots upgrade` | Upgrade managed software in active desired scope |
| `dots install X` | Add known software/capability to persistent desired state |
| `dots profile` | Inspect/edit desired state |
| `dots setup` | Bootstrap/reconfigure/converge |

```bash
./dots update
./dots upgrade --dry-run
./dots upgrade
./dots check
./dots packages outdated
```

Prefer a feature branch for local development work — do not commit features
directly to `master`.
