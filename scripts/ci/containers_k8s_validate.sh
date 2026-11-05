#!/usr/bin/env bash
# scripts/ci/containers_k8s_validate.sh — local container / Kubernetes validation
#
# Read-only wrt runtime and clusters:
#   never starts OrbStack/Docker Desktop, never pulls images, never compose up,
#   never modifies kubeconfig/context/namespace, never applies Helmfile / Argo CD.
#
# Usage:
#   ./scripts/ci/containers_k8s_validate.sh containers [status|gate]
#   ./scripts/ci/containers_k8s_validate.sh k8s [status|gate]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

DOMAIN="${1:-}"
MODE="${2:-gate}"
shift 2 2>/dev/null || shift $# 2>/dev/null || true

usage() {
	cat <<'EOF'
Usage:
  ./scripts/ci/containers_k8s_validate.sh containers [gate|status]
  ./scripts/ci/containers_k8s_validate.sh k8s [gate|status]

containers gate: Dockerfile lint (hadolint), Compose config (static), OCI CLI presence
k8s gate:        kubectl client, local manifest kubeconform (+ optional kubescape)

Never starts runtimes, creates clusters, or mutates kube/Docker config.
Requires package groups `containers` / `k8s` as appropriate.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }
pass() { echo "${GREEN}PASS${NC} $1"; }
fail() {
	echo "${RED}FAIL${NC} $1"
	return 1
}
skip() { echo "${YELLOW}SKIP${NC} $1"; }
ok_line() { printf '  %-22s %s\n' "$1" "$2"; }

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

missing_hint() {
	local group="$1"
	echo "" >&2
	echo "Missing ${group} tooling." >&2
	echo "  ./setup.sh --packages core,modern,${group}" >&2
	echo "  ./setup.sh --profile home" >&2
	echo "" >&2
}

# ── Runtime detection (informational) ───────────────────────────────────────

docker_cli_state() {
	have docker && echo "OK" || echo "missing"
}

compose_plugin_state() {
	if have docker && docker compose version >/dev/null 2>&1; then
		echo "OK"
	elif have docker-compose; then
		echo "OK (docker-compose)"
	else
		echo "missing"
	fi
}

runtime_reachable() {
	# Non-mutating ping; do not start anything.
	if have docker && docker info >/dev/null 2>&1; then
		echo "YES"
		return
	fi
	if have podman && podman info >/dev/null 2>&1; then
		echo "YES (podman)"
		return
	fi
	echo "NO"
}

runtime_type() {
	if ! have docker; then
		echo "n/a"
		return
	fi
	local ctx
	ctx="$(docker context show 2>/dev/null || echo default)"
	if echo "${ctx}" | grep -qi orbstack; then
		echo "OrbStack context (${ctx})"
		return
	fi
	if docker info 2>/dev/null | grep -qi orbstack; then
		echo "OrbStack-compatible"
		return
	fi
	if docker info >/dev/null 2>&1; then
		echo "Docker-compatible (${ctx})"
		return
	fi
	echo "CLI present; runtime not reachable"
}

orbstack_installed() {
	[[ "$(uname -s)" == Darwin ]] || {
		echo "unsupported (non-Darwin)"
		return
	}
	if [[ -d /Applications/OrbStack.app ]] || brew list --cask orbstack >/dev/null 2>&1; then
		echo "installed"
		return
	fi
	echo "not installed"
}

orbstack_running() {
	[[ "$(uname -s)" == Darwin ]] || {
		echo "n/a"
		return
	}
	# Read-only process check — never launch. Prefer exact app name; avoid broad -f matches.
	if pgrep -xq OrbStack 2>/dev/null; then
		echo "YES"
		return
	fi
	echo "NO"
}

tool_ok() {
	local bin="$1"
	have "${bin}" && echo "OK" || echo "missing"
}

# ── Containers ──────────────────────────────────────────────────────────────

find_compose_files() {
	find "${ROOT}" \
		\( -path '*/.git/*' -o -path '*/node_modules/*' -o -path '*/.tools/*' -o -path '*/site/*' -o -path '*/artifacts/*' -o -path '*/scripts/tests/fixtures/*' \) -prune -o \
		\( -name 'compose.yml' -o -name 'compose.yaml' -o -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \) -type f -print \
		2>/dev/null | sort -u
}

find_dockerfiles() {
	find "${ROOT}" \
		\( -path '*/.git/*' -o -path '*/node_modules/*' -o -path '*/.tools/*' -o -path '*/site/*' \) -prune -o \
		\( -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' \) -type f -print \
		2>/dev/null | sort -u
}

run_hadolint_containers() {
	if ! have hadolint; then
		skip "hadolint (install via package group dev)"
		return 0
	fi
	local files=() f
	while IFS= read -r f; do
		[[ -n ${f} ]] && files+=("${f}")
	done < <(find_dockerfiles)
	if [[ ${#files[@]} -eq 0 ]]; then
		skip "hadolint (no Dockerfiles)"
		return 0
	fi
	hadolint "${files[@]}"
}

run_compose_config() {
	local files=() f
	while IFS= read -r f; do
		[[ -n ${f} ]] && files+=("${f}")
	done < <(find_compose_files)
	if [[ ${#files[@]} -eq 0 ]]; then
		skip "compose (no compose files)"
		return 0
	fi
	if ! have docker || ! docker compose version >/dev/null 2>&1; then
		skip "compose (docker compose plugin missing — static file presence only)"
		return 0
	fi
	# `docker compose config` validates YAML without starting services or pulling.
	# Provide harmless placeholders for required interpolate vars (never written to disk).
	local rc=0
	for f in "${files[@]}"; do
		if ! (
			export LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-dots-compose-validate-placeholder}"
			docker compose -f "${f}" config >/dev/null
		) 2>"${TMPDIR:-/tmp}/dots-compose-err.$$"; then
			echo "compose config failed: ${f}" >&2
			sed -n '1,5p' "${TMPDIR:-/tmp}/dots-compose-err.$$" >&2 || true
			rc=1
		fi
		rm -f "${TMPDIR:-/tmp}/dots-compose-err.$$"
	done
	return "${rc}"
}

run_oci_presence() {
	local missing=0
	local t
	for t in skopeo crane oras dive lazydocker; do
		if ! have "${t}"; then
			echo "missing: ${t}" >&2
			missing=1
		fi
	done
	# Optional heavier CLIs — warn only
	for t in devcontainer dagger; do
		have "${t}" || echo "optional missing: ${t}" >&2
	done
	[[ ${missing} -eq 0 ]] || {
		missing_hint containers
		return 1
	}
	return 0
}

containers_status() {
	echo "${BLUE}Containers${NC}"
	echo "────────────────────────────"
	ok_line "docker CLI" "$(docker_cli_state)"
	ok_line "compose plugin" "$(compose_plugin_state)"
	ok_line "runtime reachable" "$(runtime_reachable)"
	ok_line "runtime type" "$(runtime_type)"
	ok_line "OrbStack" "$(orbstack_installed)"
	ok_line "OrbStack running" "$(orbstack_running)"
	echo ""
	echo "OCI tools"
	ok_line "skopeo" "$(tool_ok skopeo)"
	ok_line "crane" "$(tool_ok crane)"
	ok_line "oras" "$(tool_ok oras)"
	ok_line "dive" "$(tool_ok dive)"
	ok_line "lazydocker" "$(tool_ok lazydocker)"
	echo ""
	echo "Dev tooling"
	ok_line "devcontainer" "$(tool_ok devcontainer)"
	ok_line "dagger" "$(tool_ok dagger)"
	echo ""
	echo "No runtime started. No images pulled. Docker Desktop not removed."
	return 0
}

containers_gate() {
	local rc=0
	echo "${BLUE}Container Validation${NC}"
	echo "────────────────────────────"
	run_step "oci-clis" run_oci_presence || rc=1
	run_step "hadolint" run_hadolint_containers || rc=1
	run_step "compose-config" run_compose_config || rc=1
	echo ""
	containers_status || true
	# Runtime absence is informational — does not fail the gate.
	return "${rc}"
}

# ── Kubernetes ──────────────────────────────────────────────────────────────

is_k8s_manifest() {
	local f="$1"
	# Cheap heuristic: apiVersion + kind near top; exclude Actions / MkDocs / compose.
	case "${f}" in
	*/.github/workflows/* | */mkdocs.yml | */compose.y*ml | */docker-compose.y*ml) return 1 ;;
	esac
	head -n 40 "${f}" | grep -qE '^apiVersion:[[:space:]]' || return 1
	head -n 40 "${f}" | grep -qE '^kind:[[:space:]]' || return 1
	return 0
}

find_k8s_manifests() {
	local f
	while IFS= read -r f; do
		[[ -z ${f} ]] && continue
		if is_k8s_manifest "${f}"; then
			printf '%s\n' "${f}"
		fi
	done < <(
		find "${ROOT}" \
			\( -path '*/.git/*' -o -path '*/node_modules/*' -o -path '*/.tools/*' -o -path '*/site/*' -o -path '*/artifacts/*' -o -path '*/scripts/tests/fixtures/*' \) -prune -o \
			\( -name '*.yaml' -o -name '*.yml' \) -type f -print 2>/dev/null | sort -u
	)
}

kubectl_client_ok() {
	have kubectl || {
		missing_hint k8s
		return 1
	}
	kubectl version --client --output=yaml >/dev/null 2>&1 || kubectl version --client >/dev/null 2>&1
}

kubeconfig_state() {
	if [[ -n ${KUBECONFIG:-} && -f ${KUBECONFIG} ]]; then
		echo "present (KUBECONFIG)"
		return
	fi
	if [[ -f ${HOME}/.kube/config ]]; then
		echo "present (~/.kube/config)"
		return
	fi
	echo "NOT CONFIGURED"
}

current_context_state() {
	have kubectl || {
		echo "n/a"
		return
	}
	local ctx
	ctx="$(kubectl config current-context 2>/dev/null || true)"
	[[ -n ${ctx} ]] && echo "${ctx}" || echo "NOT CONFIGURED"
}

cluster_reachable_state() {
	have kubectl || {
		echo "n/a"
		return
	}
	# Short timeout; never mutate.
	if kubectl cluster-info --request-timeout=2s >/dev/null 2>&1; then
		echo "YES"
	else
		echo "NOT CONFIGURED / UNREACHABLE"
	fi
}

run_kubeconform() {
	if ! have kubeconform; then
		skip "kubeconform (not installed)"
		return 0
	fi
	local files=() f
	while IFS= read -r f; do
		[[ -n ${f} ]] && files+=("${f}")
	done < <(find_k8s_manifests)
	if [[ ${#files[@]} -eq 0 ]]; then
		skip "kubeconform (no Kubernetes manifests)"
		return 0
	fi
	kubeconform -summary -ignore-missing-schemas "${files[@]}"
}

run_kubescape_local() {
	if ! have kubescape; then
		skip "kubescape (not installed)"
		return 0
	fi
	local files=() f
	while IFS= read -r f; do
		[[ -n ${f} ]] && files+=("${f}")
	done < <(find_k8s_manifests)
	if [[ ${#files[@]} -eq 0 ]]; then
		skip "kubescape (no Kubernetes manifests)"
		return 0
	fi
	# Local file scan — no login / no cluster / no upload.
	local tmp out
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/dots-kubescape.XXXXXX")"
	out="${tmp}/out.txt"
	local i=0
	for f in "${files[@]}"; do
		cp "${f}" "${tmp}/m-${i}.yaml"
		i=$((i + 1))
	done
	set +e
	kubescape scan "${tmp}" --format pretty-printer --severity-threshold high >"${out}" 2>&1
	local rc=$?
	set -e
	if [[ ${rc} -ne 0 ]] && grep -Eiq 'network|download|framework|offline|connection' "${out}"; then
		skip "kubescape (framework/DB unavailable — not a cluster failure)"
		rm -rf "${tmp}"
		return 0
	fi
	rm -rf "${tmp}"
	return "${rc}"
}

k8s_status() {
	echo "${BLUE}Kubernetes${NC}"
	echo "────────────────────────────"
	echo "TOOLS"
	ok_line "kubectl" "$(tool_ok kubectl)"
	if have kubectl; then
		ok_line "kubectl client" "$(kubectl version --client -o yaml 2>/dev/null | awk '/gitVersion:/{print $2; exit}' || echo present)"
	fi
	ok_line "k9s" "$(tool_ok k9s)"
	ok_line "kubectx" "$(tool_ok kubectx)"
	ok_line "kubens" "$(tool_ok kubens)"
	ok_line "stern" "$(tool_ok stern)"
	ok_line "krew" "$(have krew && echo OK || have kubectl-krew && echo OK || echo missing)"
	ok_line "kubeconform" "$(tool_ok kubeconform)"
	ok_line "kubescape" "$(tool_ok kubescape)"
	ok_line "popeye" "$(tool_ok popeye)"
	ok_line "helmfile" "$(tool_ok helmfile)"
	ok_line "argocd" "$(tool_ok argocd)"
	ok_line "helm" "$(tool_ok helm)"
	echo ""
	echo "CONNECTED ENVIRONMENT"
	ok_line "kubeconfig" "$(kubeconfig_state)"
	ok_line "current context" "$(current_context_state)"
	ok_line "cluster" "$(cluster_reachable_state)"
	echo ""
	echo "No kubeconfig modified. No context/namespace switch. No deploy/sync."
	return 0
}

k8s_gate() {
	local rc=0
	echo "${BLUE}Kubernetes Validation${NC}"
	echo "────────────────────────────"
	run_step "kubectl-client" kubectl_client_ok || rc=1
	run_step "kubeconform" run_kubeconform || rc=1
	run_step "kubescape-local" run_kubescape_local || rc=1
	echo ""
	k8s_status || true
	# Missing/unreachable cluster is informational only.
	return "${rc}"
}

case "${DOMAIN}" in
"" | -h | --help)
	usage
	exit 0
	;;
containers)
	case "${MODE}" in
	status)
		containers_status
		exit $?
		;;
	gate | "")
		containers_gate
		exit $?
		;;
	*)
		echo "Unknown containers mode: ${MODE}" >&2
		usage >&2
		exit 1
		;;
	esac
	;;
k8s)
	case "${MODE}" in
	status)
		k8s_status
		exit $?
		;;
	gate | "")
		k8s_gate
		exit $?
		;;
	*)
		echo "Unknown k8s mode: ${MODE}" >&2
		usage >&2
		exit 1
		;;
	esac
	;;
*)
	echo "Unknown domain: ${DOMAIN}" >&2
	usage >&2
	exit 1
	;;
esac
