#!/usr/bin/env bash
# scripts/tests/ai_server_test.sh — ai-server component, config, CLI, compose
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${ROOT}"
pass=0
fail=0

write_mini_gguf() {
	printf 'GGUF\x00\x00\x00' >"$1"
}

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
# shellcheck source=../../helpers/components.sh
source "${ROOT}/helpers/components.sh"
# shellcheck source=../../helpers/ai_server.sh
source "${ROOT}/helpers/ai_server.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-ai-test.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
export HOME="${TMP}/home"
mkdir -p "${HOME}/.config/dots"

echo "=== registry ==="
if dots_selector_is_known ai-server 2>/dev/null; then ok "ai-server known selector"; else bad "ai-server not in registry"; fi
if dots_component_brewfile ai-server | grep -q Brewfile.ai-server; then ok "brewfile mapped"; else bad "brewfile mapping"; fi

echo "=== bootstrap show ==="
show="$("${ROOT}/bootstrap.sh" --profile server --with ai-server --show 2>&1)"
echo "${show}" | grep -Fq 'ai-server' && ok "server --with ai-server in show" || bad "show missing ai-server"
base_show="$("${ROOT}/bootstrap.sh" --profile server --show 2>&1)"
echo "${base_show}" | grep -Fq 'ai-server' && bad "plain server includes ai-server" || ok "server opt-in"

echo "=== config validation ==="
cp "${ROOT}/configs/ai-server/defaults.toml" "${HOME}/.config/dots/ai-server.toml"
if dots_ai_validate_config; then ok "defaults valid"; else bad "defaults invalid"; fi
cat >"${HOME}/.config/dots/ai-server.toml" <<'TOML'
[ai_server]
backend = "not-a-backend"
TOML
if dots_ai_validate_config 2>/dev/null; then bad "invalid backend accepted"; else ok "invalid backend rejected"; fi

echo "=== compose render ==="
dots_require_python 0 || bad "python missing"
mkdir -p "${TMP}/runtime/models"
write_mini_gguf "${TMP}/runtime/models/tiny.gguf"
cat >"${HOME}/.config/dots/ai-server.toml" <<TOML
[ai_server]
enabled = true
inference = "llama_cpp"
backend = "cpu"
runtime_root = "${TMP}/runtime"
default_model = "tiny.gguf"
webui_port = 3000
llama_port = 8080
context_size = 8192
gpu_layers = 0
threads = 4
parallel = 1
publish_llama = false

[ai_server.open_webui]
image = "ghcr.io/open-webui/open-webui:main"

[ai_server.llama]
extra_args = []
TOML
dots_ai_render_compose || bad "render failed"
[[ -f ${HOME}/.config/dots/ai-server/compose.yml ]] && ok "compose.yml generated" || bad "no compose.yml"
if grep -q 'open-webui' "${HOME}/.config/dots/ai-server/compose.yml" &&
	grep -q 'llama' "${HOME}/.config/dots/ai-server/compose.yml"; then
	ok "services present"
else
	bad "compose services"
fi
if grep -q '8080/v1' "${HOME}/.config/dots/ai-server/compose.yml" ||
	grep -q 'OPENAI_API_BASE_URL' "${HOME}/.config/dots/ai-server/.env" 2>/dev/null; then
	ok "Open WebUI backend wiring"
else
	# env is separate; check compose environment block
	grep -q 'OPENAI_API_BASE_URL' "${HOME}/.config/dots/ai-server/compose.yml" && ok "Open WebUI backend wiring" || bad "Open WebUI wiring"
fi
if grep -q '^  llama:' "${HOME}/.config/dots/ai-server/compose.yml" &&
	! grep -E '^[[:space:]]*-[[:space:]]*"[0-9]+:8080"' "${HOME}/.config/dots/ai-server/compose.yml" | grep -v open-webui; then
	ok "llama not host-published by default"
else
	# allow expose-only llama
	grep -q 'expose:' "${HOME}/.config/dots/ai-server/compose.yml" && ok "llama internal expose" || bad "llama publish policy"
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
	if (cd "${HOME}/.config/dots/ai-server" && docker compose -f compose.yml config >/dev/null 2>&1); then
		ok "docker compose config"
	else
		bad "docker compose config failed"
	fi
else
	echo "SKIP: docker compose config (docker unavailable)"
fi

echo "=== model safety ==="
if dots_ai_model_set_default '../../etc/passwd' 2>/dev/null; then
	bad "path traversal default accepted"
else
	ok "path traversal rejected"
fi

echo "=== CLI smoke ==="
export DOTS_AI_MOCK_DOCKER=1
help="$("${ROOT}/dots" ai --help 2>&1)" || help=""
echo "${help}" | grep -Fq 'dots ai up' && ok "dots ai --help" || bad "dots ai help"
status="$("${ROOT}/dots" ai status 2>&1)" || status=""
echo "${status}" | grep -Fq 'AI server' && ok "dots ai status" || bad "dots ai status"
models_out="$("${ROOT}/dots" ai models 2>&1)" || models_out=""
echo "${models_out}" | grep -Fq 'Managed models' &&
	echo "${models_out}" | grep -Fq 'tiny.gguf' &&
	ok "dots ai models" || bad "dots ai models"
doctor="$("${ROOT}/dots" ai doctor 2>&1)" || true
echo "${doctor}" | grep -Fq PASS && ok "dots ai doctor output" || bad "dots ai doctor"

echo "=== setup dry-run ==="
dry="$("${ROOT}/setup.sh" --dry-run --with ai-server 2>&1)" || dry=""
echo "${dry}" | grep -Fq 'ai-server' && ok "setup dry-run mentions ai-server" || bad "setup dry-run"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
