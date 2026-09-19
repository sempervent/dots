#!/usr/bin/env bash
# scripts/ci/lint.sh — ShellCheck + shfmt for the DOTS bootstrap/CI surface
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

# shellcheck source=ensure_lint_tools.sh
source "${ROOT}/scripts/ci/ensure_lint_tools.sh"
# Install/verify pinned ShellCheck + shfmt (SHA-256 checked). Fails clearly
# if the pinned versions cannot be obtained — never silently uses a mismatch.
dots_ensure_lint_tools

# Curated lint set: entrypoints, helpers, CI harness, model subsystem, key tests.
# Deliberately excludes shell/ (zsh) and noisy legacy scripts.
SCRIPTS=(
	bootstrap.sh
	setup.sh
	configure.sh
	dots
	helpers/toml.sh
	helpers/packages.sh
	helpers/links.sh
	helpers/git_config.sh
	helpers/profiles.sh
	helpers/components.sh
	helpers/bootstrap_prereqs.sh
	helpers/python_runtime.sh
	helpers/hardware.sh
	helpers/models.sh
	helpers/model_providers.sh
	helpers/optional_components.sh
	helpers/ui.sh
	helpers/state.sh
	helpers/wizard.sh
	helpers/cask_apps.sh
	helpers/backup.sh
	helpers/mactools.sh
	helpers/package_state.sh
	shell/runtime.sh
	shell/fnm.sh
	shell/exports.sh
	scripts/pull_models.sh
	scripts/profile_resolution_test.sh
	scripts/ci/prepare_runner.sh
	scripts/ci/ensure_lint_tools.sh
	scripts/ci/lint.sh
	scripts/ci/test.sh
	scripts/ci/distro_smoke.sh
	scripts/ci/macos_smoke.sh
	scripts/tests/runtime_precedence_test.sh
	scripts/tests/dry_run_test.sh
	scripts/tests/bootstrap_test.sh
	scripts/tests/component_supergroups_test.sh
	scripts/tests/model_policy_test.sh
	scripts/tests/model_plan_test.sh
	scripts/tests/dots_cli_test.sh
	scripts/tests/dots_wizard_test.sh
	scripts/tests/dots_wizard_failure_test.sh
	scripts/tests/cask_app_test.sh
	scripts/tests/optional_failure_summary_test.sh
	scripts/tests/activation_transaction_test.sh
	scripts/tests/prompt_contract_test.sh
	scripts/tests/backup_test.sh
	scripts/tests/skills_location_test.sh
	scripts/tests/skills_desired_state_test.sh
	scripts/tests/mactools_test.sh
	scripts/tests/backup_gate_test.sh
	scripts/tests/package_state_test.sh
	scripts/mactools/export-configs.sh
	scripts/mactools/import-configs.sh
	scripts/mactools/docker-orbstack-audit.sh
)

missing=0
for f in "${SCRIPTS[@]}"; do
	if [[ ! -f ${f} ]]; then
		echo "Error: lint target missing: ${f}" >&2
		missing=1
	fi
done
[[ ${missing} -eq 0 ]] || exit 1

echo "=== ShellCheck (${#SCRIPTS[@]} files) ==="
# Intentional disables for sourced dynamic paths and common test idioms.
# SC2218 is NOT ignored — fix call-before-definition structurally.
shellcheck -x -e SC1091,SC2011,SC2016,SC1007,SC2034,SC2015,SC2317,SC2119,SC2329,SC2097,SC2098,SC2010,SC2012 \
	"${SCRIPTS[@]}"

echo "=== shfmt ==="
shfmt -d -s \
	bootstrap.sh setup.sh configure.sh dots \
	helpers/packages.sh helpers/links.sh helpers/git_config.sh \
	helpers/toml.sh helpers/bootstrap_prereqs.sh \
	helpers/hardware.sh helpers/models.sh helpers/model_providers.sh \
	helpers/ui.sh helpers/state.sh helpers/wizard.sh helpers/cask_apps.sh \
	helpers/backup.sh helpers/package_state.sh \
	shell/runtime.sh shell/fnm.sh \
	scripts/pull_models.sh \
	scripts/ci/prepare_runner.sh \
	scripts/ci/ensure_lint_tools.sh \
	scripts/ci/lint.sh \
	scripts/ci/test.sh \
	scripts/ci/distro_smoke.sh \
	scripts/ci/macos_smoke.sh

echo "OK: lint"
