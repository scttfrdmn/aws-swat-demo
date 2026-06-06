# swat_io.R — Apply scenario parameter edits into a SWAT+ TxtInOut directory and
# parse simulated streamflow back out.
#
# This is deliberately minimal and binary-agnostic in structure: a "scenario" is
# a named list of parameter knobs (e.g. cn2_pct = -5 means reduce curve number by
# 5%). Real SWAT+ calibration edits files like 'hydrology.hyd', 'parameters.bsn',
# or uses the SWAT+ 'calibration.cal' interface. We keep the edit surface small
# and documented so the demo is honest about what it does and doesn't change.

#' Apply a scenario's parameter edits to a copy of a TxtInOut directory.
#'
#' @param model_dir path to a SWAT+ TxtInOut directory (will be copied, not mutated).
#' @param scenario  one row of the scenario matrix as a named list/vector.
#' @return path to the prepared run directory.
apply_scenario <- function(model_dir, scenario) {
  run_dir <- file.path(tempdir(), paste0("swatrun-", scenario[["scenario_id"]]))
  unlink(run_dir, recursive = TRUE)
  dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(model_dir, full.names = TRUE), run_dir, recursive = TRUE)

  # SWAT+ applies parameter changes via 'calibration.cal' (no need to edit every
  # HRU file). The file format is verified against SWAT+ rev 60.5.2:
  #   line1: free-text header
  #   line2: integer count of parameters
  #   line3: column header
  #   then one row per param: NAME CHG_TYP VAL CONDS LYR1 LYR2 YEAR1 YEAR2 DAY1 DAY2 OBJ_TOT
  # CHG_TYP: pctchg = relative %, absval = set absolute value, abschg = add.
  # Each demo BMP knob maps to a SWAT+ calibration parameter:
  #   cn2_pct -> cn2 pctchg   (curve number, % change; cover crops / reduced till)
  #   esco    -> esco absval  (soil evaporation compensation, absolute 0..1)
  #   surlag  -> surlag absval(surface runoff lag; drainage water management)
  knob_map <- list(
    cn2_pct = c("cn2",    "pctchg"),
    esco    = c("esco",   "absval"),
    surlag  = c("surlag", "absval"),
    perco   = c("perco",  "pctchg"),
    awc     = c("awc",    "pctchg"),
    alpha   = c("alpha",  "pctchg")
  )
  rows <- list()
  for (nm in names(knob_map)) {
    v <- suppressWarnings(as.numeric(scenario[[nm]]))
    if (length(v) == 0 || is.na(v)) next
    parm <- knob_map[[nm]][1]; chg <- knob_map[[nm]][2]
    rows[[length(rows) + 1]] <- sprintf(
      "%-14s %-10s %12s %7d %5d %5d %6d %6d %6d %6d %8d",
      parm, chg, format(v, nsmall = 0), 0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L)
  }
  if (length(rows)) {
    cal <- file.path(run_dir, "calibration.cal")
    writeLines(c(
      sprintf("calibration.cal: aws-swat-demo scenario %s", scenario[["scenario_id"]]),
      sprintf(" %d", length(rows)),
      "NAME           CHG_TYP                  VAL   CONDS  LYR1   LYR2  YEAR1  YEAR2   DAY1   DAY2  OBJ_TOT",
      unlist(rows)
    ), cal)
  }
  run_dir
}

#' Parse SWAT+ channel output into daily streamflow at the outlet reach.
#'
#' SWAT+ writes channel discharge to 'channel_sd_day.txt' (or 'channel_sdmorph_day.txt');
#' column 'flo_out' is outflow in m^3/s. We read the outlet channel's series.
#'
#' @param run_dir  prepared/executed run directory.
#' @param outlet_unit optional channel 'unit' id for the outlet; if NULL, use max area / last.
#' @return data.frame(date, flow_cms)
parse_swat_streamflow <- function(run_dir, outlet_unit = NULL, start_date = NULL) {
  candidates <- c("channel_sd_day.txt", "channel_sdmorph_day.txt", "channel_day.txt")
  f <- candidates[file.exists(file.path(run_dir, candidates))][1]
  if (is.na(f)) {
    stop("No SWAT+ channel daily output found in ", run_dir,
         " (looked for: ", paste(candidates, collapse = ", "), ")")
  }
  path <- file.path(run_dir, f)

  # SWAT+ output: 1 title line, 1 header line, then a units line, then data.
  raw <- readLines(path, warn = FALSE)
  hdr <- strsplit(trimws(raw[2]), "\\s+")[[1]]
  dat <- utils::read.table(path, skip = 3, header = FALSE, col.names = hdr,
                           stringsAsFactors = FALSE, fill = TRUE)

  # Outlet selection: explicit unit, else the channel with the largest mean flow.
  flo_col <- if ("flo_out" %in% names(dat)) "flo_out" else tail(names(dat), 1)
  if (is.null(outlet_unit)) {
    agg <- stats::aggregate(dat[[flo_col]], list(unit = dat$unit), mean, na.rm = TRUE)
    outlet_unit <- agg$unit[which.max(agg$x)]
  }
  d <- dat[dat$unit == outlet_unit, ]

  # Reconstruct dates from yr/mon/day columns if present, else a synthetic daily index.
  if (all(c("yr", "mon", "day") %in% names(d))) {
    date <- as.Date(sprintf("%04d-%02d-%02d", d$yr, d$mon, d$day))
  } else {
    s <- if (is.null(start_date)) as.Date("2015-01-01") else as.Date(start_date)
    date <- seq(s, by = "day", length.out = nrow(d))
  }
  data.frame(date = date, flow_cms = as.numeric(d[[flo_col]]),
             stringsAsFactors = FALSE)
}
