# Data tooling (PostgreSQL + tabular / analytical)

Package group **`data`** installs inspection and exploration CLIs. DOTS does
**not** open database connections, store credentials, or process user datasets
during setup or `./dots check data`.

## Install

```bash
./setup.sh --packages data
# or profiles that already include data: work, home, all
```

## PostgreSQL

| Tool | Role |
|------|------|
| `psql` | Native PostgreSQL client (authoritative when present; not replaced) |
| `pgcli` | Enhanced interactive client |
| `pg_activity` | Live session / query activity viewer |

DOTS never creates `~/.pgpass`, connection profiles, or `alias psql=pgcli`.

```bash
# User-directed only — never run by DOTS setup/check
pgcli "postgresql://user@localhost/dbname"
pg_activity -U user -d dbname
```

## Analytical / tabular

| Binary | Package id | Notes |
|--------|------------|-------|
| `duckdb` | `duckdb` | DuckDB **CLI** (distinct from any Python `duckdb` package) |
| `qsv` | `qsv` | CSV toolkit |
| `mlr` | `miller` | Name-indexed CSV/TSV/JSON |
| `vd` | `visidata` | Terminal spreadsheet |
| `jless` | `jless` | JSON pager |

Pre-existing ownership in `data` is preserved; Phase 5 only adds PostgreSQL
tools and diagnostics.

## Diagnostics

```bash
./dots check data              # binary presence / versions
./dots check data examples     # print examples (does not execute against files)
```

Checks may run `--version` / `--help` style probes only. They do **not** read
CSV, Parquet, JSON, or database contents.

## Platforms

Homebrew formulae on Darwin (and Homebrew-on-Linux when available). Linux native
maps may be empty for some ids → SKIP with a note (same pattern as other brew-
first CLIs).
