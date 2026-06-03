# aws-swat-demo

**Run [SWAT+](https://swat.tamu.edu/) hydrological-model ensembles on AWS and compare them
against real open streamflow data — driven from a visual Shiny app, using
[staRburst](https://github.com/scttfrdmn/starburst) for cloud bursting.**

A **demonstration / feasibility spike** (not a product) modeled on the workload of OSU's
Kalcic/AgWater group: **Maumee River → Western Lake Erie BMP scenario ensembles**. It fans
many SWAT+ runs across AWS workers from a Shiny UI, then validates them against **real
science data** pulled from the **AWS Registry of Open Data (RODA)**.

> Built against `starburst/SWAT-FEASIBILITY-BRIEF.md`.

---

## The real science

The demo answers a genuine question: *how do different agricultural BMP / parameter
scenarios change simulated streamflow in the Maumee, and how do those simulations compare to
an independent national reanalysis?*

- **Study reach:** Maumee River at **Waterville, OH** — USGS gauge **04193500**, the
  flux-monitoring point for P loading into Western Lake Erie.
- **Independent reference (RODA):** **NOAA National Water Model CONUS Retrospective v3.0** —
  `s3://noaa-nwm-retrospective-3-0-pds` (Zarr, `us-east-1`, 1979–2023, open / no AWS account
  needed). Real reach-level streamflow reanalysis.
- **Reach linkage:** NWM identifies reaches by `feature_id` = **NHDPlus COMID**. We resolve
  gauge 04193500 → COMID at runtime via **USGS NLDI** (not hard-coded), then pull that
  reach's streamflow from the RODA Zarr store.
- **Ground truth (optional):** USGS observed daily discharge for the same gauge via
  `dataRetrieval`.

The Shiny app overlays **each SWAT+ scenario's hydrograph** against the **NWM reanalysis**
(and observed) for the same reach and period — a real three-way comparison
(physical-model ensemble vs. national reanalysis vs. gauge).

## What it demonstrates (staRburst angle)

- A **BMP / parameter ensemble**: N scenarios → one SWAT+ run each, in parallel on cloud
  workers → collected and compared.
- **detached sessions** so the Shiny UI submits, polls, and renders without blocking.
- A **visual** front-end: a Leaflet map of the reach/gauge, interactive hydrographs, a
  scenario-comparison table, and goodness-of-fit (NSE/KGE) vs. the NWM reference.

## What it intentionally exposes (the spike's findings)

staRburst ships **R closures**, not binaries or file trees. Two gaps, marked `# GAP A` /
`# GAP B` in the code:

- **GAP A — binary in the image.** SWAT+ must be in the worker container. Handled by a
  **custom staRburst base image** with SWAT+ compiled in (`docker/`). No first-class
  "add a binary" hook yet.
- **GAP B — file staging.** A SWAT model is a `TxtInOut` directory; outputs are files. We
  hand-roll S3 upload/download + parsing **inside the task closure** (`R/run_model.R`). A
  first-class `submit(inputs=, outputs=)` contract would remove this boilerplate.

---

## Layout

```
aws-swat-demo/
├── R/
│   ├── nwm_roda.R     # RODA: gauge 04193500 -> COMID (NLDI) -> NWM retrospective streamflow (Zarr on S3)
│   ├── swat_io.R      # apply scenario parameter edits to TxtInOut; parse output (discharge)
│   ├── run_model.R    # worker-side: S3 in -> edit -> run SWAT+ -> parse -> return            (GAP B)
│   ├── ensemble.R     # scenario matrix -> fan across workers -> collect -> fit vs NWM
│   ├── metrics.R      # NSE / KGE / PBIAS goodness-of-fit
│   └── mock_swat.R    # local stand-in for SWAT+ (develop the UI/ensemble without AWS or SWAT)
├── app/
│   └── app.R          # visual Shiny: map + hydrographs + scenario table + fit
├── docker/
│   ├── Dockerfile         # staRburst base + SWAT+ + reticulate/xarray for Zarr            (GAP A)
│   └── build-and-push.sh
├── scripts/
│   ├── 01-setup.R              # starburst_setup() + stage SWAT model to your bucket
│   ├── 02-run-ensemble-local.R # ensemble locally with mock SWAT + REAL NWM data (no AWS compute)
│   └── 03-run-ensemble-aws.R   # ensemble on AWS workers
├── data-raw/
│   ├── fetch-sample-model.sh   # download a small public SWAT+ TxtInOut sample
│   └── scenarios.csv           # example BMP / parameter scenario matrix
├── DESCRIPTION
└── .gitignore
```

## Quick start (no AWS compute, but REAL RODA data)

The fastest path uses **mock SWAT for compute** but **real NWM data from RODA** — so the
visualization and the science comparison are genuine, with zero cloud-compute or SWAT setup:

```r
# Python deps for the Zarr read (one-time): reticulate::py_install(c("xarray","zarr","s3fs","fsspec"))
source("R/nwm_roda.R"); source("R/metrics.R")
source("R/swat_io.R"); source("R/mock_swat.R"); source("R/run_model.R"); source("R/ensemble.R")

scenarios <- read.csv("data-raw/scenarios.csv")
res <- run_ensemble(scenarios, backend = "local",
                    start = "2015-01-01", end = "2015-12-31")   # real NWM reference pulled from RODA
print(res$fit)            # NSE/KGE per scenario vs NWM

shiny::runApp("app", launch.browser = TRUE)   # SWAT_DEMO_BACKEND defaults to "local"
```

> The NWM read uses `reticulate` + `xarray`/`zarr`/`s3fs` (anonymous S3). If Python isn't
> available, `nwm_roda.R` falls back to a cached slice in `data-raw/nwm_cache/` and labels it.

## Running the SWAT compute on AWS

```bash
docker/build-and-push.sh us-east-1     # build SWAT+ worker base image -> your ECR  (GAP A)
Rscript scripts/01-setup.R             # starburst_setup() + stage model to S3
Rscript scripts/03-run-ensemble-aws.R  # fan the ensemble across cloud workers
# or:  SWAT_DEMO_BACKEND=aws Rscript -e 'shiny::runApp("app")'
```

## Status — what's verified vs pending

**Verified working (run locally during the build):**
- ✅ **gauge → COMID** is live: USGS NLDI resolves gauge `04193500` → NWM `feature_id`
  **15634673** (Maumee at Waterville).
- ✅ **Real RODA data pull**: `data-raw/cache-nwm.py` read 365 days of 2015 NWM
  retrospective streamflow for that reach from `s3://noaa-nwm-retrospective-3-0-pds`
  (anonymous) — mean ≈ **204 m³/s**, peak ≈ 1386 m³/s on 2015-06-19 (a real wet period).
  Cached to `data-raw/nwm_cache/nwm_15634673.csv`.
- ✅ **End-to-end ensemble + scoring**: `scripts/02-run-ensemble-local.R` runs all 6
  scenarios and scores each against the real NWM series (NSE/KGE/PBIAS), ranked.
- ✅ All R sources parse; core compute/metrics unit-checked.

**Python via uv:** the Zarr/RODA stack lives in a uv-managed venv (`.venv`, Python 3.12:
`xarray zarr s3fs fsspec numpy pandas`). At runtime `nwm_roda.R` uses `reticulate` to call it;
if reticulate/Python isn't wired up it falls back to the committed cache and labels the source.

**Pending (needs your AWS + a real model):**
- SWAT *compute* is currently the labelled **mock surrogate** (calibrated only in magnitude
  to look believable; `mock = TRUE` everywhere). Real SWAT+ runs need the worker image
  (`docker/Dockerfile`, **pin the SWAT+ version**) and a real `TxtInOut` model.
- Not yet executed against live AWS workers (`scripts/03-run-ensemble-aws.R`).
- Shiny viz needs `plotly`/`leaflet`/`DT` installed (declared in `DESCRIPTION`).

**Reproduce the real data pull:**
```bash
uv venv --python 3.12 .venv && uv pip install --python .venv/bin/python xarray zarr s3fs fsspec numpy pandas
.venv/bin/python data-raw/cache-nwm.py --comid 15634673 --start 2015-01-01 --end 2015-12-31
```
