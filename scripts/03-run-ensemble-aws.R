#!/usr/bin/env Rscript
# 03-run-ensemble-aws.R — Run the SWAT+ BMP ensemble on REAL AWS workers via
# staRburst, validated against real USGS observed flow.
#
# Each scenario is one staRburst task: a worker pulls the model tarball from S3,
# applies the scenario's calibration.cal, runs SWAT+ (baked into the worker
# image), parses the outlet hydrograph, and returns it. staRburst fans the 6
# scenarios across EC2 workers.
#
# PREREQS (all provisioned by this session — see docs/DEPLOY-AWS.md):
#   - staRburst configured (starburst_is_configured() == TRUE)
#   - SWAT+ worker image in ECR: starburst-worker:base-swatplus
#   - model staged in S3 (data-raw/model_s3_uri.txt)
# This LAUNCHES BILLABLE EC2 INSTANCES.

for (f in c("metrics.R","nwm_roda.R","swat_io.R","mock_swat.R","run_model.R","ensemble.R"))
  source(file.path("R", f))

model_uri <- tryCatch(readLines("data-raw/model_s3_uri.txt", warn = FALSE)[1],
                      error = function(e) NULL)
if (is.null(model_uri) || !nzchar(model_uri))
  stop("No model S3 URI — see docs/DEPLOY-AWS.md (stage the model first).")
message("SWAT model: ", model_uri)

scenarios <- utils::read.csv("data-raw/scenarios.csv", stringsAsFactors = FALSE)

# Tiffin River @ Stryker (the real demo model); validate vs real USGS observed.
res <- run_ensemble(scenarios, backend = "aws",
                    model_ref = model_uri,
                    start = "2016-01-01", end = "2018-12-31",
                    gauge = "04185000", ref_source = "usgs",
                    workers = nrow(scenarios))

cat("\nReference:", res$meta$ref_source %||% "n/a", "\n")
cat("Scenario skill vs USGS observed (ranked by KGE):\n")
print(res$fit, row.names = FALSE)
saveRDS(res, "ensemble_result.rds")
message("\nSaved ensemble_result.rds — open the Shiny app to explore visually.")
