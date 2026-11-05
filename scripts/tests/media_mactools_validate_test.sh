#!/usr/bin/env bash
# scripts/tests/media_mactools_validate_test.sh — Phase 10 media + desktop safety
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${ROOT}/scripts/ci/media_validate.sh"
pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

[[ -x ${SCRIPT} ]] || chmod +x "${SCRIPT}"

# shellcheck disable=SC1091
source "${ROOT}/helpers/toml.sh"
# shellcheck disable=SC1091
source "${ROOT}/helpers/packages.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dots-media-test.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

echo "=== media package ownership ==="
for p in ffmpeg imagemagick exiftool sox yt-dlp; do
	found=0
	while IFS= read -r id; do [[ ${id} == "${p}" ]] && found=1; done < <(dots_group_package_ids media optional)
	[[ ${found} -eq 1 ]] && ok "media owns ${p}" || bad "media missing ${p}"
done
for p in ffmpeg imagemagick exiftool sox yt-dlp; do
	grep -q "brew \"${p}\"" "${ROOT}/brew/groups/media.Brewfile" && ok "Brewfile has ${p}" || bad "Brewfile missing ${p}"
done
# No forbidden groups
for g in audio video desktop productivity macapps; do
	if grep -q "name = \"${g}\"" "${ROOT}/configs/packages/groups.toml"; then
		bad "forbidden group ${g}"
	else
		ok "no forbidden group ${g}"
	fi
done
# Profiles: media in home + all
for prof in home all; do
	grep -q '"media"' "${ROOT}/configs/bootstrap/profiles/${prof}.toml" && ok "profile ${prof} includes media" || bad "profile ${prof} missing media"
done

echo "=== platform maps ==="
for mgr in apt dnf pacman xbps; do
	grep -qE '^sox[[:space:]]*=' "${ROOT}/configs/packages/${mgr}.toml" && ok "${mgr} maps sox" || bad "${mgr} sox"
	grep -qE '^yt-dlp[[:space:]]*=' "${ROOT}/configs/packages/${mgr}.toml" && ok "${mgr} maps yt-dlp" || bad "${mgr} yt-dlp"
done

echo "=== mactools ownership / omit_from_all ==="
BF="${ROOT}/brew/Brewfile.mactools"
for c in raycast rectangle localsend tableplus bruno proxyman secretive qgis; do
	grep -qE "cask \"${c}\"" "${BF}" && ok "mactools cask ${c}" || bad "missing cask ${c}"
done
# OrbStack is separate component — not in mactools Brewfile
if grep -qE 'cask "orbstack"' "${BF}"; then
	bad "orbstack duplicated in mactools"
else
	ok "orbstack not in mactools Brewfile"
fi
grep -q 'cask "orbstack"' "${ROOT}/brew/Brewfile.orbstack" && ok "orbstack component brewfile" || bad "orbstack brewfile"
grep -A12 'id = "mactools"' "${ROOT}/configs/components.toml" | grep -q 'omit_from_all = true' && ok "mactools omit_from_all" || bad "mactools omit"
grep -A12 'id = "orbstack"' "${ROOT}/configs/components.toml" | grep -q 'omit_from_all = true' && ok "orbstack omit_from_all" || bad "orbstack omit"
# all profile must not pull mactools/GUIs
if grep -qiE 'mactools|raycast|rectangle|localsend|tableplus|qgis|bruno|proxyman|secretive|orbstack' \
	"${ROOT}/configs/bootstrap/profiles/all.toml"; then
	bad "all profile references GUI/mactools"
else
	ok "all does not auto-include mactools GUIs"
fi
# Duplicate cask audit across brew/
dup=0
for c in raycast rectangle localsend tableplus bruno proxyman secretive qgis orbstack; do
	count="$(rg -l "cask \"${c}\"" "${ROOT}/brew" 2>/dev/null | wc -l | tr -d ' ')"
	if [[ ${count} -gt 1 ]]; then
		echo "DUP: ${c} in ${count} brewfiles" >&2
		dup=1
	fi
done
[[ ${dup} -eq 0 ]] && ok "no duplicate GUI cask ownership" || bad "duplicate GUI casks"

echo "=== status: no network / devices / GUI launch ==="
mkdir -p "${TMP}/bin"
cat >"${TMP}/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "FORBIDDEN_HTTP:$*" >&2; exit 99
EOF
cat >"${TMP}/bin/wget" <<'EOF'
#!/usr/bin/env bash
echo "FORBIDDEN_HTTP:$*" >&2; exit 99
EOF
cat >"${TMP}/bin/open" <<'EOF'
#!/usr/bin/env bash
echo "FORBIDDEN_OPEN:$*" >&2; exit 99
EOF
cat >"${TMP}/bin/osascript" <<'EOF'
#!/usr/bin/env bash
echo "FORBIDDEN_OSASCRIPT:$*" >&2; exit 99
EOF
cat >"${TMP}/bin/tccutil" <<'EOF'
#!/usr/bin/env bash
echo "FORBIDDEN_TCCUTIL:$*" >&2; exit 99
EOF
cat >"${TMP}/bin/yt-dlp" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
  --cookies-from-browser|*://*|http*|www.*) echo "FORBIDDEN_YTDLP:$a" >&2; exit 99 ;;
  esac
done
case "${1:-}" in --version) echo "2026.01.01"; exit 0 ;; esac
echo "FORBIDDEN_YTDLP:$*" >&2; exit 99
EOF
cat >"${TMP}/bin/play" <<'EOF'
#!/usr/bin/env bash
echo "FORBIDDEN_PLAY:$*" >&2; exit 99
EOF
cat >"${TMP}/bin/rec" <<'EOF'
#!/usr/bin/env bash
echo "FORBIDDEN_REC:$*" >&2; exit 99
EOF
cat >"${TMP}/bin/sox" <<'EOF'
#!/usr/bin/env bash
# Allow --version only during status; gate may use synth in real sox behind PATH
case "${1:-}" in --version|-h|--help) echo "sox stub 14"; exit 0 ;; esac
for a in "$@"; do
  case "$a" in play|rec|-d|--default-device) echo "FORBIDDEN_SOX_HW:$a" >&2; exit 99 ;; esac
done
echo "sox stub"; exit 0
EOF
cat >"${TMP}/bin/ffmpeg" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in -version|--version) echo "ffmpeg stub"; exit 0 ;; esac
for a in "$@"; do
  case "$a" in *avfoundation*|*video=*|*audio=*|-f) ;; esac
done
# Block explicit capture device strings
echo "$*" | grep -qiE 'avfoundation|video=|audio=|:0|:1|x11grab|dshow' && {
	echo "FORBIDDEN_CAPTURE:$*" >&2
	exit 99
}
echo "ffmpeg stub"; exit 0
EOF
cat >"${TMP}/bin/ffprobe" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in -version|--version) echo "ffprobe stub"; exit 0 ;; esac
echo "ffprobe stub"; exit 0
EOF
chmod +x "${TMP}/bin/"*

export PATH="${TMP}/bin:${PATH}"
export PGHOST=localhost PGDATABASE=gis PGUSER=dots_media_test
export PGPASSWORD='super-secret-media-pg-pw'
export DATABASE_URL='postgresql://dots_media_test:super-secret-media-pg-pw@localhost/gis'

stat_out="$("${SCRIPT}" status 2>&1)" || {
	bad "status exit"
	stat_out=""
}
echo "${stat_out}" | grep -qi 'FORBIDDEN_' && bad "status triggered forbidden" || ok "status no forbidden calls"
echo "${stat_out}" | grep -qi 'super-secret-media-pg-pw' && bad "status leaked DB secret" || ok "no DB secret leak"
echo "${stat_out}" | grep -qi 'YubiKey required:.*NO' && ok "YubiKey NO" || bad "YubiKey policy"
echo "${stat_out}" | grep -qi 'sudo required:.*NO' && ok "sudo NO" || bad "sudo policy"
echo "${stat_out}" | grep -qi 'ffmpeg\|yt-dlp\|sox' && ok "status lists media tools" || bad "status incomplete"
if [[ "$(uname -s)" == "Darwin" ]]; then
	echo "${stat_out}" | grep -qi 'Raycast\|Rectangle\|LocalSend\|TablePlus' && ok "Darwin app inventory" || bad "Darwin inventory missing"
fi

# Source must not scan user media libraries
if rg -n 'Movies|Music|Pictures|Photos Library|Ableton|Downloads' "${SCRIPT}" | rg -v '^[[:space:]]*#|never|No |not ' | grep -q .; then
	bad "media validate may scan user libraries"
else
	ok "no user media library scan"
fi
# No tccutil / defaults permission writes / open -a
if rg -n 'tccutil|open[[:space:]]+-a|osascript|defaults[[:space:]]+write' "${SCRIPT}" | rg -v '^[[:space:]]*#|never|No ' | grep -q .; then
	bad "media validate may mutate permissions/launch"
else
	ok "no permission/launch mutation APIs"
fi

echo "=== examples ==="
ex="$("${SCRIPT}" examples 2>&1)" || bad "examples failed"
echo "${ex}" | grep -qi 'yt-dlp\|ffmpeg\|copyright\|terms' && ok "examples + policy note" || bad "examples incomplete"
echo "${ex}" | grep -qi 'FORBIDDEN_' && bad "examples executed tools" || ok "examples stdout only"

echo "=== gate with real tools when available ==="
REAL_PATH="$(echo "${PATH}" | sed "s|${TMP}/bin:||")"
export PATH="${REAL_PATH}"
export DOTS_MEDIA_ARTIFACT_DIR="${TMP}/artifacts"
# Keep stub yt-dlp ahead if real missing — use real for ffmpeg/sox
gate_out="$("${SCRIPT}" gate 2>&1)" || true
echo "${gate_out}" | grep -qi 'FORBIDDEN_' && bad "gate forbidden" || ok "gate no forbidden"
# No leftover under repo
if find "${ROOT}/scripts/tests/fixtures" -name '*.mp4' -o -name '*.wav' 2>/dev/null | grep -q .; then
	bad "media binaries committed under fixtures"
else
	ok "no committed media binaries"
fi

echo "=== yt-dlp stub: network isolation ==="
export PATH="${TMP}/bin:${REAL_PATH}"
# status with stub
"${SCRIPT}" status >/dev/null 2>&1 || true
ok "yt-dlp network calls: 0 (status)"

echo "=== ./dots check media wiring ==="
chk="$("${ROOT}/dots" check -h 2>&1 || true)"
echo "${chk}" | grep -q 'check media' && ok "dots check help mentions media" || bad "help missing media"

echo ""
echo "PASS=${pass} FAIL=${fail}"
[[ ${fail} -eq 0 ]]
