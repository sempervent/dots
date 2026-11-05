# Geospatial workstation tooling

Package group **`geo`** installs geospatial CLIs for format conversion, OSM
processing, vector simplification, and vector-tile / PMTiles workflows. DOTS
**installs, validates, and documents** these tools — it does **not** download
OSM extracts, open databases, import into PostGIS, launch QGIS, process
arbitrary user datasets, or generate production tile archives during setup or
`./dots check geo`.

## Install

```bash
./setup.sh --packages geo
# or profiles that already include geo: work, home, all
```

QGIS is **not** part of `geo`. It is a heavy Darwin GUI under
`./setup.sh --with mactools` (`omit_from_all`).

## Tool roles

| Tool | Role |
|------|------|
| GDAL / OGR (`gdalinfo`, `ogrinfo`, `ogr2ogr`) | Format conversion; raster/vector operations |
| PROJ / GEOS | Coordinate transforms / geometry kernels (typically deps of GDAL / osm2pgsql — not separate DOTS package ids) |
| QGIS | Desktop GIS (optional; mactools cask) |
| `osmium` (osmium-tool) | OSM PBF/XML inspection, filtering, merging, extracts, metadata |
| `osm2pgsql` | OSM → PostgreSQL/PostGIS **ingestion capability** |
| `mapshaper` | Vector simplification / topology / transforms (npm via existing fnm/Node) |
| `tippecanoe` | Source features → vector tiles / MBTiles |
| `pmtiles` | Single-file PMTiles archive inspect / convert CLI |

**tippecanoe** and **PMTiles** are complementary: tippecanoe generates tiles;
PMTiles packages/distributes them. Neither replaces the other.

GeoPandas and DuckDB remain owned elsewhere (Python / `data` group). DOTS does
**not** run `INSTALL spatial; LOAD spatial;` during checks (may require network).

## Diagnostics

```bash
./dots check geo              # tooling status + env capability metadata
./dots check geo gate         # local fixture stages only
./dots check geo examples     # print examples (not executed)
```

Status separates **tools** from **data / database environment**. A missing
PostgreSQL target does not fail the CLI toolchain. Missing optional QGIS does
not fail CLI geo checks.

### What checks never do

- Download OSM / contact Overpass, Geofabrik, OpenStreetMap APIs, or tile CDNs
- Open PostgreSQL / PostGIS / run `osm2pgsql` import / `CREATE EXTENSION`
- Launch QGIS, open projects, install plugins, or modify QGIS profiles
- Run `pmtiles serve`, bind ports, or start daemons
- Scan `$HOME` for GIS files or transmit coordinates
- Require sudo or a YubiKey

## OSM processing

```bash
osmium --version
osmium fileinfo region.osm.pbf
osmium tags-filter region.osm.pbf w/highway -o highways.osm.pbf
```

DOTS never auto-downloads planet/region extracts. Acquire data yourself
(e.g. Geofabrik) when needed.

## PostGIS ingestion (capability only)

```bash
# USER-DIRECTED ONLY — connects to PostgreSQL; creates/modifies tables;
# can consume substantial CPU and storage. DOTS never runs this in setup/check.
osm2pgsql -d gis -C 2048 --create --slim region.osm.pbf
```

Relationship:

- **osm2pgsql** — ingestion tool DOTS may install
- **PostGIS** — target database you provision
- **DOTS Phase 9** — installs the tool; does **not** provision the target

## Vector tiles / PMTiles

```bash
# tippecanoe can be CPU/storage intensive — keep zooms bounded for experiments
tippecanoe -o out.mbtiles -zg --drop-densest-as-needed in.geojson

pmtiles show map.pmtiles
pmtiles convert out.mbtiles out.pmtiles
```

Do not use DOTS checks to build production archives. Never run `pmtiles serve`
via DOTS.

## CRS

Know **source CRS**, **target CRS**, and **EPSG** identifiers before converting
or reprojecting. DOTS does not silently reproject arbitrary user data.

```bash
ogr2ogr -t_srs EPSG:3857 out.gpkg in.geojson
```

## QGIS (optional)

- Heavy GUI; Darwin via mactools cask
- **Not** included in profile `all`
- Never auto-launched; plugins/profiles/projects not managed in Phase 9
- Linux QGIS packages are not invented for symmetry — use mactools on Darwin

## Platforms

Homebrew formulae on Darwin (and Homebrew-on-Linux when available). Linux native
maps provide `osmium-tool` / `osm2pgsql` on apt/dnf/pacman where verified; Void
and some tile tools may `SKIP_UNSUPPORTED`. `mapshaper` is npm-only.

## Privacy

Diagnostics do not inspect or transmit user datasets or coordinates. Database
credentials in the environment are never printed.
