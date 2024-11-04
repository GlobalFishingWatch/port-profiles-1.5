

visits_to_portstate_by_flagstate_bar <- function(df, port_state, country_map,
                                                 vessel_type = "fishing") {
  fishing_by_flag_bar <- df %>%
    filter(vessel_class == {{ vessel_type }} & end_port_iso3 == {{ port_state }}) %>%
    group_by(vessel_flag, year) %>%
    summarize(total = n(), .groups = "drop")

  top_flag_state_v <- fishing_by_flag_bar %>%
    group_by(vessel_flag) %>%
    summarize(grand_total = sum(total, na.rm = TRUE), .groups = "drop") %>%
    arrange(desc(grand_total)) %>%
    slice_head(., n = 8) %>%
    distinct(vessel_flag) %>%
    pull(vessel_flag)

  others <- fishing_by_flag_bar %>%
    distinct(vessel_flag) %>%
    filter(!vessel_flag %in% top_flag_state_v) %>%
    pull(vessel_flag)

  fishing_by_flag_bar <- fishing_by_flag_bar %>%
    mutate(plot_flag = ifelse(vessel_flag %in% top_flag_state_v, vessel_flag, "Others")) %>%
    mutate(plot_flag = factor(plot_flag, levels = c(top_flag_state_v, "Others")))

  if (vessel_type == "fishing") {
    title_suffix <- "Visits by foreign fishing vessel flag"
  } else {
    title_suffix <- "Visits by foreign carrier vessel flag"
  }

  ggplot() +
    geom_col(
      data = fishing_by_flag_bar,
      aes(
        x = year,
        y = total,
        fill = plot_flag,
        color = plot_flag
      )
    ) +
    scale_x_continuous(breaks = c(2012:2022)) +
    scale_fill_manual(
      breaks = c(top_flag_state_v, "Others"),
      values = c(
        gfw_palettes$chart[1],
        gfw_palettes$chart[8],
        gfw_palettes$chart[7],
        gfw_palettes$chart[6],
        gfw_palettes$chart[4],
        gfw_palettes$chart[3],
        gfw_palettes$chart[2],
        gfw_palettes$secondary[3],
        "gray"
      )
    ) +
    scale_color_manual(
      breaks = c(top_flag_state_v, "Others"),
      values = c(
        gfw_palettes$chart[1],
        gfw_palettes$chart[8],
        gfw_palettes$chart[7],
        gfw_palettes$chart[6],
        gfw_palettes$chart[4],
        gfw_palettes$chart[3],
        gfw_palettes$chart[2],
        gfw_palettes$secondary[3],
        "gray"
      )
    ) +
    coord_flip() +
    labs(
      title = glue::glue("{country_map[[port_state]]}:  {title_suffix}"),
      x = "",
      y = "Number of entry events",
      fill = "",
      color = "",
      caption = glue::glue("Others: {paste0(others, collapse = ', ')}")
    ) +
    theme_gfw() +
    theme(
      legend.position = "bottom",
      # legend.direction="horizontal",
      panel.grid.minor.y = element_blank(),
      plot.caption = element_text(size = 6, color = "grey45"),
      legend.key.size = unit(0.4, "cm")
    ) +
    guides(fill = guide_legend(nrow = 2))
}


visits_to_portstate_by_port_bar <- function(df, port_state, top_n = 5,
                                            country_map, vessel_type = "fishing") {
  fishing_by_port_bar <- df %>%
    filter(vessel_class == {{ vessel_type }} & end_port_iso3 == {{ port_state }}) %>%
    group_by(end_port_label, year) %>%
    summarize(total = n(), .groups = "drop")


  top_port_v <- fishing_by_port_bar %>%
    group_by(end_port_label) %>%
    summarize(grand_total = sum(total, na.rm = TRUE), .groups = "drop") %>%
    arrange(desc(grand_total)) %>%
    slice_head(., n = top_n) %>%
    distinct(end_port_label) %>%
    pull(end_port_label)

  fishing_by_port_bar <- fishing_by_port_bar %>%
    mutate(plot_port = ifelse(end_port_label %in% top_port_v, end_port_label, "Others")) %>%
    mutate(plot_port = factor(plot_port, levels = c(top_port_v, "Others")))

  others <- fishing_by_port_bar %>%
    distinct(end_port_label) %>%
    filter(!end_port_label %in% top_port_v) %>%
    pull(end_port_label)

  if (vessel_type == "fishing") {
    title_suffix <- "Foreign fishing vessel visits by port"
  } else {
    title_suffix <- "Foreign carrier vessel visits by port"
  }

  ggplot() +
    geom_col(
      data = fishing_by_port_bar,
      aes(
        x = year,
        y = total,
        fill = plot_port,
        color = plot_port
      )
    ) +
    scale_x_continuous(breaks = c(2012:2022)) +
    scale_fill_manual(
      breaks = c(top_port_v, "Others"),
      values = c(
        gfw_palettes$chart[1],
        gfw_palettes$chart[8],
        gfw_palettes$chart[7],
        gfw_palettes$chart[6],
        gfw_palettes$chart[4],
        gfw_palettes$chart[3],
        gfw_palettes$chart[2],
        gfw_palettes$secondary[3],
        "gray"
      )
    ) +
    scale_color_manual(
      breaks = c(top_port_v, "Others"),
      values = c(
        gfw_palettes$chart[1],
        gfw_palettes$chart[8],
        gfw_palettes$chart[7],
        gfw_palettes$chart[6],
        gfw_palettes$chart[4],
        gfw_palettes$chart[3],
        gfw_palettes$chart[2],
        gfw_palettes$secondary[3],
        "gray"
      )
    ) +
    coord_flip() +
    labs(
      title = glue::glue("{country_map[[port_state]]}:  {title_suffix}"),
      x = "",
      y = "Number of entry events",
      fill = "",
      color = "",
      caption = glue::glue("Others: {paste0(others, collapse = ', ')}")
    ) +
    theme_gfw() +
    theme(
      legend.position = "bottom",
      # legend.direction="horizontal",
      panel.grid.minor.y = element_blank(),
      plot.caption = element_text(size = 6, color = "grey45"),
      legend.key.size = unit(0.4, "cm")
    ) +
    guides(fill = guide_legend(nrow = 2))
}






visits_to_portstate_by_gear_bar <- function(df, port_state, country_map) {
  fishing_by_gear_bar <- df %>%
    filter(vessel_class == "fishing" & end_port_iso3 == {{ port_state }}) %>%
    group_by(vessel_label, year) %>%
    summarize(total = n(), .groups = "drop")


  top_gear_v <- fishing_by_gear_bar %>%
    group_by(vessel_label) %>%
    summarize(grand_total = sum(total, na.rm = TRUE), .groups = "drop") %>%
    arrange(desc(grand_total)) %>%
    slice_head(., n = 9) %>%
    distinct(vessel_label) %>%
    pull(vessel_label)

  others <- fishing_by_gear_bar %>%
    distinct(vessel_label) %>%
    filter(!vessel_label %in% c(
      "squid_jigger", "trawlers", "tuna_purse_seines",
      "drifting_longlines", "other_purse_seines", "fishing",
      "set_longlines", "pole_and_line", "set_gillnets"
    )) %>%
    pull(vessel_label)

  ggplot() +
    geom_col(
      data = fishing_by_gear_bar,
      aes(
        x = year,
        y = total,
        fill = vessel_label
      )
    ) +
    scale_x_continuous(breaks = c(2012:2021)) +
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
    )) +
    labs(
      title = glue::glue("{country_map[[port_state]]}: Visits by foreign fishing vessel by class"),
      x = "",
      y = "Number of entry events",
      fill = "",
      caption = glue::glue("Others: {paste0(others, collapse = ', ')}")
    ) +
    theme_gfw() +
    theme(
      panel.grid.minor.x = element_blank(),
      plot.caption = element_text(size = 6, color = "grey45")
    )
}



visits_to_portstate_by_port_gear_bar <- function(df, port_state, country_map, vessel_type = "fishing") {

  top_ports_v <- df %>%
    filter(vessel_class == {{ vessel_type }} & end_port_iso3 == {{ port_state }}) %>%
    group_by(end_port_label) %>%
    summarise(grand_total = n(), .groups = "drop") %>%
    filter(grand_total > 15) %>%
    pull(end_port_label)

  if (length(top_ports_v) < 1) {
    break
  } else {
    fishing_by_gear_port_bar <- df %>%
      filter(vessel_class == {{ vessel_type }} & end_port_iso3 == {{ port_state }}) %>%
      filter(end_port_label %in% top_ports_v) %>%
      group_by(vessel_label, end_port_label, year) %>%
      summarize(total = n(), .groups = "drop")

    others <- fishing_by_gear_port_bar %>%
      distinct(vessel_label) %>%
      filter(!vessel_label %in% c(
        "squid_jigger", "trawlers", "tuna_purse_seines",
        "drifting_longlines", "other_purse_seines", "fishing",
        "set_longlines", "pole_and_line", "set_gillnets"
      )) %>%
      pull(vessel_label)


    ggplot() +
      geom_col(
        data = fishing_by_gear_port_bar,
        aes(
          x = year,
          y = total,
          fill = vessel_label
        )
      ) +
      scale_x_continuous(breaks = c(2012:2021)) +
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
      )) +
      labs(
        title = glue::glue("{country_map[[port_state]]}: Visits by foreign fishing vessel by class"),
        x = "",
        y = "Number of entry events",
        fill = "",
        caption = glue::glue("Others: {paste0(others, collapse = ', ')}")
      ) +
      theme_gfw() +
      theme(
        panel.grid.minor.x = element_blank(),
        plot.caption = element_text(size = 6, color = "grey45")
      ) +
      facet_wrap(~end_port_label, scales = "free_y", ncol = 2)
  }
}





visits_to_portstate_by_port_flagstate_gear_bar <- function(df, port_state, country_map, vessel_type = "fishing") {



  top_ports_v <- df %>%
    filter(vessel_class == {{vessel_type}} & end_port_iso3 == {{port_state}}) %>%
    group_by(end_port_label) %>%
    summarise(grand_total = n(), .groups = "drop") %>%
    filter(grand_total > 15) %>%
    pull(end_port_label)


  if (length(top_ports_v) < 1) {
    break } else {
      fishing_by_flag_port_bar <- df %>%
        filter(vessel_class == {{vessel_type}} & end_port_iso3 == {{port_state}}) %>%
        filter(end_port_label %in% top_ports_v) %>%
        group_by(vessel_flag, end_port_label, year) %>%
        summarize(total = n(), .groups = "drop")

      top_flag_state_v <- fishing_by_flag_port_bar %>%
        group_by(vessel_flag) %>%
        summarize(grand_total = sum(total, na.rm = TRUE), .groups = "drop") %>%
        arrange(desc(grand_total)) %>%
        slice_head(., n = 8) %>%
        distinct(vessel_flag) %>%
        pull(vessel_flag)

      others <- fishing_by_flag_port_bar %>%
        distinct(vessel_flag) %>%
        filter(!vessel_flag %in% top_flag_state_v) %>%
        pull(vessel_flag)

      fishing_by_flag_port_bar <- fishing_by_flag_port_bar %>%
        mutate(plot_flag = ifelse(vessel_flag %in% top_flag_state_v, vessel_flag, "Others")) %>%
        mutate(plot_flag = factor(plot_flag, levels = c(top_flag_state_v, "Others")))

      ggplot() +
        geom_col(
          data = fishing_by_flag_port_bar,
          aes(
            x = year,
            y = total,
            fill = plot_flag
          )
        ) +
        scale_x_continuous(breaks = c(2012:2022)) +
        scale_fill_manual(
          breaks = c(top_flag_state_v, "Others"),
          values = c(
            gfw_palettes$chart[1],
            gfw_palettes$chart[8],
            gfw_palettes$chart[7],
            gfw_palettes$chart[6],
            gfw_palettes$chart[4],
            gfw_palettes$chart[3],
            gfw_palettes$chart[2],
            gfw_palettes$secondary[3],
            "gray"
          )
        ) +
        scale_color_manual(
          breaks = c(top_flag_state_v, "Others"),
          values = c(
            gfw_palettes$chart[1],
            gfw_palettes$chart[8],
            gfw_palettes$chart[7],
            gfw_palettes$chart[6],
            gfw_palettes$chart[4],
            gfw_palettes$chart[3],
            gfw_palettes$chart[2],
            gfw_palettes$secondary[3],
            "gray"
          )
        ) +
        labs(
          title = glue::glue("{country_map[[port_state]]}: Visits by foreign fishing vessel Flag State"),
          x = "",
          y = "Number of entry events",
          fill = "",
          caption = glue::glue("Others: {paste0(others, collapse = ', ')}")
        ) +
        theme_gfw() +
        theme(
          panel.grid.minor.x = element_blank(),
          plot.caption = element_text(size = 6, color = "grey45")
        ) +
        facet_wrap(~end_port_label, scales = "free_y", ncol = 2)
  }
}
