# shellcheck shell=bash
# helpers/model_providers.sh — provider adapters for pull_models.sh
#
# Each provider exposes:
#   dots_mp_<provider>_available   → 0 if runtime binary present
#   dots_mp_<provider>_has_model <id-fields...> → 0 if installed
#   dots_mp_<provider>_pull <...>  → download (respects DRY_RUN / DOTS_MODEL_DRY_RUN)
#   dots_mp_<provider>_list        → inventory (best-effort)
#
# Test injection: set DOTS_MODEL_MOCK=1 and use mock binaries on PATH, or
# set DOTS_MP_MOCK_<PROVIDER>_HAS / DOTS_MP_MOCK_<PROVIDER>_PULL.

# --- Ollama ------------------------------------------------------------------
# Upstream: https://docs.ollama.com/cli

dots_mp_ollama_bin() {
	command -v ollama 2>/dev/null || true
}

dots_mp_ollama_available() {
	[[ -n ${DOTS_MP_MOCK_OLLAMA:-} ]] && return 0
	[[ -n "$(dots_mp_ollama_bin)" ]]
}

dots_mp_ollama_list() {
	if [[ -n ${DOTS_MP_MOCK_OLLAMA_LIST:-} ]]; then
		printf '%s\n' "${DOTS_MP_MOCK_OLLAMA_LIST}"
		return 0
	fi
	ollama ls 2>/dev/null || ollama list 2>/dev/null || true
}

dots_mp_ollama_has_model() {
	local want="$1" line name
	if [[ -n ${DOTS_MP_MOCK_OLLAMA_HAS:-} ]]; then
		case " ${DOTS_MP_MOCK_OLLAMA_HAS} " in
		*" ${want} "*) return 0 ;;
		*) return 1 ;;
		esac
	fi
	while IFS= read -r line; do
		[[ -z ${line} || ${line} == NAME* || ${line} == NAME\ * ]] && continue
		name="${line%%[[:space:]]*}"
		# Match exact or tag-prefix (qwen2.5:7b == qwen2.5:7b)
		[[ ${name} == "${want}" || ${name} == "${want}:"* ]] && return 0
		# Also match when want has no tag and list has :latest
		[[ ${want} != *:* && ${name} == "${want}:"* ]] && return 0
	done < <(dots_mp_ollama_list)
	return 1
}

# Start ollama serve temporarily if needed; restore prior state.
dots_mp_ollama_ensure_server() {
	local dry="${DOTS_MODEL_DRY_RUN:-0}"
	if [[ -n ${DOTS_MP_MOCK_OLLAMA:-} ]]; then
		DOTS_MP_OLLAMA_STARTED_TEMP=0
		return 0
	fi
	DOTS_MP_OLLAMA_STARTED_TEMP=0
	if ollama list >/dev/null 2>&1 || ollama ls >/dev/null 2>&1; then
		return 0
	fi
	if [[ ${dry} -eq 1 ]]; then
		echo "[dry-run] would start temporary: ollama serve"
		return 0
	fi
	echo "Note: starting temporary ollama serve for model pull..."
	ollama serve >/dev/null 2>&1 &
	DOTS_MP_OLLAMA_SERVE_PID=$!
	DOTS_MP_OLLAMA_STARTED_TEMP=1
	local i=0
	while [[ ${i} -lt 30 ]]; do
		if ollama list >/dev/null 2>&1 || ollama ls >/dev/null 2>&1; then
			return 0
		fi
		sleep 1
		i=$((i + 1))
	done
	echo "Error: ollama serve did not become ready" >&2
	return 1
}

dots_mp_ollama_restore_server() {
	if [[ ${DOTS_MP_OLLAMA_STARTED_TEMP:-0} -eq 1 ]]; then
		if [[ ${DOTS_MODEL_DRY_RUN:-0} -eq 1 ]]; then
			echo "[dry-run] would stop temporary ollama serve"
		else
			echo "Note: stopping temporary ollama serve"
			kill "${DOTS_MP_OLLAMA_SERVE_PID:-}" 2>/dev/null || true
			wait "${DOTS_MP_OLLAMA_SERVE_PID:-}" 2>/dev/null || true
		fi
		DOTS_MP_OLLAMA_STARTED_TEMP=0
	fi
}

dots_mp_ollama_pull() {
	local model="$1"
	local dry="${DOTS_MODEL_DRY_RUN:-0}"
	echo "Source: Ollama registry (${model})"
	if [[ ${dry} -eq 1 ]]; then
		echo "[dry-run] ollama pull ${model}"
		return 0
	fi
	if [[ -n ${DOTS_MP_MOCK_OLLAMA_PULL:-} ]]; then
		echo "[mock] ollama pull ${model}"
		return 0
	fi
	dots_mp_ollama_ensure_server || return 1
	ollama pull "${model}"
}

# --- llama.cpp ---------------------------------------------------------------
# Upstream: https://github.com/ggml-org/llama.cpp — llama-cli -hf / --cache-list

dots_mp_llamacpp_bin() {
	command -v llama-cli 2>/dev/null || command -v llama 2>/dev/null || true
}

dots_mp_llamacpp_available() {
	[[ -n ${DOTS_MP_MOCK_LLAMACPP:-} ]] && return 0
	[[ -n "$(dots_mp_llamacpp_bin)" ]]
}

dots_mp_llamacpp_cache_list() {
	if [[ -n ${DOTS_MP_MOCK_LLAMACPP_LIST:-} ]]; then
		printf '%s\n' "${DOTS_MP_MOCK_LLAMACPP_LIST}"
		return 0
	fi
	local bin
	bin="$(dots_mp_llamacpp_bin)"
	[[ -z ${bin} ]] && return 0
	"${bin}" --cache-list 2>/dev/null || true
}

dots_mp_grep_fixed() {
	local pat="$1"
	if command -v rg >/dev/null 2>&1; then
		rg -q --fixed-strings -- "${pat}"
	else
		grep -Fq -- "${pat}"
	fi
}

dots_mp_llamacpp_has_model() {
	local repo="$1" quant="${2:-}"
	local needle="${repo}"
	[[ -n ${quant} ]] && needle="${repo}:${quant}"
	if [[ -n ${DOTS_MP_MOCK_LLAMACPP_HAS:-} ]]; then
		case " ${DOTS_MP_MOCK_LLAMACPP_HAS} " in
		*" ${needle} "* | *" ${repo} "*) return 0 ;;
		*) return 1 ;;
		esac
	fi
	local out
	out="$(dots_mp_llamacpp_cache_list)"
	printf '%s\n' "${out}" | dots_mp_grep_fixed "${repo}" || return 1
	if [[ -n ${quant} ]]; then
		printf '%s\n' "${out}" | dots_mp_grep_fixed "${quant}" || return 1
	fi
	return 0
}

dots_mp_llamacpp_pull() {
	local repo="$1" quant="${2:-}"
	local spec="${repo}"
	[[ -n ${quant} ]] && spec="${repo}:${quant}"
	local bin dry="${DOTS_MODEL_DRY_RUN:-0}"
	bin="$(dots_mp_llamacpp_bin)"
	echo "Source: Hugging Face via llama-cli -hf (${spec})"
	if [[ ${dry} -eq 1 ]]; then
		echo "[dry-run] ${bin:-llama-cli} -hf ${spec} -n 0 --no-warmup"
		return 0
	fi
	if [[ -n ${DOTS_MP_MOCK_LLAMACPP_PULL:-} ]]; then
		echo "[mock] llama-cli -hf ${spec}"
		return 0
	fi
	[[ -n ${bin} ]] || {
		echo "Error: llama-cli not found" >&2
		return 1
	}
	# Fill HF cache without meaningful generation (-n 0).
	# HF_TOKEN honored by llama-cli; never print it.
	"${bin}" -hf "${spec}" -n 0 --no-warmup </dev/null
}

# --- Draw Things -------------------------------------------------------------
# Upstream: draw-things-cli models list|ensure

dots_mp_drawthings_bin() {
	command -v draw-things-cli 2>/dev/null || true
}

dots_mp_drawthings_available() {
	[[ -n ${DOTS_MP_MOCK_DRAWTHINGS:-} ]] && return 0
	[[ -n "$(dots_mp_drawthings_bin)" ]]
}

dots_mp_drawthings_list_downloaded() {
	if [[ -n ${DOTS_MP_MOCK_DRAWTHINGS_LIST:-} ]]; then
		printf '%s\n' "${DOTS_MP_MOCK_DRAWTHINGS_LIST}"
		return 0
	fi
	draw-things-cli models list --downloaded-only 2>/dev/null || true
}

dots_mp_drawthings_has_model() {
	local want="$1"
	if [[ -n ${DOTS_MP_MOCK_DRAWTHINGS_HAS:-} ]]; then
		case " ${DOTS_MP_MOCK_DRAWTHINGS_HAS} " in
		*" ${want} "*) return 0 ;;
		*) return 1 ;;
		esac
	fi
	dots_mp_drawthings_list_downloaded | dots_mp_grep_fixed "${want}"
}

dots_mp_drawthings_pull() {
	local model="$1"
	local dry="${DOTS_MODEL_DRY_RUN:-0}"
	echo "Source: Draw Things model catalog (${model})"
	if [[ ${dry} -eq 1 ]]; then
		echo "[dry-run] draw-things-cli models ensure --model ${model}"
		return 0
	fi
	if [[ -n ${DOTS_MP_MOCK_DRAWTHINGS_PULL:-} ]]; then
		echo "[mock] draw-things-cli models ensure --model ${model}"
		return 0
	fi
	draw-things-cli models ensure --model "${model}"
}

# --- FluidVoice --------------------------------------------------------------
# Upstream: app UI only — https://github.com/altic-dev/FluidVoice

dots_mp_fluidvoice_available() {
	[[ -n ${DOTS_MP_MOCK_FLUIDVOICE:-} ]] && return 0
	[[ -d /Applications/FluidVoice.app ]] || brew list --cask fluidvoice >/dev/null 2>&1
}

dots_mp_fluidvoice_has_model() {
	# No supported inventory API — always "unknown"/absent for automation.
	if [[ -n ${DOTS_MP_MOCK_FLUIDVOICE_HAS:-} ]]; then
		case " ${DOTS_MP_MOCK_FLUIDVOICE_HAS} " in
		*" $1 "*) return 0 ;;
		*) return 1 ;;
		esac
	fi
	return 1
}

dots_mp_fluidvoice_pull() {
	local model="$1"
	local dry="${DOTS_MODEL_DRY_RUN:-0}"
	echo "FluidVoice:"
	echo "  automatic model pull unsupported by current upstream interface"
	echo "  recommended: ${model}"
	echo "  download via FluidVoice app onboarding / Settings → Models"
	if [[ ${dry} -eq 1 ]]; then
		echo "[dry-run] would not launch FluidVoice; would not write caches"
		return 0
	fi
	# Return special code 2 = MANUAL (caller maps to MANUAL status, non-fatal)
	return 2
}

dots_mp_fluidvoice_maybe_open() {
	local dry="${DOTS_MODEL_DRY_RUN:-0}"
	if [[ ${dry} -eq 1 ]]; then
		echo "[dry-run] would offer: open -a FluidVoice"
		return 0
	fi
	if [[ ${DOTS_MODEL_YES:-0} -eq 1 ]]; then
		return 0
	fi
	local ans
	read -r -p "Open FluidVoice now so you can download models? [y/N] " ans
	case "${ans}" in
	y | Y | yes | YES)
		open -a FluidVoice 2>/dev/null || true
		;;
	esac
}
