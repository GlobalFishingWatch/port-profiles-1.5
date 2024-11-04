




regional_port_map <- function(df, breaks_c, xlim, ylim, vessel_type = "fishing") {
  visits <- df %>%
    filter(vessel_class == {{ vessel_type }}) %>%
    group_by(end_port_label, end_port_iso3) %>%
    summarize(
      lat = mean(start_latitude),
      long = mean(start_longitude),
      total = n()
    )

  bbox <- fishwatchr::transform_box(xlim = xlim,
                                    ylim = ylim,
                                    output_crs = "+proj=eqearth +lon_0=0 +wktext")


  if (vessel_type == "fishing") {
    title_prefix <- "Fishing"
    subtitle_prefix <- "fishing"
  } else {
    title_prefix <- "Carrier"
    subtitle_prefix <- "carrier"
  }

  # cutoffs based on the number of cases


  visits_sf <- visits %>%
    sf::st_as_sf(., coords = c("long", "lat"), crs = 4326) %>%
    fishwatchr::recenter_sf(center = 0)


  gg <-
    ggplot() +
    geom_gfw_land() +
    geom_sf(
      data = visits_sf,
      aes(
        size = `total`,
        color = `total`
      ),
      stroke = FALSE,
      alpha = 0.7
    ) +
    scale_size_continuous(
      name = "Port events",
      range = c(1, 8),
      breaks = breaks_c,
      labels = c("1-9", "10-99", "100-999", "1000-1999", "2000+")
    ) +
    scale_color_viridis_c(
      option = "inferno",
      name = "Port events",
      trans = "log",
      breaks = breaks_c,
      labels = c("1-9", "10-99", "100-999", "1000-1999", "2000+")
    ) +
    coord_sf(
      xlim = c(
        bbox$box_out[["xmin"]],
        bbox$box_out[["xmax"]]
      ),
      ylim = c(
        bbox$box_out[["ymin"]],
        bbox$box_out[["ymax"]]
      )
    ) +
    theme_gfw_map() +
    guides(colour = guide_legend()) +
    labs(
      title = glue::glue("{title_prefix} Port entry events between 2012-2021"),
      subtitle = glue::glue("The bubble colors represent the sum of all port entry events for {subtitle_prefix} vessels")
    ) +
    theme(
      plot.title = element_text(color = "#363C4C", size = 9, face = "bold"),
      plot.subtitle = element_text(color = "#848B9B", size = 6),
      legend.title = element_text(color = "#848B9B")
    ) +
    theme(
      legend.position = c(.15, .28)
    )

  add_logo(gg,
    style = "color",
    logo_rel_size = 0.25,
    xloc = 0.28,
    yloc = 0.2
  )
}
