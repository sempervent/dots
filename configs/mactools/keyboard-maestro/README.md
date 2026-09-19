# Keyboard Maestro macros

## Status: manual (official UI / AppleScript; no silent Library scrape)

Keyboard Maestro’s supported portability paths:

1. **Editor UI:** File → Export → Export Macros / Export as Folder.
2. **AppleScript:** the Keyboard Maestro editor dictionary can import macros;
   the CLI tool (`keyboardmaestro`) runs macros — it is **not** a settings
   backup tool.
3. **Do not** commit `~/Library/Application Support/Keyboard Maestro/` wholesale
   (licenses, machine state, credentials may be present).

## Recommended workflow

```bash
./scripts/mactools/export-configs.sh keyboard-maestro
# follows printed steps; then optionally:
./scripts/mactools/export-configs.sh keyboard-maestro /path/to/Exported.kmmacros
```

Store reviewed `.kmmacros` / export folders under this directory only after
stripping secrets (API tokens inside macros, passwords in text actions, etc.).

## Import

```bash
./scripts/mactools/import-configs.sh keyboard-maestro
```

Open Keyboard Maestro → File → Import Macros… and select the export.
