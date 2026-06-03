#!/usr/bin/env Rscript
# screenshot-app.R — Launch the Shiny app with shinytest2::AppDriver, run an
# ensemble, and capture screenshots of each tab into docs/screenshots/.
#
# shinytest2 is the supported way to drive + screenshot a live Shiny app (it
# wraps chromote and handles the websocket/event-loop timing that raw chromote
# clicks miss). Reticulate points at the uv venv; NWM data is served cache-first
# (real RODA data), so a run completes in well under a second.

library(shinytest2)

Sys.setenv(RETICULATE_PYTHON = file.path(getwd(), ".venv", "bin", "python"))
Sys.setenv(SWAT_DEMO_BACKEND = Sys.getenv("SWAT_DEMO_BACKEND", "local"))

out_dir <- "docs/screenshots"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

app <- AppDriver$new("app", name = "swat-demo", height = 720, width = 1200,
                     load_timeout = 30000, timeout = 30000)
on.exit(app$stop(), add = TRUE)

# Map tab (default).
app$set_inputs(`.shinytab` = "Map", allow_no_input_binding_ = TRUE, wait_ = FALSE)
Sys.sleep(2)
app$get_screenshot(file.path(out_dir, "01-map.png"))
cat("wrote 01-map.png\n")

# Fire the run; AppDriver waits for the server to go idle (the ensemble + scoring).
app$click("run")
app$wait_for_idle(timeout = 60000)
Sys.sleep(1)

# Hydrographs tab.
app$run_js("document.querySelector('a[data-value=\"Hydrographs\"]').click()")
Sys.sleep(3)
app$get_screenshot(file.path(out_dir, "02-hydrographs.png"))
cat("wrote 02-hydrographs.png\n")

# Skill tab.
app$run_js("document.querySelector('a[data-value=\"Skill vs NWM\"]').click()")
Sys.sleep(2)
app$get_screenshot(file.path(out_dir, "03-skill.png"))
cat("wrote 03-skill.png\n")

cat("done\n")
