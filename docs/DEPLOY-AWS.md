# Deploying the SWAT+ BMP ensemble on live AWS (via staRburst)

This is the **live cloud-burst path**: the 6 BMP scenarios fan across real EC2
workers, each running SWAT+ over the Tiffin model pulled from S3, returning its
outlet hydrograph — then scored against real USGS observed flow.

## Provisioned in this session (ready)

| Piece | Value |
|---|---|
| AWS account | `942542972736` (us-east-1) |
| staRburst config | present (`starburst_is_configured()` == TRUE) |
| **Worker base image (GAP A)** | `…/starburst-worker:base-4.6.0` — a strict **superset of staRburst's stock R-4.6.0 base** (same apt + R deps) plus the official **SWAT+ 61.0.2 ifx** binary (`SWAT_BIN=/usr/local/bin/swatplus`). **Multi-arch** (amd64 runs SWAT+; arm64 carries it unused). Built by `docker/build-and-push.sh` (`R_VERSION=4.6.0`). The prior stock base is preserved as `base-4.6.0-stock-backup`. |
| **Model in S3 (GAP B)** | `s3://starburst-942542972736-5555996a/swat-demo/tiffin-model.tar.gz` (real Tiffin TxtInOut, 70 files) — recorded in `data-raw/model_s3_uri.txt` |

Verified this session: staRburst picks up `base-4.6.0`, builds its renv layer on
top, and registers an **X86_64** task definition. The remaining step is
provisioning the `c7i.xlarge` capacity provider (GAP A′ below) — then the workers
launch. That EC2 launch is the only billable step.

## 🚧 What the live run proved — two real feasibility findings

Driving the live run end-to-end on 2026-06-13 produced two distinct, verified
findings. **The base-image workaround was applied and it worked** — the run got
all the way to worker launch before hitting a *second*, smaller gap. Net: every
layer through "build the worker image and register an x86_64 task" now works on
real AWS; the only thing between here and a green ensemble is one supported setup
call.

### GAP A — no first-class "use my binary image" hook (the headline) — WORKAROUND VERIFIED

staRburst workers do **not** run a prebuilt image directly. `ensure_environment()`
builds a *new* per-environment image: `FROM base-<Rversion>` + `COPY renv.lock` +
`renv::restore()` + the staRburst `worker.R`, tagged by an renv hash. The worker
runs **that** image. So a non-R binary only reaches a worker if it lives in the
**base** image staRburst builds on top of — and staRburst picks the base purely by
**R version** (`base-<major.minor>`), not by a custom tag (`get_base_image_uri()`,
`R/images.R:227`; `ensure_base_image()`, `R/images.R:480` checks only that the
`base-<rver>` tag *exists*).

**The workaround we applied (and verified this session):** rebuild the SWAT+ image
as a strict **superset of staRburst's stock `base-4.6.0`** (same apt + R deps, plus
the SWAT+ ifx binary) and push it **over the `base-4.6.0` tag**. staRburst then
logs `[OK] Using existing private base image: …base-4.6.0`, builds its renv layer
`FROM` it (the binary survives — `renv::restore()` only adds R packages), and
registers an **`Architecture: X86_64`** task definition. Confirmed in the live log.

Three things make this a *workaround, not a clean integration* — and each is its
own GAP-A data point:
1. **You must clobber the shared `base-<rver>` tag.** There is no per-workload
   base; the binary-bearing image has to masquerade as *the* R-4.6.0 base every
   staRburst job in the account resolves. (We retag the prior image as
   `base-4.6.0-stock-backup` to make it reversible — see Teardown.)
2. **R-version coupling.** The image's R must match the client's R exactly, or
   staRburst won't pick it up. Bump R → rebuild the binary image.
3. **Forced multi-arch.** staRburst hardcodes `--platform linux/amd64,linux/arm64`
   on the env build (`R/images.R:606`), so the base must be a multi-arch manifest
   even though SWAT+ only runs on amd64 — the arm64 variant carries a non-runnable
   x86 binary purely to satisfy buildx.

→ **Cleanest fix:** a first-class **`base_image=` / `worker_image=` override** on
`starburst_session()`/`plan()` — "use exactly this ECR image as the worker, skip
the renv build, don't force multi-arch" — for workloads that bring a non-R
environment. (Or a custom-layers hook with R-version reconciliation.)

### GAP A′ — the session path assumes the instance-type's capacity provider is pre-provisioned

With the base-image workaround in place, the live run advanced past image build and
task-def registration, then failed at warm-pool start:

```
[Starting] Starting warm pool: 6 instances of c7i.xlarge...
Error: ValidationError (HTTP 400). AutoScalingGroup name not found - null
```

Cause: because SWAT+ is x86_64, the demo forces `instance_type="c7i.xlarge"`, so
staRburst looks for the ASG `starburst-asg-c7i-xlarge`. But the **session path**
(`start_warm_pool()`, `R/ec2-pool.R:337`, called from `session-backend.R:136`)
calls `set_desired_capacity` on that ASG **without first ensuring it exists** —
ASG/capacity-provider creation lives only in `setup_ec2_capacity_provider()`, which
the *session* path never invokes. The account had only `starburst-asg-c6a-large`
provisioned (a different x86_64 type from an earlier setup), so the c7i ASG was
missing and the error surfaced as an opaque `name not found - null`.

This is a smaller, cleaner gap than GAP A:
- **Supported fix (no code change):** pre-provision the type once with the public
  API — `starburst_setup_ec2(instance_types = "c7i.xlarge")` (its default list even
  includes `c7i.xlarge`). That creates the Launch Template + ASG (`DesiredCapacity=0`,
  free at rest) + capacity provider; the session then scales it.
- **Ergonomic fix (small):** have the EC2 session path lazily call
  `setup_ec2_capacity_provider()` when the ASG is absent, instead of erroring — and
  surface a clear "run starburst_setup_ec2() for this instance type" message rather
  than `name not found - null`.

We stopped here by choice (the *finding* is the deliverable; provisioning new infra
was out of scope for this pass). No billable compute ran — the failure was at
`set_desired_capacity`, before any instance launched (verified: zero EC2 instances,
zero ECS tasks, no stray c7i ASG).

### ✅ GREEN RUN (2026-06-13) — the full ensemble ran on live EC2

After clearing GAP A′ with `starburst_setup_ec2(instance_types="c7i.xlarge")`, all
**6 BMP scenarios ran real SWAT+ on live c7i.xlarge spot workers** and returned real
Tiffin River streamflow (1096 daily values each, 2016–2018), scored against real
USGS gauge 04185000. Skill vs observed (uncalibrated, honest):

| scenario | NSE | KGE | PBIAS | mean (m³/s) | peak |
|---|---|---|---|---|---|
| s06 Aggressive BMP combo | 0.37 | 0.35 | −51% | 5.60 | 71.3 |
| s05 Higher ET (esco 0.80) | 0.38 | 0.35 | −49% | 5.92 | 65.7 |
| s04 Drainage water mgmt | 0.38 | 0.34 | −50% | 5.80 | 63.1 |
| s03 Reduced tillage | 0.35 | 0.33 | −51% | 5.59 | 66.9 |
| s01 Baseline | 0.37 | 0.33 | −50% | 5.74 | 62.4 |
| s02 Cover crops | 0.34 | 0.33 | −53% | 5.42 | 69.5 |

(USGS observed mean 11.5 m³/s; positive NSE/KGE, ~−50% PBIAS — the model
under-predicts, consistent with the known single-soil/tile-drainage limitation,
honestly labeled. The scenarios produce **distinct hydrographs** — the ensemble
differentiates BMP options, which is the demo's whole point.) Recorded in
`maumee-build/tiffin/results/live-aws-fit.csv`.

### Two more gaps surfaced at the task layer (worked around demo-side)
1. **renv.lock must be COMPLETE.** The env build runs `renv::init(bare=TRUE);
   renv::restore()`, which isolates `.libPaths()` to the project library — so any
   package NOT in the lock (even one baked into the base, like `qs2`) is invisible
   at runtime. A 3-package lock killed every worker with "no package called 'qs2'".
   Fix: generate the lock from the base image's `installed.packages()` (complete,
   exact versions) so restore is a no-op.
2. **Globals don't follow into a shipped function's body.** `run_one_scenario` calls
   `.s3_download_and_untar`/`apply_scenario`/`parse_swat_streamflow`; R resolves
   those via the function's *own* closure env, not the names staRburst assigns into
   the worker exec env — so passing them as `globals=` does nothing (every task
   errored "could not find function .s3_download_and_untar"). Fix: re-parent all
   helpers into one fresh env and ship that closure (qs2 serializes a non-global
   closure env by value). See `.run_ensemble_aws()` in `R/ensemble.R`.

   → These two reinforce the **GAP B** ask: a first-class "ship this function +
   its dependency closure + an input dir, get named outputs back" hook.

### Bottom line
Real GIS → SWAT+ model → ensemble → visual app → image in ECR built on the SWAT+
base → x86_64 workers → **6 real SWAT+ runs on live EC2, scored vs USGS**. Proven
end-to-end. The friction (GAP A: clobber the shared base; GAP A′: pre-provision the
capacity provider; GAP B: complete-lock + closure-shipping by hand) all points at
the same first-class extensions: a `worker_image=` override, lazy/clear
capacity-provider setup, and a function+inputs+outputs staging hook.

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
…and staRburst's `base-<rversion>` tag for that worker's R version must be the
SWAT+ superset image (built by `docker/build-and-push.sh` with `R_VERSION` matching
the client — see GAP A above). The worker reads `SWAT_BIN` from the image.

## Run it

```bash
cd aws-swat-demo

# One-time per instance type (GAP A′): provision the c7i.xlarge capacity provider
# + ASG (DesiredCapacity=0, free at rest). The session path does NOT auto-create it.
AWS_PROFILE=aws Rscript -e 'starburst::starburst_setup_ec2(instance_types="c7i.xlarge", force=TRUE)'

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
- ECR base image storage: ~2 GB multi-arch ≈ \$0.20/month.
- staRburst tears workers down after the run (warm-pool timeout configurable).

So a full live ensemble run is **a few cents**. We stopped short of the EC2 launch
here by choice (GAP A′ — the finding was the deliverable), not cost.

## Teardown

```r
# staRburst cleans up workers on session end; to force:
AWS_PROFILE=aws Rscript -e 'starburst::starburst_status()'   # check for running tasks
```

**Restore the stock R-4.6.0 base** (undo the GAP-A tag overwrite) by retagging the
backup over `base-4.6.0`:

```bash
M=$(AWS_PROFILE=aws aws ecr batch-get-image --repository-name starburst-worker --region us-east-1 \
      --image-ids imageTag=base-4.6.0-stock-backup --query 'images[0].imageManifest' --output text)
AWS_PROFILE=aws aws ecr put-image --repository-name starburst-worker --region us-east-1 \
  --image-tag base-4.6.0 --image-manifest "$M"
```

The ECR base image + S3 model persist (cheap) for repeat runs; delete with
`aws ecr batch-delete-image` / `aws s3 rm` if no longer needed. To remove the c7i
capacity provider/ASG: `aws autoscaling delete-auto-scaling-group
--auto-scaling-group-name starburst-asg-c7i-xlarge --force-delete`.
