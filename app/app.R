# app.R — Visual Shiny front-end for the SWAT+ ensemble demo.
#
# Layout:
#   - Sidebar: simulation period, backend (local mock / AWS), scenario picker, Run.
#   - Map tab:   Leaflet map of the Maumee @ Waterville gauge + reach.
#   - Hydrograph tab: interactive overlay of each scenario vs the real NWM reanalysis
#                     (and USGS observed) pulled from the AWS Registry of Open Data.
#   - Skill tab: scenario goodness-of-fit (NSE / KGE / PBIAS) vs NWM, ranked.
#
# Backend is chosen by SWAT_DEMO_BACKEND env var or the sidebar (default: local).

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
default_backend <- Sys.getenv("SWAT_DEMO_BACKEND", "local")

ui <- fluidPage(
  titlePanel("SWAT+ BMP Ensemble — Maumee River → Western Lake Erie"),
  tags$p(style = "color:#555;margin-top:-8px;",
    "Cloud-bursted SWAT+ scenario ensemble (via staRburst), validated against the ",
    tags$b("NOAA National Water Model retrospective"),
    " from the AWS Registry of Open Data."),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      selectInput("backend", "Compute backend",
                  choices = c("Local (mock SWAT)" = "local", "AWS workers" = "aws"),
                  selected = default_backend),
      dateRangeInput("period", "Simulation period",
                     start = "2015-01-01", end = "2015-12-31",
                     min = "1979-02-01", max = "2023-01-31"),
      checkboxGroupInput("scen", "Scenarios",
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
        tabPanel("Skill vs NWM", DTOutput("skill"),
                 tags$p(style="color:#777",
                   "KGE/NSE: 1 = perfect. PBIAS: 0 = unbiased. Reference = NWM retrospective (RODA)."))
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

  # Base map always shows the study location (gauge resolved live by run).
  output$map <- renderLeaflet({
    leaflet() |> addProviderTiles("CartoDB.Positron") |>
      setView(lng = -83.71, lat = 41.50, zoom = 8) |>     # Waterville, OH area
      addMarkers(lng = -83.7130, lat = 41.5006,
                 popup = "USGS 04193500 — Maumee River at Waterville, OH") |>
      addPopups(lng = -83.71, lat = 41.70,
                popup = "Maumee basin → Western Lake Erie (P loading / HABs)")
  })

  observeEvent(input$run, {
    req(length(input$scen) > 0)
    rv$running <- TRUE
    rv$msg <- sprintf("Running %d scenarios on '%s' backend… pulling NWM reference from RODA…",
                      length(input$scen), input$backend)

    sel <- default_scenarios[default_scenarios$scenario_id %in% input$scen, , drop = FALSE]
    res <- tryCatch(
      run_ensemble(sel, backend = input$backend,
                   start = as.character(input$period[1]),
                   end   = as.character(input$period[2])),
      error = function(e) { rv$msg <- paste("Error:", conditionMessage(e)); NULL }
    )
    rv$running <- FALSE
    if (!is.null(res)) {
      rv$result <- res
      mock_note <- if (any(res$fit$mock)) " (SWAT mocked; NWM data real)" else ""
      rv$msg <- sprintf("Done: %d scenarios, %d days vs NWM%s.",
                        nrow(res$fit), max(res$fit$n), mock_note)
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
    # Real NWM reference (bold black).
    rf <- res$reference$flow
    p <- add_lines(p, x = rf$date, y = rf$flow_cms, name = "NWM retrospective (RODA)",
                   line = list(width = 3, color = "black"))
    # USGS observed, if available (grey dashed).
    if (!is.null(res$observed)) {
      ob <- res$observed
      p <- add_lines(p, x = ob$date, y = ob$flow_cms, name = "USGS observed",
                     line = list(width = 2, color = "grey", dash = "dash"))
    }
    layout(p, title = "Daily streamflow at Maumee @ Waterville",
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
