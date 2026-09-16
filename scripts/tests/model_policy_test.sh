#!/usr/bin/env bash
# scripts/tests/model_policy_test.sh — hardware tier selection (mocked)
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

expect_tier() {
	local ram="$1" want="$2" chip="${3:-}"
	unset DOTS_MODEL_TIER || true
	export DOTS_FORCE_RAM_GB="${ram}" DOTS_FORCE_OS=darwin DOTS_FORCE_ARCH=arm64
	[[ -n ${chip} ]] && export DOTS_FORCE_CHIP="${chip}"
	got="$(dots_models_select_tier)"
	if [[ ${got} == "${want}" ]]; then
		ok "${ram} GB → ${want}"
	else
		bad "${ram} GB want=${want} got=${got}"
	fi
}

echo "=== model registry ==="
if out="$(dots_validate_models_registry 2>&1)" && [[ ${out} == OK ]]; then
	ok "models.toml validates"
else
	bad "models.toml: ${out}"
fi

echo "=== tier selection ==="
expect_tier 8 minimal "Intel"
expect_tier 16 balanced "Apple M1"
expect_tier 24 balanced "Apple M2"
expect_tier 32 large "Apple M2"
expect_tier 64 max "Apple M3"

export DOTS_FORCE_OS=linux DOTS_FORCE_ARCH=x86_64 DOTS_FORCE_RAM_GB=16 DOTS_FORCE_CHIP="Intel Xeon"
unset DOTS_MODEL_TIER || true
got="$(dots_models_select_tier)"
[[ ${got} == balanced ]] && ok "16 GB Linux → balanced" || bad "16 GB Linux got=${got}"

export DOTS_FORCE_RAM_GB=32
got="$(dots_models_select_tier)"
[[ ${got} == large ]] && ok "32 GB Linux → large" || bad "32 GB Linux got=${got}"

export DOTS_MODEL_TIER=minimal DOTS_FORCE_RAM_GB=64
got="$(dots_models_select_tier)"
[[ ${got} == minimal ]] && ok "explicit --tier overrides RAM" || bad "override got=${got}"
unset DOTS_MODEL_TIER || true

echo "=== hardware helpers ==="
export DOTS_FORCE_RAM_GB=24 DOTS_FORCE_DISK_FREE_GB=412 DOTS_FORCE_CHIP="Apple M2"
[[ $(dots_hw_ram_gb) -eq 24 ]] && ok "ram mock" || bad "ram"
[[ $(dots_hw_disk_free_gb) -eq 412 ]] && ok "disk mock" || bad "disk"
[[ $(dots_hw_chip) == "Apple M2" ]] && ok "chip mock" || bad "chip"

echo ""
echo "model_policy_test: ${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
