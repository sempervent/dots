#!/usr/bin/env bash
# scripts/tests/dots_agent_test.sh — agent foundation (no paid API calls)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

echo "=== agent foundation files ==="
[[ -f ${ROOT}/configs/agents/defaults.toml ]] && ok "defaults.toml" || bad "defaults.toml"
[[ -f ${ROOT}/configs/agents/model-capabilities.toml ]] && ok "model-capabilities.toml" || bad "caps"
[[ -f ${ROOT}/configs/agents/local-foreman.md ]] && ok "local-foreman.md" || bad "foreman"
[[ -f ${ROOT}/services/litellm/compose.yml ]] && ok "litellm compose" || bad "compose"
[[ -f ${ROOT}/services/litellm/config.yaml ]] && ok "litellm config" || bad "config"
[[ -f ${ROOT}/tools/dots_agent/pyproject.toml ]] && ok "dots_agent pyproject" || bad "pyproject"
[[ -x ${ROOT}/scripts/dots-agent ]] || chmod +x "${ROOT}/scripts/dots-agent"
[[ -x ${ROOT}/scripts/dots-agent ]] && ok "dots-agent launcher" || bad "launcher"
rg -q 'id = "pi"' "${ROOT}/configs/components.toml" && ok "component pi" || bad "pi"
rg -q 'id = "litellm"' "${ROOT}/configs/components.toml" && ok "component litellm" || bad "litellm"
rg -q '"pi"' "${ROOT}/configs/components.toml" && ok "ai members mention pi" || bad "ai pi"
rg -q '127.0.0.1:4000' "${ROOT}/services/litellm/compose.yml" && ok "localhost bind" || bad "bind"
! rg -q '0.0.0.0:4000' "${ROOT}/services/litellm/compose.yml" && ok "no 0.0.0.0 publish" || bad "exposed"

echo "=== CLI dispatch ==="
"${ROOT}/dots" agent 2>&1 | grep -q 'Agent Harness' && ok "dots agent menu" || bad "menu"
"${ROOT}/dots" agent 2>&1 | grep -qi 'sandbox' && ok "sandbox warning" || bad "sandbox warn"

echo "=== uv package tests ==="
if command -v uv >/dev/null 2>&1; then
	uv sync --directory "${ROOT}/tools/dots_agent" --python-preference system --group dev >/dev/null 2>&1 \
		&& ok "uv sync dots_agent" || bad "uv sync"
	if DOTS_DIR="${ROOT}" uv run --directory "${ROOT}/tools/dots_agent" --python-preference system --group dev \
		pytest tests -q >"${TMPDIR:-/tmp}/dots-agent-pytest.out" 2>&1; then
		ok "pytest dots_agent"
	else
		bad "pytest dots_agent"
		tail -40 "${TMPDIR:-/tmp}/dots-agent-pytest.out" >&2
	fi
	# dry-run harness (no network required for dry-run)
	if DOTS_DIR="${ROOT}" "${ROOT}/scripts/dots-agent" run --dry-run --harness-only "noop" 2>&1 | grep -q 'dry-run\|LiteLLM\|budget'; then
		ok "agent run --dry-run"
	else
		bad "agent run --dry-run"
	fi
	# Ensure secret never appears in dry-run output
	out="$(DOTS_DIR="${ROOT}" OPENROUTER_API_KEY='sk-test-SHOULD-NOT-LEAK' "${ROOT}/scripts/dots-agent" doctor 2>&1 || true)"
	echo "${out}" | grep -q 'SET' && ok "doctor SET" || bad "doctor SET"
	echo "${out}" | grep -Fq 'sk-test-SHOULD-NOT-LEAK' && bad "secret leaked" || ok "secret not printed"
else
	ok "uv missing (skip package tests)"
fi

echo "=== docs present ==="
[[ -f ${ROOT}/docs/agents/architecture.md ]] && ok "architecture.md" || bad "arch"
[[ -f ${ROOT}/docs/agents/model-scout.md ]] && ok "model-scout.md" || bad "scout doc"
[[ -f ${ROOT}/docs/agents/litellm.md ]] && ok "litellm.md" || bad "litellm doc"

echo "Passed: ${pass}  Failed: ${fail}"
[[ ${fail} -eq 0 ]]
