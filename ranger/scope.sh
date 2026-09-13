#!/usr/bin/env bash
# ranger scope.sh — modern preview helper for dots
# Args: path width height [cached_image_path]
set -o noclobber -o noglob -o nounset -o pipefail
IFS=$'\n'

FILE_PATH="${1:-}"
PV_WIDTH="${2:-80}"
# PV_HEIGHT="${3:-}"
# IMAGE_CACHE_PATH="${4:-}"

[[ -z "${FILE_PATH}" ]] && exit 1

# Exit codes: 0=stdout continue, 1=no preview, 2=plain, 3=fix, 4=fixed, 5=ANSI, 6=image cache
MAX_BYTES="${RANGER_PREVIEW_MAX_BYTES:-1048576}"

file_size() {
  if stat -f%z "${FILE_PATH}" >/dev/null 2>&1; then
    stat -f%z "${FILE_PATH}"
  else
    stat -c%s "${FILE_PATH}"
  fi
}

too_large() {
  local sz
  sz="$(file_size 2>/dev/null || echo 0)"
  [[ "${sz}" -gt "${MAX_BYTES}" ]]
}

handle_extension() {
  local ext="${FILE_PATH##*.}"
  ext="$(printf '%s' "${ext}" | tr '[:upper:]' '[:lower:]')"
  case "${ext}" in
    a|ace|alz|arc|arj|bz|bz2|cab|cpio|deb|gz|jar|lha|lz|lzh|lzma|lzo|rpm|rz|t7z|tar|tbz|tbz2|tgz|tlz|txz|tZ|tzo|war|xpi|xz|Z|zip)
      atool --list -- "${FILE_PATH}" 2>/dev/null && exit 5
      bsdtar --list --file "${FILE_PATH}" 2>/dev/null && exit 5
      unzip -l -- "${FILE_PATH}" 2>/dev/null && exit 5
      exit 1
      ;;
    rar)
      unrar lt -p- -- "${FILE_PATH}" 2>/dev/null && exit 5
      exit 1
      ;;
    7z)
      7z l -p -- "${FILE_PATH}" 2>/dev/null && exit 5
      exit 1
      ;;
    pdf)
      pdftotext -l 10 -nopgbrk -q -- "${FILE_PATH}" - 2>/dev/null | head -c "${MAX_BYTES}" && exit 5
      exit 1
      ;;
    json)
      if too_large; then echo "[large JSON — truncated metadata]"; file --brief -- "${FILE_PATH}"; exit 5; fi
      jq -C . "${FILE_PATH}" 2>/dev/null | head -c "${MAX_BYTES}" && exit 5
      exit 1
      ;;
    yml|yaml)
      if too_large; then echo "[large YAML]"; file --brief -- "${FILE_PATH}"; exit 5; fi
      yq -C e . "${FILE_PATH}" 2>/dev/null | head -c "${MAX_BYTES}" && exit 5
      bat --color=always --style=plain -- "${FILE_PATH}" 2>/dev/null | head -c "${MAX_BYTES}" && exit 5
      exit 1
      ;;
    md|markdown)
      bat --color=always --style=plain --language=markdown -- "${FILE_PATH}" 2>/dev/null | head -c "${MAX_BYTES}" && exit 5
      exit 1
      ;;
    csv)
      if command -v xsv >/dev/null 2>&1; then
        xsv table "${FILE_PATH}" 2>/dev/null | head -n 40 && exit 5
      fi
      head -n 40 -- "${FILE_PATH}" && exit 5
      ;;
    sqlite|db|sqlite3)
      sqlite3 -header -column "${FILE_PATH}" ".tables" 2>/dev/null && exit 5
      exit 1
      ;;
    torrent)
      transmission-show -- "${FILE_PATH}" 2>/dev/null && exit 5
      exit 1
      ;;
  esac
}

handle_mime() {
  local mimetype
  mimetype="$(file --mime-type --dereference --brief -- "${FILE_PATH}" 2>/dev/null || echo application/octet-stream)"
  case "${mimetype}" in
    text/*|*/xml|application/javascript|application/x-sh|application/json|application/x-yaml)
      if too_large; then
        echo "[file larger than ${MAX_BYTES} bytes — showing head]"
        head -c "${MAX_BYTES}" -- "${FILE_PATH}"
        exit 5
      fi
      bat --color=always --style=plain --paging=never -- "${FILE_PATH}" 2>/dev/null && exit 5
      highlight --out-format=ansi --force -- "${FILE_PATH}" 2>/dev/null && exit 5
      exit 2
      ;;
    image/*)
      if command -v chafa >/dev/null 2>&1; then
        chafa --size="${PV_WIDTH}x$((PV_WIDTH / 2))" -- "${FILE_PATH}" 2>/dev/null && exit 5
      fi
      if command -v exiftool >/dev/null 2>&1; then
        exiftool "${FILE_PATH}" && exit 5
      fi
      file --brief -- "${FILE_PATH}" && exit 5
      ;;
    video/*|audio/*)
      if command -v mediainfo >/dev/null 2>&1; then
        mediainfo "${FILE_PATH}" && exit 5
      fi
      if command -v ffprobe >/dev/null 2>&1; then
        ffprobe -hide_banner -- "${FILE_PATH}" 2>&1 && exit 5
      fi
      exit 1
      ;;
    application/pdf)
      pdftotext -l 10 -nopgbrk -q -- "${FILE_PATH}" - 2>/dev/null && exit 5
      exit 1
      ;;
  esac
}

handle_fallback() {
  echo '----- File Type Classification -----'
  file --dereference --brief -- "${FILE_PATH}"
  exit 5
}

handle_extension
handle_mime
handle_fallback
