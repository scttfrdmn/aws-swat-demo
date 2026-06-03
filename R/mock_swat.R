# mock_swat.R — Local stand-in for the SWAT+ binary.
#
# Lets you develop and demo the ENSEMBLE + UI + real-NWM-comparison logic with
# zero AWS/SWAT setup. It produces a plausible, parameter-responsive synthetic
# hydrograph so scenarios visibly differ and goodness-of-fit numbers move — but
# every result is clearly labelled mock = TRUE. This is NOT a hydrological model;
# it is a deterministic surrogate for wiring up the pipeline.

#' Generate a synthetic daily hydrograph that responds to scenario knobs.
#'
#' Shape: seasonal baseflow + storm pulses, modulated by the scenario's
#' parameters so the ensemble shows spread:
#'   cn2_pct  (curve number)   -> higher CN => flashier, higher peaks
#'   esco     (evap comp)      -> higher => less ET loss => higher flow
#'   surlag   (surface lag)    -> higher => more attenuated peaks
#'
#' @param scenario named list/vector with optional cn2_pct, esco, surlag.
#' @param start,end ISO dates.
#' @return data.frame(date, flow_cms, mock)
mock_swat_run <- function(scenario, start = "2015-01-01", end = "2015-12-31") {
  dates <- seq(as.Date(start), as.Date(end), by = "day")
  n <- length(dates)
  doy <- as.integer(format(dates, "%j"))

  knob <- function(name, default) {
    v <- suppressWarnings(as.numeric(scenario[[name]]))
    if (length(v) == 0 || is.na(v)) default else v
  }
  cn2_pct <- knob("cn2_pct", 0)
  esco    <- knob("esco", 0.95)
  surlag  <- knob("surlag", 4)

  # Seasonal baseflow: higher in spring (snowmelt/rain), low late summer.
  # Magnitudes are roughly scaled to the Maumee @ Waterville so the *baseline*
  # scenario sits in a believable range (~200 m^3/s mean) for the demo; this is
  # a surrogate, NOT a calibrated model (every result is labelled mock = TRUE).
  base <- 70 + 90 * exp(-((doy - 90)^2) / (2 * 60^2)) +
               35 * exp(-((doy - 300)^2) / (2 * 40^2))

  # Deterministic "storms": fixed pulse days so runs are reproducible.
  storm_days <- c(35, 78, 95, 140, 175, 210, 260, 305, 330)
  pulse <- numeric(n)
  for (sd_i in storm_days) {
    if (sd_i <= n) {
      decay <- exp(-(pmax(0, seq_len(n) - sd_i)) / max(1, surlag))
      pulse <- pulse + 130 * decay
    }
  }

  cn_factor   <- 1 + cn2_pct / 100          # CN up => more runoff
  esco_factor <- 0.85 + 0.16 * (esco - 0.8) / 0.2  # esco up => less ET => more flow (~1.0 at baseline)
  # Single calibration factor so the baseline scenario's mean (~204 m^3/s)
  # matches the real NWM mean for this reach — keeps the demo visually honest.
  MOCK_CAL <- 0.298
  flow <- (base + pulse * cn_factor) * esco_factor * MOCK_CAL
  flow <- pmax(flow, 1)

  data.frame(date = dates, flow_cms = flow, mock = TRUE,
             stringsAsFactors = FALSE)
}
