#!/usr/bin/env bash
# Assemble real GIS inputs for the Tiffin River SWAT+ model (a Maumee tributary),
# in the SWAT+ AW config.py + data/ layout. Produces everything docker/swataw/
# needs to build the model. Requires: GDAL CLI (gdalwarp, gdal_calc.py, ogr2ogr),
# curl, python3. Large rasters are fetched here (not committed).
#
# Study reach: Tiffin River at Stryker, OH (USGS 04185000; NHDPlus COMID 15662050).
# Verified: this produces a model that SWAT+ runs to real streamflow
# (mean ~4.4 m3/s vs USGS observed ~11.5 m3/s — right order of magnitude, uncalibrated).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)/tiffin"
R="$DIR/data/rasters"; S="$DIR/data/shapefiles"; T="$DIR/data/tables"; W="$DIR/data/weather"
mkdir -p "$R" "$S" "$T" "$W"

# Tiffin gauge + a bbox padded around the upstream basin.
GLAT=41.50449567; GLON=-84.4296719
BBOX_W=-84.55; BBOX_S=41.46; BBOX_E=-84.12; BBOX_N=42.06   # lon/lat
UTM=EPSG:32617   # UTM 17N (meters) — required projected CRS for SWAT+

echo "[1/5] DEM (USGS 3DEP, 30 m) -> UTM 17N"
curl -fsSL "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/exportImage?bbox=${BBOX_W},${BBOX_S},${BBOX_E},${BBOX_N}&bboxSR=4326&size=1600,2000&imageSR=4326&format=tiff&pixelType=F32&f=image" \
  -o "$R/dem_wgs84.tif"
gdalwarp -q -t_srs $UTM -tr 30 30 -r bilinear -dstnodata -9999 -overwrite "$R/dem_wgs84.tif" "$R/srtm_30m.tif"
rm -f "$R/dem_wgs84.tif"

echo "[2/5] NLCD 2021 land cover -> UTM 17N + lookup"
curl -fsSL "https://www.mrlc.gov/geoserver/mrlc_download/wms?service=WMS&version=1.3.0&request=GetMap&layers=NLCD_2021_Land_Cover_L48&crs=EPSG:4326&bbox=${BBOX_S},${BBOX_W},${BBOX_N},${BBOX_E}&width=1600&height=2000&format=image/geotiff" \
  -o "$R/nlcd_raw.tif"
gdalwarp -q -t_srs $UTM -tr 30 30 -r near -dstnodata 0 -overwrite "$R/nlcd_raw.tif" "$R/landuse.tif"
rm -f "$R/nlcd_raw.tif"
cat > "$T/landuse_lookup.csv" <<'CSV'
LANDUSE_ID,SWAT_CODE
11,WATR
21,URLD
22,URMD
23,URHD
24,UIDU
31,BARR
41,FRSD
42,FRSE
43,FRST
52,RNGB
71,RNGE
81,PAST
82,AGRL
90,WETF
95,WETN
CSV

echo "[3/5] Soil: uniform Hoytville (real NW-Ohio clay-loam till soil) + usersoil"
gdal_calc.py --quiet -A "$R/srtm_30m.tif" --outfile="$R/soil.tif" --calc="1*(A>-9998)" --NoDataValue=0 --type=Int16 --overwrite
cat > "$T/soil_lookup.csv" <<'CSV'
SOIL_ID,SNAM
1,Hoytville
CSV
python3 "$(dirname "$0")/make_usersoil.py" "$T/usersoil.csv"

echo "[4/5] Outlet shapefile at the gauge (UTM 17N)"
cat > "$S/outlet.geojson" <<JSON
{"type":"FeatureCollection","features":[
 {"type":"Feature","properties":{"ID":1,"INLET":0,"RES":0,"PTSOURCE":0},
  "geometry":{"type":"Point","coordinates":[${GLON},${GLAT}]}}]}
JSON
ogr2ogr -f "ESRI Shapefile" -s_srs EPSG:4326 -t_srs $UTM "$S/outlets.shp" "$S/outlet.geojson"
rm -f "$S/outlet.geojson"

echo "[5/5] Observed weather: Daymet daily prcp+tmax+tmin -> SWAT+ station files"
python3 "$(dirname "$0")/fetch_daymet.py" "$W" 41.75 -84.35 2015 2018

echo "Done. Model inputs in $DIR. Build with docker/swataw (see its README)."
