# Geospatial tooling

Package group `geo`: GDAL/OGR, osmium-tool, osm2pgsql, mapshaper (npm),
tippecanoe, PMTiles CLI. QGIS remains optional via `--with mactools`
(`omit_from_all`).

```bash
./setup.sh --packages geo
./dots check geo
./dots check geo gate
./dots check geo examples
```

DOTS never downloads OSM, opens PostgreSQL/PostGIS, runs osm2pgsql import,
launches QGIS, serves PMTiles, or processes user datasets during setup/check.
See `docs/using/geo-tooling.md`.
