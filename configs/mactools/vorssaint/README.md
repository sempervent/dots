# Vorssaint settings export

## Status: manual export → optional ingest (automated scrape: unsupported)

Vorssaint supports **Settings → Export / Import** to a portable plist
(`Vorssaint Settings.plist`). The format excludes machine-specific state
(device IDs, paths, usage history, window geometry) per upstream design.

There is **no documented CLI**. DOTS will not read `UserDefaults` or copy
`~/Library` preference databases.

## Export (in app)

1. Open Vorssaint → Settings.
2. Export settings to a plist (default name: `Vorssaint Settings.plist`).
3. Ingest into the repo (review for secrets first):

```bash
./scripts/mactools/export-configs.sh vorssaint ~/Desktop/Vorssaint\ Settings.plist
```

## Import

```bash
./scripts/mactools/import-configs.sh vorssaint
```

Then use Vorssaint’s Import UI on the file under
`configs/mactools/vorssaint/` (or open the file from Finder).

## Git

Exported plists are gitignored by default. Commit only after a human review
confirms no secrets or machine-local paths remain.
