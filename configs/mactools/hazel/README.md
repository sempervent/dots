# Hazel rules

## Status: manual (official Export Rules / Export All)

Noodlesoft documents:

- Action → **Export Rules** (one folder)
- Action → **Export All** (all folders → separate files)

Restoring from a full Time Machine-style copy of
`~/Library/Application Support/Hazel` + `com.noodlesoft.*` preferences is
documented by Noodlesoft for disaster recovery — that path is **not** suitable
for a clean Git-managed portable config (paths, licenses, machine state).

DOTS will not automate GUI clicking or copy Hazel’s Application Support tree.

## Recommended workflow

```bash
./scripts/mactools/export-configs.sh hazel
# then, after Export All from Hazel:
./scripts/mactools/export-configs.sh hazel /path/to/export-directory
```

Review exports for absolute home paths before any commit (gitignored by default).

## Import

```bash
./scripts/mactools/import-configs.sh hazel
```

Use Hazel → Action → Import Rules on the exported files.
