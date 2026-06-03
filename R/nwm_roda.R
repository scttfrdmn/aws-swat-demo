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

#' Pull NWM retrospective daily-mean streamflow for one reach from RODA.
#'
#' Uses reticulate + xarray/zarr/s3fs (anonymous S3). Falls back to a cached
#' slice in data-raw/nwm_cache/ if Python/network is unavailable, and labels
#' the result with attr(x, "source").
#'
#' @param comid integer NWM feature_id / NHDPlus COMID.
#' @param start,end ISO date strings.
#' @return data.frame(date, flow_cms, source) — daily mean streamflow (m^3/s).
nwm_streamflow <- function(comid, start = "2015-01-01", end = "2015-12-31") {
  stopifnot(!is.null(comid))

  pulled <- tryCatch(
    .nwm_streamflow_xarray(comid, start, end),
    error = function(e) {
      message(sprintf("NWM Zarr read failed (%s); trying cache.", conditionMessage(e)))
      NULL
    }
  )
  if (!is.null(pulled)) {
    attr(pulled, "source") <- "RODA: NOAA NWM Retrospective v3.0"
    return(pulled)
  }

  # Fallback: cached slice committed to the repo for offline/dev use.
  cache <- file.path("data-raw", "nwm_cache", sprintf("nwm_%s.csv", comid))
  if (file.exists(cache)) {
    df <- utils::read.csv(cache)
    df$date <- as.Date(df$date)
    df <- df[df$date >= as.Date(start) & df$date <= as.Date(end), ]
    attr(df, "source") <- "cache (offline NWM slice)"
    return(df)
  }

  stop("NWM streamflow unavailable: no Python/xarray and no cache for COMID ", comid,
       ". Run reticulate::py_install(c('xarray','zarr','s3fs','fsspec')) or provide a cache.")
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
  reach <- reach$sel(time = reticulate::py_slice(start, end))

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
  if (!requireNamespace("dataRetrieval", quietly = TRUE)) return(NULL)
  tryCatch({
    raw <- dataRetrieval::readNWISdv(gauge, "00060", start, end)  # 00060 = discharge, cfs
    raw <- dataRetrieval::renameNWISColumns(raw)
    data.frame(date = as.Date(raw$Date),
               flow_cms = raw$Flow * 0.0283168,  # cfs -> m^3/s
               stringsAsFactors = FALSE)
  }, error = function(e) {
    message(sprintf("USGS observed retrieval failed: %s", conditionMessage(e)))
    NULL
  })
}
