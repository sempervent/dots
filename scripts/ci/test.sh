#!/usr/bin/env bash
# scripts/ci/test.sh — full non-mutating DOTS test suite (Ubuntu CI / local)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

run() {
	echo ""
	echo ">>> $*"
	bash "$@"
}

echo "=== Profile --show ==="
./bootstrap.sh --profile base --show
./bootstrap.sh --profile home --show
./bootstrap.sh --profile work --show
./bootstrap.sh --profile server --show
./bootstrap.sh --profile all --show

echo "=== Resolution / isolation / contracts ==="
run scripts/profile_resolution_test.sh
run scripts/provider_isolation_test.sh
run scripts/tests/custom_profile_test.sh
run scripts/tests/component_supergroups_test.sh
run scripts/tests/multiplexer_nesting_test.sh
run scripts/tests/stage0_prereqs_test.sh
run scripts/tests/provider_mapping_test.sh

echo "=== Bootstrap + setup dry-run ==="
./bootstrap.sh --profile server --dry-run
./setup.sh --dry-run
./setup.sh --dry-run --with herdr
./setup.sh --dry-run --with hermes,ollama
./setup.sh --dry-run --with ai
./setup.sh --dry-run --profile base --packages core,modern
if [[ "$(uname -s)" != "Darwin" ]]; then
	if ./setup.sh --dry-run --with fluidvoice; then
		echo "expected fluidvoice to fail on Linux" >&2
		exit 1
	fi
else
	./setup.sh --dry-run --with fluidvoice
fi

echo "=== Runtime / dry-run / transitions ==="
run scripts/tests/runtime_precedence_test.sh
run scripts/tests/dry_run_test.sh
run scripts/tests/link_manifest_test.sh
run scripts/tests/git_identity_test.sh
run scripts/tests/provider_transition_test.sh
run scripts/tests/bootstrap_test.sh
run scripts/tests/profile_transition_test.sh
run scripts/tests/idempotence_test.sh
run scripts/tests/check_contract_test.sh
run scripts/tests/shell_startup_test.sh
run scripts/tests/python_runtime_test.sh

echo "=== Model policy (mocked; no downloads) ==="
run scripts/tests/model_policy_test.sh
run scripts/tests/model_plan_test.sh

echo "=== Unified ./dots CLI + wizard ==="
run scripts/tests/dots_cli_test.sh
run scripts/tests/dots_wizard_test.sh
run scripts/tests/dots_wizard_failure_test.sh

echo "=== Cask presence + transactional activation ==="
run scripts/tests/cask_app_test.sh
run scripts/tests/optional_failure_summary_test.sh
run scripts/tests/activation_transaction_test.sh

echo "=== Prompt / backup / skills location ==="
run scripts/tests/prompt_contract_test.sh
run scripts/tests/backup_test.sh
run scripts/tests/skills_location_test.sh
run scripts/tests/skills_desired_state_test.sh

echo "OK: all CI tests passed"
