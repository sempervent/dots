#!/usr/bin/env bash
# scripts/ci/lint.sh — ShellCheck + shfmt over tracked shell scripts
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

SCRIPTS=()
while IFS= read -r f; do
	[[ -n ${f} ]] && SCRIPTS+=("${f}")
done < <(
	{
		git ls-files '*.sh'
		git ls-files 'bootstrap.sh' 'setup.sh' 'configure.sh'
	} | awk 'NF && !seen[$0]++' | sort
)

if [[ ${#SCRIPTS[@]} -eq 0 ]]; then
	echo "Error: no shell scripts discovered" >&2
	exit 1
fi

echo "=== ShellCheck (${#SCRIPTS[@]} files) ==="
# Intentional SC1091 disables live in sourced helpers for dynamic paths.
shellcheck -x -e SC1091,SC2011,SC2016,SC1007,SC2034 "${SCRIPTS[@]}"

echo "=== shfmt ==="
shfmt -d -s \
	bootstrap.sh setup.sh configure.sh \
	helpers/packages.sh helpers/links.sh helpers/git_config.sh \
	helpers/toml.sh helpers/bootstrap_prereqs.sh \
	helpers/hardware.sh helpers/models.sh helpers/model_providers.sh \
	helpers/components.sh \
	shell/runtime.sh shell/fnm.sh \
	scripts/pull_models.sh \
	scripts/ci/prepare_runner.sh \
	scripts/ci/lint.sh \
	scripts/ci/test.sh \
	scripts/ci/distro_smoke.sh \
	scripts/ci/macos_smoke.sh

echo "OK: lint"
