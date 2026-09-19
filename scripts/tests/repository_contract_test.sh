#!/usr/bin/env bash
# scripts/tests/repository_contract_test.sh — declarative architecture invariants
# Offline only: no live HTTP. Validates registries, paths, and stale-doc guards.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${ROOT}"
export DIR ROOT

pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/package_state.sh"

echo "=== component registry ==="
comp_rc=0
comp_out="$(
	dots_toml_query "${ROOT}/configs/components.toml" <<'PY'
import sys

comps = data.get("components") or []
ids = []
seen = set()
dup = []
for c in comps:
    cid = (c.get("id") or "").strip()
    if not cid:
        print("empty component id", file=sys.stderr)
        sys.exit(2)
    if cid in seen:
        dup.append(cid)
    seen.add(cid)
    ids.append(cid)
    for p in c.get("platforms") or []:
        if p not in ("darwin", "linux"):
            print(f"invalid platform {p!r} on {cid}", file=sys.stderr)
            sys.exit(3)
    bf = (c.get("brewfile") or "").strip()
    if bf:
        print(f"BF\t{cid}\t{bf}")
if dup:
    print("duplicate component ids: " + ",".join(dup), file=sys.stderr)
    sys.exit(4)

idset = set(ids)
sg_seen = set()
for g in data.get("supergroups") or []:
    gid = (g.get("id") or "").strip()
    if not gid:
        print("empty supergroup id", file=sys.stderr)
        sys.exit(5)
    if gid in sg_seen:
        print(f"duplicate supergroup id: {gid}", file=sys.stderr)
        sys.exit(6)
    sg_seen.add(gid)
    if gid in idset:
        print(f"supergroup id collides with component: {gid}", file=sys.stderr)
        sys.exit(7)
    for m in g.get("members") or []:
        m = str(m).strip()
        if m not in idset:
            print(f"supergroup {gid} unknown member {m}", file=sys.stderr)
            sys.exit(8)
print("SUPEROK")
PY
)" || comp_rc=$?

if [[ ${comp_rc} -eq 0 ]]; then
	ok "component ids unique + platforms valid"
	while IFS=$'\t' read -r kind cid bf; do
		[[ ${kind} == BF ]] || continue
		if [[ -f ${ROOT}/${bf} ]]; then
			ok "brewfile exists for ${cid}: ${bf}"
		else
			bad "missing brewfile for ${cid}: ${bf}"
		fi
	done <<<"${comp_out}"
	if grep -qx 'SUPEROK' <<<"${comp_out}"; then
		ok "supergroup members valid"
	else
		bad "supergroup validation missing SUPEROK"
	fi
else
	bad "components.toml validation failed (rc=${comp_rc})"
fi

echo "=== dots_component_brewfile registry lookup ==="
for id in herdr hermes ollama mactools archify skills ai-skills; do
	got="$(dots_component_brewfile "${id}" 2>/dev/null || true)"
	if [[ -n ${got} && -f ${ROOT}/${got} ]]; then
		ok "dots_component_brewfile ${id} → ${got}"
	else
		bad "dots_component_brewfile ${id} failed (got='${got}')"
	fi
done
if dots_component_brewfile "not-a-real-component" >/dev/null 2>&1; then
	bad "unknown component should not resolve brewfile"
else
	ok "unknown component brewfile lookup fails"
fi

echo "=== skills manifest ==="
skills_rc=0
dots_toml_query "${ROOT}/configs/skills/manifest.toml" <<'PY' || skills_rc=$?
import sys

seen = set()
groups_declared = set()
for s in data.get("skills") or []:
    name = (s.get("name") or "").strip()
    source = (s.get("source") or "").strip()
    group = (s.get("group") or "").strip()
    enabled = s.get("enabled", True)
    if not name:
        print("skill missing name", file=sys.stderr)
        sys.exit(2)
    if name in seen:
        print(f"duplicate skill name: {name}", file=sys.stderr)
        sys.exit(3)
    seen.add(name)
    if enabled:
        if not source or not group:
            print(f"enabled skill {name} missing source/group", file=sys.stderr)
            sys.exit(4)
        groups_declared.add(group)

orphan_pack = []
for pname, pdata in (data.get("packs") or {}).items():
    for g in pdata.get("groups") or []:
        g = str(g).strip()
        if g not in groups_declared:
            orphan_pack.append(f"{pname}:{g}")
if orphan_pack:
    print("orphan pack groups: " + ",".join(orphan_pack), file=sys.stderr)
    sys.exit(5)
print("SKILLSOK")
PY
if [[ ${skills_rc} -eq 0 ]]; then
	ok "skills integrity (unique names, enabled fields, pack groups)"
else
	bad "skills manifest integrity failed (rc=${skills_rc})"
fi

echo "=== package groups ==="
groups_rc=0
groups_out="$(
	dots_toml_query "${ROOT}/configs/packages/groups.toml" <<'PY'
seen = set()
for g in data.get("groups") or []:
    name = str(g.get("name") or "").strip()
    if not name:
        raise SystemExit(2)
    if name in seen:
        raise SystemExit(3)
    seen.add(name)
    print(name)
PY
)" || groups_rc=$?
if [[ ${groups_rc} -eq 0 ]]; then
	ok "package group names unique"
	while IFS= read -r g; do
		[[ -z ${g} ]] && continue
		if [[ -f ${ROOT}/brew/groups/${g}.Brewfile ]]; then
			ok "brew/groups/${g}.Brewfile exists"
		else
			bad "missing brew/groups/${g}.Brewfile"
		fi
	done <<<"${groups_out}"
else
	bad "groups.toml invalid (rc=${groups_rc})"
fi

echo "=== links sources exist ==="
links_rc=0
export ROOT
dots_toml_query "${ROOT}/configs/links.toml" <<'PY' || links_rc=$?
import os, sys
from pathlib import Path

root = Path(os.environ["ROOT"])
missing = []
for link in data.get("links") or []:
    src = (link.get("source") or "").strip()
    if not src:
        continue
    if not (root / src).exists():
        missing.append(src)
if missing:
    sys.stderr.write("missing link sources:\n  " + "\n  ".join(missing) + "\n")
    sys.exit(2)
print("LINKSOK")
PY
if [[ ${links_rc} -eq 0 ]]; then
	ok "all configs/links.toml sources exist"
else
	bad "link source paths missing"
fi

echo "=== Homebrew aggregate + packages.txt ==="
if [[ -f ${ROOT}/brew/Brewfile ]]; then
	ok "brew/Brewfile exists"
else
	bad "brew/Brewfile missing"
fi
if [[ -e ${ROOT}/brew/packages.txt ]]; then
	bad "brew/packages.txt must not exist"
else
	ok "packages.txt absent"
fi

echo "=== brew/Brewfile ↔ group drift ==="
drift_rc=0
python3 - <<'PY' || drift_rc=$?
import os, re, sys
from pathlib import Path

root = Path(os.environ["ROOT"])
token_re = re.compile(r'^\s*(brew|cask)\s+"([^"]+)"')

def tokens(path: Path):
    out = set()
    if not path.is_file():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        m = token_re.match(line)
        if m:
            out.add((m.group(1), m.group(2)))
    return out

agg = tokens(root / "brew/Brewfile")
missing = []
for g in ("core", "modern", "workstation", "media", "gui", "infra"):
    for kind, name in tokens(root / "brew/groups" / f"{g}.Brewfile"):
        if (kind, name) not in agg:
            missing.append(f"{g}:{kind}:{name}")
if missing:
    sys.stderr.write(
        "aggregate brew/Brewfile missing group tokens:\n  "
        + "\n  ".join(missing)
        + "\n"
    )
    sys.exit(2)
print("DRIFTOK")
PY
if [[ ${drift_rc} -eq 0 ]]; then
	ok "brew/Brewfile contains group Brewfile tokens (core…infra)"
else
	bad "brew/Brewfile drifted from brew/groups"
fi

echo "=== stale phrase guards ==="
stale_hits=0
while IFS= read -r hit; do
	[[ -z ${hit} ]] && continue
	echo "  stale: ${hit}" >&2
	stale_hits=$((stale_hits + 1))
done < <(
	rg -n --glob '!scripts/tests/repository_contract_test.sh' \
		-e 'Homebrew truth is `brew/Brewfile` only' \
		-e 'Homebrew truth is brew/Brewfile only' \
		-e 'SUPPORTED_WITH in setup\.sh' \
		-e 'add the name to `SUPPORTED_WITH`' \
		-e 'add the name to SUPPORTED_WITH' \
		"${ROOT}/README.md" "${ROOT}/AGENTS.md" "${ROOT}/helpers" "${ROOT}/docs" \
		"${ROOT}/setup.sh" 2>/dev/null || true
)
if [[ ${stale_hits} -eq 0 ]]; then
	ok "no stale Homebrew-truth / SUPPORTED_WITH setup.sh guidance"
else
	bad "stale architectural phrases present (${stale_hits})"
fi

echo "=== internal doc links resolve ==="
link_fail=0
check_md_links() {
	local file="$1"
	[[ -f ${file} ]] || return 0
	local dir rel target
	dir="$(cd "$(dirname "${file}")" && pwd)"
	while IFS= read -r rel; do
		[[ -z ${rel} ]] && continue
		rel="${rel%%#*}"
		[[ -z ${rel} ]] && continue
		case "${rel}" in
		http://* | https://* | mailto:* | //*) continue ;;
		esac
		if [[ ${rel} == /* ]]; then
			target="${rel}"
		else
			target="${dir}/${rel}"
		fi
		if [[ ! -e ${target} ]]; then
			echo "  broken: ${file} → ${rel}" >&2
			link_fail=$((link_fail + 1))
		fi
	done < <(rg -o '\[[^\]]*\]\(([^)]+)\)' -r '$1' "${file}" 2>/dev/null || true)
}

check_md_links "${ROOT}/README.md"
check_md_links "${ROOT}/AGENTS.md"
check_md_links "${ROOT}/CONTRIBUTING.md"
for f in "${ROOT}/docs/"*.md; do
	check_md_links "${f}"
done
if [[ ${link_fail} -eq 0 ]]; then
	ok "internal markdown links resolve"
else
	bad "broken internal markdown links (${link_fail})"
fi

echo ""
echo "repository_contract_test: ${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
