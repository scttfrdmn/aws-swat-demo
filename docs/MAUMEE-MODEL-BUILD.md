# Building a real Maumee SWAT+ model — staged plan & findings

Status: **toolchain investigation done; model not yet built.** This documents the
verified path so the next session can execute it directly.

## Why we're building one

No public, runnable **SWAT+** TxtInOut model of the Maumee / Western Lake Erie
basin exists (searched DuckDuckGo, swat-model/SWATPlus-datasets, HydroShare API,
Zenodo API). The well-known Maumee water-quality modeling (Kalcic, Muenich,
Scavia) is **SWAT2012-era**, whose file formats are **incompatible** with the
SWAT+ binary we verified. So to keep the Maumee framing with real science, we
build a SWAT+ model ourselves.

## Verified groundwork (done)

- **SWAT+ binary:** official `swatplus-61.0.2-ifx-lin_x86_64-Rel` (Intel ifx) runs
  complete models to "Execution successfully completed" on `janus.local` (native
  x86_64). Do NOT build from source with gfortran (spins/segfaults).
- **Runnable reference model:** `SWATPlus-datasets/example1` (Hubbard Brook) works
  end-to-end; our parser reads its `channel_sd_day.txt`.
- **Real validation data:** NWM retrospective on RODA; gauge 04193500
  (Maumee @ Waterville) → NHDPlus COMID **15634673** via USGS NLDI.

## The build tool: SWAT+ AW (headless)

`celray/swatplus-automatic-workflow` (MIT). Config-driven, runs via PyQGIS:
`prepare_project → generate_namelist → run_qswat → run_editor → calibration →
figures`. Deps: QGIS (PyQGIS) + **QSWAT+ plugin**, **TauDEM** (Linux bins bundled
in its install.sh v2.1.0), SWAT+ Editor, `swatplus_wgn.sqlite`.

### Toolchain finding (important)
There is **no ready-made headless SWAT+ AW Docker image**:
- `mintproject/swatplus:59` (52 MB) = SWAT+ binary only.
- `crazyzlj/swatplus:*` = SWAT+ binary only.
- `npavlovikj/swatplus:latest` (7.7 GB) = **interactive** QSWAT+ GUI desktop
  (TurboVNC + VirtualGL + nvidia); QGIS Python not importable headless. Wrong tool
  for automation.
→ **We must build our own headless QGIS+QSWAT++TauDEM+SWAT+AW image** (a Dockerfile
  on janus). PyQGIS plugin loading headless is the main risk; budget for iteration.

## Inputs SWAT+ AW needs (from its bundled `example_dataset.zip`, Robit)

```
config.py                         # paths, projection, dates, options
data/rasters/<dem>.tif            # DEM            -> Maumee: USGS 3DEP/SRTM, clipped
data/rasters/<landuse>/           # land use grid  -> Maumee: NLCD (MRLC, free)
data/rasters/<soil>/              # soil grid      -> Maumee: gSSURGO/STATSGO (USDA)
data/tables/landuse_lookup.csv    # grid code -> SWAT+ plant/urban class
data/tables/soil_lookup.csv       # grid code -> soil series
data/tables/usersoil.csv          # soil physical properties
data/shapefiles/outlets.shp       # outlet(s)      -> gauge 04193500 @ -83.713,41.500
data/weather/*.txt                # pcp/tmp/etc    -> or use WGN (swatplus_wgn.sqlite)
data/observations/                # for calibration vs gauge (optional)
```

## Toolchain status (headless SWAT+ AW Docker image) — IN PROGRESS

Built `docker/swataw/` (Dockerfile + build_pyx.py + run-build.sh), image
`swataw:latest` (~4 GB) on janus. Verified working step-by-step:

- ✅ Base `qgis/qgis:3.44` (Python 3.13, PyQt5/Qt 5.15, NumPy 2.2.4).
- ✅ PyQGIS imports headless with `QT_QPA_PLATFORM=offscreen`; `processing`
  framework + bundled `qswatplus` batch code import (add
  `/usr/share/qgis/python/plugins` to sys.path).
- ✅ Component URL fixes vs the stale `install.sh`: source = **master** tarball
  (no v2.x tag), TauDEM = **v1.0.4** release asset, WGN sqlite =
  **plus.swat.tamu.edu/downloads/swatplus_wgn.sqlite** (bitbucket is dead).
- ✅ Runtime Python deps: `setuptools` (distutils for Cython pyximport on
  py3.13), `pandas`, `geopandas`.
- ✅ **NumPy 2 fix:** QSWAT+ `.pyx` use removed `np.int_t` → `sed` to
  `np.int64_t`; **pre-compile** the 4 Cython extensions to `.so` at image build
  (`build_pyx.py`, with `-I$(numpy.get_include())`) so import doesn't fail.
- ✅ `prepare_project.py` (config.py → project + sqlite + lookups): **rc=0**.
- ✅ Skip `generate_namelist.py` — it's an interactive REVERSE tool (prompts
  "for which model…"), not part of the build; drove a 10 GB infinite-loop log.
  Build path is: prepare_project → run_qswat → run_editor (set `BASE_DIR`).

### ✅ RESOLVED — toolchain proven end-to-end
The headless image (`docker/swataw/`) now builds a SWAT+ model from raw GIS
inputs and runs SWAT+ to completion. Verified on the bundled Robit example:
`prepare_project` rc=0 → `run_qswat` rc=0 (TauDEM delineation + HRUs) →
`run_editor` rc=0 (SWAT+ "simulating: 1992/1/1") → real
`Scenarios/Default/TxtInOut/` with `channel_sd_day.txt` daily streamflow that the
demo's `parse_swat_streamflow()` reads.

The earlier "stall" was a red herring: the real blockers were (a) the bundled
TauDEM binaries failing to load (libgdal.so.26 vs the image's GDAL) and the
pre-5.3.8 OGR NULL-layer-name bug, and (b) NumPy-2 incompatibilities on the QGIS
3.44 base. Both fixed: rebuild TauDEM v5.5.0 from source against the image GDAL,
and base on `qgis/qgis:3.40-jammy` (Python 3.10 + NumPy 1.21, QSWAT+'s native
era). See `docker/swataw/README.md` for the full list of fixes.

### Next: Maumee GIS data assembly (below)
Toolchain is proven; the remaining work is assembling real Maumee inputs into the
SWAT+ AW `config.py` + `data/` layout and running the image on them.
2. **Assemble Maumee GIS inputs** (real, public):
   - DEM: USGS 3DEP (or NWM NHDPlus) clipped to the Maumee HUC (04100009 + upstream).
   - Land use: NLCD 2021 (MRLC) clipped + `landuse_lookup.csv`.
   - Soils: gSSURGO (Ohio/Indiana/Michigan) + `usersoil.csv` + `soil_lookup.csv`.
   - Outlet: point shapefile at gauge 04193500 (Waterville).
   - Weather: WGN (simplest) or real PRISM/station data.
   - `config.py` for Maumee (projection: UTM 17N / EPSG:32617).
3. **Run SWAT+ AW** → produces a Maumee SWAT+ TxtInOut.
4. **Wire into the demo**: stage the TxtInOut to S3, point `run_model.R` at it,
   set the demo's gauge/COMID to 04193500/15634673 (already wired), run the BMP
   ensemble on AWS workers, validate vs the cached NWM reference.

## Honest scope note

Step 2 (GIS assembly for a 17,000 km² basin) is the long pole and may need
iteration to delineate cleanly. A faster first proof is a single Maumee tributary
with its own USGS gauge (e.g. Tiffin/Auglaize) — same toolchain, smaller domain.
