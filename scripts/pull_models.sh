#!/usr/bin/env bash
# scripts/pull_models.sh — adaptive local model acquisition for DOTS
#
# Installs runtimes via setup/bootstrap; this script fills them.
# Large downloads are never implied by ordinary bootstrap.
#
# Usage:
#   ./scripts/pull_models.sh
#   ./scripts/pull_models.sh --dry-run
#   ./scripts/pull_models.sh --list
#   ./scripts/pull_models.sh --provider ollama
#   ./scripts/pull_models.sh --tier balanced
#   ./scripts/pull_models.sh --yes
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

# shellcheck source=../helpers/toml.sh
source "${DIR}/helpers/toml.sh"
# shellcheck source=../helpers/hardware.sh
source "${DIR}/helpers/hardware.sh"
# shellcheck source=../helpers/model_providers.sh
source "${DIR}/helpers/model_providers.sh"
# shellcheck source=../helpers/models.sh
source "${DIR}/helpers/models.sh"

DOTS_MODEL_DRY_RUN=0
DOTS_MODEL_YES=0
LIST_ONLY=0
DO_UPDATE=0
OPEN_FLUIDVOICE=0
PROVIDER_ARGS=()
MODEL_IDS=()
TIER_ARG=""

usage() {
	cat <<'EOF'
Usage: ./scripts/pull_models.sh [options]

Select and download local models according to hardware + configs/models.toml.
Bootstrap/setup do NOT pull large models by default.

Options:
  --list              Show hardware, tier, plan, and local status (no mutations)
  --dry-run           Print actions without downloading / starting services
  --yes               Skip confirmation prompts
  --tier <name>       minimal|balanced|large|max|auto (default: auto)
  --provider <name>   ollama|llamacpp|drawthings|fluidvoice|all (repeatable)
  --model <id>        Registry model id (repeatable)
  --update            Re-pull registry targets even if present
  --include-cleanup   Include optional Fluid-1 cleanup model
  -h, --help          Show this help

Examples:
  ./scripts/pull_models.sh --list
  ./scripts/pull_models.sh --dry-run
  ./scripts/pull_models.sh --provider ollama --tier balanced
  ./scripts/pull_models.sh --yes

User overrides: ~/.config/dots/models.toml
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	--list)
		LIST_ONLY=1
		shift
		;;
	--dry-run)
		DOTS_MODEL_DRY_RUN=1
		shift
		;;
	--yes | -y)
		DOTS_MODEL_YES=1
		shift
		;;
	--tier)
		TIER_ARG="${2:-}"
		shift 2
		;;
	--tier=*)
		TIER_ARG="${1#*=}"
		shift
		;;
	--provider)
		IFS=',' read -r -a _provs <<<"${2:-}"
		PROVIDER_ARGS+=("${_provs[@]+"${_provs[@]}"}")
		shift 2
		;;
	--provider=*)
		IFS=',' read -r -a _provs <<<"${1#*=}"
		PROVIDER_ARGS+=("${_provs[@]+"${_provs[@]}"}")
		shift
		;;
	--model)
		MODEL_IDS+=("${2:-}")
		shift 2
		;;
	--model=*)
		MODEL_IDS+=("${1#*=}")
		shift
		;;
	--update)
		DO_UPDATE=1
		shift
		;;
	--include-cleanup)
		DOTS_MODEL_INCLUDE_CLEANUP=1
		export DOTS_MODEL_INCLUDE_CLEANUP
		shift
		;;
	*)
		echo "Error: unknown option: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

export DOTS_MODEL_DRY_RUN DOTS_MODEL_YES

if [[ -n ${TIER_ARG} ]]; then
	case "${TIER_ARG}" in
	auto | minimal | balanced | large | max) ;;
	*)
		echo "Error: invalid --tier '${TIER_ARG}'" >&2
		exit 1
		;;
	esac
	export DOTS_MODEL_TIER="${TIER_ARG}"
fi

# Expand --provider all
if [[ ${#PROVIDER_ARGS[@]} -gt 0 ]]; then
	local_expanded=()
	for p in "${PROVIDER_ARGS[@]}"; do
		if [[ ${p} == all ]]; then
			local_expanded+=(ollama llamacpp drawthings fluidvoice)
		else
			case "${p}" in
			ollama | llamacpp | drawthings | fluidvoice) local_expanded+=("${p}") ;;
			*)
				echo "Error: unknown provider '${p}'" >&2
				exit 1
				;;
			esac
		fi
	done
	# dedupe
	DOTS_MODEL_PROVIDERS="$(printf '%s\n' "${local_expanded[@]}" | awk 'NF && !seen[$0]++' | tr '\n' ',' | sed 's/,$//')"
	export DOTS_MODEL_PROVIDERS
fi

if [[ ${#MODEL_IDS[@]} -gt 0 ]]; then
	DOTS_MODEL_IDS="$(
		IFS=,
		echo "${MODEL_IDS[*]}"
	)"
	export DOTS_MODEL_IDS
fi

dots_require_python 0 || exit 1
dots_validate_models_registry >/dev/null || exit 1

tier="$(dots_models_select_tier)"
reserve="$(dots_models_reserve_disk_gb)"
free_disk="$(dots_hw_disk_free_gb)"

echo "=== DOTS local models ==="
dots_hw_summary
echo "  selected tier: ${tier}"
echo ""

# Detect providers (unless filtered)
mapfile_providers=()
while IFS= read -r line; do
	[[ -n ${line} ]] && mapfile_providers+=("${line}")
done < <(dots_models_detect_providers)

echo "Installed providers:"
if [[ ${#mapfile_providers[@]} -eq 0 ]]; then
	echo "  (none — install with ./setup.sh --with ollama,llamacpp,…)"
else
	printf '  %s\n' "${mapfile_providers[@]}"
fi
echo ""

# If user did not specify providers, restrict plan to installed ones.
if [[ -z ${DOTS_MODEL_PROVIDERS:-} ]]; then
	if [[ ${#mapfile_providers[@]} -eq 0 ]]; then
		echo "No local-model runtimes detected. Nothing to pull."
		echo "Install runtimes first, e.g.:"
		echo "  ./setup.sh --with ollama,llamacpp"
		echo "  ./setup.sh --with ai"
		exit 0
	fi
	DOTS_MODEL_PROVIDERS="$(
		IFS=,
		echo "${mapfile_providers[*]}"
	)"
	export DOTS_MODEL_PROVIDERS
fi

# Warn about provider all disk cost
case ",${DOTS_MODEL_PROVIDERS}," in
*,ollama,*llamacpp,* | *,llamacpp,*ollama,*)
	echo "Note: Ollama (general) and llama.cpp (coding) use different models by default."
	echo "      Explicit dual-stack pulls still use separate caches (disk cost adds up)."
	echo ""
	;;
esac

plan_lines=()
while IFS= read -r line; do
	[[ -n ${line} ]] && plan_lines+=("${line}")
done < <(dots_models_build_plan)

if [[ ${#plan_lines[@]} -eq 0 ]]; then
	echo "Plan: (empty — no matching models for this host/providers/roles)"
	exit 0
fi

echo "Plan:"
total_est=0
need_est=0
declare -a STATUS_ARR=()
declare -a ACTION_ARR=()

for line in "${plan_lines[@]}"; do
	IFS='|' read -r mid prov role label est auto pull_key src <<<"${line}"
	st="$(dots_models_status_for_line "${prov}" "${label}" "${pull_key}" "${auto}")"
	STATUS_ARR+=("${st}")
	# estimate: bash can't float; use awk
	total_est="$(awk -v a="${total_est}" -v b="${est}" 'BEGIN { printf "%.1f", a + b }')"
	printf '  %-12s %-36s ~%s GB  [%s]\n' "${prov}" "${label}" "${est}" "${role}"
	if [[ ${st} == missing || ${DO_UPDATE} -eq 1 ]]; then
		if [[ ${auto} != manual ]]; then
			need_est="$(awk -v a="${need_est}" -v b="${est}" 'BEGIN { printf "%.1f", a + b }')"
			ACTION_ARR+=("pull")
		else
			ACTION_ARR+=("manual")
		fi
	elif [[ ${st} == already ]]; then
		ACTION_ARR+=("skip")
	else
		ACTION_ARR+=("manual")
	fi
done

echo ""
echo "Expected catalog footprint: ~${total_est} GB"
echo "Estimated additional download: ~${need_est} GB"
echo "Free disk: ${free_disk} GB (reserve ${reserve} GB)"

# Disk budget: free - need >= reserve
ok_disk="$(awk -v f="${free_disk}" -v n="${need_est}" -v r="${reserve}" 'BEGIN { print ((f - n) >= r) ? 1 : 0 }')"
if [[ ${ok_disk} -ne 1 && ${LIST_ONLY} -eq 0 ]]; then
	# Only error when we would actually download something
	has_pull=0
	for a in "${ACTION_ARR[@]+"${ACTION_ARR[@]}"}"; do
		[[ ${a} == pull ]] && has_pull=1
	done
	if [[ ${has_pull} -eq 1 ]]; then
		echo "Error: estimated free disk after download would violate reserve (${reserve} GB)." >&2
		exit 1
	fi
fi

if [[ ${LIST_ONLY} -eq 1 ]]; then
	echo ""
	echo "Status:"
	i=0
	for line in "${plan_lines[@]}"; do
		IFS='|' read -r mid prov role label est auto pull_key src <<<"${line}"
		printf '  %-12s %-36s %s\n' "${prov}" "${label}" "${STATUS_ARR[$i]}"
		i=$((i + 1))
	done
	exit 0
fi

# Confirmation
if [[ ${DOTS_MODEL_YES} -ne 1 && ${DOTS_MODEL_DRY_RUN} -ne 1 ]]; then
	echo ""
	read -r -p "Proceed with model acquisition? [y/N] " ans
	case "${ans}" in
	y | Y | yes | YES) ;;
	*)
		echo "Aborted."
		exit 0
		;;
	esac
fi

echo ""
declare -a RESULT_PROV=() RESULT_MODEL=() RESULT_STATUS=()
failures=0
manuals=0
i=0
for line in "${plan_lines[@]}"; do
	IFS='|' read -r mid prov role label est auto pull_key src <<<"${line}"
	action="${ACTION_ARR[$i]}"
	st="${STATUS_ARR[$i]}"
	RESULT_PROV+=("${prov}")
	RESULT_MODEL+=("${label}")

	if [[ ${action} == skip && ${DO_UPDATE} -eq 0 ]]; then
		echo "OK: ${prov} ${label} — already present"
		RESULT_STATUS+=("SKIPPED")
		i=$((i + 1))
		continue
	fi

	if [[ ${action} == manual || ${auto} == manual ]]; then
		echo "--- ${prov}: ${label} ---"
		if [[ ${prov} == fluidvoice ]]; then
			dots_mp_fluidvoice_pull "${label}" || true
			OPEN_FLUIDVOICE=1
		else
			echo "  MANUAL: ${label} (no automatic pull for this provider/model)"
		fi
		RESULT_STATUS+=("MANUAL")
		manuals=$((manuals + 1))
		i=$((i + 1))
		continue
	fi

	echo "--- ${prov}: ${label} ---"
	echo "  ${src}"
	rc=0
	case "${prov}" in
	ollama)
		dots_mp_ollama_pull "${pull_key}" || rc=$?
		;;
	llamacpp)
		repo="${pull_key%%$'\t'*}"
		quant="${pull_key#*$'\t'}"
		[[ ${quant} == "${pull_key}" ]] && quant=""
		dots_mp_llamacpp_pull "${repo}" "${quant}" || rc=$?
		;;
	drawthings)
		dots_mp_drawthings_pull "${pull_key}" || rc=$?
		;;
	*)
		echo "Error: no pull adapter for ${prov}" >&2
		rc=1
		;;
	esac

	if [[ ${rc} -eq 0 ]]; then
		if [[ ${st} == already && ${DO_UPDATE} -eq 1 ]]; then
			RESULT_STATUS+=("SUCCESS")
		elif [[ ${DOTS_MODEL_DRY_RUN} -eq 1 ]]; then
			RESULT_STATUS+=("SUCCESS")
		else
			RESULT_STATUS+=("SUCCESS")
		fi
	elif [[ ${rc} -eq 2 ]]; then
		RESULT_STATUS+=("MANUAL")
		manuals=$((manuals + 1))
	else
		RESULT_STATUS+=("FAILED")
		failures=$((failures + 1))
	fi
	i=$((i + 1))
done

dots_mp_ollama_restore_server || true

if [[ ${OPEN_FLUIDVOICE} -eq 1 && ${DOTS_MODEL_DRY_RUN} -eq 0 ]]; then
	dots_mp_fluidvoice_maybe_open || true
fi

echo ""
echo "=== Result ==="
printf '%-12s %-36s %s\n' "provider" "model" "status"
printf '%-12s %-36s %s\n' "--------" "-----" "------"
i=0
while [[ ${i} -lt ${#RESULT_PROV[@]} ]]; do
	printf '%-12s %-36s %s\n' "${RESULT_PROV[$i]}" "${RESULT_MODEL[$i]}" "${RESULT_STATUS[$i]}"
	i=$((i + 1))
done

echo ""
echo "MANUAL FluidVoice rows are informational (no supported upstream automation)."
if [[ ${failures} -gt 0 ]]; then
	exit 1
fi
exit 0
