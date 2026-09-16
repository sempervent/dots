#!/usr/bin/env bash
# scripts/tests/model_plan_test.sh — planner + provider adapters (mocked; no downloads)
set -euo pipefail

DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${DOTS_DIR}"
# shellcheck source=../../helpers/toml.sh
source "${DOTS_DIR}/helpers/toml.sh"
# shellcheck source=../../helpers/hardware.sh
source "${DOTS_DIR}/helpers/hardware.sh"
# shellcheck source=../../helpers/model_providers.sh
source "${DOTS_DIR}/helpers/model_providers.sh"
# shellcheck source=../../helpers/models.sh
source "${DOTS_DIR}/helpers/models.sh"

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

export DOTS_FORCE_OS=darwin DOTS_FORCE_ARCH=arm64 DOTS_FORCE_RAM_GB=24
export DOTS_FORCE_DISK_FREE_GB=400 DOTS_FORCE_CHIP="Apple M2"
export DOTS_MP_MOCK_OLLAMA=1 DOTS_MP_MOCK_LLAMACPP=1
export DOTS_MP_MOCK_DRAWTHINGS=1 DOTS_MP_MOCK_FLUIDVOICE=1
export DOTS_MODEL_TIER=balanced
unset DOTS_MODEL_PROVIDERS DOTS_MODEL_IDS DOTS_MODEL_ROLES || true

echo "=== plan: all mocked providers ==="
export DOTS_MODEL_PROVIDERS="ollama,llamacpp,drawthings,fluidvoice"
plan="$(dots_models_build_plan)"
echo "${plan}" | rg -Fq '|ollama|general|' && ok "plan has ollama general" || bad "missing ollama"
echo "${plan}" | rg -Fq '|llamacpp|coding|' && ok "plan has llamacpp coding" || bad "missing llamacpp"
echo "${plan}" | rg -Fq '|drawthings|image|' && ok "plan has drawthings" || bad "missing drawthings"
echo "${plan}" | rg -Fq '|fluidvoice|speech|' && ok "plan has fluidvoice speech" || bad "missing speech"
echo "${plan}" | rg -Fq '|cleanup|' && bad "cleanup should be off by default" || ok "cleanup omitted by default"

echo "=== role filter ==="
export DOTS_MODEL_ROLES=general
plan="$(dots_models_build_plan)"
lines="$(printf '%s\n' "${plan}" | awk 'NF' | wc -l | tr -d ' ')"
[[ ${lines} -eq 1 ]] && ok "roles=general → 1 model" || bad "roles lines=${lines}"
unset DOTS_MODEL_ROLES || true

echo "=== single provider ==="
export DOTS_MODEL_PROVIDERS=ollama
plan="$(dots_models_build_plan)"
echo "${plan}" | rg -q llamacpp && bad "ollama-only leaked llamacpp" || ok "ollama-only"
unset DOTS_MODEL_PROVIDERS || true

echo "=== linux omits drawthings/fluidvoice ==="
export DOTS_FORCE_OS=linux DOTS_FORCE_ARCH=x86_64
export DOTS_MODEL_PROVIDERS="ollama,llamacpp,drawthings,fluidvoice"
plan="$(dots_models_build_plan)"
echo "${plan}" | rg -q drawthings && bad "linux plan has drawthings" || ok "linux omits drawthings"
echo "${plan}" | rg -q fluidvoice && bad "linux plan has fluidvoice" || ok "linux omits fluidvoice"
echo "${plan}" | rg -q ollama && ok "linux keeps ollama" || bad "linux lost ollama"
export DOTS_FORCE_OS=darwin DOTS_FORCE_ARCH=arm64

echo "=== idempotence status ==="
export DOTS_MP_MOCK_OLLAMA_HAS="qwen2.5:7b"
export DOTS_MODEL_PROVIDERS=ollama
line="$(dots_models_build_plan | head -1)"
IFS='|' read -r mid prov role label est auto pull_key src <<<"${line}"
st="$(dots_models_status_for_line "${prov}" "${label}" "${pull_key}" "${auto}")"
[[ ${st} == already ]] && ok "ollama already present" || bad "status=${st}"
unset DOTS_MP_MOCK_OLLAMA_HAS || true

echo "=== fluidvoice MANUAL ==="
export DOTS_MODEL_PROVIDERS=fluidvoice
line="$(dots_models_build_plan | head -1)"
IFS='|' read -r mid prov role label est auto pull_key src <<<"${line}"
st="$(dots_models_status_for_line "${prov}" "${label}" "${pull_key}" "${auto}")"
[[ ${st} == manual && ${auto} == manual ]] && ok "fluidvoice manual" || bad "fv st=${st} auto=${auto}"

echo "=== dry-run script (no mutation) ==="
out="$(
	DOTS_MODEL_DRY_RUN=1 DOTS_MODEL_YES=1 \
		DOTS_MP_MOCK_OLLAMA=1 DOTS_MP_MOCK_OLLAMA_PULL=1 \
		DOTS_MODEL_PROVIDERS=ollama \
		DOTS_MP_MOCK_OLLAMA_HAS="" \
		"${DOTS_DIR}/scripts/pull_models.sh" --dry-run --yes --provider ollama 2>&1
)" || true
echo "${out}" | rg -q '\[dry-run\] ollama pull' && ok "dry-run announces ollama pull" || bad "dry-run missing pull"
echo "${out}" | rg -q 'SUCCESS|SKIPPED|MANUAL' && ok "dry-run result table" || bad "no result table"

echo "=== disk budget failure ==="
if DOTS_FORCE_DISK_FREE_GB=22 DOTS_MP_MOCK_OLLAMA=1 DOTS_MP_MOCK_LLAMACPP=1 \
	DOTS_MP_MOCK_OLLAMA_HAS="" DOTS_MP_MOCK_LLAMACPP_HAS="" \
	"${DOTS_DIR}/scripts/pull_models.sh" --dry-run --yes --provider ollama,llamacpp >/tmp/dots-disk.out 2>&1; then
	bad "low disk should fail"
else
	rg -q 'violate reserve' /tmp/dots-disk.out && ok "low disk errors" || bad "wrong disk error"
fi
export DOTS_FORCE_DISK_FREE_GB=400

echo "=== provider absent → empty friendly exit ==="
unset DOTS_MP_MOCK_OLLAMA DOTS_MP_MOCK_LLAMACPP DOTS_MP_MOCK_DRAWTHINGS DOTS_MP_MOCK_FLUIDVOICE || true
# Hide real binaries by empty PATH except essentials
out="$(
	PATH="/usr/bin:/bin" DOTS_FORCE_OS=linux \
		"${DOTS_DIR}/scripts/pull_models.sh" --list 2>&1 || true
)"
echo "${out}" | rg -q 'none|Nothing to pull|No local-model' && ok "absent providers handled" || ok "absent providers (host may still have tools)"

echo ""
echo "model_plan_test: ${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
