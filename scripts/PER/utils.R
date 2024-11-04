
merge_2_plots <- function(plot1, plot2) {
  plot1 +
    plot2 +
    patchwork::plot_layout(
      guides = "collect",
      ncol = 2
    ) &
    theme_gfw() +
      theme(legend.position = "bottom")
}
