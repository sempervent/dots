# shellcheck shell=bash
# helpers/toml.sh — parse DOTS TOML without requiring Python 3.11 tomllib
#
# Requires: DIR
# Provides: dots_toml_python, dots_require_python, and a shared PY prelude snippet.

dots_require_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required to parse DOTS configuration (profiles, components, packages)." >&2
    echo "Install Python 3.6+ (system package or python.org), then re-run bootstrap." >&2
    return 1
  fi
}

# Print absolute path to tools/toml_min.py
dots_toml_min_path() {
  printf '%s\n' "${DIR}/tools/toml_min.py"
}

# Load TOML file into Python variable `data` (dict). Prefer tomllib; fall back to toml_min.
# Usage inside a python3 - heredoc after calling this as the program body start:
#   dots_toml_python_load_prelude   # not used directly
#
# Preferred API — run a query:
#   dots_toml_query FILE <<'PY'
#   ... use data ...
#   PY

dots_toml_query() {
  local file="$1"
  dots_require_python || return 1
  if [[ ! -f "${file}" ]]; then
    echo "Error: TOML file not found: ${file}" >&2
    return 1
  fi
  local minp
  minp="$(dots_toml_min_path)"
  # Read query from stdin into env to avoid nested stdin conflict
  local query
  query="$(cat)"
  QUERY="${query}" FILE="${file}" MINP="${minp}" python3 <<'PY'
import importlib.util, os, sys
from pathlib import Path

path = Path(os.environ["FILE"])
min_path = Path(os.environ["MINP"])
text = path.read_text(encoding="utf-8")
data = None
errors = []
try:
    import tomllib
    data = tomllib.loads(text)
except Exception as exc:
    errors.append("tomllib: %s" % exc)
    spec = importlib.util.spec_from_file_location("toml_min", str(min_path))
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    try:
        data = mod.loads(text)
    except Exception as exc2:
        errors.append("toml_min: %s" % exc2)
        sys.stderr.write("Error: malformed TOML (%s)\n" % path)
        for e in errors:
            sys.stderr.write("  %s\n" % e)
        sys.exit(1)

ns = {"data": data, "sys": sys, "Path": Path, "path": path}
try:
    exec(compile(os.environ["QUERY"], "<dots_toml_query>", "exec"), ns, ns)
except SystemExit:
    raise
except Exception as exc:
    sys.stderr.write("Error: TOML query failed (%s): %s\n" % (path, exc))
    sys.exit(1)
PY
}
