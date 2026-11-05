#!/usr/bin/env bash
# scripts/ci/local_validate.sh — fast local CI / docs / workflow validation
#
# Read-only: never installs packages, never mutates git hooks, never starts Docker.
# Requires tools from package group `dev` (see configs/packages/groups.toml).
#
# Usage:
#   ./scripts/ci/local_validate.sh fast
#   ./scripts/ci/local_validate.sh workflows
#   ./scripts/ci/local_validate.sh docs [--offline|status|render|gate|…]
#   ./scripts/ci/local_validate.sh all-local
#   ./scripts/ci/local_validate.sh act [list|JOB]
#   ./scripts/ci/local_validate.sh release-notes
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

MODE="${1:-}"
shift || true

usage() {
	cat <<'EOF'
Usage: ./scripts/ci/local_validate.sh <mode> [args]

Modes:
  fast           Cheap deterministic checks (workflows + Dockerfiles + docs lint/spell)
  workflows      actionlint + zizmor on .github/workflows
  docs           markdownlint + cspell + Vale + lychee + diagram/publish stages
                 (add --offline to skip external HTTP; submodes: status|render|gate)
  all-local      fast + full docs links + pre-commit (when configured)
  act            List or run a Linux-compatible GitHub Actions job via act
                 (act list | act <job>)
  release-notes  Preview git-cliff notes since previous tag (stdout only)
  security       Delegates to scripts/ci/security_validate.sh (supply-chain gate)
  containers     Delegates to scripts/ci/containers_k8s_validate.sh containers
  k8s            Delegates to scripts/ci/containers_k8s_validate.sh k8s
  dev            Delegates to scripts/ci/dev_validate.sh (developer tooling)

Does not install tools. Select package group `dev`, e.g.:
  ./setup.sh --profile work
  ./setup.sh --packages core,modern,dev
EOF
}

missing_tools_hint() {
	echo "" >&2
	echo "Missing local validation tools." >&2
	echo "" >&2
	echo "Select package group 'dev' (not a --with component), for example:" >&2
	echo "  ./setup.sh --profile work" >&2
	echo "  ./setup.sh --packages core,modern,dev" >&2
	echo "" >&2
	echo "Then re-run: ./dots check ${MODE:-fast}" >&2
}

require_cmd() {
	local bin="$1"
	if ! command -v "${bin}" >/dev/null 2>&1; then
		echo "${RED}✗${NC} missing required tool: ${bin}" >&2
		missing_tools_hint
		return 1
	fi
}

pass() { echo "${GREEN}PASS${NC} $1"; }
fail() {
	echo "${RED}FAIL${NC} $1"
	return 1
}
skip() { echo "${YELLOW}SKIP${NC} $1"; }

run_step() {
	local name="$1"
	shift
	echo "${BLUE}=== ${name} ===${NC}"
	if "$@"; then
		pass "${name}"
		return 0
	fi
	fail "${name}"
}

find_dockerfiles() {
	# Robust discovery; exclude .git and common vendor paths.
	find "${ROOT}" \
		\( -path '*/.git/*' -o -path '*/node_modules/*' -o -path '*/.tools/*' -o -path '*/site/*' \) -prune -o \
		\( -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' \) -type f -print \
		2>/dev/null | sort -u
}

run_actionlint() {
	require_cmd actionlint
	local workflows=()
	local f
	while IFS= read -r f; do
		[[ -n ${f} ]] && workflows+=("${f}")
	done < <(find "${ROOT}/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
	[[ ${#workflows[@]} -gt 0 ]] || {
		skip "actionlint (no workflows)"
		return 0
	}
	actionlint -shellcheck= "${workflows[@]}"
}

run_zizmor() {
	require_cmd zizmor
	# Offline: do not phone home; audit local workflow trees only.
	# Informational findings (e.g. preferring `gh release` over softprops) do not fail.
	# Low+ findings fail — unpinned uses / credential persistence are treated as errors.
	zizmor --offline --min-severity=low "${ROOT}/.github/workflows"
}

run_hadolint() {
	require_cmd hadolint
	local files=()
	local f
	while IFS= read -r f; do
		[[ -n ${f} ]] && files+=("${f}")
	done < <(find_dockerfiles)
	if [[ ${#files[@]} -eq 0 ]]; then
		skip "hadolint (no Dockerfiles)"
		return 0
	fi
	hadolint "${files[@]}"
}

run_markdownlint() {
	require_cmd markdownlint-cli2
	# Config: .markdownlint-cli2.jsonc at repo root
	markdownlint-cli2
}

run_cspell() {
	require_cmd cspell
	cspell --no-progress --config "${ROOT}/cspell.json" \
		"README.md" \
		"AGENTS.md" \
		"SKILL.md" \
		"CONTRIBUTING.md" \
		"docs/**/*.md" \
		"configs/help/**/*.toml"
}

run_lychee() {
	require_cmd lychee
	local offline=0
	local arg
	for arg in "$@"; do
		[[ ${arg} == --offline ]] && offline=1
	done
	local args=(--config "${ROOT}/.lychee.toml" --no-progress)
	if [[ ${offline} -eq 1 ]]; then
		# Skip remote HTTP(S); still validate relative / file / mailto references.
		args+=(--exclude '^https?://')
	fi
	lychee "${args[@]}" \
		README.md AGENTS.md SKILL.md CONTRIBUTING.md \
		docs
}

run_pre_commit() {
	require_cmd pre-commit
	if [[ ! -f ${ROOT}/.pre-commit-config.yaml ]]; then
		skip "pre-commit (no .pre-commit-config.yaml)"
		return 0
	fi
	# Never install hooks; run once against the tree.
	pre-commit run --all-files --show-diff-on-failure
}

run_shell_lint_subset() {
	# Reuse existing CI lint when tools are present; otherwise skip.
	if ! command -v shellcheck >/dev/null 2>&1 || ! command -v shfmt >/dev/null 2>&1; then
		skip "shell lint (shellcheck/shfmt not on PATH)"
		return 0
	fi
	# Existing ensure_lint_tools may download — avoid that on `fast`.
	# Lint only the new Phase 1 surface + dots entrypoints already in CI list subset.
	# SC2329: helpers are invoked via run_step "$@" (indirect); not dead code.
	shellcheck -x -e SC1091,SC2016,SC2034,SC2329 \
		"${ROOT}/scripts/ci/local_validate.sh" \
		"${ROOT}/scripts/ci/lint.sh"
	shfmt -d -s "${ROOT}/scripts/ci/local_validate.sh"
}

run_fast() {
	local rc=0
	run_step "actionlint" run_actionlint || rc=1
	run_step "zizmor" run_zizmor || rc=1
	run_step "hadolint" run_hadolint || rc=1
	run_step "markdownlint-cli2" run_markdownlint || rc=1
	run_step "cspell" run_cspell || rc=1
	run_step "shell-lint-subset" run_shell_lint_subset || rc=1
	# Internal docs references without requiring the public internet.
	run_step "lychee-offline" run_lychee --offline || rc=1
	return "${rc}"
}

run_workflows() {
	local rc=0
	run_step "actionlint" run_actionlint || rc=1
	run_step "zizmor" run_zizmor || rc=1
	return "${rc}"
}

run_docs() {
	local rc=0
	local offline=0
	local sub=""
	local arg
	local rest=()
	for arg in "$@"; do
		case "${arg}" in
		--offline) offline=1 ;;
		status | render | gate | examples | vale | diagrams)
			sub="${arg}"
			;;
		*)
			rest+=("${arg}")
			;;
		esac
	done
	# Submodes for publishing diagnostics / previews (Phase 8).
	case "${sub}" in
	status | render | gate | examples | vale | diagrams)
		exec "${ROOT}/scripts/ci/docs_validate.sh" "${sub}" "${rest[@]+"${rest[@]}"}"
		;;
	esac

	# Default docs pipeline — keep `check fast` cheap (no Vale/diagrams there).
	run_step "markdownlint-cli2" run_markdownlint || rc=1
	run_step "cspell" run_cspell || rc=1
	run_step "vale" "${ROOT}/scripts/ci/docs_validate.sh" vale || rc=1
	if [[ ${offline} -eq 1 ]]; then
		run_step "lychee-offline" run_lychee --offline || rc=1
	else
		run_step "lychee" run_lychee || rc=1
	fi
	run_step "docs-diagrams" "${ROOT}/scripts/ci/docs_validate.sh" diagrams || rc=1
	return "${rc}"
}

run_all_local() {
	local rc=0
	run_fast || rc=1
	run_step "lychee" run_lychee || rc=1
	run_step "pre-commit" run_pre_commit || rc=1
	return "${rc}"
}

run_act() {
	require_cmd act
	local sub="${1:-list}"
	if ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
		echo "act requires a container runtime (docker/podman) on PATH." >&2
		echo "DOTS will not start Docker Desktop or OrbStack automatically." >&2
		return 1
	fi
	# Never forward host secrets into act.
	case "${sub}" in
	list | -l | --list)
		act -l
		;;
	*)
		# Job name only; no -s secrets, no --bind of credentials.
		act -j "${sub}"
		;;
	esac
}

run_release_notes() {
	require_cmd git-cliff
	local cfg="${ROOT}/cliff.toml"
	local prev
	prev="$(git describe --tags --abbrev=0 2>/dev/null || true)"
	if [[ -z ${prev} ]]; then
		echo "No previous tag found; generating notes for full history." >&2
		git-cliff --config "${cfg}"
	else
		echo "# Release notes since ${prev}" >&2
		git-cliff --config "${cfg}" "${prev}..HEAD"
	fi
}

case "${MODE}" in
"" | -h | --help)
	usage
	exit 0
	;;
fast)
	run_fast
	exit $?
	;;
workflows)
	run_workflows
	exit $?
	;;
docs)
	run_docs "$@"
	exit $?
	;;
all-local)
	run_all_local
	exit $?
	;;
act)
	run_act "$@"
	exit $?
	;;
release-notes)
	run_release_notes
	exit $?
	;;
security)
	# Deeper security / supply-chain gate — not part of `fast`.
	exec "${ROOT}/scripts/ci/security_validate.sh" "$@"
	;;
containers | k8s)
	exec "${ROOT}/scripts/ci/containers_k8s_validate.sh" "${MODE}" "$@"
	;;
dev)
	exec "${ROOT}/scripts/ci/dev_validate.sh" "$@"
	;;
*)
	echo "Unknown mode: ${MODE}" >&2
	usage >&2
	exit 1
	;;
esac
