# shellcheck shell=bash
# helpers/wizard.sh — interactive machine setup orchestrator (delegates to subsystems)
#
# Requires: DIR, helpers/ui.sh, helpers/state.sh
# Soft-requires after Stage 0: components/profiles/hardware/models helpers

# Wizard plan globals (set by dots_wizard_collect)
WIZ_BUILTIN=""
WIZ_CUSTOMIZE=0
WIZ_PROFILE_NAME=""
WIZ_PROFILE_PATH=""
WIZ_EXTENDS=""
WIZ_WITH=""
WIZ_WITHOUT=""
WIZ_PKG_ADD=""
WIZ_MUX=""
WIZ_MODELS=0 # 0=skip 1=recommended 2=choose-tier
WIZ_MODEL_TIER="auto"
WIZ_MODEL_CLEANUP=0
WIZ_DRY_RUN=0
WIZ_YES=0
WIZ_PASSTHRU_PROFILE="" # noninteractive --profile
WIZ_PASSTHRU_WITH=""

dots_wizard_reset() {
	WIZ_BUILTIN=""
	WIZ_CUSTOMIZE=0
	WIZ_PROFILE_NAME=""
	WIZ_PROFILE_PATH=""
	WIZ_EXTENDS=""
	WIZ_WITH=""
	WIZ_WITHOUT=""
	WIZ_PKG_ADD=""
	WIZ_MUX=""
	WIZ_MODELS=0
	WIZ_MODEL_TIER="auto"
	WIZ_MODEL_CLEANUP=0
}

# Map machine-type choice (1-6) → builtin name
dots_wizard_choice_to_builtin() {
	case "$1" in
	1) printf 'home\n' ;;
	2) printf 'work\n' ;;
	3) printf 'server\n' ;;
	4) printf 'base\n' ;;
	5) printf 'all\n' ;;
	6) printf 'custom\n' ;;
	*) return 1 ;;
	esac
}

dots_wizard_explain_builtin() {
	case "$1" in
	home) echo "home    rich personal workstation" ;;
	work) echo "work    conservative work machine, no AI by default" ;;
	server) echo "server  headless environment, tmux + Herdr" ;;
	base) echo "base    portable CLI foundation" ;;
	all) echo "all     broad lab/experimental environment" ;;
	custom) echo "custom  start from base and build up" ;;
	esac
}

# Soft-load registry helpers if Python available; otherwise use static fallbacks.
dots_wizard_ensure_registry() {
	if declare -F dots_component_ids >/dev/null 2>&1; then
		return 0
	fi
	# shellcheck source=toml.sh
	source "${DIR}/helpers/toml.sh" 2>/dev/null || true
	# shellcheck source=components.sh
	source "${DIR}/helpers/components.sh" 2>/dev/null || true
	# shellcheck source=profiles.sh
	source "${DIR}/helpers/profiles.sh" 2>/dev/null || true
	# shellcheck source=hardware.sh
	source "${DIR}/helpers/hardware.sh" 2>/dev/null || true
	# shellcheck source=model_providers.sh
	source "${DIR}/helpers/model_providers.sh" 2>/dev/null || true
	# shellcheck source=models.sh
	source "${DIR}/helpers/models.sh" 2>/dev/null || true
}

dots_wizard_host_os() {
	if declare -F dots_hw_os >/dev/null 2>&1; then
		dots_hw_os
		return 0
	fi
	case "$(uname -s)" in
	Darwin) printf 'darwin\n' ;;
	Linux) printf 'linux\n' ;;
	*) printf 'unknown\n' ;;
	esac
}

# Returns 0 if component id is likely available (best-effort without Python).
dots_wizard_component_ok_here() {
	local id="$1" os
	os="$(dots_wizard_host_os)"
	case "${id}" in
	fluidvoice | cursor | codex)
		[[ ${os} == darwin ]] && return 0
		return 1
		;;
	drawthings)
		# bridge exists on Linux but GUI models are macOS-oriented — still offer
		return 0
		;;
	*) return 0 ;;
	esac
}

dots_wizard_print_unavailable() {
	local id="$1"
	case "${id}" in
	fluidvoice) echo "     (unavailable on Linux — macOS 15+ only)" ;;
	cursor | codex) echo "     (unavailable on Linux — macOS Homebrew cask)" ;;
	esac
}

# Interactive component picker. Sets WIZ_WITH / WIZ_WITHOUT (CSV).
dots_wizard_pick_components() {
	local builtin="$1"
	local os ans
	os="$(dots_wizard_host_os)"

	if [[ ${builtin} == work ]]; then
		dots_ui_section "Work-machine safety"
		echo "  Work profile starts with no AI applications."
		echo "  Add only software approved for this machine."
	fi

	if [[ ${builtin} == home ]]; then
		dots_ui_section "Home profile defaults"
		echo "  Home includes a personal AI/workstation stack via the profile"
		echo "  registry (ai supergroup + herdr, skills, images, tex; FluidVoice off)."
		echo "  See: ./dots components list"
		ans="$(dots_prompt_yesno "Keep home defaults" y)"
		if [[ ${ans} == y ]]; then
			WIZ_WITH=""
			WIZ_WITHOUT=""
			return 0
		fi
	fi

	if [[ ${builtin} == server || ${builtin} == base ]]; then
		WIZ_WITH=""
		WIZ_WITHOUT=""
	fi

	dots_ui_section "Optional components"
	echo "  Select additions (blank = none). Descriptions from configs/components.toml."
	echo ""

	local want_ai=0 want_herdr=0 want_skills=0 want_aiskills=0
	local want_images=0 want_tex=0
	local excl=""
	local _desc

	_desc="$(
		WANT=ai dots_toml_query "$(dots_components_registry_path)" <<'PY' 2>/dev/null || echo "AI applications"
import os
want = os.environ.get("WANT", "").strip()
for g in data.get("supergroups") or []:
    if (g.get("id") or "").strip() == want:
        print((g.get("description") or g.get("label") or want).strip())
        raise SystemExit(0)
print("AI applications")
PY
	)"
	ans="$(dots_prompt_yesno "Add AI applications (--with ai) — ${_desc}" n)"
	[[ ${ans} == y ]] && want_ai=1

	if [[ ${want_ai} -eq 1 ]]; then
		echo "  AI applications selected. Exclude any?"
		for id in cursor codex fluidvoice drawthings; do
			if ! dots_wizard_component_ok_here "${id}"; then
				echo "  - ${id}: skipped (platform)"
				continue
			fi
			_desc="$(dots_component_description "${id}" 2>/dev/null || echo "${id}")"
			ans="$(dots_prompt_yesno "  Exclude ${id} (${_desc})" n)"
			[[ ${ans} == y ]] && excl="${excl}${excl:+,}${id}"
		done
	fi

	if [[ ${builtin} != server ]]; then
		_desc="$(dots_component_description herdr 2>/dev/null || echo "Herdr")"
		ans="$(dots_prompt_yesno "Add Herdr — ${_desc}" n)"
		[[ ${ans} == y ]] && want_herdr=1
	fi
	_desc="$(dots_component_description skills 2>/dev/null || echo "Engineering skills")"
	ans="$(dots_prompt_yesno "Add Engineering skills — ${_desc}" n)"
	[[ ${ans} == y ]] && want_skills=1
	_desc="$(dots_component_description ai-skills 2>/dev/null || echo "AI skills")"
	ans="$(dots_prompt_yesno "Add AI skills — ${_desc}" n)"
	[[ ${ans} == y ]] && want_aiskills=1
	_desc="$(dots_component_description images 2>/dev/null || echo "Images")"
	ans="$(dots_prompt_yesno "Add Images toolkit — ${_desc}" n)"
	[[ ${ans} == y ]] && want_images=1
	_desc="$(dots_component_description tex 2>/dev/null || echo "TeX")"
	ans="$(dots_prompt_yesno "Add TeX — ${_desc}" n)"
	[[ ${ans} == y ]] && want_tex=1

	# Also offer leaf AI runtimes if ai not selected (server path)
	if [[ ${want_ai} -eq 0 ]]; then
		_desc="$(dots_component_description ollama 2>/dev/null || echo "Ollama")"
		ans="$(dots_prompt_yesno "Add Ollama — ${_desc}" n)"
		[[ ${ans} == y ]] && WIZ_WITH="${WIZ_WITH}${WIZ_WITH:+,}ollama"
		_desc="$(dots_component_description llamacpp 2>/dev/null || echo "llama.cpp")"
		ans="$(dots_prompt_yesno "Add llama.cpp — ${_desc}" n)"
		[[ ${ans} == y ]] && WIZ_WITH="${WIZ_WITH}${WIZ_WITH:+,}llamacpp"
	fi

	local parts=()
	[[ ${want_ai} -eq 1 ]] && parts+=("ai")
	[[ ${want_herdr} -eq 1 ]] && parts+=("herdr")
	[[ ${want_skills} -eq 1 ]] && parts+=("skills")
	[[ ${want_aiskills} -eq 1 ]] && parts+=("ai-skills")
	[[ ${want_images} -eq 1 ]] && parts+=("images")
	[[ ${want_tex} -eq 1 ]] && parts+=("tex")
	local p
	for p in "${parts[@]+"${parts[@]}"}"; do
		WIZ_WITH="${WIZ_WITH}${WIZ_WITH:+,}${p}"
	done
	WIZ_WITHOUT="${excl}"
	return 0
}

dots_wizard_pick_runtime() {
	local builtin="$1" ans
	dots_ui_section "Runtime"
	echo "  Both tmux and Herdr remain manually available regardless of auto choice."
	DOTS_UI_CHOICE_DEFAULT=1
	case "${builtin}" in
	home) DOTS_UI_CHOICE_DEFAULT=2 ;;
	*) DOTS_UI_CHOICE_DEFAULT=1 ;;
	esac
	ans="$(dots_prompt_choice "Automatic multiplexer:" \
		"tmux (default for work/server/base)" \
		"Herdr (default for home)" \
		"none")"
	case "${ans}" in
	1) WIZ_MUX="tmux" ;;
	2) WIZ_MUX="herdr" ;;
	3) WIZ_MUX="none" ;;
	esac
	# Sparse: only set if differs from typical builtin default
	case "${builtin}" in
	home)
		[[ ${WIZ_MUX} == herdr ]] && WIZ_MUX=""
		;;
	*)
		[[ ${WIZ_MUX} == tmux ]] && WIZ_MUX=""
		;;
	esac
	return 0
}

dots_wizard_pick_models() {
	local has_model_runtime=0
	case ",${WIZ_WITH}," in
	*,ai,* | *,ollama,* | *,llamacpp,* | *,drawthings,* | *,fluidvoice,*) has_model_runtime=1 ;;
	esac
	# home defaults include AI stack
	if [[ ${WIZ_BUILTIN} == home && -z ${WIZ_WITH} && ${WIZ_CUSTOMIZE} -eq 0 ]]; then
		has_model_runtime=1
	fi
	if [[ ${WIZ_BUILTIN} == all ]]; then
		has_model_runtime=1
	fi

	dots_ui_section "Local models"
	if [[ ${has_model_runtime} -eq 0 ]]; then
		echo "  No local model runtimes selected."
		echo "  Skip model configuration."
		WIZ_MODELS=0
		return 0
	fi

	DOTS_UI_CHOICE_DEFAULT=3
	local ans
	ans="$(dots_prompt_choice "Configure local models?" \
		"Yes, recommended for this machine" \
		"Choose model tier/options" \
		"Not now")"
	case "${ans}" in
	1)
		WIZ_MODELS=1
		WIZ_MODEL_TIER="auto"
		;;
	2)
		WIZ_MODELS=2
		dots_wizard_ensure_registry
		if declare -F dots_hw_summary >/dev/null 2>&1; then
			dots_hw_summary
			echo "  recommended tier: $(dots_models_select_tier 2>/dev/null || echo balanced)"
		fi
		DOTS_UI_CHOICE_DEFAULT=1
		ans="$(dots_prompt_choice "Model tier:" \
			"Auto / recommended" \
			"Minimal" \
			"Balanced" \
			"Large" \
			"Max")"
		case "${ans}" in
		1) WIZ_MODEL_TIER="auto" ;;
		2) WIZ_MODEL_TIER="minimal" ;;
		3) WIZ_MODEL_TIER="balanced" ;;
		4) WIZ_MODEL_TIER="large" ;;
		5) WIZ_MODEL_TIER="max" ;;
		esac
		ans="$(dots_prompt_yesno "Include Fluid-1 cleanup model (optional, ~3.5 GB)" n)"
		if [[ ${ans} == y ]]; then
			WIZ_MODEL_CLEANUP=1
		fi
		;;
	*)
		WIZ_MODELS=0
		;;
	esac
	return 0
}

dots_wizard_collect() {
	dots_wizard_reset
	dots_ui_load_answers
	dots_ui_header "DOTS Setup"
	echo "  Version $(dots_version)"
	echo "  Interactive machine setup — existing scripts remain for automation."

	# Existing machine?
	if dots_state_load_active 2>/dev/null; then
		dots_ui_section "Existing configuration detected"
		echo "  profile: ${DOTS_ACTIVE_PROFILE:-unknown}"
		[[ -n ${DOTS_ACTIVE_PROFILE_FILE:-} ]] && echo "  file: ${DOTS_ACTIVE_PROFILE_FILE}"
		DOTS_UI_CHOICE_DEFAULT=1
		local ans
		ans="$(dots_prompt_choice "What next?" \
			"Reapply current profile" \
			"Edit / create another profile (wizard)" \
			"Models only" \
			"Verify only" \
			"Start over with another profile")"
		case "${ans}" in
		1)
			WIZ_PASSTHRU_PROFILE="${DOTS_ACTIVE_PROFILE_FILE:-${DOTS_ACTIVE_PROFILE}}"
			WIZ_BUILTIN="reapply"
			return 0
			;;
		3)
			WIZ_BUILTIN="models-only"
			return 0
			;;
		4)
			WIZ_BUILTIN="check-only"
			return 0
			;;
		2 | 5) ;; # fall through to full wizard
		esac
	fi

	dots_ui_section "1. Machine type"
	echo "  What kind of machine is this?"
	DOTS_UI_CHOICE_DEFAULT=1
	local c
	c="$(dots_prompt_choice "Machine type:" \
		"Personal / Home workstation" \
		"Work / Employer workstation" \
		"Server / Headless system" \
		"Minimal / Base" \
		"Lab / Everything" \
		"Custom")"
	WIZ_BUILTIN="$(dots_wizard_choice_to_builtin "${c}")"
	dots_wizard_explain_builtin "${WIZ_BUILTIN}"
	[[ ${WIZ_BUILTIN} == custom ]] && WIZ_BUILTIN="base" && WIZ_CUSTOMIZE=1

	dots_ui_section "2. Profile"
	if [[ ${WIZ_CUSTOMIZE} -eq 0 ]]; then
		local ans
		ans="$(dots_prompt_yesno "Use '${WIZ_BUILTIN}' profile as-is" y)"
		if [[ ${ans} == n ]]; then
			WIZ_CUSTOMIZE=1
		fi
	fi

	if [[ ${WIZ_CUSTOMIZE} -eq 1 ]]; then
		WIZ_EXTENDS="${WIZ_BUILTIN}"
		local def_name="${WIZ_BUILTIN}-custom" host
		host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
		if [[ -n ${host} && ${host} != localhost ]]; then
			ans="$(dots_prompt_yesno "Detected hostname '${host}'. Use as profile name" y)"
			[[ ${ans} == y ]] && def_name="${host}"
		fi
		WIZ_PROFILE_NAME="$(dots_prompt_text "Profile name" "${def_name}")"
		WIZ_PROFILE_PATH="$(dots_user_profiles_dir)/${WIZ_PROFILE_NAME}.toml"
		dots_wizard_pick_components "${WIZ_EXTENDS}"
		dots_wizard_pick_runtime "${WIZ_EXTENDS}"
		# server infra shortcut
		if [[ ${WIZ_EXTENDS} == server ]]; then
			ans="$(dots_prompt_yesno "Add infra package group" n)"
			[[ ${ans} == y ]] && WIZ_PKG_ADD="infra"
		fi
	else
		WIZ_PROFILE_NAME="${WIZ_BUILTIN}"
		WIZ_PROFILE_PATH=""
		WIZ_EXTENDS=""
		# still allow component additions via CLI-style for as-is? keep empty
		if [[ ${WIZ_BUILTIN} == server ]]; then
			dots_wizard_pick_runtime server
		fi
	fi

	dots_wizard_pick_models
	return 0
}

dots_wizard_print_plan() {
	dots_ui_header "DOTS Setup Plan"
	echo ""
	echo "Profile:"
	if [[ -n ${WIZ_PROFILE_PATH} ]]; then
		echo "  ${WIZ_PROFILE_NAME}  (extends ${WIZ_EXTENDS})"
		echo "  → ${WIZ_PROFILE_PATH}"
	else
		echo "  ${WIZ_BUILTIN}  (builtin)"
	fi
	echo ""
	echo "Components:"
	if [[ -n ${WIZ_WITH} ]]; then
		echo "  with: ${WIZ_WITH}"
	else
		echo "  (profile defaults)"
	fi
	[[ -n ${WIZ_WITHOUT} ]] && echo "  without: ${WIZ_WITHOUT}"
	[[ -n ${WIZ_PKG_ADD} ]] && echo "  packages add: ${WIZ_PKG_ADD}"
	echo ""
	echo "Runtime:"
	if [[ -n ${WIZ_MUX} ]]; then
		echo "  auto multiplexer: ${WIZ_MUX}"
	else
		echo "  auto multiplexer: (profile default)"
	fi
	echo ""
	echo "Models:"
	case "${WIZ_MODELS}" in
	0) echo "  skip (not now)" ;;
	1) echo "  recommended / tier=${WIZ_MODEL_TIER}" ;;
	2) echo "  tier=${WIZ_MODEL_TIER}  cleanup=${WIZ_MODEL_CLEANUP}" ;;
	esac
	echo ""
	echo "Backup:"
	echo "  pre-change snapshot will be created when unmanaged targets would be replaced"
	echo "  (no-op when all managed targets are already current)"
	echo "  recover later with: ./dots backups && ./dots restore"
	echo ""
	echo "Actions:"
	echo "  Stage 0 prerequisites if needed"
	[[ -n ${WIZ_PROFILE_PATH} ]] && echo "  write ${WIZ_PROFILE_PATH}"
	[[ ${WIZ_MODELS} -ne 0 ]] && echo "  write $(dots_user_models_file)"
	echo "  bootstrap / install"
	[[ ${WIZ_MODELS} -ne 0 ]] && echo "  pull_models.sh"
	echo "  health check"
	echo ""
	if [[ ${WIZ_DRY_RUN} -eq 1 ]]; then
		echo "(dry-run — no mutations)"
	fi
}

# Run pull_models with durable MODEL START/RESULT lines in the setup log.
# Interactive (-t 1): invoke directly so provider CR progress keeps a TTY
# (never pipe solely for logging). Dry-run may capture plan output. Noninteractive
# runs without faking a TTY. Does not trap SIGINT. Override binary via
# DOTS_PULL_MODELS_SH (tests). Remaining args are forwarded to pull_models.
dots_wizard_run_models() {
	local log="$1"
	shift
	local pm_bin="${DOTS_PULL_MODELS_SH:-${DIR}/scripts/pull_models.sh}"
	local rc=0
	local args_desc="$*"
	local tier="${WIZ_MODEL_TIER:-}"

	printf 'MODEL START tier=%s args=%s\n' "${tier}" "${args_desc}" >>"${log}"

	# Avoid set -e here so we do not leak shell options to callers; capture rc explicitly.
	if [[ ${WIZ_DRY_RUN:-0} -eq 1 ]]; then
		# Plan output is line-oriented; capture for the durable log is OK.
		"${pm_bin}" "$@" 2>&1 | tee -a "${log}" || true
		rc=${PIPESTATUS[0]}
	elif [[ -t 1 ]]; then
		# Preserve stdout TTY for ollama / llama-cli / draw-things-cli progress.
		"${pm_bin}" "$@" || rc=$?
	else
		# Noninteractive / no TTY: run normally; do not fake a TTY or tee for logging.
		"${pm_bin}" "$@" || rc=$?
	fi

	if [[ ${rc} -eq 0 ]]; then
		printf 'MODEL RESULT success rc=%s\n' "${rc}" >>"${log}"
	else
		printf 'MODEL RESULT failed rc=%s\n' "${rc}" >>"${log}"
	fi
	return "${rc}"
}

# Apply collected plan. Returns nonzero on hard failure.
dots_wizard_apply() {
	local log profile_arg rc=0
	DOTS_APPLY_STARTED=1
	# Dry-run: never write under HOME (logs go to TMPDIR)
	if [[ ${WIZ_DRY_RUN} -eq 1 ]]; then
		log="$(mktemp "${TMPDIR:-/tmp}/dots-setup.XXXXXX.log")"
	else
		log="$(dots_state_new_log setup)"
	fi
	echo "Log: ${log}"

	# Special short-circuits
	case "${WIZ_BUILTIN}" in
	reapply)
		profile_arg="${WIZ_PASSTHRU_PROFILE}"
		dots_ui_stage 1 3 "Bootstrap" "…"
		set +e
		if [[ ${WIZ_DRY_RUN} -eq 1 ]]; then
			"${DIR}/bootstrap.sh" --profile "${profile_arg}" --dry-run 2>&1 | tee -a "${log}"
		else
			"${DIR}/bootstrap.sh" --profile "${profile_arg}" 2>&1 | tee -a "${log}"
		fi
		rc=${PIPESTATUS[0]}
		set -e
		dots_ui_stage 2 3 "Health check" "…"
		"${DIR}/scripts/check.sh" --profile "${profile_arg}" 2>&1 | tee -a "${log}" || true
		dots_ui_stage 3 3 "Done" "OK"
		[[ ${WIZ_DRY_RUN} -eq 1 ]] && rm -f "${log}"
		return "${rc}"
		;;
	models-only)
		set +e
		if [[ ${WIZ_DRY_RUN} -eq 1 ]]; then
			dots_wizard_run_models "${log}" --dry-run
		else
			dots_wizard_run_models "${log}"
		fi
		rc=$?
		set -e
		[[ ${WIZ_DRY_RUN} -eq 1 ]] && rm -f "${log}"
		return "${rc}"
		;;
	check-only)
		local p="${DOTS_ACTIVE_PROFILE_FILE:-${DOTS_ACTIVE_PROFILE:-base}}"
		set +e
		"${DIR}/scripts/check.sh" --profile "${p}" 2>&1 | tee -a "${log}"
		rc=${PIPESTATUS[0]}
		set -e
		[[ ${WIZ_DRY_RUN} -eq 1 ]] && rm -f "${log}"
		return "${rc}"
		;;
	esac

	if [[ ${WIZ_DRY_RUN} -eq 1 ]]; then
		dots_ui_stage 1 5 "Preview only" "OK"
		echo "Would write profile: ${WIZ_PROFILE_PATH:-builtin:${WIZ_BUILTIN}}"
		[[ ${WIZ_MODELS} -ne 0 ]] && echo "Would write models override: $(dots_user_models_file)"
		echo "Would run: bootstrap.sh --profile ${WIZ_PROFILE_PATH:-${WIZ_BUILTIN}}"
		[[ ${WIZ_MODELS} -ne 0 ]] && echo "Would run: pull_models.sh --tier ${WIZ_MODEL_TIER}"
		echo "Would run: check.sh"
		# Also run bootstrap --dry-run for visibility when python available
		if [[ -n ${WIZ_PROFILE_PATH} ]]; then
			local tmp
			tmp="$(mktemp "${TMPDIR:-/tmp}/dots-wiz.XXXXXX.toml")"
			dots_write_profile_toml_bash "${tmp}" "${WIZ_PROFILE_NAME}" "${WIZ_EXTENDS}" \
				"custom profile from ./dots" "${WIZ_MUX}" "${WIZ_WITH}" "${WIZ_WITHOUT}" "${WIZ_PKG_ADD}"
			"${DIR}/bootstrap.sh" --profile "${tmp}" --dry-run 2>&1 | tee -a "${log}" || true
			rm -f "${tmp}"
		else
			local boot_args=(--profile "${WIZ_BUILTIN}" --dry-run)
			[[ -n ${WIZ_WITH} ]] && boot_args+=(--with "${WIZ_WITH}")
			[[ -n ${WIZ_WITHOUT} ]] && boot_args+=(--without "${WIZ_WITHOUT}")
			"${DIR}/bootstrap.sh" "${boot_args[@]}" 2>&1 | tee -a "${log}" || true
		fi
		rm -f "${log}"
		return 0
	fi

	dots_ui_stage 1 5 "Bootstrap prerequisites" "…"
	if [[ ${DOTS_SKIP_STAGE0:-0} -eq 1 ]]; then
		echo "Note: DOTS_SKIP_STAGE0=1 — skipping Stage 0 in wizard"
		dots_ui_stage 1 5 "Bootstrap prerequisites" "SKIP"
	else
		# shellcheck source=bootstrap_prereqs.sh
		source "${DIR}/helpers/bootstrap_prereqs.sh"
		set +e
		dots_stage0_ensure 0 2>&1 | tee -a "${log}"
		stage0_rc=${PIPESTATUS[0]}
		set -e
		if [[ ${stage0_rc} -ne 0 ]]; then
			dots_ui_stage 1 5 "Bootstrap prerequisites" "FAILED"
			dots_ui_stage 2 5 "Profile activation" "NOT COMMITTED"
			dots_ui_err "Stage 0 failed — see ${log}"
			echo ""
			echo "Setup failed before profile activation."
			echo "Previous active profile remains unchanged."
			echo "Re-run ./dots after resolving the error; installation steps are idempotent."
			return 1
		fi
		dots_ui_stage 1 5 "Bootstrap prerequisites" "OK"
	fi

	dots_ui_stage 2 5 "Write configuration" "…"
	if [[ -n ${WIZ_PROFILE_PATH} ]]; then
		if [[ -f ${WIZ_PROFILE_PATH} ]]; then
			local ov
			ov="$(dots_prompt_yesno "Profile exists (${WIZ_PROFILE_PATH}). Overwrite" n)"
			if [[ ${ov} != y ]]; then
				local alt
				alt="$(dots_prompt_text "Save as new name" "${WIZ_PROFILE_NAME}-2")"
				WIZ_PROFILE_NAME="${alt}"
				WIZ_PROFILE_PATH="$(dots_user_profiles_dir)/${alt}.toml"
			fi
		fi
		dots_write_profile_toml_bash "${WIZ_PROFILE_PATH}" "${WIZ_PROFILE_NAME}" "${WIZ_EXTENDS}" \
			"custom profile from ./dots" "${WIZ_MUX}" "${WIZ_WITH}" "${WIZ_WITHOUT}" "${WIZ_PKG_ADD}"
		dots_ui_ok "wrote ${WIZ_PROFILE_PATH}"
		profile_arg="${WIZ_PROFILE_PATH}"
	else
		profile_arg="${WIZ_BUILTIN}"
	fi
	if [[ ${WIZ_MODELS} -ne 0 ]]; then
		local mf
		mf="$(dots_user_models_file)"
		if [[ -f ${mf} ]]; then
			local ov
			ov="$(dots_prompt_yesno "Model policy exists. Overwrite" n)"
			[[ ${ov} != y ]] && mf=""
		fi
		if [[ -n ${mf} ]]; then
			dots_write_models_override_bash "${mf}" "${WIZ_MODEL_TIER}" "true" "" "${WIZ_MODEL_CLEANUP}"
			dots_ui_ok "wrote ${mf}"
		fi
	fi
	dots_ui_stage 2 5 "Write configuration" "OK"

	dots_ui_stage 3 5 "Packages/components" "…"
	local boot_args=(--profile "${profile_arg}")
	if [[ -z ${WIZ_PROFILE_PATH} ]]; then
		[[ -n ${WIZ_WITH} ]] && boot_args+=(--with "${WIZ_WITH}")
		[[ -n ${WIZ_WITHOUT} ]] && boot_args+=(--without "${WIZ_WITHOUT}")
	fi
	# Capture bootstrap status explicitly — `local x=${PIPESTATUS[0]}` is unsafe
	# because `local` itself resets PIPESTATUS on some Bash builds.
	local boot_rc=0
	set +e
	"${DIR}/bootstrap.sh" "${boot_args[@]}" 2>&1 | tee -a "${log}"
	boot_rc=${PIPESTATUS[0]}
	set -e
	if [[ ${boot_rc} -ne 0 ]]; then
		dots_ui_stage 3 5 "Packages/components" "FAILED"
		dots_ui_stage 4 5 "Profile activation" "NOT COMMITTED"
		dots_ui_stage 5 5 "Models" "NOT RUN"
		dots_ui_err "bootstrap failed — see ${log}"
		echo ""
		echo "Setup failed before profile activation."
		echo "Previous active profile remains unchanged."
		echo "Re-run ./dots after resolving the error; installation steps are idempotent."
		return 1
	fi
	local pkg_stage="OK"
	if [[ -n ${log} && -f ${log} ]] &&
		grep -q "WARN: static review findings" "${log}" 2>/dev/null; then
		pkg_stage="OK (warnings)"
	fi
	dots_ui_stage 3 5 "Packages/components" "${pkg_stage}"
	dots_ui_stage 4 5 "Profile activation" "OK"

	dots_ui_stage 4 5 "Models" "…"
	if [[ ${WIZ_MODELS} -ne 0 ]]; then
		local pm=(--yes --tier "${WIZ_MODEL_TIER}")
		[[ ${WIZ_MODEL_CLEANUP} -eq 1 ]] && pm+=(--include-cleanup)
		local models_rc=0
		set +e
		dots_wizard_run_models "${log}" "${pm[@]}"
		models_rc=$?
		set -e
		if [[ ${models_rc} -eq 0 ]]; then
			dots_ui_stage 4 5 "Models" "OK"
		else
			dots_ui_stage 4 5 "Models" "WARN/FAILED"
			rc=1
		fi
	else
		dots_ui_stage 4 5 "Models" "SKIP"
	fi

	dots_ui_stage 5 5 "Verification" "…"
	"${DIR}/scripts/check.sh" --profile "${profile_arg}" 2>&1 | tee -a "${log}" || true
	dots_ui_stage 5 5 "Verification" "OK"

	if [[ -n ${log} && -f ${log} ]] &&
		grep -q "WARN: static review findings" "${log}" 2>/dev/null; then
		local adv
		adv="$(grep -c "WARN: static review findings" "${log}" 2>/dev/null || true)"
		[[ -z ${adv} || ${adv} == 0 ]] && adv=1
		echo ""
		echo "Setup complete with ${adv} advisory warning(s)."
		echo "Installed skills remain enabled; review findings above if desired."
	fi

	dots_wizard_followups
	return "${rc}"
}

dots_wizard_followups() {
	dots_ui_header "Setup complete — manual follow-ups"
	echo "  FluidVoice (if selected): open app → download Parakeet TDT v3;"
	echo "    grant Microphone + Accessibility permissions."
	echo "  Codex / Cursor (if selected): complete interactive login."
	echo "  Hermes (if selected): hermes login / first-run auth."
	echo "  Git: edit ~/.config/git/personal and ~/.config/git/work"
	echo "  iTerm: set font to JetBrainsMono Nerd Font"
	echo "  Machine overrides: ~/.config/dots/local.sh"
	echo ""
	echo "  Re-run ./dots anytime — operations are idempotent."
}

# Main interactive setup entry (also --dry-run / --yes passthrough).
dots_cmd_setup() {
	WIZ_DRY_RUN=0
	WIZ_YES=0
	WIZ_PASSTHRU_PROFILE=""
	WIZ_PASSTHRU_WITH=""
	WIZ_PASSTHRU_WITHOUT=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--dry-run) WIZ_DRY_RUN=1 ;;
		--yes | -y) WIZ_YES=1 ;;
		--profile)
			WIZ_PASSTHRU_PROFILE="${2:-}"
			shift
			;;
		--profile=*) WIZ_PASSTHRU_PROFILE="${1#*=}" ;;
		--with)
			WIZ_PASSTHRU_WITH="${2:-}"
			shift
			;;
		--with=*) WIZ_PASSTHRU_WITH="${1#*=}" ;;
		--without)
			WIZ_PASSTHRU_WITHOUT="${2:-}"
			shift
			;;
		--without=*) WIZ_PASSTHRU_WITHOUT="${1#*=}" ;;
		-h | --help)
			cat <<EOF
Usage: ./dots setup [--dry-run] [--yes] [--profile NAME] [--with LIST] [--without LIST]

  --with / --without   optional component selectors
  Discover: ./dots components list
  Docs: https://sempervent.github.io/dots/using/components/
EOF
			return 0
			;;
		*)
			echo "Unknown option: $1" >&2
			return 1
			;;
		esac
		shift
	done

	# Noninteractive delegation
	if [[ -n ${WIZ_PASSTHRU_PROFILE} && ${WIZ_YES} -eq 1 ]]; then
		local args=(--profile "${WIZ_PASSTHRU_PROFILE}")
		[[ ${WIZ_DRY_RUN} -eq 1 ]] && args+=(--dry-run)
		[[ -n ${WIZ_PASSTHRU_WITH} ]] && args+=(--with "${WIZ_PASSTHRU_WITH}")
		[[ -n ${WIZ_PASSTHRU_WITHOUT} ]] && args+=(--without "${WIZ_PASSTHRU_WITHOUT}")
		exec "${DIR}/bootstrap.sh" "${args[@]}"
	fi

	dots_wizard_collect

	# Short-circuit existing-machine modes (no full review loop)
	case "${WIZ_BUILTIN}" in
	reapply | models-only | check-only)
		dots_wizard_apply
		return $?
		;;
	esac

	# Review loop
	while true; do
		dots_wizard_print_plan
		if [[ ${WIZ_DRY_RUN} -eq 1 ]]; then
			dots_wizard_apply
			return $?
		fi
		if [[ ${WIZ_YES} -eq 1 ]]; then
			dots_wizard_apply
			return $?
		fi
		DOTS_UI_CHOICE_DEFAULT=3
		local act
		act="$(dots_prompt_choice "Next:" "Back / edit (restart wizard)" "Apply" "Quit")"
		case "${act}" in
		1) dots_wizard_collect ;;
		2)
			dots_wizard_apply
			return $?
			;;
		3)
			echo "No changes made."
			return 0
			;;
		esac
	done
}
