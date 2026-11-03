# shellcheck shell=bash
# helpers/suggest.sh — lightweight typo suggestions (no Python, no network)

# Levenshtein distance for short tokens. Prefer Python (available after Stage 0);
# pure-Bash fallback stays usable when python3 is absent.
dots_edit_distance() {
	local a="$1" b="$2"
	if command -v python3 >/dev/null 2>&1; then
		A="$a" B="$b" python3 - <<'PY'
import os
a, b = os.environ["A"], os.environ["B"]
n, m = len(a), len(b)
dp = list(range(m + 1))
for i, ca in enumerate(a, 1):
    prev, dp[0] = dp[0], i
    for j, cb in enumerate(b, 1):
        cur = dp[j]
        dp[j] = prev if ca == cb else 1 + min(prev, dp[j], dp[j - 1])
        prev = cur
print(dp[m])
PY
		return 0
	fi
	# Bash fallback (Bash only — not Zsh-safe)
	[[ -n ${BASH_VERSION:-} ]] || {
		printf '%s\n' 99
		return 0
	}
	local -i n=${#a} m=${#b} i j cost
	local -a d=()
	for ((i = 0; i <= n; i++)); do
		d[$((i * (m + 1)))]=$i
	done
	for ((j = 0; j <= m; j++)); do
		d[$j]=$j
	done
	for ((i = 1; i <= n; i++)); do
		for ((j = 1; j <= m; j++)); do
			if [[ ${a:i-1:1} == "${b:j-1:1}" ]]; then
				cost=0
			else
				cost=1
			fi
			local -i del=$((d[$(((i - 1) * (m + 1) + j))] + 1))
			local -i ins=$((d[$((i * (m + 1) + (j - 1)))] + 1))
			local -i sub=$((d[$(((i - 1) * (m + 1) + (j - 1)))] + cost))
			local -i best=$del
			((ins < best)) && best=$ins
			((sub < best)) && best=$sub
			d[$((i * (m + 1) + j))]=$best
		done
	done
	printf '%s\n' "${d[$((n * (m + 1) + m))]}"
}

# Print best matches for needle among candidates (space/newline separated).
# Max distance: 2 for len<=6, else 3. Max 3 suggestions.
dots_suggest_matches() {
	local needle="$1"
	shift || true
	local cand dist maxd=2
	local -a scored=()
	[[ -z ${needle} ]] && return 0
	((${#needle} > 6)) && maxd=3
	for cand in "$@"; do
		[[ -z ${cand} || ${cand} == "${needle}" ]] && continue
		dist="$(dots_edit_distance "${needle}" "${cand}")"
		if ((dist <= maxd)); then
			scored+=("${dist}:${cand}")
		fi
	done
	((${#scored[@]} == 0)) && return 0
	local line
	printf '%s\n' "${scored[@]}" | LC_ALL=C sort -t: -k1,1n -k2,2 | head -3 | while IFS= read -r line; do
		printf '%s\n' "${line#*:}"
	done
}

dots_suggest_print() {
	local needle="$1"
	shift || true
	local -a hits=()
	local h
	while IFS= read -r h; do
		[[ -n ${h} ]] && hits+=("${h}")
	done < <(dots_suggest_matches "${needle}" "$@")
	((${#hits[@]} == 0)) && return 1
	echo "Did you mean:" >&2
	local s
	for s in "${hits[@]}"; do
		echo "  ${s}" >&2
	done
	return 0
}

# Known top-level dots commands from generated usage / metadata snapshot.
# Prefer parsing commands.toml via Python when available; else static list.
# (Named dots_suggest_* to avoid clobbering helpers/packages.sh symbols.)
dots_suggest_known_commands() {
	if [[ -f ${DIR}/configs/help/commands.toml ]] && command -v python3 >/dev/null 2>&1; then
		DIR="${DIR}" python3 - <<'PY' 2>/dev/null && return 0
import tomllib, os
from pathlib import Path
data = tomllib.loads((Path(os.environ["DIR"]) / "configs/help/commands.toml").read_text())
for c in data.get("commands") or []:
    n = (c.get("name") or "").strip()
    if n:
        print(n)
PY
	fi
	printf '%s\n' setup status components lsp ai packages backup backups restore \
		profile models check update help shell completion
}

dots_suggest_known_components() {
	if [[ -f ${DIR}/configs/components.toml ]] && command -v python3 >/dev/null 2>&1; then
		DIR="${DIR}" python3 - <<'PY' 2>/dev/null && return 0
import tomllib, os
from pathlib import Path
root = Path(os.environ["DIR"])
data = tomllib.loads((root / "configs/components.toml").read_text())
for c in data.get("components") or []:
    n = (c.get("id") or "").strip()
    if n: print(n)
for g in data.get("supergroups") or []:
    if isinstance(g, dict):
        n = (g.get("id") or "").strip()
        if n: print(n)
PY
	fi
}

dots_suggest_known_package_groups() {
	if declare -F dots_known_package_groups >/dev/null 2>&1; then
		dots_known_package_groups
		return 0
	fi
	if [[ -f ${DIR}/configs/packages/groups.toml ]] && command -v python3 >/dev/null 2>&1; then
		DIR="${DIR}" python3 - <<'PY' 2>/dev/null && return 0
import tomllib, os
from pathlib import Path
data = tomllib.loads((Path(os.environ["DIR"]) / "configs/packages/groups.toml").read_text())
for g in data.get("groups") or []:
    n = (g.get("name") or "").strip()
    if n: print(n)
PY
	fi
}

dots_suggest_known_help_topics() {
	if [[ -f ${DIR}/configs/help/topics.toml ]] && command -v python3 >/dev/null 2>&1; then
		DIR="${DIR}" python3 - <<'PY' 2>/dev/null && return 0
import tomllib, os
from pathlib import Path
data = tomllib.loads((Path(os.environ["DIR"]) / "configs/help/topics.toml").read_text())
for t in data.get("topics") or []:
    n = (t.get("id") or "").strip()
    if n: print(n)
PY
	fi
	printf '%s\n' overview getting-started shell completion keybindings profiles \
		components packages ai models lsp skills backup diagnostics commands files
}
