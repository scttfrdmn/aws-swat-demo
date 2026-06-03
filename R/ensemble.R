# ensemble.R — Build the scenario matrix, fan it across workers, collect results,
# and score every scenario against the real NWM reference pulled from RODA.
#
# This is the Kalcic-lab shape, miniaturized: "evaluate management options
# across an ensemble of model runs."

#' Run a SWAT+ scenario ensemble.
#'
#' @param scenarios data.frame; one row per scenario. Must include scenario_id,
#'   label, and any parameter-knob columns (e.g. cn2_pct, esco, surlag).
#' @param backend "local" (sequential, mock SWAT) or "aws" (fan across staRburst workers).
#' @param model_ref local TxtInOut dir (local backend) or s3:// model tarball (aws).
#' @param start,end simulation + comparison period.
#' @param gauge USGS gauge for the NWM/observed reference (default Maumee @ Waterville).
#' @param workers cloud workers when backend = "aws".
#' @return list(series, fit, reference, observed, meta)
run_ensemble <- function(scenarios,
                         backend  = c("local", "aws"),
                         model_ref = NULL,
                         start = "2015-01-01", end = "2015-12-31",
                         gauge = "04193500",
                         workers = NULL) {
  backend <- match.arg(backend)
  scenarios <- .normalize_scenarios(scenarios)

  # --- 1. Real reference data from RODA (NWM) + optional USGS observed. ------
  ref <- nwm_reference(gauge = gauge, start = start, end = end)
  obs <- usgs_observed(gauge = gauge, start = start, end = end)

  # --- 2. Run the ensemble. -------------------------------------------------
  rows <- split(scenarios, seq_len(nrow(scenarios)))
  as_list <- function(r) as.list(r)

  if (backend == "local") {
    options(swat_demo.use_mock = TRUE)
    series_list <- lapply(rows, function(r)
      run_one_scenario(as_list(r), model_ref %||% "LOCAL_MOCK",
                       backend = "local", start = start, end = end))
  } else {
    # AWS: fan across staRburst workers via a detached session.
    if (is.null(model_ref)) stop("backend='aws' requires model_ref = 's3://.../model.tar.gz'")
    series_list <- .run_ensemble_aws(rows, model_ref, start, end, workers)
  }
  series <- do.call(rbind, series_list)

  # --- 3. Score each scenario against the NWM reference. --------------------
  fit <- do.call(rbind, lapply(series_list, function(s) {
    f <- fit_against(s, ref$flow)
    data.frame(scenario_id = s$scenario_id[1], label = s$label[1],
               nse = f$nse, kge = f$kge, pbias = f$pbias, n = f$n,
               mock = isTRUE(s$mock[1]), stringsAsFactors = FALSE)
  }))
  fit <- fit[order(-fit$kge), ]

  list(
    series    = series,
    fit       = fit,
    reference = ref,            # list(comid, gauge, flow)  — source attr on flow
    observed  = obs,            # data.frame or NULL
    meta      = list(backend = backend, start = start, end = end, gauge = gauge,
                     ref_source = attr(ref$flow, "source"))
  )
}

# Fan the ensemble across staRburst cloud workers (detached session).
.run_ensemble_aws <- function(rows, model_ref, start, end, workers) {
  if (!requireNamespace("starburst", quietly = TRUE)) {
    stop("backend='aws' requires the 'starburst' package")
  }
  options(swat_demo.use_mock = FALSE)
  n <- length(rows)
  session <- starburst::starburst_session(workers = workers %||% min(n, 10L),
                                          launch_type = "EC2")
  on.exit(try(session$cleanup(), silent = TRUE), add = TRUE)

  ids <- lapply(rows, function(r) {
    sc <- as.list(r)
    session$submit(quote(
      run_one_scenario(sc, model_ref, backend = "aws", start = start, end = end)
    ), globals = list(sc = sc, model_ref = model_ref, start = start, end = end,
                      run_one_scenario = run_one_scenario,
                      apply_scenario = apply_scenario,
                      parse_swat_streamflow = parse_swat_streamflow))
  })
  res <- session$collect(wait = TRUE)
  # collect() returns results keyed/ordered by submission; coerce to list of frames.
  lapply(res, function(x) x$value %||% x)
}

# Ensure required columns + sane types.
.normalize_scenarios <- function(scenarios) {
  scenarios <- as.data.frame(scenarios, stringsAsFactors = FALSE)
  if (!"scenario_id" %in% names(scenarios)) {
    scenarios$scenario_id <- sprintf("s%02d", seq_len(nrow(scenarios)))
  }
  if (!"label" %in% names(scenarios)) {
    scenarios$label <- scenarios$scenario_id
  }
  scenarios
}

`%||%` <- function(a, b) if (is.null(a)) b else a
