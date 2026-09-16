# shellcheck shell=bash
# helpers/toml.sh — DOTS TOML via stdlib tomllib (Python ≥3.11)
#
# Requires: DIR
# Prefer an already-installed Python ≥3.11; otherwise provision (mutating runs only).
# Never replaces system python/aliases; uses an isolated HOME for invocations.

# shellcheck source=python_runtime.sh
[[ -n ${DIR:-} && -f ${DIR}/helpers/python_runtime.sh ]] && source "${DIR}/helpers/python_runtime.sh"

# Resolve interpreter into DOTS_PYTHON (≥3.11 with tomllib).
# soft=1 → report-only when missing (for --show/--dry-run); soft=0 → provision.
dots_require_python() {
	local soft="${1:-0}"
	local found
	if found="$(dots_find_python311 2>/dev/null)"; then
		DOTS_PYTHON="${found}"
		export DOTS_PYTHON
		return 0
	fi

	# Fallback: plain python3 if it already has tomllib
	if command -v python3 >/dev/null 2>&1; then
		local pyhome ver
		pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pyhome.XXXXXX")"
		if HOME="${pyhome}" PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import tomllib' 2>/dev/null; then
			rm -rf "${pyhome}"
			DOTS_PYTHON="$(command -v python3)"
			export DOTS_PYTHON
			return 0
		fi
		ver="$(HOME="${pyhome}" python3 -B -c 'import sys; print("%d.%d.%d"%sys.version_info[:3])' 2>/dev/null || echo unknown)"
		rm -rf "${pyhome}"
		echo "Error: Python >=3.11 required (stdlib tomllib)." >&2
		echo "Found: Python ${ver}" >&2
	else
		echo "Error: Python >=3.11 required (stdlib tomllib). No python3 on PATH." >&2
	fi

	if [[ ${soft} -eq 1 ]] || [[ ${DRY_RUN:-0} -eq 1 ]] || [[ ${SHOW_ONLY:-0} -eq 1 ]]; then
		if command -v brew >/dev/null 2>&1; then
			echo "Would provision Python 3.12 via Homebrew (brew install python@3.12)." >&2
		elif [[ "$(uname -s)" == "Linux" ]]; then
			echo "Would provision Python >=3.11 via the platform package manager (python3.12 / python3.11)." >&2
		else
			echo "Would provision Python >=3.11 after Homebrew is available." >&2
		fi
		return 1
	fi

	if ! dots_provision_python311 "DOTS bootstrap / tomllib"; then
		return 1
	fi
	if found="$(dots_find_python311 2>/dev/null)"; then
		DOTS_PYTHON="${found}"
		export DOTS_PYTHON
		echo "OK: using provisioned Python → ${DOTS_PYTHON}"
		return 0
	fi
	echo "Error: Python >=3.11 provisioned but not discoverable on PATH." >&2
	return 1
}

# Run DOTS_PYTHON (or python3) with HOME isolation.
dots_python3() {
	local bin="${DOTS_PYTHON:-}"
	[[ -z ${bin} ]] && bin="$(command -v python3 2>/dev/null || true)"
	[[ -n ${bin} ]] || {
		echo "Error: no Python interpreter (DOTS_PYTHON unset)." >&2
		return 1
	}
	local pyhome rc=0
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pyhome.XXXXXX")"
	HOME="${pyhome}" PYTHONDONTWRITEBYTECODE=1 PYTHONNOUSERSITE=1 "${bin}" -B "$@" || rc=$?
	rm -rf "${pyhome}"
	return "${rc}"
}

# Load TOML via tomllib into `data`, then run query from stdin.
#   dots_toml_query FILE <<'PY'
#   ... use data ...
#   PY
dots_toml_query() {
	local file="$1"
	dots_require_python 0 || return 1
	if [[ ! -f ${file} ]]; then
		echo "Error: TOML file not found: ${file}" >&2
		return 1
	fi
	local query
	query="$(cat)"
	local pyhome rc=0
	local bin="${DOTS_PYTHON}"
	pyhome="$(mktemp -d "${TMPDIR:-/tmp}/dots-pyhome.XXXXXX")"
	QUERY="${query}" FILE="${file}" \
		HOME="${pyhome}" \
		PYTHONDONTWRITEBYTECODE=1 \
		PYTHONNOUSERSITE=1 \
		"${bin}" -B <<'PY' || rc=$?
import os, sys
from pathlib import Path
import tomllib

path = Path(os.environ["FILE"])
text = path.read_text(encoding="utf-8")
try:
    data = tomllib.loads(text)
except Exception as exc:
    sys.stderr.write("Error: malformed TOML (%s): %s\n" % (path, exc))
    sys.exit(1)

ns = {"data": data, "sys": sys, "Path": Path, "path": path, "tomllib": tomllib}
try:
    exec(compile(os.environ["QUERY"], "<dots_toml_query>", "exec"), ns, ns)
except SystemExit:
    raise
except Exception as exc:
    sys.stderr.write("Error: TOML query failed (%s): %s\n" % (path, exc))
    sys.exit(1)
PY
	rm -rf "${pyhome}"
	return "${rc}"
}
