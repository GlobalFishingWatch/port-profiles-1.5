



visits_to_portstate_by_gear_donut <- function(df, port_state, country_map) {

  fishing_by_gear_donut <- df %>%
    filter(vessel_class == "fishing" & end_port_iso3 == {{ port_state }}) %>%
    group_by(vessel_label) %>%
    summarize(vessels = n(), .groups = "drop")

  if (nrow(fishing_by_gear_donut) < 1) {
    break
  }

  plot_donut_chart(fishing_by_gear_donut,
    group_var = vessel_label,
    value_var = vessels,
    donut_title = glue::glue("{country_map[[port_state]]}:  Fishing vessels \nby vessel class"),
    add_labels = T,
    show_legend = F,
    label_frac = 0.05,
    show_caption = T
  ) +
    scale_fill_manual(values = c(
      "squid_jigger" = gfw_palettes$chart[5],
      "trawlers" = gfw_palettes$chart[1],
      "tuna_purse_seines" = gfw_palettes$chart[2],
      "drifting_longlines" = gfw_palettes$chart[8],
      "other_purse_seines" = gfw_palettes$chart[7],
      "fishing" = gfw_palettes$chart[6],
      "set_longlines" = gfw_palettes$chart[3],
      "pole_and_line" = gfw_palettes$chart[4],
      "set_gillnets" = gfw_palettes$tracks[2],
      "Others" = "gray"
    ))
}
