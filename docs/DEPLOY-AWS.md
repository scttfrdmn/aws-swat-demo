# Deploying the SWAT+ BMP ensemble on live AWS (via staRburst)

This is the **live cloud-burst path**: the 6 BMP scenarios fan across real EC2
workers, each running SWAT+ over the Tiffin model pulled from S3, returning its
outlet hydrograph — then scored against real USGS observed flow.

## Provisioned in this session (ready)

| Piece | Value |
|---|---|
| AWS account | `942542972736` (us-east-1) |
| staRburst config | present (`starburst_is_configured()` == TRUE) |
| **Worker image (GAP A)** | `942542972736.dkr.ecr.us-east-1.amazonaws.com/starburst-worker:base-swatplus` — staRburst base + official **SWAT+ 61.0.2 ifx** binary (`SWAT_BIN=/usr/local/bin/swatplus`), x86_64, 545 MB. Built on janus from `docker/Dockerfile`. |
| **Model in S3 (GAP B)** | `s3://starburst-942542972736-5555996a/swat-demo/tiffin-model.tar.gz` (real Tiffin TxtInOut, 70 files) — recorded in `data-raw/model_s3_uri.txt` |

Everything except **launching the EC2 workers** is done (the only billable step).

## 🚧 The live run surfaces GAP A — the headline feasibility finding

Attempting the live run exposes the exact staRburst limitation the feasibility
brief predicted (**GAP A: no first-class "use my binary image" hook**):

- staRburst workers do **not** run a prebuilt image directly. `ensure_environment()`
  builds a *new* per-environment image: `FROM base-<Rversion>` + `COPY renv.lock` +
  `renv::restore()` + the staRburst `worker.R`, tagged by an renv hash. The worker
  runs **that** image.
- So the SWAT+ binary only reaches a worker if it lives in the **base** image that
  staRburst builds on top of — and staRburst picks the base by **R version**
  (`base-<major.minor>`), not by a custom tag.
- Mismatch hit here: the **client R is 4.6.0** (staRburst wants `base-4.6.0`), but
  the SWAT+ image is built on **rocker/r-ver:4.4.2** (`base-swatplus`). staRburst
  won't use it, and forcing a 4.4.2 base under a 4.6.0-locked renv mismatches.

**This is the real result of the whole exercise:** every layer works (real GIS →
SWAT+ model → ensemble → visual app → image in ECR → model in S3), but staRburst
needs a **GAP-A extension** to cleanly run a binary-bearing image:

1. **`base_image=` / `worker_image=` override** on `starburst_session()`/`plan()` —
   "use exactly this ECR image as the worker, skip the renv build" (for tools that
   bring their own non-R environment). *The cleanest fix.*
2. Or a **custom-layers hook** so the renv image is built `FROM` a user base that
   carries the binary, with R-version reconciliation.

Until then, the live run requires reconciling R versions: rebuild the SWAT+ image
on `rocker/r-ver:4.6.0`, push as `base-4.6.0`, and let staRburst's renv layer build
on top (the binary survives in the base; renv only adds R packages). That's a
viable workaround, not a clean integration — which is precisely the GAP-A point.

## ⚠️ Critical: x86_64 workers only

The official SWAT+ Linux binary is **x86_64 / ifx** — it will NOT run on
staRburst's default `c7g.xlarge` (ARM64/Graviton). The live run **must** use an
x86_64 instance, e.g. `c7i.xlarge`, and point staRburst at the SWAT+ base image:

```r
# in run_one_scenario()/ the aws backend, the staRburst session must be:
starburst::starburst_session(
  workers       = 6,
  launch_type   = "EC2",
  instance_type = "c7i.xlarge",   # x86_64 — SWAT+ binary is not ARM
  use_spot      = TRUE
)
```
…and staRburst's base image for that worker must be the `base-swatplus` tag above
(not the default `base-<rversion>`). The worker sets `SWAT_BIN` from the image.

## Run it

```bash
cd aws-swat-demo
AWS_PROFILE=aws Rscript scripts/03-run-ensemble-aws.R
# fans 6 scenarios across EC2 workers -> ensemble_result.rds
# then: SWAT_DEMO_BACKEND=aws Rscript -e 'shiny::runApp("app")'
```

`run_one_scenario(backend="aws")` on each worker: download model tarball from S3
→ `apply_scenario()` writes the scenario `calibration.cal` → run `$SWAT_BIN` →
`parse_swat_streamflow()` (outlet ch 1195) → return the daily series. staRburst
serializes the returns back to the client, which scores each vs USGS.

## Cost estimate (small)

Per the staRburst pricing table, `c7i.xlarge` on-demand ≈ \$0.178/hr (spot
≈ \$0.05/hr). Each scenario = one short SWAT+ run (~2–3 min) plus image pull +
S3 fetch (workers reuse the cached image after first pull).

- **6 spot workers, ~10 min each (incl. cold start/pull):** ≈ 6 × (10/60) × \$0.05
  ≈ **\$0.05 total compute**, plus negligible S3/ECR egress.
- ECR image storage: ~545 MB ≈ \$0.05/month.
- staRburst tears workers down after the run (warm-pool timeout configurable).

So a full live ensemble run is **a few cents**. The reason we stopped short of it
here was policy (no unattended billable compute), not cost.

## Teardown

```r
# staRburst cleans up workers on session end; to force:
AWS_PROFILE=aws Rscript -e 'starburst::starburst_status()'   # check for running tasks
```
The ECR image + S3 model persist (cheap) for repeat runs; delete with
`aws ecr batch-delete-image` / `aws s3 rm` if no longer needed.
