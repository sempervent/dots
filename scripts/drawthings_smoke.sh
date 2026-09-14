#!/usr/bin/env bash
# Optional low-cost Draw Things smoke generation (NOT run by scripts/check.sh).
#
# Usage:
#   ./scripts/drawthings_smoke.sh
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v realpath >/dev/null 2>&1; then
  SCRIPT_PATH="$(realpath "${SCRIPT_PATH}")"
fi
DOTS_DIR="$(cd "$(dirname "${SCRIPT_PATH}")/.." && pwd)"
CONFIG="${DOTS_DRAWTHINGS_CONFIG:-${HOME}/.config/drawthings-mcp/config.toml}"
if [[ ! -f "${CONFIG}" ]]; then
  CONFIG="${DOTS_DIR}/configs/drawthings/config.toml"
fi

if ! command -v draw-things-cli >/dev/null 2>&1; then
  echo "Error: draw-things-cli not found. Run: ./setup.sh --with drawthings" >&2
  exit 1
fi

eval "$(python3 - "${CONFIG}" <<'PY'
import tomllib, shlex, sys
from pathlib import Path
cfg = tomllib.loads(Path(sys.argv[1]).read_text()) if Path(sys.argv[1]).is_file() else {}
smoke = cfg.get("smoke") or {}
model = (cfg.get("model") or {}).get("default") or ""
out_dir = (cfg.get("output") or {}).get("dir") or "~/Pictures/AI/DrawThings"
print(f"SMOKE_PROMPT={shlex.quote(str(smoke.get('prompt', 'a red cube on a black background')))}")
print(f"SMOKE_WIDTH={int(smoke.get('width', 512))}")
print(f"SMOKE_HEIGHT={int(smoke.get('height', 512))}")
print(f"SMOKE_STEPS={int(smoke.get('steps', 4))}")
print(f"SMOKE_MODEL={shlex.quote(str(model))}")
print(f"SMOKE_OUTDIR={shlex.quote(str(out_dir))}")
PY
)"

OUTDIR="${SMOKE_OUTDIR/#\~/${HOME}}"
mkdir -p "${OUTDIR}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${OUTDIR}/smoke-${STAMP}.png"

if [[ -z "${SMOKE_MODEL}" ]]; then
  # First downloaded model
  SMOKE_MODEL="$(draw-things-cli models list --downloaded-only --offline 2>/dev/null | python3 -c '
import re,sys
for line in sys.stdin:
    m=re.match(r"^(\S+\.ckpt)\b", line.strip())
    if m:
        print(m.group(1)); break
')"
fi
if [[ -z "${SMOKE_MODEL}" ]]; then
  echo "Error: no Draw Things models installed (CLI OK). Install models in the app or set DRAWTHINGS_MODELS_DIR." >&2
  exit 2
fi

echo "Generating smoke image (small/cheap)…"
echo "  model=${SMOKE_MODEL}"
echo "  size=${SMOKE_WIDTH}x${SMOKE_HEIGHT} steps=${SMOKE_STEPS}"
echo "  out=${OUT}"

draw-things-cli generate \
  --model "${SMOKE_MODEL}" \
  --prompt "${SMOKE_PROMPT}" \
  --width "${SMOKE_WIDTH}" \
  --height "${SMOKE_HEIGHT}" \
  --steps "${SMOKE_STEPS}" \
  --output "${OUT}"

if [[ ! -f "${OUT}" ]]; then
  echo "Error: expected output missing: ${OUT}" >&2
  exit 1
fi
ls -la "${OUT}"
echo "OK: smoke image written to ${OUT}"
