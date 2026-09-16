# helpers/skills_pack.sh — curated skill packs (--with skills / --with ai-skills)
#
# Manifest: configs/skills/manifest.toml (packs + groups + [[skills]])
# Uses skills CLI (npx -y skills …) with -s per skill for multi-skill repos.
# Provenance: ~/.agents/.skill-lock.json (skills CLI) — content-hash based.
#
# Union/dedupe: selecting multiple packs installs each skill once.
# Provider isolation: Hermes exposure only when hermes co-selected.
#
# Requires: DIR, DRY_RUN, ensure_node_major, agent_skill_is_installed
# Requires: helpers/python_runtime.sh for Python ≥3.11 when parsing skill manifests

# shellcheck source=python_runtime.sh
[[ -n ${DIR:-} ]] && source "${DIR}/helpers/python_runtime.sh" 2>/dev/null || true

dots_skills_manifest_path() {
	printf '%s\n' "${DIR}/configs/skills/manifest.toml"
}

# Interpreter for skill-manifest tomllib (set by dots_ensure_python311_for).
dots_skills_python() {
	if [[ -n ${DOTS_SKILLS_PYTHON:-} ]]; then
		printf '%s\n' "${DOTS_SKILLS_PYTHON}"
		return 0
	fi
	dots_find_python311
}

# List enabled skills for one or more packs (union, security first).
# Args: pack names (skills | ai-skills). Empty → all enabled skills (legacy).
# Output: name<TAB>source<TAB>group (unique by name, first occurrence wins)
dots_skills_manifest_entries_for_packs() {
	local manifest py
	manifest="$(dots_skills_manifest_path)"
	[[ -f ${manifest} ]] || return 1
	# Manifest uses dotted tables ([packs.skills]) — requires tomllib (Python ≥3.11).
	py="$(dots_skills_python)" || {
		echo "Error: no Python ≥3.11 with tomllib for skill manifest parse." >&2
		return 1
	}
	dots_run_python_bin "${py}" - "${manifest}" "$@" <<'PY'
import sys
from pathlib import Path
import tomllib

data = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
packs = [p.strip() for p in sys.argv[2:] if p.strip()]
wanted_groups = None
if packs:
    wanted_groups = set()
    pack_table = data.get("packs") or {}
    for pname in packs:
        meta = pack_table.get(pname) or {}
        for g in meta.get("groups") or []:
            wanted_groups.add(g)
    if not wanted_groups:
        print(f"Error: unknown pack(s): {', '.join(packs)}", file=sys.stderr)
        sys.exit(1)

skills = []
for s in data.get("skills") or []:
    if not s.get("enabled", True):
        continue
    name = (s.get("name") or "").strip()
    source = (s.get("source") or "").strip()
    group = (s.get("group") or "").strip()
    if not name or not source:
        continue
    if wanted_groups is not None and group not in wanted_groups:
        continue
    skills.append((name, source, group))

# Dedupe by name; prefer security group first in ordering
seen = set()
ordered = []
for name, source, group in skills:
    if group == "security" and name not in seen:
        ordered.append((name, source, group))
        seen.add(name)
for name, source, group in skills:
    if name not in seen:
        ordered.append((name, source, group))
        seen.add(name)

for name, source, group in ordered:
    print(f"{name}\t{source}\t{group}")
PY
}

# Legacy helper: engineering pack only (backward compatible for check.sh)
dots_skills_manifest_entries() {
	dots_skills_manifest_entries_for_packs skills | while IFS=$'\t' read -r name source group; do
		printf '%s\t%s\n' "${name}" "${source}"
	done
}

dots_skill_lock_has() {
	local name="$1"
	dots_python3 - "$name" <<'PY'
import json, pathlib, sys
name = sys.argv[1]
lock = pathlib.Path.home() / ".agents" / ".skill-lock.json"
if not lock.is_file():
    sys.exit(1)
try:
    data = json.loads(lock.read_text(encoding="utf-8"))
except Exception:
    sys.exit(1)
skills = data.get("skills") or {}
sys.exit(0 if name in skills else 1)
PY
}

# Static review — read files only; never execute skill scripts.
dots_static_review_skill() {
	local name="$1"
	local root="${HOME}/.agents/skills/${name}"
	if [[ ! -d ${root} ]]; then
		echo "Warn: cannot review missing skill dir ${root}" >&2
		return 1
	fi
	dots_python3 - "${root}" "${name}" <<'PY'
import re, sys
from pathlib import Path

root = Path(sys.argv[1])
name = sys.argv[2]
text_parts = []
for p in root.rglob("*"):
    if not p.is_file():
        continue
    if p.suffix.lower() in {".md", ".txt", ".toml", ".yml", ".yaml", ".json", ".py", ".sh", ".js", ".mjs", ".ts"}:
        try:
            text_parts.append(p.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            pass
blob = "\n".join(text_parts)
patterns = [
    (r"curl\s+[^\n|]*\|\s*(?:ba)?sh", "curl|shell pipe"),
    (r"wget\s+[^\n|]*\|\s*(?:ba)?sh", "wget|shell pipe"),
    (r"\beval\s*\(", "eval("),
    (r"base64\s+(?:--?d(?:ecode)?|/d)", "base64 decode"),
    (r"/dev/tcp/", "bash /dev/tcp"),
    (r"os\.system\s*\(", "os.system"),
]
findings = []
for pat, label in patterns:
    if re.search(pat, blob, re.I):
        findings.append(label)
if findings:
    print(f"FAIL: static security review for '{name}': {', '.join(findings)}", file=sys.stderr)
    sys.exit(1)
print(f"OK: static security review passed for '{name}'")
sys.exit(0)
PY
}

install_skill_from_source() {
	local name="$1" source="$2" group="${3:-}"
	local min_node=18
	local hermes_link="${HOME}/.hermes/skills/${name}"
	local need_install=1
	local expose_hermes=0
	local agent_args=()

	if declare -F dots_may_configure_hermes >/dev/null 2>&1 && dots_may_configure_hermes; then
		expose_hermes=1
		agent_args=(-a hermes-agent)
	fi

	echo "=== Skill: ${name} (${source}${group:+ [${group}]}) ==="

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		if agent_skill_is_installed "${name}"; then
			echo "[dry-run] skip content install (${name} already under ~/.agents/skills)"
			if [[ ${expose_hermes} -eq 1 ]] && [[ ! -e ${hermes_link} ]]; then
				echo "[dry-run] would ensure Hermes discovery: npx skills add … -a hermes-agent"
			elif [[ ${expose_hermes} -eq 0 ]]; then
				echo "[dry-run] skip Hermes skill link (hermes not selected this run)"
			fi
		else
			if [[ ${expose_hermes} -eq 1 ]]; then
				echo "[dry-run] npx -y skills add ${source} -g -y -s ${name} -a hermes-agent"
			else
				echo "[dry-run] npx -y skills add ${source} -g -y -s ${name}  (global store only)"
			fi
			echo "[dry-run] static security review after install"
		fi
		return 0
	fi

	ensure_node_major "${min_node}" || return 1

	if agent_skill_is_installed "${name}"; then
		need_install=0
		echo "OK: '${name}' already installed under ~/.agents/skills"
	fi

	local need_hermes_link=0
	if [[ ${expose_hermes} -eq 1 ]] && [[ ! -e ${hermes_link} ]]; then
		need_hermes_link=1
	fi

	if [[ ${need_install} -eq 0 ]] && [[ ${need_hermes_link} -eq 0 ]]; then
		if [[ ${expose_hermes} -eq 1 ]]; then
			echo "OK: Hermes discovery present (~/.hermes/skills/${name})"
		else
			echo "OK: global skill present (Hermes not selected — no ~/.hermes/skills mutation)"
		fi
		# Still run static review on existing AI-group skills once
		if [[ ${group} == "ai" ]] || [[ ${group} == "security" ]]; then
			dots_static_review_skill "${name}" || return 1
		fi
		return 0
	fi

	if [[ ${source} == *"/skill-security-review" ]] || [[ ${source} == "tt-a1i/archify" ]]; then
		echo "Installing '${name}' from ${source}..."
		npx -y skills add "${source}" -g -y "${agent_args[@]}" </dev/null || true
	else
		echo "Installing '${name}' from ${source} (-s ${name})..."
		npx -y skills add "${source}" -g -y -s "${name}" "${agent_args[@]}" </dev/null || true
	fi

	if ! agent_skill_is_installed "${name}"; then
		echo "Error: skill '${name}' not found under ~/.agents/skills/${name}" >&2
		return 1
	fi
	echo "OK: installed '${name}'"

	if ! dots_static_review_skill "${name}"; then
		echo "Error: removing '${name}' after failed static security review" >&2
		rm -rf "${HOME}/.agents/skills/${name}"
		return 1
	fi

	if [[ ${expose_hermes} -eq 1 ]]; then
		if [[ -e ${hermes_link} ]] || [[ -L ${hermes_link} ]]; then
			echo "OK: Hermes discovers '${name}' via ~/.hermes/skills/${name}"
		else
			echo "Warn: hermes selected but skills/${name} link missing after install" >&2
		fi
	else
		echo "Note: skill in ~/.agents/skills only (Hermes link requires --with hermes)"
	fi
	if dots_skill_lock_has "${name}"; then
		echo "OK: lock entry present (~/.agents/.skill-lock.json)"
	else
		echo "Note: skill installed; lock entry may appear after skills CLI flush"
	fi
}

# Install union of selected packs (skills / ai-skills). Dedupes by skill name.
dots_install_skill_packs() {
	local packs=("$@")
	local manifest line name source group
	local -a plan_names=()
	manifest="$(dots_skills_manifest_path)"
	if [[ ! -f ${manifest} ]]; then
		echo "Error: missing skills manifest ${manifest}" >&2
		return 1
	fi
	if [[ ${#packs[@]} -eq 0 ]]; then
		echo "Error: dots_install_skill_packs requires pack names" >&2
		return 1
	fi

	echo "=== Skill packs: ${packs[*]} ==="
	echo "Manifest: ${manifest}"
	if declare -F dots_may_configure_hermes >/dev/null 2>&1 && dots_may_configure_hermes; then
		echo "Hermes skill exposure: enabled (hermes co-selected)"
	else
		echo "Hermes skill exposure: disabled (global store only)"
	fi

	# Skill manifests need tomllib (Python ≥3.11). Provision when missing; never
	# use an EOL interpreter. DOTS minimum is Python ≥3.11 for all TOML.
	local reason
	reason="$(
		IFS=', '
		echo "${packs[*]}"
	)"
	if ! dots_ensure_python311_for "${reason}"; then
		return 1
	fi

	if [[ ${DRY_RUN:-0} -eq 1 ]] && [[ -z ${DOTS_SKILLS_PYTHON:-} ]]; then
		# No ≥3.11 on host yet — dry-run already announced provisioning.
		echo "[dry-run] skill manifest parse deferred until Python ≥3.11 is provisioned"
		echo "[dry-run] would install union of packs without duplicates: ${packs[*]}"
		return 0
	fi

	while IFS=$'\t' read -r name source group; do
		[[ -z ${name} ]] && continue
		plan_names+=("${name}")
	done < <(dots_skills_manifest_entries_for_packs "${packs[@]}")

	if [[ ${#plan_names[@]} -eq 0 ]]; then
		echo "Error: no skills resolved for packs: ${packs[*]}" >&2
		return 1
	fi

	echo "Planned unique skills (${#plan_names[@]}): ${plan_names[*]}"
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] would install union without duplicates"
	fi

	while IFS=$'\t' read -r name source group; do
		[[ -z ${name} ]] && continue
		install_skill_from_source "${name}" "${source}" "${group}" || return 1
	done < <(dots_skills_manifest_entries_for_packs "${packs[@]}")

	if [[ ${DRY_RUN:-0} -eq 0 ]] && [[ -f "${HOME}/.agents/.skill-lock.json" ]]; then
		ensure_dir "${HOME}/.config/dots/skills"
		cp "${HOME}/.agents/.skill-lock.json" "${HOME}/.config/dots/skills/skills-lock.json"
		echo "OK: copied skills lock → ~/.config/dots/skills/skills-lock.json"
	elif [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] copy ~/.agents/.skill-lock.json → ~/.config/dots/skills/skills-lock.json"
	fi
}

# Backward-compatible engineering pack entrypoint
dots_install_skills_pack() {
	dots_install_skill_packs skills
}

dots_install_ai_skills_pack() {
	dots_install_skill_packs ai-skills
}

# Update curated skills from selected packs (opt-in)
dots_update_skills_pack() {
	ensure_node_major 18 || return 1
	local packs=()
	if has_component skills 2>/dev/null || [[ ${1:-} == "skills" ]]; then
		packs+=(skills)
	fi
	if has_component ai-skills 2>/dev/null || [[ ${1:-} == "ai-skills" ]]; then
		packs+=(ai-skills)
	fi
	if [[ ${#packs[@]} -eq 0 ]]; then
		packs=(skills)
	fi
	local names=() name source group
	while IFS=$'\t' read -r name source group; do
		[[ -n ${name} ]] && names+=("${name}")
	done < <(dots_skills_manifest_entries_for_packs "${packs[@]}")
	if [[ ${#names[@]} -eq 0 ]]; then
		echo "No skills in selected packs"
		return 0
	fi
	echo "Updating curated skills: ${names[*]}"
	npx -y skills update -g -y "${names[@]}" || npx -y skills update -g -y
}
