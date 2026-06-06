# app.R — Visual Shiny front-end for the SWAT+ ensemble demo.
#
# Layout:
#   - Sidebar: simulation period, backend (real SWAT+ / mock / AWS), scenario picker.
#   - Map tab:   Leaflet map of the Tiffin River @ Stryker gauge (model outlet).
#   - Hydrograph tab: each BMP scenario vs real USGS observed flow.
#   - Skill tab: scenario goodness-of-fit (NSE / KGE / PBIAS) vs USGS observed.
#
# Backend is chosen by SWAT_DEMO_BACKEND env var or the sidebar (default: real).

suppressWarnings(suppressMessages({
  library(shiny)
  library(plotly)
  library(leaflet)
  library(DT)
}))

# Source the project R/ (app runs from project root or app/).
.src <- function(f) {
  for (p in c(file.path("R", f), file.path("..", "R", f))) if (file.exists(p)) { source(p); return(invisible()) }
  stop("cannot find R/", f)
}
invisible(lapply(c("metrics.R", "nwm_roda.R", "swat_io.R", "mock_swat.R",
                   "run_model.R", "ensemble.R"), .src))

scenarios_path <- if (file.exists("data-raw/scenarios.csv")) "data-raw/scenarios.csv" else "../data-raw/scenarios.csv"
default_scenarios <- utils::read.csv(scenarios_path, stringsAsFactors = FALSE)
default_backend <- Sys.getenv("SWAT_DEMO_BACKEND", "real")

ui <- fluidPage(
  titlePanel("SWAT+ BMP Ensemble — Tiffin River (Maumee tributary)"),
  tags$p(style = "color:#555;margin-top:-8px;",
    "Real SWAT+ BMP scenario ensemble (the staRburst cloud-burst workload), ",
    "validated against ", tags$b("real USGS gauge observations"), ". Model is a ",
    "real Tiffin River SWAT+ build (uncalibrated)."),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      selectInput("backend", "Compute backend",
                  choices = c("Real SWAT+ ensemble" = "real",
                              "Local (mock SWAT)" = "local",
                              "AWS workers" = "aws"),
                  selected = default_backend),
      dateRangeInput("period", "Simulation period",
                     start = "2016-01-01", end = "2018-12-31",
                     min = "2016-01-01", max = "2018-12-31"),
      checkboxGroupInput("scen", "BMP scenarios",
                         choices  = stats::setNames(default_scenarios$scenario_id,
                                                    default_scenarios$label),
                         selected = default_scenarios$scenario_id),
      actionButton("run", "Run ensemble", class = "btn-primary", width = "100%"),
      tags$hr(),
      uiOutput("status")
    ),
    mainPanel(
      width = 9,
      tabsetPanel(
        tabPanel("Map", leafletOutput("map", height = 480)),
        tabPanel("Hydrographs", plotlyOutput("hydro", height = 520)),
        tabPanel("Skill vs observed", DTOutput("skill"),
                 tags$p(style="color:#777",
                   "KGE/NSE: 1 = perfect. PBIAS: 0 = unbiased. Reference = USGS observed flow."))
      )
    )
  )
)

server <- function(input, output, session) {
  rv <- reactiveValues(result = NULL, running = FALSE, msg = "Idle. Pick scenarios and Run.")

  output$status <- renderUI({
    col <- if (rv$running) "#b8860b" else "#2e7d32"
    tagList(tags$small(style = sprintf("color:%s;", col), rv$msg),
            if (!is.null(rv$result))
              tags$small(tags$br(), sprintf("Reference: %s",
                         rv$result$meta$ref_source %||% "n/a")))
  })

  # Base map shows the study reach: Tiffin River at Stryker, OH (the model gauge).
  output$map <- renderLeaflet({
    leaflet() |> addProviderTiles("CartoDB.Positron") |>
      setView(lng = -84.43, lat = 41.55, zoom = 9) |>     # Tiffin basin, NW Ohio
      addMarkers(lng = -84.4297, lat = 41.5045,
                 popup = "USGS 04185000 — Tiffin River at Stryker, OH (model outlet)") |>
      addPopups(lng = -84.40, lat = 41.75,
                popup = "Tiffin River basin (~1062 km²) → Maumee → Western Lake Erie")
  })

  observeEvent(input$run, {
    req(length(input$scen) > 0)
    rv$running <- TRUE
    rv$msg <- sprintf("Running %d BMP scenarios on '%s' backend… fetching USGS observed…",
                      length(input$scen), input$backend)

    sel <- default_scenarios[default_scenarios$scenario_id %in% input$scen, , drop = FALSE]
    res <- tryCatch(
      run_ensemble(sel, backend = input$backend,
                   start = as.character(input$period[1]),
                   end   = as.character(input$period[2]),
                   gauge = "04185000", ref_source = "usgs"),
      error = function(e) { rv$msg <- paste("Error:", conditionMessage(e)); NULL }
    )
    rv$running <- FALSE
    if (!is.null(res)) {
      rv$result <- res
      note <- if (any(res$fit$mock)) " (SWAT mocked)" else " (real SWAT+, uncalibrated)"
      rv$msg <- sprintf("Done: %d scenarios, %d days vs USGS%s.",
                        nrow(res$fit), max(res$fit$n), note)
    }
  })

  output$hydro <- renderPlotly({
    res <- rv$result; req(res)
    p <- plot_ly()
    # Scenario hydrographs.
    for (sid in unique(res$series$scenario_id)) {
      s <- res$series[res$series$scenario_id == sid, ]
      p <- add_lines(p, x = s$date, y = s$flow_cms, name = s$label[1],
                     line = list(width = 1.3))
    }
    # Real reference (bold black) — USGS observed (or NWM if selected).
    rf <- res$reference$flow
    p <- add_lines(p, x = rf$date, y = rf$flow_cms,
                   name = res$meta$ref_source %||% "reference",
                   line = list(width = 3, color = "black"))
    # USGS observed as a separate grey line only when the bold reference is NOT
    # already USGS (i.e. when reference = NWM). Avoids drawing observed twice.
    ref_is_usgs <- grepl("USGS", res$meta$ref_source %||% "")
    if (!is.null(res$observed) && !ref_is_usgs) {
      ob <- res$observed
      p <- add_lines(p, x = ob$date, y = ob$flow_cms, name = "USGS observed",
                     line = list(width = 2, color = "grey", dash = "dash"))
    }
    layout(p, title = "Daily streamflow at Tiffin River @ Stryker, OH",
           xaxis = list(title = ""),
           yaxis = list(title = "Flow (m³/s)"),
           legend = list(orientation = "h"))
  })

  output$skill <- renderDT({
    res <- rv$result; req(res)
    df <- res$fit
    df$nse <- round(df$nse, 3); df$kge <- round(df$kge, 3); df$pbias <- round(df$pbias, 1)
    datatable(df[, c("label", "kge", "nse", "pbias", "n", "mock")],
              rownames = FALSE, options = list(dom = "t", pageLength = 25)) |>
      formatStyle("kge", background = styleColorBar(c(0, 1), "#cfe8cf"))
  })
}

shinyApp(ui, server)
