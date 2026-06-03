# metrics.R — Standard hydrological goodness-of-fit metrics.
# Used to score each SWAT+ scenario against the NWM reanalysis reference.

#' Nash-Sutcliffe Efficiency. 1 = perfect; 0 = no better than mean of obs; <0 worse.
nse <- function(sim, obs) {
  ok <- is.finite(sim) & is.finite(obs)
  sim <- sim[ok]; obs <- obs[ok]
  if (length(obs) < 2) return(NA_real_)
  1 - sum((sim - obs)^2) / sum((obs - mean(obs))^2)
}

#' Kling-Gupta Efficiency (2009). 1 = perfect. Decomposes into correlation,
#' variability ratio, and bias ratio.
kge <- function(sim, obs) {
  ok <- is.finite(sim) & is.finite(obs)
  sim <- sim[ok]; obs <- obs[ok]
  if (length(obs) < 2 || sd(obs) == 0 || mean(obs) == 0) return(NA_real_)
  r     <- suppressWarnings(stats::cor(sim, obs))
  alpha <- sd(sim) / sd(obs)
  beta  <- mean(sim) / mean(obs)
  if (!is.finite(r)) return(NA_real_)
  1 - sqrt((r - 1)^2 + (alpha - 1)^2 + (beta - 1)^2)
}

#' Percent bias. 0 = unbiased; positive = simulation overestimates.
pbias <- function(sim, obs) {
  ok <- is.finite(sim) & is.finite(obs)
  sim <- sim[ok]; obs <- obs[ok]
  if (length(obs) < 1 || sum(obs) == 0) return(NA_real_)
  100 * sum(sim - obs) / sum(obs)
}

#' Score one simulated series against a reference, joining on date.
#' @param sim_df data.frame(date, flow_cms) — scenario output
#' @param ref_df data.frame(date, flow_cms) — NWM (or observed) reference
#' @return list(nse, kge, pbias, n)
fit_against <- function(sim_df, ref_df) {
  m <- merge(sim_df[c("date", "flow_cms")],
             ref_df[c("date", "flow_cms")],
             by = "date", suffixes = c("_sim", "_ref"))
  list(
    nse   = nse(m$flow_cms_sim, m$flow_cms_ref),
    kge   = kge(m$flow_cms_sim, m$flow_cms_ref),
    pbias = pbias(m$flow_cms_sim, m$flow_cms_ref),
    n     = nrow(m)
  )
}
