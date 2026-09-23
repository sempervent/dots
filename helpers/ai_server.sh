# shellcheck shell=bash
# helpers/ai_server.sh — ai-server component (Compose + llama.cpp + Open WebUI)
#
# Requires: DIR, helpers/toml.sh, helpers/state.sh

# shellcheck source=state.sh
[[ -n ${DIR:-} ]] && source "${DIR}/helpers/state.sh" 2>/dev/null || true
# shellcheck source=toml.sh
[[ -n ${DIR:-} ]] && source "${DIR}/helpers/toml.sh" 2>/dev/null || true

dots_ai_registry_dir() {
	printf '%s\n' "${DIR}/configs/ai-server"
}

dots_ai_user_config() {
	printf '%s\n' "$(dots_config_dir)/ai-server.toml"
}

dots_ai_project_dir() {
	printf '%s\n' "$(dots_config_dir)/ai-server"
}

dots_ai_compose_file() {
	printf '%s\n' "$(dots_ai_project_dir)/compose.yml"
}

dots_ai_valid_backend_ids() {
	dots_toml_query "${DIR}/configs/ai-server/backends.toml" <<'PY'
for b in data.get("backends") or []:
    bid = str(b.get("id") or "").strip()
    if bid:
        print(bid)
PY
}

dots_ai_configured() {
	[[ -f $(dots_ai_user_config) ]] || return 1
	return 0
}

dots_ai_require_python_soft() {
	dots_require_python 1 2>/dev/null || command -v python3 >/dev/null 2>&1
}

dots_ai_render_compose() {
	local cfg
	cfg="$(dots_ai_user_config)"
	if [[ ! -f ${cfg} ]]; then
		echo "Error: ai-server not configured ($(dots_ai_user_config) missing)." >&2
		echo "Run: ./setup.sh --with ai-server" >&2
		return 1
	fi
	dots_require_python 0 || return 1
	local secret
	secret="$(dots_ai_ensure_webui_secret)"
	DOTS_AI_WEBUI_SECRET="${secret}" "${DOTS_PYTHON:-python3}" "${DIR}/scripts/ai_compose_render.py" \
		"${DIR}" "${cfg}" "$(dots_ai_project_dir)" render
}

dots_ai_ensure_webui_secret() {
	local envf
	envf="$(dots_ai_project_dir)/.env"
	if [[ -f ${envf} ]] && grep -q '^WEBUI_SECRET_KEY=' "${envf}" 2>/dev/null; then
		grep '^WEBUI_SECRET_KEY=' "${envf}" | head -1 | cut -d= -f2-
		return 0
	fi
	if command -v openssl >/dev/null 2>&1; then
		openssl rand -hex 24
	else
		python3 - <<'PY'
import secrets
print(secrets.token_hex(24))
PY
	fi
}

dots_ai_merged_json() {
	local cfg="${1:-$(dots_ai_user_config)}"
	dots_require_python 0 || return 1
	local secret
	secret="$(dots_ai_ensure_webui_secret)"
	DOTS_AI_WEBUI_SECRET="${secret}" "${DOTS_PYTHON:-python3}" "${DIR}/scripts/ai_compose_render.py" \
		"${DIR}" "${cfg}" "$(dots_ai_project_dir)" print-json 2>/dev/null
}

dots_ai_inventory() {
	local cmd="$1"
	shift
	dots_require_python 0 >/dev/null || return 1
	local cfg
	cfg="$(dots_ai_user_config)"
	[[ -f ${cfg} ]] || {
		echo "Error: ai-server not configured." >&2
		return 1
	}
	"${DOTS_PYTHON:-python3}" "${DIR}/scripts/ai_model_inventory.py" "${DIR}" "${cfg}" "${cmd}" "$@"
}

dots_ai_discover_cmd() {
	dots_ai_inventory discover "$@"
}

dots_ai_model_adopt() {
	local copy=0 target=""
	local arg
	for arg in "$@"; do
		case "${arg}" in
		--copy) copy=1 ;;
		-*)
			echo "Unknown adopt option: ${arg}" >&2
			return 1
			;;
		*)
			target="${arg}"
			;;
		esac
	done
	[[ -n ${target} ]] || {
		echo "Usage: dots ai model adopt [--copy] <path|name|id>" >&2
		return 1
	}
	if [[ ${copy} -eq 1 ]]; then
		dots_ai_inventory adopt "${target}" --copy
	else
		dots_ai_inventory adopt "${target}"
	fi
}

dots_ai_seed_config() {
	local dest src
	dest="$(dots_ai_user_config)"
	src="${DIR}/configs/ai-server/defaults.toml"
	mkdir -p "$(dots_config_dir)"
	if [[ -f ${dest} ]]; then
		echo "OK: ai-server config already present → ${dest}"
		return 0
	fi
	cp "${src}" "${dest}"
	echo "OK: seeded ai-server config → ${dest}"
}

dots_ai_ensure_runtime_dirs() {
	local json rt models webui state
	json="$(dots_ai_merged_json)" || return 1
	rt="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["runtime_root"])')"
	models="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["models_dir"])')"
	webui="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["webui_data_dir"])')"
	state="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["state_dir"])')"
	mkdir -p "${rt}" "${models}" "${webui}" "${state}" "$(dots_ai_project_dir)"
}

dots_ai_validate_config() {
	local cfg="${1:-$(dots_ai_user_config)}"
	[[ -f ${cfg} ]] || {
		echo "Error: missing ${cfg}" >&2
		return 1
	}
	dots_require_python 0 || return 1
	local backend
	backend="$(dots_toml_query "${cfg}" <<'PY'
print(str(data.get("ai_server", {}).get("backend") or "cpu"))
PY
)" || return 1
	local ok=0 id
	while IFS= read -r id; do
		[[ ${id} == "${backend}" ]] && ok=1
	done < <(dots_ai_valid_backend_ids)
	if [[ ${ok} -ne 1 ]]; then
		echo "Error: invalid ai_server.backend '${backend}'." >&2
		echo "Supported backends:" >&2
		dots_ai_valid_backend_ids | sed 's/^/  /' >&2
		return 1
	fi
	dots_ai_merged_json "${cfg}" >/dev/null || return 1
	return 0
}

dots_ai_compose_cmd() {
	local subcmd="$1"
	shift
	local files=(-f "$(dots_ai_compose_file)")
	local override
	override="$(dots_ai_project_dir)/compose.override.yml"
	[[ -f ${override} ]] && files+=(-f "${override}")
	if [[ -n ${DOTS_AI_MOCK_DOCKER:-} ]]; then
		echo "[mock] docker compose ${subcmd} ${files[*]} $*"
		return 0
	fi
	if ! command -v docker >/dev/null 2>&1; then
		echo "Error: docker not found on PATH." >&2
		return 1
	fi
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
		cd "$(dots_ai_project_dir)" || exit 1
		"${compose_args[@]}" "${files[@]}" "${subcmd}" "$@"
	)
}

dots_ai_list_models() {
	# Managed basenames only (ai-server models_dir).
	local models_dir json
	json="$(dots_ai_merged_json)" || return 1
	models_dir="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["models_dir"])')"
	[[ -d ${models_dir} ]] || return 0
	local f base
	while IFS= read -r f; do
		[[ -n ${f} ]] || continue
		base="$(basename "${f}")"
		[[ ${base} == *.part ]] && continue
		printf '%s\n' "${base}"
	done < <(find "${models_dir}" -maxdepth 1 \( -type f -o -type l \) \( -name '*.gguf' -o -name '*.GGUF' \) 2>/dev/null | sort)
}

dots_ai_model_set_default() {
	local name="$1" cfg
	if [[ ${name} == *"/"* || ${name} == *".."* ]]; then
		echo "Error: model name must be a basename." >&2
		return 1
	fi
	name="$(basename "${name}")"
	if [[ ${name} == *"/"* || ${name} == *".."* ]]; then
		echo "Error: model name must be a basename." >&2
		return 1
	fi
	cfg="$(dots_ai_user_config)"
	[[ -f ${cfg} ]] || return 1
	local models_dir
	models_dir="$(dots_ai_merged_json | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["models_dir"])')"
	if [[ ! -f ${models_dir}/${name} ]]; then
		echo "Error: '${name}' is not in the managed models directory (${models_dir})." >&2
		echo "Adopt an existing GGUF first:  dots ai model adopt <path>" >&2
		echo "Or discover inventory:         dots ai discover" >&2
		return 1
	fi
	dots_require_python 0 || return 1
	NAME="${name}" CFG="${cfg}" "${DOTS_PYTHON:-python3}" - <<'PY'
import os, pathlib, tomllib
cfg = pathlib.Path(os.environ["CFG"])
name = os.environ["NAME"]
text = cfg.read_text(encoding="utf-8")
lines = text.splitlines()
out = []
in_ai = False
found = False
for line in lines:
    if line.strip() == "[ai_server]":
        in_ai = True
        out.append(line)
        continue
    if in_ai and line.startswith("[") and line.strip() != "[ai_server]":
        if not found:
            out.append(f'default_model = "{name}"')
            found = True
        in_ai = False
    if in_ai and line.strip().startswith("default_model"):
        out.append(f'default_model = "{name}"')
        found = True
        continue
    out.append(line)
if in_ai and not found:
    out.append(f'default_model = "{name}"')
    found = True
if not found:
    out.append("")
    out.append("[ai_server]")
    out.append(f'default_model = "{name}"')
cfg.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
	dots_ai_render_compose
}

dots_ai_model_add() {
	local src="$1" json models_dir url out base tmp
	[[ -n ${src} ]] || {
		echo "Usage: dots ai model add <path-or-hf://…>" >&2
		return 1
	}
	json="$(dots_ai_merged_json)" || return 1
	models_dir="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["models_dir"])')"
	mkdir -p "${models_dir}/.incomplete"
	if [[ -f ${src} ]]; then
		base="$(basename "${src}")"
		cp -p "${src}" "${models_dir}/${base}"
		echo "OK: installed ${base}"
		return 0
	fi
	if [[ ${src} == hf://* ]]; then
		url="https://huggingface.co/${src#hf://}"
		base="$(basename "${url}")"
		tmp="${models_dir}/.incomplete/${base}.part"
		out="${models_dir}/${base}"
		if [[ -f ${out} ]]; then
			echo "OK: already present ${base}"
			return 0
		fi
		if ! command -v curl >/dev/null 2>&1; then
			echo "Error: curl required for Hugging Face downloads." >&2
			return 1
		fi
		local curl_args=(-fL --retry 3 --connect-timeout 30)
		if [[ -t 1 ]]; then
			curl_args+=(--progress-bar)
		else
			curl_args+=(-sS)
		fi
		echo "Downloading ${base}…"
		if ! curl "${curl_args[@]}" -o "${tmp}" "${url}"; then
			rm -f "${tmp}"
			echo "Error: download failed for ${url}" >&2
			return 1
		fi
		mv -f "${tmp}" "${out}"
		echo "OK: downloaded ${base}"
		return 0
	fi
	echo "Error: unsupported source (use a local .gguf path or hf://owner/repo/file.gguf)." >&2
	return 1
}

dots_ai_model_remove() {
	local name="$1" json models_dir path
	name="$(basename "${name}")"
	json="$(dots_ai_merged_json)" || return 1
	models_dir="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["models_dir"])')"
	path="${models_dir}/${name}"
	[[ -f ${path} ]] || {
		echo "Error: model not found: ${path}" >&2
		return 1
	}
	rm -f "${path}"
	echo "OK: removed ${name}"
}

dots_ai_http_ok() {
	local url="$1"
	if command -v curl >/dev/null 2>&1; then
		curl -fsS --max-time 5 "${url}" >/dev/null 2>&1
		return $?
	fi
	return 1
}

dots_ai_service_health() {
	local kind="$1" json port webui_port
	json="$(dots_ai_merged_json)" || return 1
	port="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["llama_port"])')"
	webui_port="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["webui_port"])')"
	case "${kind}" in
	llama)
		dots_ai_http_ok "http://127.0.0.1:${port}/v1/models" && return 0
		dots_ai_http_ok "http://127.0.0.1:${port}/health" && return 0
		return 1
		;;
	webui)
		dots_ai_http_ok "http://127.0.0.1:${webui_port}/health" && return 0
		dots_ai_http_ok "http://127.0.0.1:${webui_port}/" && return 0
		return 1
		;;
	esac
	return 1
}

dots_ai_container_state() {
	local svc="$1"
	if [[ -n ${DOTS_AI_MOCK_DOCKER:-} ]]; then
		printf '%s\n' "stopped"
		return 0
	fi
	local line
	line="$(docker compose -f "$(dots_ai_compose_file)" ps --format '{{.Service}} {{.State}}' 2>/dev/null | awk -v s="${svc}" '$1==s {print $2; exit}')"
	[[ -n ${line} ]] && printf '%s\n' "${line}" || printf '%s\n' "not_created"
}

dots_ai_status() {
	local json backend rt models webui_port default_model
	if ! dots_ai_configured; then
		echo "AI server: not configured"
		echo "  Run: ./setup.sh --profile server --with ai-server"
		return 0
	fi
	json="$(dots_ai_merged_json)" || return 1
	backend="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["backend_id"])')"
	rt="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["runtime_root"])')"
	models="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["models_dir"])')"
	webui_port="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["webui_port"])')"
	default_model="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["default_model"])')"
	echo "AI server"
	echo "  component:     ai-server"
	echo "  backend:       ${backend}"
	echo "  runtime root:  ${rt}"
	echo "  models:        ${models}"
	echo "  Open WebUI:    http://127.0.0.1:${webui_port}"
	echo "  default model: ${default_model:-(none)}"
	if dots_ai_configured && dots_ai_require_python_soft; then
		local dst
		dst="$(dots_ai_inventory default-status 2>/dev/null || true)"
		if [[ -n ${dst} ]]; then
			local ok resolved src
			ok="$(printf '%s' "${dst}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin).get("ok"))' 2>/dev/null || true)"
			resolved="$(printf '%s' "${dst}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin).get("resolved_path") or "")' 2>/dev/null || true)"
			src="$(printf '%s' "${dst}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin).get("source") or "")' 2>/dev/null || true)"
			if [[ -n ${default_model} ]]; then
				if [[ ${ok} == True ]]; then
					echo "  model resolve: OK (${src})"
					echo "  model path:    ${resolved}"
				else
					echo "  model resolve: MISSING in models_dir (found elsewhere: ${src:-unknown})"
					echo "  model path:    ${resolved:-—}"
					echo "  hint:          dots ai model adopt ${default_model}"
				fi
			fi
		fi
	fi
	if [[ -n ${DOTS_AI_MOCK_DOCKER:-} ]]; then
		echo "  webui:         (mock)"
		echo "  llama-server:  (mock)"
		echo "  API:           (mock)"
		return 0
	fi
	local lstate wstate
	lstate="$(dots_ai_container_state llama 2>/dev/null || echo unknown)"
	wstate="$(dots_ai_container_state open-webui 2>/dev/null || echo unknown)"
	echo "  webui:         ${wstate}"
	echo "  llama-server:  ${lstate}"
	if dots_ai_service_health llama 2>/dev/null; then
		echo "  llama API:     HEALTHY"
	else
		echo "  llama API:     unavailable"
	fi
	if dots_ai_service_health webui 2>/dev/null; then
		echo "  WebUI HTTP:    HEALTHY"
	else
		echo "  WebUI HTTP:    unavailable"
	fi
}

dots_ai_doctor_line() {
	local level="$1" msg="$2"
	printf '%-5s %s\n' "${level}" "${msg}"
}

dots_ai_doctor() {
	local fails=0 warns=0
	if dots_ai_configured; then
		dots_ai_doctor_line PASS "ai-server config present"
	else
		dots_ai_doctor_line FAIL "ai-server not configured (run setup --with ai-server)"
		fails=$((fails + 1))
	fi
	if dots_ai_validate_config 2>/dev/null; then
		dots_ai_doctor_line PASS "config/backend valid"
	else
		dots_ai_doctor_line FAIL "config/backend invalid"
		fails=$((fails + 1))
	fi
	if command -v docker >/dev/null 2>&1; then
		dots_ai_doctor_line PASS "Docker available"
	else
		dots_ai_doctor_line FAIL "Docker not found"
		fails=$((fails + 1))
	fi
	if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
		dots_ai_doctor_line PASS "Compose available"
	else
		dots_ai_doctor_line FAIL "Compose not available"
		fails=$((fails + 1))
	fi
	local json backend
	json="$(dots_ai_merged_json 2>/dev/null || true)"
	if [[ -n ${json} ]]; then
		backend="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["backend_id"])')"
		dots_ai_doctor_line PASS "backend ${backend}"
		local models_dir default_model
		models_dir="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["models_dir"])')"
		default_model="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["default_model"])')"
		if [[ -d ${models_dir} && -w ${models_dir} ]]; then
			dots_ai_doctor_line PASS "models dir writable"
		else
			dots_ai_doctor_line WARN "models dir missing or not writable (${models_dir})"
			warns=$((warns + 1))
		fi
		if [[ -n ${default_model} && -f ${models_dir}/${default_model} ]]; then
			dots_ai_doctor_line PASS "default model present in models_dir"
		elif [[ -n ${default_model} ]]; then
			dots_ai_doctor_line WARN "default model configured but missing in models_dir: ${default_model}"
			warns=$((warns + 1))
		else
			dots_ai_doctor_line WARN "no default model selected"
			warns=$((warns + 1))
		fi
		if dots_ai_require_python_soft; then
			while IFS= read -r line; do
				[[ -z ${line} ]] && continue
				case "${line}" in
				PASS*) dots_ai_doctor_line PASS "${line#PASS }" ;;
				WARN*) dots_ai_doctor_line WARN "${line#WARN }"; warns=$((warns + 1)) ;;
				INFO*) dots_ai_doctor_line INFO "${line#INFO }" ;;
				esac
			done < <(dots_ai_inventory doctor 2>/dev/null || true)
		fi
		case "${backend}" in
		cuda)
			if docker info 2>/dev/null | grep -qi nvidia; then
				dots_ai_doctor_line PASS "NVIDIA runtime visible to Docker"
			else
				dots_ai_doctor_line WARN "NVIDIA runtime not detected (CUDA backend)"
				warns=$((warns + 1))
			fi
			;;
		native)
			if command -v llama-server >/dev/null 2>&1; then
				dots_ai_doctor_line PASS "llama-server on PATH"
			else
				dots_ai_doctor_line FAIL "native backend requires llama-server binary"
				fails=$((fails + 1))
			fi
			;;
		esac
		if [[ -f $(dots_ai_compose_file) ]]; then
			if docker compose -f "$(dots_ai_compose_file)" config >/dev/null 2>&1; then
				dots_ai_doctor_line PASS "compose config validates"
			else
				dots_ai_doctor_line FAIL "compose config invalid"
				fails=$((fails + 1))
			fi
		fi
	fi
	if [[ ${fails} -gt 0 ]]; then
		return 1
	fi
	return 0
}

dots_ai_up() {
	dots_ai_validate_config || return 1
	dots_ai_ensure_runtime_dirs || return 1
	dots_ai_render_compose || return 1
	local json models_dir default_model backend compose_ok
	json="$(dots_ai_merged_json)" || return 1
	backend="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["backend_id"])')"
	compose_ok="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["compose_enabled"])')"
	models_dir="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["models_dir"])')"
	default_model="$(printf '%s' "${json}" | "${DOTS_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["default_model"])')"
	if [[ ${compose_ok} != "True" && ${compose_ok} != "true" ]]; then
		echo "Error: backend '${backend}' uses native lifecycle (not implemented in v1 Compose path)." >&2
		echo "Select a Docker backend in $(dots_ai_user_config) or use llama-server manually." >&2
		return 1
	fi
	if [[ -z ${default_model} ]]; then
		echo "Error: no default_model configured." >&2
		echo "List models:  dots ai models" >&2
		echo "Set default:  dots ai model default <model.gguf>" >&2
		return 1
	fi
	if [[ ! -f ${models_dir}/${default_model} ]]; then
		echo "Error: default model missing: ${models_dir}/${default_model}" >&2
		echo "Managed models:" >&2
		dots_ai_list_models | sed 's/^/  /' >&2 || true
		echo "Discover others: dots ai discover" >&2
		echo "Adopt then default: dots ai model adopt <path> && dots ai model default ${default_model}" >&2
		return 1
	fi
	dots_ai_compose_cmd up -d
}

dots_ai_down() {
	[[ -f $(dots_ai_compose_file) ]] || {
		echo "AI stack not rendered yet (nothing to stop)."
		return 0
	}
	dots_ai_compose_cmd down --remove-orphans
}

dots_ai_restart() {
	dots_ai_down || true
	dots_ai_up
}

dots_ai_logs() {
	local svc="${1:-}"
	shift || true
	if [[ -z ${svc} ]]; then
		dots_ai_compose_cmd logs "$@"
	else
		dots_ai_compose_cmd logs "${svc}" "$@"
	fi
}

dots_ai_ps() {
	dots_ai_compose_cmd ps
}

dots_ai_models_cmd() {
	dots_ai_inventory managed "$@"
}

dots_ai_server_setup() {
	echo "=== AI server (ai-server) ==="
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] would seed $(dots_ai_user_config) and runtime directories"
		return 0
	fi
	dots_ai_seed_config || return 1
	dots_ai_validate_config || return 1
	dots_ai_ensure_runtime_dirs || return 1
	dots_ai_render_compose || return 1
	echo "Runtime root and compose project ready."
	echo "Next: dots ai discover → model adopt → model default → dots ai up"
}
