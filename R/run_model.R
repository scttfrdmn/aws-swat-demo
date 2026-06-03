# run_model.R — The per-scenario unit of work.
#
# This is the function that runs ON A WORKER (or locally). It is written as a
# self-contained closure so it can be shipped by staRburst.
#
# GAP B (file staging) lives here: staRburst has no first-class way to send an
# input directory to a worker or pull output files back, so we hand-roll the S3
# round-trip. A future `submit(inputs="TxtInOut/", outputs="channel_sd_day.txt")`
# would replace the marked blocks.

#' Run one SWAT+ scenario and return its outlet hydrograph.
#'
#' @param scenario   named list/vector: scenario_id, label, + parameter knobs.
#' @param model_ref  where the SWAT model lives:
#'                    - backend "local": a local TxtInOut directory path.
#'                    - backend "aws":   an S3 URI "s3://bucket/key/model.tar.gz".
#' @param backend    "local" (mock SWAT) or "aws" (real SWAT+ in the worker image).
#' @param start,end  simulation period (ISO dates).
#' @return data.frame(date, flow_cms, scenario_id, label[, mock])
run_one_scenario <- function(scenario, model_ref, backend = "local",
                             start = "2015-01-01", end = "2015-12-31") {

  if (identical(backend, "local") && isTRUE(getOption("swat_demo.use_mock", TRUE))) {
    # ---- Local/dev path: surrogate model, no SWAT binary, no S3. -------------
    out <- mock_swat_run(scenario, start = start, end = end)
  } else {
    # ---- Real path (runs on a worker with SWAT+ in the image). ---------------

    # GAP B (input staging): fetch the model tree from S3 and unpack it.
    local_model <- file.path(tempdir(), "swat_model")
    if (grepl("^s3://", model_ref)) {
      .s3_download_and_untar(model_ref, local_model)   # GAP B
    } else {
      local_model <- model_ref
    }

    # Apply this scenario's parameter edits into a fresh run dir.
    run_dir <- apply_scenario(local_model, scenario)

    # Run SWAT+ (binary present via the custom worker image — GAP A).
    swat_bin <- Sys.getenv("SWAT_BIN", "swatplus")
    res <- processx::run(swat_bin, character(), wd = run_dir,
                         error_on_status = FALSE)
    if (res$status != 0) {
      stop(sprintf("SWAT+ run failed (exit %d) for scenario %s:\n%s",
                   res$status, scenario[["scenario_id"]], res$stderr))
    }

    # Parse the outlet streamflow back out (GAP B: output retrieval).
    out <- parse_swat_streamflow(run_dir, start_date = start)
    out$mock <- FALSE
  }

  out$scenario_id <- scenario[["scenario_id"]]
  out$label       <- scenario[["label"]]
  out
}

# Internal: download s3://bucket/key.tar.gz and extract to dest. (GAP B helper.)
.s3_download_and_untar <- function(s3_uri, dest) {
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  m <- regmatches(s3_uri, regexec("^s3://([^/]+)/(.+)$", s3_uri))[[1]]
  if (length(m) != 3) stop("Bad S3 URI: ", s3_uri)
  bucket <- m[2]; key <- m[3]
  tar <- file.path(tempdir(), basename(key))
  s3 <- paws.storage::s3()
  obj <- s3$get_object(Bucket = bucket, Key = key)
  writeBin(obj$Body, tar)
  utils::untar(tar, exdir = dest)
  invisible(dest)
}
