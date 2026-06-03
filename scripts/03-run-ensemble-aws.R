#!/usr/bin/env Rscript
# 03-run-ensemble-aws.R — Run the SWAT+ ensemble on AWS workers via staRburst,
# validated against the real NWM reference from RODA.
#
# Prereqs: scripts/01-setup.R has run (resources provisioned + model staged);
# the SWAT+ worker base image is published (docker/build-and-push.sh).

for (f in c("metrics.R","nwm_roda.R","swat_io.R","mock_swat.R","run_model.R","ensemble.R"))
  source(file.path("R", f))

model_uri <- tryCatch(readLines("data-raw/model_s3_uri.txt", warn = FALSE)[1],
                      error = function(e) NULL)
if (is.null(model_uri) || !nzchar(model_uri)) {
  stop("No model S3 URI — run scripts/01-setup.R first.")
}
message("SWAT model: ", model_uri)

scenarios <- utils::read.csv("data-raw/scenarios.csv", stringsAsFactors = FALSE)

res <- run_ensemble(scenarios, backend = "aws",
                    model_ref = model_uri,
                    start = "2015-01-01", end = "2015-12-31",
                    workers = nrow(scenarios))

cat("\nReference source:", res$meta$ref_source %||% "n/a", "\n")
cat("Scenario skill vs NWM (ranked by KGE):\n")
print(res$fit, row.names = FALSE)
saveRDS(res, "ensemble_result.rds")
message("\nSaved ensemble_result.rds — open the Shiny app to explore visually.")
