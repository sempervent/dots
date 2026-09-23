#!/usr/bin/env bash
# scripts/tests/img_test.sh — img resolves --model without calling real draw-things-cli generate
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() {
	echo "OK: $1"
	pass=$((pass + 1))
}
bad() {
	echo "FAIL: $1" >&2
	fail=$((fail + 1))
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-img.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
export HOME="${TMP}/home"
mkdir -p "${HOME}/.config/drawthings-mcp" "${TMP}/bin"

cat >"${HOME}/.config/drawthings-mcp/config.toml" <<'TOML'
[model]
default = ""

[output]
dir = "/tmp/dots-img-out"
TOML

write_mock_cli() {
	cat >"${TMP}/bin/draw-things-cli" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == "models" && "${2:-}" == "list" ]]; then
  echo "flux_2_klein_4b_q6p.ckpt            Flux Klein"
  exit 0
fi
if [[ "${1:-}" == "generate" ]]; then
  out=""
  model=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --output) out="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    *) shift ;;
    esac
  done
  [[ -n "${model}" ]] || { echo "Error: --model is required." >&2; exit 1; }
  [[ "${model}" == "flux_2_klein_4b_q6p.ckpt" ]] || { echo "unexpected model: ${model}" >&2; exit 1; }
  printf 'PNG' >"${out}"
  exit 0
fi
echo "unexpected: $*" >&2
exit 1
MOCK
	chmod +x "${TMP}/bin/draw-things-cli"
}

write_mock_cli
export PATH="${TMP}/bin:${PATH}"
export DOTS_DIR="${ROOT}"
export DOTS_TELEMETRY=0

echo "=== img uses first downloaded model ==="
out="$("${ROOT}/scripts/img" -o "${TMP}/pic.png" -n "test prompt" 2>&1)" || {
	bad "img failed: ${out}"
}
[[ -f ${TMP}/pic.png ]] && ok "img wrote output" || bad "missing png"
echo "${out}" | grep -q 'Generating' && ok "img started generate" || bad "no generate line"

echo "=== img fails without model ==="
cat >"${TMP}/bin/draw-things-cli" <<'MOCK2'
#!/usr/bin/env bash
if [[ "${1:-}" == "models" && "${2:-}" == "list" ]]; then
  echo "MODEL                               NAME"
  echo "Tip: none"
  exit 0
fi
exit 1
MOCK2
chmod +x "${TMP}/bin/draw-things-cli"
if "${ROOT}/scripts/img" -o "${TMP}/pic2.png" -n "x" 2>"${TMP}/err.txt"; then
	bad "img should fail without model"
else
	ok "img exits non-zero without model"
fi
grep -q 'pull_models.sh' "${TMP}/err.txt" && ok "actionable error" || bad "error message"

echo "=== img -m override ==="
cat >"${TMP}/bin/draw-things-cli" <<'MOCK3'
#!/usr/bin/env bash
if [[ "${1:-}" == "models" ]]; then exit 0; fi
if [[ "${1:-}" == "generate" ]]; then
  out=""
  model=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --output) out="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    *) shift ;;
    esac
  done
  [[ "${model}" == "custom.ckpt" ]] || { echo "wrong model: ${model}" >&2; exit 1; }
  printf 'PNG' >"${out}"
  exit 0
fi
exit 1
MOCK3
chmod +x "${TMP}/bin/draw-things-cli"
"${ROOT}/scripts/img" -m custom.ckpt -o "${TMP}/pic3.png" -n "y" >/dev/null && ok "img -m override" || bad "img -m override"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
