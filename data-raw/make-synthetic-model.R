#!/usr/bin/env Rscript
# make-synthetic-model.R — Generate a tiny *synthetic* SWAT+ TxtInOut directory.
#
# This is NOT a real SWAT+ model and the executable will not run on it. Its sole
# purpose is to exercise the demo's file-handling paths offline:
#   - apply_scenario()        writes calibration.cal into a copy
#   - parse_swat_streamflow() reads a real SWAT+-FORMAT channel_sd_day.txt
#
# It lets `03`'s parse half and the round-trip be tested without the SWAT+ binary
# or AWS. Replace data-raw/model/ with a real TxtInOut for actual runs.

dest <- file.path("data-raw", "model")
dir.create(dest, recursive = TRUE, showWarnings = FALSE)

# --- Minimal SWAT+ control files (placeholders, structurally plausible) -------
writeLines(c(
  "file.cio: synthetic demo (NOT a runnable model)",
  "simulation        time.sim",
  "basin             parameters.bsn",
  "channel           channel_sd_day.txt"
), file.path(dest, "file.cio"))

writeLines(c(
  "time.sim: synthetic",
  "day_start  yr_start  day_end  yr_end  step",
  "        1      2015      365    2015     0"
), file.path(dest, "time.sim"))

writeLines(c(
  "hydrology.hyd: synthetic baseline knobs",
  "name           cn2    esco   surlag",
  "default      75.00    0.95     4.00"
), file.path(dest, "hydrology.hyd"))

# --- A realistic SWAT+-format channel_sd_day.txt at the outlet ----------------
# Format mirrors what parse_swat_streamflow() expects:
#   line 1: title
#   line 2: header (column names)
#   line 3: units
#   line 4+: data  (yr mon day unit flo_out)
gen_flow <- function(year = 2015) {
  dates <- seq(as.Date(sprintf("%d-01-01", year)),
               as.Date(sprintf("%d-12-31", year)), by = "day")
  doy <- as.integer(format(dates, "%j"))
  base <- 60 + 80 * exp(-((doy - 90)^2) / (2 * 55^2)) +
               30 * exp(-((doy - 300)^2) / (2 * 40^2))
  set.seed(42)  # reproducible synthetic series
  noise <- abs(stats::rnorm(length(doy), 0, 8))
  flow <- round(pmax(base + noise, 5), 3)
  list(dates = dates, flow = flow)
}

g <- gen_flow(2015)
hdr <- c("jday", "mon", "day", "yr", "unit", "gis_id", "name", "flo_out")
lines <- c(
  "channel_sd_day.txt: synthetic SWAT+-format output (demo)",
  paste(hdr, collapse = "  "),
  paste(c("---", "---", "---", "---", "---", "---", "---", "m^3/s"), collapse = "  ")
)
for (i in seq_along(g$dates)) {
  d <- g$dates[i]
  lines <- c(lines, sprintf("%d  %d  %d  %d  %d  %d  %s  %.3f",
    as.integer(format(d, "%j")), as.integer(format(d, "%m")),
    as.integer(format(d, "%d")), as.integer(format(d, "%Y")),
    1L, 1L, "outlet_ch", g$flow[i]))
}
writeLines(lines, file.path(dest, "channel_sd_day.txt"))

cat("Wrote synthetic TxtInOut to", dest, "\n")
cat("Files:", paste(list.files(dest), collapse = ", "), "\n")
cat("NOTE: synthetic — exercises file parsing only; not runnable by SWAT+.\n")
