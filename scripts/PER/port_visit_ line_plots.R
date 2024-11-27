
# function to plot lines
visits_by_portstate_line <- function(df, iso3, max_limit, country_map) {
  fishing_vessels_events <-
    df %>%
    filter(end_port_iso3 == {{ iso3 }}) %>%
    group_by(vessel_class, year) %>%
    summarize(Total = n())

  ggplot(
    data = fishing_vessels_events,
    aes(x = year, y = Total, colour = vessel_class)
  ) +
    geom_line(size = 0.8) +
    scale_color_manual(values = gfw_palette("primary")) +
    labs(title = country_map[[iso3]],
         x = "",
         y = "Number of entry events",
         colour = "Vessel_class") +
    geom_text(aes(label = Total),
      vjust = -1, hjust = 0.5,
      show.legend = FALSE, size = 3
    ) +
    scale_x_discrete(limits = c(2012:2022)) +
    ylim(0, max_limit) +
    theme_gfw() +
    theme(
      legend.position = c(0.85, 1),
      legend.direction = "horizontal"
    )
}


port_entries_by_port_state_line <- function(df, vessel_type = "fishing") {
  df <- df %>%
    filter(vessel_class == {{ vessel_type }}) %>%
    group_by(end_port_iso3, year) %>%
    summarize(Total = n())


  ggplot() +
    geom_line(
      data = df,
      aes(
        x = year,
        y = Total,
        colour = end_port_iso3
      ),
      size = 0.6
    ) +
    scale_color_manual(values = c(gfw_palette("tracks"), gfw_palette("secondary"))) +
    labs(
      title = glue::glue("{stringr::str_to_sentence(vessel_type)} Vessels: Number of entry events"),
      x = "",
      y = "Number of entry events",
      colour = "Port State"
    ) +
    scale_x_discrete(limits = c(2012:2021)) +
    # ylim(0, 600)+
    theme_gfw() +
    theme(
      legend.position = "bottom",
      legend.direction = "horizontal"
    )
}


unique_vessel_visits_by_port_state_line <- function(df, vessel_type = "fishing") {
  df <- df %>%
    filter(vessel_class == {{ vessel_type }}) %>%
    group_by(end_port_iso3, year) %>%
    summarize(Total = n_distinct(ssvid))

  ggplot() +
    geom_line(
      data = df,
      aes(
        x = year,
        y = Total,
        colour = end_port_iso3
      ),
      size = 0.6
    ) +
    scale_color_manual(values = c(gfw_palette("tracks"), gfw_palette("secondary"))) +
    labs(
      title = glue::glue("{stringr::str_to_sentence(vessel_type)} Vessels: Number of unique vessels"),
      x = "",
      y = "Number of vessel",
      colour = "Port State"
    ) +
    scale_x_discrete(limits = c(2012:2021)) +
    # ylim(0, 600)+
    theme_gfw() +
    theme(
      legend.position = "bottom",
      legend.direction = "horizontal"
    )
}
