# Getting Started

```bash
./dots                     # interactive setup / returning-machine menu
./dots install hyperfine   # persist known software/capability + apply
./dots upgrade             # upgrade managed software (distinct from update)
./dots profile             # inspect/edit persistent desired-state overlays
./dots setup --dry-run     # preview without mutating
./dots status              # read-only dashboard
./dots check               # health verification
dots-help                  # interactive reference for THIS machine
man dots                   # traditional Unix manual
```

Expert automation:

```bash
./bootstrap.sh --profile home --show
./bootstrap.sh --profile home
./setup.sh --with lsp
```

Docs site: https://sempervent.github.io/dots/
