# Packages

Package groups live in `configs/packages/groups.toml`.

```bash
./dots tui                             # dynamic desired-state TUI
./dots install hyperfine               # resolve owner, persist overlay, apply
./dots upgrade                         # upgrade outdated managed software
./dots packages groups [--json]
./dots packages group modern
./dots packages plan
./dots packages status
./dots packages explain bat
./dots packages outdated
./dots packages adopt <name> --group modern
```

Ownership states include managed, inactive, undeclared, missing, and external.
Removing desired state never uninstalls software or runs `brew bundle cleanup`.
