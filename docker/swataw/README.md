# Headless SWAT+ AW image

Builds a **SWAT+ model from raw GIS inputs without any GUI** — QGIS/QSWAT+ +
TauDEM + SWAT+ Editor driven headlessly. Used to generate the demo's SWAT+
`TxtInOut` (e.g. the Maumee model) on a Linux/x86_64 host.

**Verified end-to-end** on the bundled SWAT+ AW Robit example: all stages return
rc=0, SWAT+ runs ("simulating: 1992/1/1"), and a real `TxtInOut/` with
`channel_sd_day.txt` (daily streamflow) is produced.

## Build & run

```bash
docker build -t swataw:latest .

# Build a model: mount a dir containing config.py + data/ (DEM, landuse, soil,
# outlets.shp, weather, lookup CSVs — see SWAT+ AW example_dataset.zip layout).
docker run --rm -e QT_QPA_PLATFORM=offscreen -v "$PWD/mymodel:/model" \
  swataw:latest bash /model/run-build.sh
# -> /model/<project>/Scenarios/Default/TxtInOut/  (file.cio, channel_sd_day.txt, …)
```

`run-build.sh` runs the three build stages directly (prepare_project → run_qswat
→ run_editor), skipping the interactive `generate_namelist.py` reverse-tool.

## Why this is non-trivial (the hard-won fixes)

QGIS/QSWAT+ headless on a modern base needed several real fixes, all encoded here:

1. **Headless Qt** — `QT_QPA_PLATFORM=offscreen` (QGIS otherwise needs a display).
2. **Stale upstream URLs** — SWAT+ AW `install.sh` points at a nonexistent v2.1.0
   release and a dead bitbucket. Use: source = `master` tarball, TauDEM bins =
   `v1.0.4` release asset, WGN sqlite = `plus.swat.tamu.edu/downloads/`.
3. **NumPy era** — base **`qgis/qgis:3.40-jammy`** (Python 3.10 + NumPy 1.21),
   QSWAT+'s native era. The NumPy-2 base (QGIS 3.44) hit a cascade of breaks
   (removed `np.int_t`, dtype-size mismatch, `AxisError` in reductions).
4. **pandas/geopandas via APT** (not pip) so they match system NumPy 1.21 — pip
   pulls NumPy 2 and triggers a binary-incompatibility `ValueError`.
   **peewee** via pip (SWAT+ Editor dependency, unpackaged).
5. **Cython extensions** — pre-compile QSWAT+'s `.pyx` to `.so` at build with
   `numpy.get_include()` (`build_pyx.py`); runtime pyximport otherwise can't find
   numpy headers.
6. **TauDEM rebuilt from source** (`build_taudem.sh`, TauDEM **v5.5.0** via CMake)
   — the bundled v1.0.4 bins link `libgdal.so.26` (GDAL 3.2) which the image
   doesn't have, and pre-5.3.8 TauDEM passes a NULL OGR layer name that modern
   GDAL rejects (broke channel `streamnet`). The build strips mpich's `-flto=auto`
   wrapper flags (this gcc rejects them) and asserts the result no longer links
   `libgdal.so.26`.

## Files
- `Dockerfile` — the image.
- `build_taudem.sh` — TauDEM v5.5.0 CMake build + install + linkage assertion.
- `build_pyx.py` — pre-compile QSWAT+ Cython extensions.
- `run-build.sh` — headless build driver (prepare → qswat → editor) for a `/model`.
