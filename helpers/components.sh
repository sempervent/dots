# shellcheck shell=bash
# helpers/components.sh — load optional-component registry
#
# Authority: configs/components.toml
# Requires: DIR, helpers/toml.sh

# shellcheck source=toml.sh
source "${DIR}/helpers/toml.sh"

dots_components_registry_path() {
  printf '%s\n' "${DIR}/configs/components.toml"
}

# Print all component ids (one per line), registry order.
dots_component_ids() {
  dots_toml_query "$(dots_components_registry_path)" <<'PY'
for c in data.get("components") or []:
    cid = (c.get("id") or "").strip()
    if cid:
        print(cid)
PY
}

# Print ids suitable for profile `all` (omit_from_all skipped).
dots_component_ids_for_all() {
  dots_toml_query "$(dots_components_registry_path)" <<'PY'
for c in data.get("components") or []:
    cid = (c.get("id") or "").strip()
    if not cid:
        continue
    if c.get("omit_from_all"):
        continue
    print(cid)
PY
}

dots_component_is_known() {
  local want="$1" id
  while IFS= read -r id; do
    [[ "${id}" == "${want}" ]] && return 0
  done < <(dots_component_ids)
  return 1
}

# Validate CSV / list of component names; print unknowns to stderr.
dots_validate_components() {
  local unknown=0 c
  for c in "$@"; do
    [[ -z "${c}" ]] && continue
    if ! dots_component_is_known "${c}"; then
      echo "Error: unknown component '${c}'" >&2
      unknown=1
    fi
  done
  if [[ "${unknown}" -ne 0 ]]; then
    echo "Supported:" >&2
    dots_component_ids | tr '\n' ' ' >&2
    echo >&2
    return 1
  fi
  return 0
}

# Cloud/external AI notice for selected components.
dots_print_cloud_notice() {
  local wanted
  wanted="$(printf '%s\n' "$@")"
  WANTED="${wanted}" dots_toml_query "$(dots_components_registry_path)" <<'PY'
import os
wanted = {x.strip() for x in os.environ.get("WANTED", "").splitlines() if x.strip()}
for c in data.get("components") or []:
    cid = (c.get("id") or "").strip()
    if cid in wanted and c.get("cloud"):
        print(cid)
PY
}

dots_print_provider_implications() {
  local wanted
  wanted="$(printf '%s\n' "$@")"
  WANTED="${wanted}" dots_toml_query "$(dots_components_registry_path)" <<'PY'
import os
wanted = {x.strip() for x in os.environ.get("WANTED", "").splitlines() if x.strip()}
local_ai, cloud_ai, image_ai = [], [], []
for c in data.get("components") or []:
    cid = (c.get("id") or "").strip()
    if cid not in wanted:
        continue
    cat = c.get("category") or ""
    if c.get("cloud"):
        cloud_ai.append(cid)
    if c.get("local_ai") and cat != "image_ai":
        local_ai.append(cid)
    if cat == "image_ai":
        image_ai.append(cid)
print("explicit provider implications:")
print("  local AI: %s" % (", ".join(local_ai) if local_ai else "(none)"))
print("  cloud AI: %s" % (", ".join(cloud_ai) if cloud_ai else "(none)"))
print("  image AI: %s" % (", ".join(image_ai) if image_ai else "(none)"))
PY
}

# Populate bash array name with registry ids (for setup SUPPORTED_WITH).
dots_load_supported_with_into() {
  local dest="$1"
  eval "${dest}=()"
  local id
  while IFS= read -r id; do
    [[ -n "${id}" ]] && eval "${dest}+=(\"\${id}\")"
  done < <(dots_component_ids)
}
