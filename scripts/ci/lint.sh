#!/usr/bin/env bash
# scripts/ci/lint.sh — ShellCheck + shfmt for the DOTS bootstrap/CI surface
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

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
	shell/runtime.sh
	shell/fnm.sh
	shell/exports.sh
	scripts/pull_models.sh
	scripts/profile_resolution_test.sh
	scripts/ci/prepare_runner.sh
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
shellcheck -x -e SC1091,SC2011,SC2016,SC1007,SC2034,SC2015,SC2317,SC2119,SC2329,SC2097,SC2098 \
	"${SCRIPTS[@]}"

echo "=== shfmt ==="
shfmt -d -s \
	bootstrap.sh setup.sh configure.sh dots \
	helpers/packages.sh helpers/links.sh helpers/git_config.sh \
	helpers/toml.sh helpers/bootstrap_prereqs.sh \
	helpers/hardware.sh helpers/models.sh helpers/model_providers.sh \
	helpers/ui.sh helpers/state.sh helpers/wizard.sh \
	shell/runtime.sh shell/fnm.sh \
	scripts/pull_models.sh \
	scripts/ci/prepare_runner.sh \
	scripts/ci/lint.sh \
	scripts/ci/test.sh \
	scripts/ci/distro_smoke.sh \
	scripts/ci/macos_smoke.sh

echo "OK: lint"
