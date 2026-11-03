# shellcheck shell=bash
# helpers/litellm.sh — LiteLLM gateway component (localhost Compose)

dots_litellm_dir() {
	printf '%s\n' "${DIR}/services/litellm"
}

dots_litellm_compose() {
	printf '%s\n' "$(dots_litellm_dir)/compose.yml"
}

dots_litellm_key_path() {
	printf '%s\n' "${HOME}/.config/dots/secrets/litellm-master-key"
}

dots_litellm_ensure_master_key() {
	# Generate a random local master key if missing. Never echo the value.
	local key_file
	key_file="$(dots_litellm_key_path)"
	mkdir -p "$(dirname "${key_file}")"
	chmod 700 "$(dirname "${key_file}")" 2>/dev/null || true
	if [[ -s ${key_file} ]]; then
		chmod 600 "${key_file}" 2>/dev/null || true
		return 0
	fi
	if [[ -n ${LITELLM_MASTER_KEY:-} ]]; then
		printf '%s\n' "${LITELLM_MASTER_KEY}" >"${key_file}"
		chmod 600 "${key_file}"
		return 0
	fi
	# Prefer python secrets; fall back to openssl
	if command -v python3 >/dev/null 2>&1; then
		python3 - "${key_file}" <<'PY'
import secrets, sys, pathlib
path = pathlib.Path(sys.argv[1])
path.write_text("sk-dots-" + secrets.token_urlsafe(32) + "\n", encoding="utf-8")
path.chmod(0o600)
PY
	elif command -v openssl >/dev/null 2>&1; then
		printf 'sk-dots-%s\n' "$(openssl rand -base64 32 | tr -d '\n=/+' | head -c 40)" >"${key_file}"
		chmod 600 "${key_file}"
	else
		echo "Error: cannot generate LiteLLM master key (need python3 or openssl)" >&2
		return 1
	fi
	echo "OK: generated LiteLLM master key at ${key_file} (mode 0600; value not printed)"
}

dots_litellm_export_master_key() {
	# Load into current shell env without printing. Required for compose + expert.
	local key_file
	key_file="$(dots_litellm_key_path)"
	if [[ -n ${LITELLM_MASTER_KEY:-} ]]; then
		return 0
	fi
	if [[ ! -s ${key_file} ]]; then
		echo "Error: LiteLLM master key missing. Run: ./dots setup --with litellm" >&2
		return 1
	fi
	# shellcheck disable=SC2002
	LITELLM_MASTER_KEY="$(tr -d '[:space:]' <"${key_file}")"
	export LITELLM_MASTER_KEY
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
		echo "[dry-run] ensure ~/.config/dots/secrets/litellm-master-key"
		echo "[dry-run] would not start LiteLLM (install only)"
		return 0
	fi
	dots_litellm_ensure_master_key || return 1
	# Refuse predictable shipped default if somehow still referenced in compose without env.
	if rg -q 'sk-dots-litellm-local' "${dest}/compose.yml" 2>/dev/null; then
		echo "Error: compose.yml still embeds predictable LITELLM_MASTER_KEY default" >&2
		return 1
	fi
	if ! command -v docker >/dev/null 2>&1; then
		echo "Warn: docker missing — LiteLLM Compose files installed but service not started" >&2
		echo "OK: LiteLLM configured (files + master key present)"
		return 0
	fi
	echo "OK: LiteLLM already configured → ${dest}"
	echo "    Start when needed: ./dots agent gateway up   (binds 127.0.0.1:4000)"
	echo "    Master key: SET (path $(dots_litellm_key_path); value never printed)"
	echo "    OPENROUTER_API_KEY must be set in the environment for remote experts."
	echo "    Note: container process may listen on 0.0.0.0:4000 inside the netns;"
	echo "          Docker publishes only 127.0.0.1:4000 on the host."
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
	dots_litellm_export_master_key || return 1
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
