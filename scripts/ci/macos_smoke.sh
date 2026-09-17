#!/usr/bin/env bash
# scripts/ci/macos_smoke.sh — macOS CI smoke (Bash 3.2 + dry-run)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

/bin/bash ./bootstrap.sh --profile work --show
/bin/bash ./bootstrap.sh --profile home --show
/bin/bash ./bootstrap.sh --profile server --show
/bin/bash ./bootstrap.sh --profile work --dry-run
/bin/bash ./setup.sh --dry-run --with ai
/bin/bash ./setup.sh --dry-run --with fluidvoice
/bin/bash ./setup.sh --dry-run --with llamacpp
brew info --cask fluidvoice || true
brew info llama.cpp || true

# Model planner (mocked; no network downloads)
DOTS_FORCE_OS=darwin DOTS_FORCE_ARCH=arm64 DOTS_FORCE_RAM_GB=24 \
	DOTS_FORCE_DISK_FREE_GB=400 DOTS_FORCE_CHIP="Apple Silicon" \
	DOTS_MP_MOCK_OLLAMA=1 DOTS_MP_MOCK_LLAMACPP=1 \
	DOTS_MP_MOCK_DRAWTHINGS=1 DOTS_MP_MOCK_FLUIDVOICE=1 \
	/bin/bash ./scripts/pull_models.sh --list

bash scripts/tests/runtime_precedence_test.sh
bash scripts/tests/dry_run_test.sh
bash scripts/tests/component_supergroups_test.sh
bash scripts/tests/model_policy_test.sh
bash scripts/tests/model_plan_test.sh
bash scripts/tests/dots_cli_test.sh
bash scripts/tests/dots_wizard_test.sh
bash scripts/tests/dots_wizard_failure_test.sh
bash scripts/tests/cask_app_test.sh
bash scripts/tests/optional_failure_summary_test.sh
bash scripts/tests/activation_transaction_test.sh
bash scripts/tests/prompt_contract_test.sh
bash scripts/tests/backup_test.sh
bash scripts/tests/skills_location_test.sh

/bin/bash ./dots --version
/bin/bash ./dots help >/dev/null

echo "OK: macos smoke"
