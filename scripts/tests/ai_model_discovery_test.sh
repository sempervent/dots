#!/usr/bin/env bash
# scripts/tests/ai_model_discovery_test.sh — model inventory / discover / adopt
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${ROOT}"
export DIR
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

# shellcheck source=../../helpers/toml.sh
source "${ROOT}/helpers/toml.sh"
# shellcheck source=../../helpers/state.sh
source "${ROOT}/helpers/state.sh"
# shellcheck source=../../helpers/ai_server.sh
source "${ROOT}/helpers/ai_server.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-ai-disc.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
export HOME="${TMP}/home"
mkdir -p "${HOME}/.config/dots"

write_mini_gguf() {
	local dest="$1"
	# GGUF magic + minimal payload
	printf 'GGUF\x00\x00\x00' >"${dest}"
}

mkdir -p "${TMP}/runtime/models" "${TMP}/extra/path with spaces/models"
write_mini_gguf "${TMP}/runtime/models/managed.gguf"
write_mini_gguf "${TMP}/extra/path with spaces/models/external.gguf"

cat >"${HOME}/.config/dots/ai-server.toml" <<TOML
[ai_server]
backend = "cpu"
runtime_root = "${TMP}/runtime"
default_model = "managed.gguf"

[ai_server.discovery]
paths = ["${TMP}/extra/path with spaces/models"]

[ai_server.llama]
extra_args = []
TOML

dots_require_python 0 >/dev/null || {
	echo "FAIL: Python >=3.11 required" >&2
	exit 1
}
export DOTS_AI_SKIP_OLLAMA_CLI=1

echo "=== discover json ==="
json="$(dots_ai_inventory discover --json)"
echo "${json}" | "${DOTS_PYTHON:-python3}" -c '
import json,sys
d=json.load(sys.stdin)
names={r["name"] for r in d["records"]}
assert "managed.gguf" in names
assert "external.gguf" in names
assert d["summary"]["compatible_llama"] >= 2
' && ok "discovers managed and configured paths" || bad "discover json"

echo "=== dedupe symlink ==="
ln -sf "${TMP}/extra/path with spaces/models/external.gguf" "${TMP}/runtime/models/link-dup.gguf"
json2="$(dots_ai_inventory discover --json)"
count="$(echo "${json2}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; d=json.load(sys.stdin); print(len({r["id"] for r in d["records"] if r["name"] in ("external.gguf","link-dup.gguf")}))')"
[[ ${count} -eq 1 ]] && ok "canonical dedupe" || bad "duplicate canonical gguf count=${count}"

echo "=== ollama manifests ==="
ollama_root="${TMP}/fake-ollama/models"
mkdir -p "${ollama_root}/manifests/registry.ollama.ai/library/qwen2.5"
printf '{"layers":[]}' >"${ollama_root}/manifests/registry.ollama.ai/library/qwen2.5/7b"
export OLLAMA_MODELS="${ollama_root}"
json3="$(dots_ai_inventory discover --json)"
echo "${json3}" | "${DOTS_PYTHON:-python3}" -c '
import json,sys
d=json.load(sys.stdin)
oll=[r for r in d["records"] if r["backend"]=="ollama"]
assert any(r["name"]=="qwen2.5:7b" for r in oll), oll
assert all(not r["compatible"] for r in oll)
' && ok "ollama logical names" || bad "ollama manifest parse"

echo "=== adopt symlink ==="
mkdir -p "${TMP}/source"
write_mini_gguf "${TMP}/source/adopt-me.gguf"
dots_ai_inventory adopt "${TMP}/source/adopt-me.gguf" || bad "adopt failed"
[[ -L ${TMP}/runtime/models/adopt-me.gguf ]] && ok "adopt symlink" || bad "adopt symlink missing"
[[ -f ${TMP}/source/adopt-me.gguf ]] && ok "source preserved" || bad "source removed"

echo "=== adopt incompatible ==="
printf 'NOTGGUF' >"${TMP}/source/bad.bin"
if dots_ai_inventory adopt "${TMP}/source/bad.bin" 2>/dev/null; then
	bad "adopt accepted non-gguf"
else
	ok "reject non-gguf adopt"
fi

echo "=== default requires managed ==="
if dots_ai_model_set_default "external.gguf" 2>/dev/null; then
	bad "default allowed unmanaged name"
else
	ok "default requires models_dir"
fi

echo "=== discover human output ==="
out="$(dots_ai_discover_cmd 2>&1)"
echo "${out}" | grep -Fq 'Discovered AI models' && ok "human discover header" || bad "human discover"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
