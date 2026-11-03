# shellcheck shell=bash
# helpers/litellm.sh — LiteLLM gateway component (localhost Compose)

dots_litellm_dir() {
	printf '%s\n' "${DIR}/services/litellm"
}

dots_litellm_compose() {
	printf '%s\n' "$(dots_litellm_dir)/compose.yml"
}

dots_litellm_setup() {
	echo "=== LiteLLM gateway ==="
	local dest
	dest="$(dots_litellm_dir)"
	if [[ ! -f ${dest}/compose.yml ]]; then
		echo "Error: missing ${dest}/compose.yml" >&2
		return 1
	fi
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] validate ${dest}/compose.yml + config.yaml"
		echo "[dry-run] would not start LiteLLM (install only)"
		return 0
	fi
	if ! command -v docker >/dev/null 2>&1; then
		echo "Warn: docker missing — LiteLLM Compose files installed but service not started" >&2
		echo "OK: LiteLLM already configured (files present)"
		return 0
	fi
	# Idempotent: files are the config; do not auto-start publicly.
	echo "OK: LiteLLM already configured → ${dest}"
	echo "    Start when needed: ./dots agent gateway up   (binds 127.0.0.1:4000)"
	echo "    OPENROUTER_API_KEY must be set in the environment for remote experts."
}

dots_litellm_compose_cmd() {
	local subcmd="$1"
	shift
	local compose_args=()
	if docker compose version >/dev/null 2>&1; then
		compose_args=(docker compose)
	elif command -v docker-compose >/dev/null 2>&1; then
		compose_args=(docker-compose)
	else
		echo "Error: docker compose / docker-compose not available." >&2
		return 1
	fi
	(
		cd "$(dots_litellm_dir)" || exit 1
		"${compose_args[@]}" -f compose.yml "${subcmd}" "$@"
	)
}

dots_litellm_up() {
	dots_litellm_compose_cmd up -d
}

dots_litellm_down() {
	dots_litellm_compose_cmd down
}

dots_litellm_health() {
	local url="${DOTS_LITELLM_URL:-http://127.0.0.1:4000/health}"
	if command -v curl >/dev/null 2>&1; then
		curl -fsS --max-time 3 "${url}" >/dev/null 2>&1
		return $?
	fi
	python3 - "${url}" <<'PY'
import sys, urllib.request
urllib.request.urlopen(sys.argv[1], timeout=3)
PY
}
