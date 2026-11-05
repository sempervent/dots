# GENERATED — DO NOT EDIT. Source: configs/help/commands.toml
# Generator: scripts/docs/generate_usage.py
DOTS — machine environment manager  (v1.6.2)

Usage:
  ./dots setup [options]            Interactive or noninteractive setup / reconfigure tow...
  ./dots status                     Show current DOTS state (profile, packages summary, c...
  ./dots components [list|active|show ID] Inspect optional components and --with selectors.
  ./dots lsp [status|check|install|list] Language-server install, status, and checks.
  ./dots ai [status|doctor|up|down|…] AI inference server (Compose + Open WebUI) control pl...
  ./dots agent [status|doctor|sandbox|models|scout|eval|team|run|…] Local-first agent harness (Pi, OpenRig, evals, guarde...
  ./dots packages [groups|group|plan|status|explain|outdated|upgrade|adopt] Package ownership, drift, groups, and upgrades.
  ./dots backup [--name N]          Snapshot managed targets under ~/.local/state/dots/ba...
  ./dots backups                    List recoverable DOTS snapshots.
  ./dots restore [ID]               Restore a snapshot (creates a safety snapshot first).
  ./dots profile …                  Create, preview, or switch machine profiles.
  ./dots models [discover|pull|…]   Local model plan, discovery, and pull workflows.
  ./dots check [--profile NAME] | dots check fast|workflows|docs|all-local|act|release-notes|security|containers|k8s|dev|data|backup Machine health, local CI, security, container, Kubern...
  ./dots update                     git pull the DOTS repo and optionally reapply setup.
  ./dots help [topic] [--plain] [--search QUERY] [--cheatsheet] Interactive Textual help (dots-help) for this machine.
  ./dots shell [status|keys|startup] Inspect shell, prompt, and keybinding ownership.
  ./dots completion [status|paths]  DOTS CLI completion and fzf-tab diagnostics.

Interactive help:
  ./dots help              Textual TUI (dots-help)
  dots-help                same launcher
  man dots                 Unix manual

Optional components use profile with= or ./setup.sh --with <ids>
(see ./dots components list). Docs:
  https://sempervent.github.io/dots/using/components/

Automation / expert scripts (still supported):
  ./bootstrap.sh   ./setup.sh   ./configure.sh
  ./scripts/pull_models.sh   ./scripts/check.sh
