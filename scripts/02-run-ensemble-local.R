#!/usr/bin/env Rscript
# 02-run-ensemble-local.R — Run the ensemble locally (mock SWAT compute) but with
# the REAL NWM reference pulled from the AWS Registry of Open Data. No AWS compute,
# no SWAT binary needed — proves the pipeline + the science comparison.

for (f in c("metrics.R","nwm_roda.R","swat_io.R","mock_swat.R","run_model.R","ensemble.R"))
  source(file.path("R", f))

scenarios <- utils::read.csv("data-raw/scenarios.csv", stringsAsFactors = FALSE)

res <- run_ensemble(scenarios, backend = "local",
                    start = "2015-01-01", end = "2015-12-31")

cat("\nReference source:", res$meta$ref_source %||% "n/a", "\n")
cat("NWM reach COMID:", res$reference$comid, "\n\n")
cat("Scenario skill vs NWM (ranked by KGE):\n")
print(res$fit, row.names = FALSE)

cat("\n(SWAT compute is mocked locally; NWM data is real. ",
    "Use scripts/03-run-ensemble-aws.R for real SWAT+ on cloud workers.)\n", sep = "")
