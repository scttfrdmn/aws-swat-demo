# nwm_roda.R — Real streamflow reference data from the AWS Registry of Open Data.
#
# Source (verified, open, no AWS account required):
#   NOAA National Water Model CONUS Retrospective v3.0
#   s3://noaa-nwm-retrospective-3-0-pds  (Zarr, us-east-1, 1979-02 .. 2023-01)
#   https://registry.opendata.aws/nwm-archive/
#
# Reaches are identified by `feature_id` == NHDPlus COMID. We resolve a USGS
# gauge to its COMID at runtime via USGS NLDI (no hard-coded IDs), then read
# that reach's streamflow from the Zarr store with xarray via reticulate.

# Maumee River at Waterville, OH — P-flux monitoring point for Western Lake Erie.
MAUMEE_GAUGE <- "04193500"

# RODA NWM retrospective v3.0 Zarr store (anonymous S3).
NWM_RETRO_ZARR <- "s3://noaa-nwm-retrospective-3-0-pds/CONUS/zarr/chrtout.zarr"

#' Resolve a USGS gauge ID to its NHDPlus COMID (== NWM feature_id) via USGS NLDI.
#'
#' @param gauge USGS site number, e.g. "04193500".
#' @return integer COMID, or NULL on failure (caller should fall back).
resolve_comid <- function(gauge = MAUMEE_GAUGE) {
  url <- sprintf(
    "https://api.water.usgs.gov/nldi/linked-data/nwissite/USGS-%s", gauge
  )
  out <- tryCatch({
    js <- jsonlite::fromJSON(url)
    # NLDI returns a GeoJSON feature; the COMID is in properties$comid.
    props <- js$features$properties
    comid <- suppressWarnings(as.integer(props$comid[[1]]))
    if (is.na(comid)) NULL else comid
  }, error = function(e) {
    message(sprintf("NLDI COMID lookup failed for %s: %s", gauge, conditionMessage(e)))
    NULL
  })
  out
}

#' NWM retrospective daily-mean streamflow for one reach from RODA.
#'
#' **Cache-first.** A live read of the full-CONUS NWM Zarr store on RODA takes
#' several MINUTES (opening the store + selecting one reach over a year is the
#' expensive step), which is too slow for an interactive app. So we read a
#' committed cache (itself real RODA data, produced by data-raw/cache-nwm.py)
#' when present, and only do a live xarray/S3 pull when the cache misses AND
#' the caller opts in via `live = TRUE` (or env SWAT_DEMO_LIVE_NWM=1).
#'
#' Either way the result carries attr(x, "source") describing provenance.
#'
#' @param comid integer NWM feature_id / NHDPlus COMID.
#' @param start,end ISO date strings.
#' @param live allow a slow live RODA pull on cache miss (default: env-gated).
#' @return data.frame(date, flow_cms, source) — daily mean streamflow (m^3/s).
nwm_streamflow <- function(comid, start = "2015-01-01", end = "2015-12-31",
                           live = identical(Sys.getenv("SWAT_DEMO_LIVE_NWM"), "1")) {
  stopifnot(!is.null(comid))

  # 1. Cache first (fast; real RODA data committed to the repo).
  cache <- .nwm_cache_path(comid)
  if (file.exists(cache)) {
    df <- utils::read.csv(cache)
    df$date <- as.Date(df$date)
    df <- df[df$date >= as.Date(start) & df$date <= as.Date(end), ]
    if (nrow(df) > 0) {
      attr(df, "source") <- "RODA: NOAA NWM Retrospective v3.0 (cached)"
      return(df)
    }
  }

  # 2. Live RODA pull (slow: minutes). Opt-in only.
  if (live) {
    pulled <- tryCatch(.nwm_streamflow_xarray(comid, start, end),
                       error = function(e) {
                         message(sprintf("Live NWM read failed: %s", conditionMessage(e)))
                         NULL
                       })
    if (!is.null(pulled)) {
      .nwm_cache_write(comid, pulled)   # populate cache for next time
      attr(pulled, "source") <- "RODA: NOAA NWM Retrospective v3.0 (live)"
      return(pulled)
    }
  }

  stop("NWM streamflow unavailable for COMID ", comid,
       ": no cache for this reach/period. Pre-cache it with\n",
       "  .venv/bin/python data-raw/cache-nwm.py --comid ", comid,
       " --start ", start, " --end ", end, "\n",
       "or call with live = TRUE (slow: several minutes).")
}

.nwm_cache_path <- function(comid) {
  for (base in c("data-raw", file.path("..", "data-raw"))) {
    p <- file.path(base, "nwm_cache", sprintf("nwm_%s.csv", comid))
    if (file.exists(p)) return(p)
  }
  file.path("data-raw", "nwm_cache", sprintf("nwm_%s.csv", comid))
}

.nwm_cache_write <- function(comid, df) {
  p <- file.path("data-raw", "nwm_cache", sprintf("nwm_%s.csv", comid))
  tryCatch({
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(df, p, row.names = FALSE)
  }, error = function(e) invisible())
}

# Internal: read the RODA Zarr store via Python xarray. Anonymous S3 access.
.nwm_streamflow_xarray <- function(comid, start, end) {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("reticulate not installed")
  }
  xr <- reticulate::import("xarray", delay_load = TRUE)

  # Anonymous-S3 zarr store. xarray opens it lazily; we then select one
  # feature_id and a time slice before pulling values into R.
  ds <- xr$open_zarr(
    NWM_RETRO_ZARR,
    storage_options = list(anon = TRUE),
    consolidated = TRUE
  )
  reach <- ds$sel(feature_id = as.integer(comid))
  py_slice <- reticulate::import_builtins()$slice
  reach <- reach$sel(time = py_slice(start, end))

  # NWM stores hourly streamflow (m^3/s) in variable 'streamflow'.
  q_hourly <- reach[["streamflow"]]
  q_daily  <- q_hourly$resample(time = "1D")$mean()

  times <- as.Date(as.character(reticulate::py_to_r(q_daily$time$values)))
  vals  <- as.numeric(reticulate::py_to_r(q_daily$values))

  data.frame(date = times, flow_cms = vals, source = "RODA NWM v3.0",
             stringsAsFactors = FALSE)
}

#' Convenience: gauge -> COMID -> NWM streamflow, in one call.
#' @return list(comid, flow = data.frame, gauge)
nwm_reference <- function(gauge = MAUMEE_GAUGE, start = "2015-01-01", end = "2015-12-31") {
  comid <- resolve_comid(gauge)
  if (is.null(comid)) {
    # Last-resort: a cache keyed by gauge, if present.
    message("Falling back to gauge-keyed cache (COMID unresolved).")
    cache <- file.path("data-raw", "nwm_cache", sprintf("gauge_%s.csv", gauge))
    if (file.exists(cache)) {
      df <- utils::read.csv(cache); df$date <- as.Date(df$date)
      return(list(comid = NA_integer_, gauge = gauge,
                  flow = df[df$date >= as.Date(start) & df$date <= as.Date(end), ]))
    }
    stop("Could not resolve COMID for gauge ", gauge, " and no cache available.")
  }
  list(comid = comid, gauge = gauge,
       flow = nwm_streamflow(comid, start, end))
}

#' Optional: USGS observed daily discharge (ground truth) for the same gauge.
#' Uses dataRetrieval if available; returns NULL otherwise.
#' @return data.frame(date, flow_cms) or NULL.
usgs_observed <- function(gauge = MAUMEE_GAUGE, start = "2015-01-01", end = "2015-12-31") {
  # Primary: USGS Water Services daily-values JSON API (no package needed).
  out <- tryCatch({
    url <- sprintf(paste0("https://waterservices.usgs.gov/nwis/dv/?format=json",
                          "&sites=%s&startDT=%s&endDT=%s&parameterCd=00060&statCd=00003"),
                   gauge, start, end)
    js <- jsonlite::fromJSON(url, simplifyVector = FALSE)
    vals <- js$value$timeSeries[[1]]$values[[1]]$value
    dates <- as.Date(vapply(vals, function(v) substr(v$dateTime, 1, 10), character(1)))
    cfs <- suppressWarnings(as.numeric(vapply(vals, function(v) v$value, character(1))))
    df <- data.frame(date = dates, flow_cms = cfs * 0.0283168,  # cfs -> m^3/s
                     stringsAsFactors = FALSE)
    df <- df[is.finite(df$flow_cms) & df$flow_cms >= 0, ]
    if (nrow(df) == 0) NULL else df
  }, error = function(e) {
    message(sprintf("USGS JSON API failed (%s); trying dataRetrieval.", conditionMessage(e)))
    NULL
  })
  if (!is.null(out)) return(out)

  # Fallback: dataRetrieval if available.
  if (!requireNamespace("dataRetrieval", quietly = TRUE)) return(NULL)
  tryCatch({
    raw <- dataRetrieval::readNWISdv(gauge, "00060", start, end)
    raw <- dataRetrieval::renameNWISColumns(raw)
    data.frame(date = as.Date(raw$Date), flow_cms = raw$Flow * 0.0283168,
               stringsAsFactors = FALSE)
  }, error = function(e) NULL)
}
