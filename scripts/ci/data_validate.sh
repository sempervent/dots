#!/usr/bin/env bash
# scripts/ci/data_validate.sh — data / tabular diagnostics (Phase 5)
#
# Read-only: never connects to PostgreSQL, never opens user datasets,
# never creates .duckdb databases / extensions / credentials.
#
# Usage:
#   ./scripts/ci/data_validate.sh           # status (default)
#   ./scripts/ci/data_validate.sh status
#   ./scripts/ci/data_validate.sh examples  # print example commands (stdout only)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

MODE="${1:-status}"

usage() {
	cat <<'EOF'
Usage: ./scripts/ci/data_validate.sh [status|examples]

  status    Report data tooling presence (non-mutating; no DB connections)
  examples  Print example commands only (does not execute against user data)

Never opens database connections, stores credentials, or inspects user datasets.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

# Safe version probes only — no connection strings, no -c against files.
tool_line() {
	local label="$1"
	local bin="$2"
	local note="${3:-}"
	if have "${bin}"; then
		local ver=""
		case "${bin}" in
		psql) ver="$(psql --version 2>/dev/null | head -n1 || true)" ;;
		pgcli) ver="$(pgcli --version 2>/dev/null | head -n1 || true)" ;;
		pg_activity) ver="$(pg_activity --version 2>/dev/null | head -n1 || true)" ;;
		duckdb) ver="$(duckdb --version 2>/dev/null | head -n1 || true)" ;;
		qsv) ver="$(qsv --version 2>/dev/null | head -n1 || true)" ;;
		mlr) ver="$(mlr --version 2>/dev/null | head -n1 || true)" ;;
		vd) ver="$(vd --version 2>/dev/null | head -n1 || true)" ;;
		jless) ver="$(jless --version 2>/dev/null | head -n1 || true)" ;;
		*) ver="present" ;;
		esac
		printf '  %-18s %s%s%s\n' "${label}" "${GREEN}OK${NC}" "${ver:+ (${ver})}" "${note:+ ${note}}"
	else
		if [[ ${label} == psql ]]; then
			printf '  %-18s %s\n' "${label}" "optional / not installed"
		else
			printf '  %-18s %s\n' "${label}" "${YELLOW}missing${NC}"
		fi
	fi
}

run_status() {
	echo "${BLUE}Data Tooling${NC}"
	echo "────────────────────────────────"
	echo ""
	echo "PostgreSQL"
	tool_line "psql" psql "(native client)"
	tool_line "pgcli" pgcli
	tool_line "pg_activity" pg_activity
	echo ""
	echo "Analytical"
	tool_line "duckdb" duckdb
	echo ""
	echo "Tabular"
	tool_line "qsv" qsv
	tool_line "mlr" mlr
	tool_line "vd" vd
	tool_line "jless" jless
	echo ""
	echo "Invariants"
	echo "  psql remains the native PostgreSQL client when present"
	echo "  No psql→pgcli alias; no ~/.pgpass or credentials written by this check"
	echo "  No database connections; no CSV/Parquet/JSON user-data inspection"
	return 0
}

run_examples() {
	cat <<'EOF'
Data tooling examples (copy/paste — not executed by DOTS)

  # DuckDB against a Parquet file (user-supplied path)
  duckdb -c "SELECT count(*) FROM 'data.parquet';"

  # qsv stats
  qsv stats data.csv

  # Miller filter
  mlr --csv filter '$status == "ok"' data.csv

  # VisiData interactive sheet
  vd data.csv

  # jless JSON navigation
  jless data.json

  # pgcli (user supplies connection — DOTS never does)
  pgcli "postgresql://user@localhost/dbname"

  # pg_activity (user supplies connection)
  pg_activity -U user -d dbname

psql vs pgcli: psql is the native client; pgcli is an enhanced interactive
client. DOTS does not replace or alias psql.
EOF
}

case "${MODE}" in
-h | --help)
	usage
	exit 0
	;;
"" | status)
	run_status
	exit $?
	;;
examples)
	run_examples
	exit 0
	;;
*)
	echo "Unknown mode: ${MODE}" >&2
	usage >&2
	exit 1
	;;
esac
