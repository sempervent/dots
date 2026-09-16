# shellcheck shell=bash
# helpers/models.sh — model registry load, tier selection, plan building
#
# Requires: DIR, helpers/toml.sh, helpers/hardware.sh, helpers/model_providers.sh

dots_models_registry_path() {
	printf '%s\n' "${DIR}/configs/models.toml"
}

dots_models_user_path() {
	printf '%s\n' "${HOME}/.config/dots/models.toml"
}

# Validate registry structure.
dots_validate_models_registry() {
	dots_toml_query "$(dots_models_registry_path)" <<'PY'
seen = set()
for m in data.get("models") or []:
    mid = (m.get("id") or "").strip()
    if not mid:
        raise SystemExit("Error: model missing id")
    if mid in seen:
        raise SystemExit("Error: duplicate model id '%s'" % mid)
    seen.add(mid)
    if not (m.get("provider") or "").strip():
        raise SystemExit("Error: model '%s' missing provider" % mid)
    if not (m.get("role") or "").strip():
        raise SystemExit("Error: model '%s' missing role" % mid)
    if not (m.get("tier") or "").strip():
        raise SystemExit("Error: model '%s' missing tier" % mid)
print("OK")
PY
}

# Resolve tier from RAM. Override: DOTS_MODEL_TIER or user config.
dots_models_select_tier() {
	local forced="${DOTS_MODEL_TIER:-}"
	if [[ -n ${forced} && ${forced} != auto ]]; then
		printf '%s\n' "${forced}"
		return 0
	fi
	# User config tier=
	local user_tier=""
	if [[ -f "$(dots_models_user_path)" ]]; then
		user_tier="$(
			dots_toml_query "$(dots_models_user_path)" <<'PY'
m = data.get("models") or {}
if isinstance(m, dict) and m.get("tier"):
    print(str(m.get("tier")).strip())
elif data.get("tier"):
    print(str(data.get("tier")).strip())
PY
		)" || true
	fi
	if [[ -n ${user_tier} && ${user_tier} != auto ]]; then
		printf '%s\n' "${user_tier}"
		return 0
	fi

	local ram min_max bal_max large_max
	ram="$(dots_hw_ram_gb)"
	min_max="$(
		dots_toml_query "$(dots_models_registry_path)" <<'PY'
print(int((data.get("policy") or {}).get("tier_minimal_max_ram_gb", 15)))
PY
	)"
	bal_max="$(
		dots_toml_query "$(dots_models_registry_path)" <<'PY'
print(int((data.get("policy") or {}).get("tier_balanced_max_ram_gb", 31)))
PY
	)"
	large_max="$(
		dots_toml_query "$(dots_models_registry_path)" <<'PY'
print(int((data.get("policy") or {}).get("tier_large_max_ram_gb", 63)))
PY
	)"
	if [[ ${ram} -le ${min_max} ]]; then
		printf 'minimal\n'
	elif [[ ${ram} -le ${bal_max} ]]; then
		printf 'balanced\n'
	elif [[ ${ram} -le ${large_max} ]]; then
		printf 'large\n'
	else
		printf 'max\n'
	fi
}

dots_models_reserve_disk_gb() {
	local v
	v="$(
		dots_toml_query "$(dots_models_registry_path)" <<'PY'
print(int((data.get("policy") or {}).get("reserve_disk_gb", 20)))
PY
	)"
	if [[ -f "$(dots_models_user_path)" ]]; then
		local u
		u="$(
			dots_toml_query "$(dots_models_user_path)" <<'PY'
m = data.get("models") or {}
if isinstance(m, dict) and m.get("reserve_disk_gb") is not None:
    print(int(m.get("reserve_disk_gb")))
elif data.get("reserve_disk_gb") is not None:
    print(int(data.get("reserve_disk_gb")))
PY
		)" || true
		[[ -n ${u} ]] && v="${u}"
	fi
	printf '%s\n' "${v}"
}

dots_models_include_cleanup() {
	local v="0"
	local pol
	pol="$(
		dots_toml_query "$(dots_models_registry_path)" <<'PY'
print("1" if (data.get("policy") or {}).get("include_cleanup_by_default") else "0")
PY
	)"
	v="${pol}"
	if [[ -f "$(dots_models_user_path)" ]]; then
		local u
		u="$(
			dots_toml_query "$(dots_models_user_path)" <<'PY'
m = data.get("models") or {}
roles = {}
if isinstance(m, dict):
    roles = m.get("roles") or {}
    if m.get("include_cleanup") is True:
        print("1")
        raise SystemExit
    if m.get("include_cleanup") is False:
        print("0")
        raise SystemExit
if isinstance(roles, dict) and "cleanup" in roles:
    print("1" if roles.get("cleanup") else "0")
PY
		)" || true
		[[ -n ${u} ]] && v="${u}"
	fi
	[[ ${DOTS_MODEL_INCLUDE_CLEANUP:-} == 1 ]] && v=1
	[[ ${DOTS_MODEL_INCLUDE_CLEANUP:-} == 0 ]] && v=0
	printf '%s\n' "${v}"
}

# Detect which model providers are available on this machine.
dots_models_detect_providers() {
	local -a out=()
	dots_mp_ollama_available && out+=(ollama)
	dots_mp_llamacpp_available && out+=(llamacpp)
	dots_mp_drawthings_available && out+=(drawthings)
	dots_mp_fluidvoice_available && out+=(fluidvoice)
	printf '%s\n' "${out[@]+"${out[@]}"}"
}

# Build plan lines: id|provider|role|label|est_gb|automation|pull_key
# Env filters: DOTS_MODEL_PROVIDERS=ollama,llamacpp  DOTS_MODEL_TIER=balanced
#              DOTS_MODEL_ROLES=general,coding,speech,image,cleanup
#              DOTS_MODEL_IDS=id1,id2 (explicit)
dots_models_build_plan() {
	local tier providers roles os arch cleanup
	tier="$(dots_models_select_tier)"
	os="$(dots_hw_os)"
	arch="$(dots_hw_arch)"
	cleanup="$(dots_models_include_cleanup)"
	providers="${DOTS_MODEL_PROVIDERS:-}"
	roles="${DOTS_MODEL_ROLES:-}"
	local ids="${DOTS_MODEL_IDS:-}"

	TIER="${tier}" OS="${os}" ARCH="${arch}" CLEANUP="${cleanup}" \
		PROVIDERS="${providers}" ROLES="${roles}" IDS="${ids}" \
		USER_CFG="$(dots_models_user_path)" \
		dots_toml_query "$(dots_models_registry_path)" <<'PY'
import os

tier = os.environ.get("TIER", "balanced")
host_os = os.environ.get("OS", "darwin")
arch = os.environ.get("ARCH", "arm64")
cleanup = os.environ.get("CLEANUP", "0") == "1"
prov_f = {x.strip() for x in os.environ.get("PROVIDERS", "").split(",") if x.strip()}
role_f = {x.strip() for x in os.environ.get("ROLES", "").split(",") if x.strip()}
id_f = {x.strip() for x in os.environ.get("IDS", "").split(",") if x.strip()}

# User role toggles
user_path = os.environ.get("USER_CFG", "")
user_roles = None
overrides = {}
if user_path and os.path.isfile(user_path):
    import tomllib
    from pathlib import Path
    ud = tomllib.loads(Path(user_path).read_text(encoding="utf-8"))
    m = ud.get("models") or {}
    if isinstance(m, dict):
        if m.get("providers"):
            prov_f = {str(x).strip() for x in m.get("providers") if str(x).strip()}
        ur = m.get("roles")
        if isinstance(ur, dict):
            user_roles = {k: bool(v) for k, v in ur.items()}
        ov = m.get("overrides") or {}
        if isinstance(ov, dict):
            overrides = {str(k): str(v) for k, v in ov.items()}

# Default roles when unset
if not role_f and user_roles is None:
    role_f = {"general", "coding", "speech", "image"}
    if cleanup:
        role_f.add("cleanup")
elif user_roles is not None and not role_f:
    role_f = {k for k, v in user_roles.items() if v}
    if not role_f:
        role_f = {"general", "coding", "speech", "image"}

models = data.get("models") or []

def arch_ok(m):
    arches = m.get("arches")
    if not arches:
        return True
    # normalize
    a = arch
    aliases = {a, a.replace("aarch64", "arm64"), a.replace("amd64", "x86_64")}
    if a == "arm64":
        aliases.add("aarch64")
    if a == "x86_64":
        aliases.add("amd64")
    return any(str(x) in aliases for x in arches)

def plat_ok(m):
    plats = m.get("platforms") or ["darwin", "linux"]
    return host_os in [str(p) for p in plats]

# Pick one default model per (provider, role) for the tier
chosen = {}
for m in models:
    mid = (m.get("id") or "").strip()
    if id_f and mid not in id_f:
        continue
    if not id_f:
        if (m.get("tier") or "").strip() != tier:
            continue
        role = (m.get("role") or "").strip()
        is_default = bool(m.get("default", True))
        if role == "cleanup":
            if not cleanup:
                continue
        elif not is_default:
            continue
    prov = (m.get("provider") or "").strip()
    role = (m.get("role") or "").strip()
    if prov_f and prov not in prov_f:
        continue
    if role_f and role not in role_f:
        continue
    if not plat_ok(m) or not arch_ok(m):
        continue
    key = (prov, role)
    # Prefer exact tier match already filtered; first wins registry order
    if key in chosen and not id_f:
        continue
    label = ""
    pull_key = ""
    if prov == "ollama":
        label = overrides.get("ollama_general") or overrides.get(mid) or m.get("ollama_model") or mid
        pull_key = label
    elif prov == "llamacpp":
        repo = m.get("hf_repo") or ""
        quant = m.get("quant") or ""
        label = overrides.get("llamacpp_coding") or overrides.get(mid) or ("%s:%s" % (repo, quant) if quant else repo)
        pull_key = "%s\t%s" % (repo, quant)
    elif prov == "drawthings":
        label = overrides.get("drawthings_image") or overrides.get(mid) or m.get("drawthings_model") or mid
        pull_key = label
    elif prov == "fluidvoice":
        label = overrides.get("fluidvoice_speech") or overrides.get(mid) or m.get("fluidvoice_model") or mid
        pull_key = label
    else:
        label = mid
        pull_key = mid
    est = m.get("estimated_disk_gb") or 0
    auto = (m.get("automation") or "auto").strip()
    src = (m.get("source") or "").strip()
    chosen[key if not id_f else mid] = (mid, prov, role, label, est, auto, pull_key, src)

for item in chosen.values():
    mid, prov, role, label, est, auto, pull_key, src = item
    # encode pull_key with unit separator replacement already tab for llamacpp
    print("%s|%s|%s|%s|%s|%s|%s|%s" % (mid, prov, role, label, est, auto, pull_key.replace("|", "/"), src))
PY
}

# Status check for a plan line → already|missing|manual
dots_models_status_for_line() {
	local provider="$1" label="$2" pull_key="$3" automation="$4"
	if [[ ${automation} == manual ]]; then
		printf 'manual\n'
		return 0
	fi
	case "${provider}" in
	ollama)
		if dots_mp_ollama_has_model "${pull_key}"; then
			printf 'already\n'
		else
			printf 'missing\n'
		fi
		;;
	llamacpp)
		local repo quant
		repo="${pull_key%%$'\t'*}"
		quant="${pull_key#*$'\t'}"
		[[ ${quant} == "${pull_key}" ]] && quant=""
		if dots_mp_llamacpp_has_model "${repo}" "${quant}"; then
			printf 'already\n'
		else
			printf 'missing\n'
		fi
		;;
	drawthings)
		if dots_mp_drawthings_has_model "${pull_key}"; then
			printf 'already\n'
		else
			printf 'missing\n'
		fi
		;;
	fluidvoice)
		printf 'manual\n'
		;;
	*)
		printf 'missing\n'
		;;
	esac
}
