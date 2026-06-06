# ensemble.R — Build the scenario matrix, fan it across workers, collect results,
# and score every scenario against the real NWM reference pulled from RODA.
#
# This is the Kalcic-lab shape, miniaturized: "evaluate management options
# across an ensemble of model runs."

#' Run a SWAT+ scenario ensemble.
#'
#' @param scenarios data.frame; one row per scenario. Must include scenario_id,
#'   label, and any parameter-knob columns (e.g. cn2_pct, esco, surlag).
#' @param backend "local" (mock SWAT), "synthetic" (real file paths, synthetic
#'   model), "real" (read committed REAL SWAT+ ensemble outputs, e.g. the Tiffin
#'   model run on janus / a staRburst worker), or "aws" (fan across staRburst
#'   workers live).
#' @param model_ref local TxtInOut dir (local backend) or s3:// model tarball (aws).
#' @param start,end simulation + comparison period.
#' @param gauge USGS gauge for the reference. Default Tiffin R. at Stryker
#'   (04185000) — the gauge of the real demo model.
#' @param ref_source "nwm" (RODA NWM retrospective) or "usgs" (USGS observed at
#'   the gauge). For the real Tiffin model the matching reference is the USGS gauge.
#' @param results_dir for backend="real": dir of <scenario_id>_flow.csv files.
#' @param workers cloud workers when backend = "aws".
#' @return list(series, fit, reference, observed, meta)
run_ensemble <- function(scenarios,
                         backend  = c("local", "synthetic", "real", "aws"),
                         model_ref = NULL,
                         start = "2016-01-01", end = "2018-12-31",
                         gauge = "04185000",
                         ref_source = c("usgs", "nwm"),
                         results_dir = "maumee-build/tiffin/results/ensemble",
                         workers = NULL) {
  backend <- match.arg(backend)
  ref_source <- match.arg(ref_source)
  scenarios <- .normalize_scenarios(scenarios)

  # --- 1. Real reference: USGS observed at the gauge, or NWM from RODA. ------
  obs <- usgs_observed(gauge = gauge, start = start, end = end)
  if (ref_source == "usgs") {
    if (is.null(obs)) stop("USGS observed unavailable for gauge ", gauge,
                           " (need dataRetrieval or network).")
    ref <- list(gauge = gauge, comid = NA_integer_, flow = obs)
    attr(ref$flow, "source") <- sprintf("USGS observed (gauge %s)", gauge)
  } else {
    ref <- nwm_reference(gauge = gauge, start = start, end = end)
  }

  # --- 2. Run / collect the ensemble. ---------------------------------------
  rows <- split(scenarios, seq_len(nrow(scenarios)))
  as_list <- function(r) as.list(r)

  if (backend == "real") {
    # Read committed REAL SWAT+ per-scenario outputs (produced by running the
    # actual model — locally, on janus, or on a staRburst worker). Each file is
    # <scenario_id>_flow.csv: Date,flow (outlet daily streamflow, m^3/s).
    # Resolve results_dir whether the app runs from the project root or app/.
    rdir <- results_dir
    if (!dir.exists(rdir) && dir.exists(file.path("..", rdir))) rdir <- file.path("..", rdir)
    series_list <- lapply(rows, function(r) {
      sc <- as_list(r); sid <- sc[["scenario_id"]]
      f <- file.path(rdir, paste0(sid, "_flow.csv"))
      if (!file.exists(f)) stop("missing real ensemble output: ", f)
      d <- utils::read.csv(f, header = FALSE, col.names = c("date", "flow_cms"))
      d$date <- as.Date(d$date)
      d <- d[d$date >= as.Date(start) & d$date <= as.Date(end), ]
      data.frame(date = d$date, flow_cms = as.numeric(d$flow_cms),
                 scenario_id = sid, label = sc[["label"]], mock = FALSE,
                 stringsAsFactors = FALSE)
    })
  } else if (backend == "local") {
    options(swat_demo.use_mock = TRUE)
    series_list <- lapply(rows, function(r)
      run_one_scenario(as_list(r), model_ref %||% "LOCAL_MOCK",
                       backend = "local", start = start, end = end))
  } else if (backend == "synthetic") {
    # Real file paths over a local synthetic TxtInOut (no binary, no S3, no AWS).
    options(swat_demo.use_mock = FALSE)
    md <- model_ref %||% file.path("data-raw", "model")
    if (!dir.exists(md)) stop("synthetic backend needs a local model dir at ", md,
                              " — run data-raw/make-synthetic-model.R")
    series_list <- lapply(rows, function(r)
      run_one_scenario(as_list(r), md, backend = "synthetic", start = start, end = end))
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
