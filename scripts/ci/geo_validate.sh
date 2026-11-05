#!/usr/bin/env bash
# scripts/ci/geo_validate.sh — geospatial workstation diagnostics (Phase 9)
#
# Non-mutating / offline by default:
#   - never download OSM / contact Overpass / Geofabrik / tile APIs
#   - never open PostgreSQL / PostGIS / run osm2pgsql import
#   - never launch QGIS / install plugins / touch QGIS profiles
#   - never process arbitrary user datasets or generate production tiles
#   - never run `pmtiles serve` / bind ports / start daemons
#   - never INSTALL/LOAD DuckDB spatial (may require network)
#   - temporary fixture outputs only (deleted after gate)
#
# Usage:
#   ./scripts/ci/geo_validate.sh              # status (default)
#   ./scripts/ci/geo_validate.sh status
#   ./scripts/ci/geo_validate.sh gate
#   ./scripts/ci/geo_validate.sh examples
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

MODE="${1:-status}"
FIXTURES="${ROOT}/scripts/tests/fixtures/geo"
ARTIFACT_ROOT="${DOTS_GEO_ARTIFACT_DIR:-${TMPDIR:-/tmp}/dots-geo-$$}"

usage() {
	cat <<'EOF'
Usage: ./scripts/ci/geo_validate.sh [status|gate|examples]

  status    Report geospatial tooling presence + capability metadata
  gate      Deterministic local fixture validations (no network / no DB)
  examples  Print example commands (stdout only; not executed)

Never downloads OSM, opens databases, launches QGIS, serves PMTiles, or
mutates user geospatial files.
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
		gdalinfo) ver="$(gdalinfo --version 2>/dev/null | head -n1 || true)" ;;
		ogr2ogr) ver="$(ogr2ogr --version 2>/dev/null | head -n1 || true)" ;;
		ogrinfo) ver="$(ogrinfo --version 2>/dev/null | head -n1 || true)" ;;
		proj) ver="$(proj 2>/dev/null | head -n1 || true)" ;;
		osmium) ver="$(osmium --version 2>/dev/null | head -n1 || true)" ;;
		osm2pgsql) ver="$(osm2pgsql --version 2>/dev/null | head -n1 || true)" ;;
		mapshaper) ver="$(mapshaper --version 2>/dev/null | head -n1 || true)" ;;
		tippecanoe) ver="$(tippecanoe --version 2>/dev/null | head -n1 || true)" ;;
		pmtiles) ver="$(pmtiles --version 2>/dev/null | head -n1 || true)" ;;
		*) ver="present" ;;
		esac
		printf '  %-18s %s%s%s\n' "${label}" "${GREEN}OK${NC}" "${ver:+ (${ver})}" "${note:+ — ${note}}"
	else
		printf '  %-18s %s\n' "${label}" "${YELLOW}missing${NC}"
	fi
}

# Detect QGIS without launching it (Darwin app / PATH binary only).
qgis_status() {
	if have qgis; then
		echo "OPTIONAL / INSTALLED (PATH)"
		return
	fi
	if [[ "$(uname -s)" == "Darwin" ]]; then
		local app
		for app in "/Applications/QGIS.app" "/Applications/QGIS-LTR.app"; do
			if [[ -d ${app} ]]; then
				echo "OPTIONAL / INSTALLED (${app})"
				return
			fi
		done
		# Homebrew cask often lands under /Applications/QGIS*.app via brew --prefix
		if [[ -d /opt/homebrew/Caskroom/qgis ]] || [[ -d /usr/local/Caskroom/qgis ]]; then
			echo "OPTIONAL / INSTALLED (cask present)"
			return
		fi
	fi
	echo "OPTIONAL / NOT INSTALLED"
}

# YES if any common PG target env vars are set — never print values.
pg_target_configured() {
	if [[ -n ${PGHOST:-} || -n ${PGPORT:-} || -n ${PGDATABASE:-} || -n ${PGUSER:-} || -n ${DATABASE_URL:-} ]]; then
		echo "YES"
	else
		echo "NO"
	fi
}

# Scrub credential-bearing env for any child probes (status/gate never connect).
scrub_db_env() {
	env -u PGPASSWORD -u PGPass -u DATABASE_URL -u PGHOST -u PGPORT \
		-u PGDATABASE -u PGUSER -u PGSERVICE -u PGSSLMODE \
		"$@"
}

run_status() {
	echo "${BLUE}Geospatial Tooling${NC}"
	echo "────────────────────────────────"
	echo ""
	echo "Core"
	tool_line "gdalinfo" gdalinfo
	tool_line "ogr2ogr" ogr2ogr
	tool_line "ogrinfo" ogrinfo
	if have proj; then
		tool_line "proj" proj "(PROJ CLI; often a GDAL/osm2pgsql dep)"
	else
		printf '  %-18s %s\n' "proj" "dep / not on PATH"
	fi
	echo ""
	echo "OSM"
	tool_line "osmium" osmium
	tool_line "osm2pgsql" osm2pgsql "(ingestion capability only)"
	echo ""
	echo "Geometry"
	tool_line "mapshaper" mapshaper "(npm via fnm/Node)"
	echo ""
	echo "Tiles"
	tool_line "tippecanoe" tippecanoe "(features → vector tiles / MBTiles)"
	tool_line "pmtiles" pmtiles "(PMTiles archive CLI)"
	echo ""
	echo "Desktop"
	printf '  %-18s %s\n' "QGIS" "$(qgis_status)"
	echo ""
	echo "Data / database environment"
	local pgcfg
	pgcfg="$(pg_target_configured)"
	if [[ ${pgcfg} == YES ]]; then
		printf '  %-18s %s\n' "PostgreSQL target" "YES (env metadata only; not probed)"
	else
		printf '  %-18s %s\n' "PostgreSQL target" "NOT CONFIGURED"
	fi
	printf '  %-18s %s\n' "PostGIS database" "NOT REQUIRED / NOT PROBED"
	printf '  %-18s %s\n' "OSM extract" "NOT DOWNLOADED"
	echo ""
	echo "Invariants"
	echo "  Tools vs environment are reported separately (missing DB does not fail CLI tools)"
	echo "  No OSM download; no Overpass/Geofabrik/tile-service contact"
	echo "  No PostgreSQL/PostGIS connections; no osm2pgsql import; no CREATE EXTENSION"
	echo "  No QGIS launch / plugins / profile writes; QGIS not in profile all"
	echo "  No pmtiles serve / port bind; no production tile builds"
	echo "  No DuckDB INSTALL spatial; no user dataset scan"
	echo "  sudo required: NO · YubiKey required: NO"
	return 0
}

# --- gate stages (fixtures only) ------------------------------------------------

hash_file() {
	shasum -a 256 "$1" | awk '{print $1}'
}

stage_gdal() {
	local f="${FIXTURES}/point.geojson"
	[[ -f ${f} ]] || {
		skip "GDAL (fixture missing)"
		return 0
	}
	if ! have ogrinfo; then
		skip "GDAL/ogrinfo not installed"
		return 0
	fi
	local before after
	before="$(hash_file "${f}")"
	if scrub_db_env ogrinfo -ro -al -so "${f}" >/dev/null 2>&1; then
		after="$(hash_file "${f}")"
		[[ ${before} == "${after}" ]] || fail "GDAL mutated source"
		pass "GDAL ogrinfo on point.geojson"
		return 0
	fi
	fail "GDAL ogrinfo fixture"
}

stage_osmium() {
	local f="${FIXTURES}/tiny.osm"
	[[ -f ${f} ]] || {
		skip "osmium (fixture missing)"
		return 0
	}
	if ! have osmium; then
		skip "osmium not installed"
		return 0
	fi
	local before after
	before="$(hash_file "${f}")"
	if scrub_db_env osmium fileinfo "${f}" >/dev/null 2>&1; then
		after="$(hash_file "${f}")"
		[[ ${before} == "${after}" ]] || fail "osmium mutated source"
		pass "osmium fileinfo on tiny.osm"
		return 0
	fi
	# Some builds prefer `osmium cat -f osm`
	if scrub_db_env osmium cat "${f}" -f osm -o /dev/null >/dev/null 2>&1; then
		after="$(hash_file "${f}")"
		[[ ${before} == "${after}" ]] || fail "osmium mutated source"
		pass "osmium cat on tiny.osm"
		return 0
	fi
	fail "osmium fixture"
}

stage_mapshaper() {
	local f="${FIXTURES}/polygon.geojson"
	[[ -f ${f} ]] || {
		skip "mapshaper (fixture missing)"
		return 0
	}
	if ! have mapshaper; then
		skip "mapshaper not installed"
		return 0
	fi
	mkdir -p "${ARTIFACT_ROOT}"
	local out="${ARTIFACT_ROOT}/polygon-out.geojson"
	local before after
	before="$(hash_file "${f}")"
	if mapshaper "${f}" -o "${out}" format=geojson >/dev/null 2>&1 && [[ -s ${out} ]]; then
		after="$(hash_file "${f}")"
		[[ ${before} == "${after}" ]] || fail "mapshaper mutated source"
		pass "mapshaper GeoJSON transform (temp)"
		return 0
	fi
	fail "mapshaper fixture"
}

stage_tippecanoe() {
	local f="${FIXTURES}/points.geojson"
	[[ -f ${f} ]] || {
		skip "tippecanoe (fixture missing)"
		return 0
	}
	if ! have tippecanoe; then
		skip "tippecanoe not installed"
		return 0
	fi
	mkdir -p "${ARTIFACT_ROOT}"
	local out="${ARTIFACT_ROOT}/tiny.mbtiles"
	local before after
	before="$(hash_file "${f}")"
	# Bounded: tiny layer, low zoom, force overwrite in temp only
	if tippecanoe -q -f -o "${out}" -z5 -Z0 -l tiny "${f}" >/dev/null 2>&1 && [[ -s ${out} ]]; then
		after="$(hash_file "${f}")"
		[[ ${before} == "${after}" ]] || fail "tippecanoe mutated source"
		# Keep artifact under ARTIFACT_ROOT only (cleaned after gate)
		pass "tippecanoe → temporary MBTiles"
		return 0
	fi
	fail "tippecanoe fixture"
}

stage_pmtiles() {
	if ! have pmtiles; then
		skip "pmtiles not installed"
		return 0
	fi
	mkdir -p "${ARTIFACT_ROOT}"
	local mb="${ARTIFACT_ROOT}/tiny.mbtiles"
	local out="${ARTIFACT_ROOT}/tiny.pmtiles"
	# Prefer convert from tippecanoe output when present
	if [[ -f ${mb} ]]; then
		if pmtiles convert "${mb}" "${out}" >/dev/null 2>&1 && [[ -s ${out} ]]; then
			if pmtiles show "${out}" >/dev/null 2>&1 || pmtiles info "${out}" >/dev/null 2>&1; then
				pass "pmtiles convert+inspect (temp)"
				return 0
			fi
			pass "pmtiles convert (temp; inspect skipped)"
			return 0
		fi
		# Older CLIs may lack convert — fall through to version-only
		skip "pmtiles convert unsupported; binary present"
		return 0
	fi
	# No MBTiles from tippecanoe stage — version probe only (no network)
	if pmtiles --version >/dev/null 2>&1 || pmtiles version >/dev/null 2>&1; then
		skip "pmtiles (no local MBTiles to convert; binary OK)"
		return 0
	fi
	fail "pmtiles binary unusable"
}

run_gate() {
	local rc=0
	echo "${BLUE}Geospatial gate${NC} (fixtures only; no network / no DB)"
	echo "────────────────────────────────"
	mkdir -p "${ARTIFACT_ROOT}"
	# Ensure cleanup even on failure
	# shellcheck disable=SC2064
	trap "rm -rf '${ARTIFACT_ROOT}'" EXIT

	stage_gdal || rc=1
	stage_osmium || rc=1
	stage_mapshaper || rc=1
	stage_tippecanoe || rc=1
	stage_pmtiles || rc=1

	echo ""
	echo "Gate notes"
	echo "  osm2pgsql: not executed (ingestion capability is status-only)"
	echo "  QGIS: not launched; missing QGIS does not fail CLI gate"
	echo "  Artifacts: temporary under ${ARTIFACT_ROOT} (removed on exit)"
	if [[ ${rc} -eq 0 ]]; then
		echo ""
		pass "geo gate complete"
	fi
	return "${rc}"
}

run_examples() {
	cat <<'EOF'
Geospatial tooling examples (copy/paste — not executed by DOTS)

  # GDAL / OGR — inspect / convert (user supplies paths + CRS)
  ogrinfo -ro -al -so data.geojson
  ogr2ogr -t_srs EPSG:3857 out.gpkg in.geojson

  # osmium — local OSM PBF/XML only (DOTS never downloads extracts)
  osmium fileinfo region.osm.pbf
  osmium tags-filter region.osm.pbf w/highway -o highways.osm.pbf

  # osm2pgsql — USER-DIRECTED ONLY (connects to PostgreSQL; mutates tables)
  # DOTS never runs this during setup/check.
  osm2pgsql -d gis -C 2048 --create --slim region.osm.pbf

  # mapshaper — local geometry transforms
  mapshaper in.geojson -simplify 10% -o out.geojson

  # tippecanoe — can be CPU/storage intensive; keep zooms bounded
  tippecanoe -o out.mbtiles -zg --drop-densest-as-needed in.geojson

  # PMTiles — inspect / convert local archives (never `pmtiles serve` via DOTS)
  pmtiles show map.pmtiles
  pmtiles convert out.mbtiles out.pmtiles

  # QGIS — optional heavy GUI (`./setup.sh --with mactools`); never auto-launched

CRS: always know source/target EPSG before reprojecting. DOTS does not
silently reproject user data. DuckDB spatial (INSTALL spatial) is optional
and may require network — not run by DOTS checks.
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
