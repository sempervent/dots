#!/usr/bin/env bash
# scripts/ci/media_validate.sh — media + optional Darwin desktop diagnostics (Phase 10)
#
# Non-mutating / offline by default:
#   - never open mic/camera/screen-capture devices
#   - never play/rec audio (no `play` / `rec`)
#   - never download media / contact YouTube or streaming services
#   - never inspect browser cookies / netrc / media credentials
#   - never launch GUI apps (no `open -a`, no osascript)
#   - never request Accessibility / Screen Recording / Local Network permissions
#   - never start LocalSend listeners or discover peers
#   - never open database connections (TablePlus / env credentials)
#   - temporary synthetic fixtures only (deleted after gate)
#
# Usage:
#   ./scripts/ci/media_validate.sh              # status (default)
#   ./scripts/ci/media_validate.sh status
#   ./scripts/ci/media_validate.sh gate
#   ./scripts/ci/media_validate.sh examples
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

MODE="${1:-status}"
ARTIFACT_ROOT="${DOTS_MEDIA_ARTIFACT_DIR:-${TMPDIR:-/tmp}/dots-media-$$}"

usage() {
	cat <<'EOF'
Usage: ./scripts/ci/media_validate.sh [status|gate|examples]

  status    Report media CLI presence (+ Darwin mactools app inventory)
  gate      Deterministic synthetic fixture stages (no devices / no network)
  examples  Print example commands (stdout only; not executed)

Never captures devices, plays audio, downloads media, launches GUIs, or
modifies macOS privacy permissions.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

pass() { echo "${GREEN}PASS${NC} $1"; }
fail() {
	echo "${RED}FAIL${NC} $1"
	return 1
}
skip() { echo "${YELLOW}SKIP${NC} $1"; }

tool_line() {
	local label="$1"
	local bin="$2"
	local note="${3:-}"
	if have "${bin}"; then
		local ver=""
		case "${bin}" in
		ffmpeg) ver="$(ffmpeg -version 2>/dev/null | head -n1 || true)" ;;
		ffprobe) ver="$(ffprobe -version 2>/dev/null | head -n1 || true)" ;;
		sox) ver="$(sox --version 2>/dev/null | head -n1 || true)" ;;
		soxi) ver="$(soxi --version 2>/dev/null | head -n1 || true)" ;;
		yt-dlp) ver="$(yt-dlp --version 2>/dev/null | head -n1 || true)" ;;
		magick | convert) ver="$(magick -version 2>/dev/null | head -n1 || convert -version 2>/dev/null | head -n1 || true)" ;;
		exiftool) ver="$(exiftool -ver 2>/dev/null | head -n1 || true)" ;;
		*) ver="present" ;;
		esac
		printf '  %-14s %s%s%s\n' "${label}" "${GREEN}OK${NC}" "${ver:+ (${ver})}" "${note:+ — ${note}}"
	else
		printf '  %-14s %s\n' "${label}" "${YELLOW}missing${NC}"
	fi
}

# Detect macOS apps without launching (filesystem / cask dirs only).
app_status() {
	local name="$1"
	shift
	local path
	for path in "$@"; do
		if [[ -d ${path} ]]; then
			echo "OPTIONAL / INSTALLED"
			return
		fi
	done
	# Homebrew caskroom presence (not launched)
	local cask_id="${name}"
	case "${name}" in
	Raycast) cask_id=raycast ;;
	Rectangle) cask_id=rectangle ;;
	LocalSend) cask_id=localsend ;;
	TablePlus) cask_id=tableplus ;;
	Bruno) cask_id=bruno ;;
	Proxyman) cask_id=proxyman ;;
	Secretive) cask_id=secretive ;;
	QGIS) cask_id=qgis ;;
	OrbStack) cask_id=orbstack ;;
	esac
	if [[ -d /opt/homebrew/Caskroom/${cask_id} ]] || [[ -d /usr/local/Caskroom/${cask_id} ]]; then
		echo "OPTIONAL / INSTALLED (cask present)"
		return
	fi
	echo "OPTIONAL / NOT INSTALLED"
}

run_status() {
	echo "${BLUE}Media Tooling${NC}"
	echo "────────────────────────────────"
	echo ""
	echo "Video"
	tool_line "ffmpeg" ffmpeg
	tool_line "ffprobe" ffprobe
	echo ""
	echo "Audio"
	tool_line "sox" sox
	if have soxi; then
		tool_line "soxi" soxi "(optional companion)"
	else
		printf '  %-14s %s\n' "soxi" "optional / not on PATH"
	fi
	echo ""
	echo "Retrieval"
	tool_line "yt-dlp" yt-dlp "(version only during checks)"
	echo ""
	echo "Image (pre-existing)"
	if have magick; then
		tool_line "magick" magick
	elif have convert; then
		tool_line "convert" convert "(ImageMagick)"
	else
		printf '  %-14s %s\n' "imagemagick" "${YELLOW}missing${NC}"
	fi
	tool_line "exiftool" exiftool

	if [[ "$(uname -s)" == "Darwin" ]]; then
		echo ""
		echo "macOS Applications (mactools / components — inventory only)"
		printf '  %-14s %s\n' "Raycast" "$(app_status Raycast "/Applications/Raycast.app")"
		printf '  %-14s %s\n' "Rectangle" "$(app_status Rectangle "/Applications/Rectangle.app")"
		printf '  %-14s %s\n' "LocalSend" "$(app_status LocalSend "/Applications/LocalSend.app")"
		printf '  %-14s %s\n' "TablePlus" "$(app_status TablePlus "/Applications/TablePlus.app")"
		printf '  %-14s %s\n' "Bruno" "$(app_status Bruno "/Applications/Bruno.app")"
		printf '  %-14s %s\n' "Proxyman" "$(app_status Proxyman "/Applications/Proxyman.app")"
		printf '  %-14s %s\n' "Secretive" "$(app_status Secretive "/Applications/Secretive.app")"
		printf '  %-14s %s\n' "QGIS" "$(app_status QGIS "/Applications/QGIS.app" "/Applications/QGIS-LTR.app")"
		printf '  %-14s %s\n' "OrbStack" "$(app_status OrbStack "/Applications/OrbStack.app")"
		echo "  (owner: mactools omit_from_all, except OrbStack = --with orbstack component)"
	fi

	echo ""
	echo "Invariants"
	echo "  No microphone/camera/screen capture; no play/rec; no device enumeration"
	echo "  No yt-dlp network / cookies-from-browser / media downloads"
	echo "  No GUI launches (open -a / osascript); no Accessibility or permission changes"
	echo "  No LocalSend peer discovery / listeners; no TablePlus DB connections"
	echo "  mactools included in all: NO · accounts required: NO"
	echo "  sudo required: NO · YubiKey required: NO"
	return 0
}

# --- gate: synthetic media only ------------------------------------------------

stage_ffmpeg() {
	if ! have ffmpeg || ! have ffprobe; then
		skip "ffmpeg/ffprobe not installed"
		return 0
	fi
	mkdir -p "${ARTIFACT_ROOT}"
	local out="${ARTIFACT_ROOT}/tiny.mp4"
	# lavfi testsrc — no hardware devices
	if ffmpeg -hide_banner -loglevel error -f lavfi -i "testsrc=duration=0.2:size=160x120:rate=10" \
		-f lavfi -i "sine=frequency=440:duration=0.2" \
		-c:v libx264 -pix_fmt yuv420p -c:a aac -shortest -y "${out}" >/dev/null 2>&1 \
		&& [[ -s ${out} ]]; then
		if ffprobe -hide_banner -loglevel error -show_format -show_streams "${out}" >/dev/null 2>&1; then
			pass "ffmpeg lavfi → tiny mp4 + ffprobe"
			return 0
		fi
		pass "ffmpeg lavfi → tiny mp4 (ffprobe soft)"
		return 0
	fi
	# Fallback without audio encode if codecs limited
	if ffmpeg -hide_banner -loglevel error -f lavfi -i "testsrc=duration=0.2:size=160x120:rate=10" \
		-frames:v 2 -y "${ARTIFACT_ROOT}/tiny.nut" >/dev/null 2>&1; then
		pass "ffmpeg lavfi → tiny nut"
		return 0
	fi
	fail "ffmpeg synthetic fixture"
}

stage_sox() {
	if ! have sox; then
		skip "sox not installed"
		return 0
	fi
	mkdir -p "${ARTIFACT_ROOT}"
	local out="${ARTIFACT_ROOT}/tone.wav"
	# Synthetic tone — never play/rec
	if sox -n -r 8000 -c 1 "${out}" synth 0.1 sine 440 >/dev/null 2>&1 && [[ -s ${out} ]]; then
		if have soxi; then
			soxi "${out}" >/dev/null 2>&1 || true
		fi
		pass "sox synth → temporary WAV"
		return 0
	fi
	fail "sox synthetic fixture"
}

stage_ytdlp_version() {
	if ! have yt-dlp; then
		skip "yt-dlp not installed"
		return 0
	fi
	# Version only — never URL / cookies
	if yt-dlp --version >/dev/null 2>&1; then
		pass "yt-dlp --version (no network)"
		return 0
	fi
	fail "yt-dlp --version"
}

run_gate() {
	local rc=0
	echo "${BLUE}Media gate${NC} (synthetic fixtures; no devices / no network)"
	echo "────────────────────────────────"
	mkdir -p "${ARTIFACT_ROOT}"
	# shellcheck disable=SC2064
	trap "rm -rf '${ARTIFACT_ROOT}'" EXIT

	stage_ffmpeg || rc=1
	stage_sox || rc=1
	stage_ytdlp_version || rc=1

	echo ""
	echo "Gate notes"
	echo "  play/rec not invoked; no avfoundation/device capture"
	echo "  yt-dlp: version only (no URL, no cookies)"
	echo "  GUI apps: not launched"
	echo "  Artifacts: temporary under ${ARTIFACT_ROOT} (removed on exit)"
	if [[ ${rc} -eq 0 ]]; then
		echo ""
		pass "media gate complete"
	fi
	return "${rc}"
}

run_examples() {
	cat <<'EOF'
Media tooling examples (copy/paste — not executed by DOTS)

  # FFmpeg / ffprobe — user supplies paths; DOTS never processes libraries
  ffmpeg -i in.mov -c:v libx264 -c:a aac out.mp4
  ffprobe -hide_banner in.mp4

  # SoX — never run play/rec via DOTS; user-directed only
  sox in.wav out.wav rate 44100
  sox -n tone.wav synth 1 sine 440   # generate tone (no hardware)

  # yt-dlp — USER-DIRECTED ONLY (network + service terms / copyright apply)
  # DOTS never downloads media or reads browser cookies during setup/check.
  yt-dlp -F 'https://example.com/watch?v=…'
  yt-dlp -x --audio-format mp3 'URL'   # may invoke ffmpeg when present

  # ImageMagick / exiftool (pre-existing media group)
  magick in.png -resize 50% out.png
  exiftool photo.jpg

macOS apps (./setup.sh --with mactools; omit_from_all):
  Raycast, Rectangle, LocalSend, TablePlus, Bruno, Proxyman, Secretive, QGIS
  OrbStack: ./setup.sh --with orbstack (separate component)

Users are responsible for service terms, copyright, and authorization when
retrieving media. DOTS does not provide service-specific bypass behavior.
EOF
}

case "${MODE}" in
-h | --help)
	usage
	exit 0
	;;
"" | status)
	run_status
	exit $?
	;;
gate)
	run_gate
	exit $?
	;;
examples)
	run_examples
	exit 0
	;;
*)
	echo "Unknown mode: ${MODE}" >&2
	usage >&2
	exit 1
	;;
esac
