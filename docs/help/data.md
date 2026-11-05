# Data tooling

Package group `data`: PostgreSQL inspection (`pgcli`, `pg_activity`) plus
tabular/analytical CLIs (`duckdb`, `qsv`, `mlr`/`miller`, `vd`/`visidata`,
`jless`).

```bash
./setup.sh --packages data
./dots check data
./dots check data examples
```

DOTS never opens database connections, stores credentials, or aliases
`psql`→`pgcli`. See `docs/using/data-tooling.md`.
