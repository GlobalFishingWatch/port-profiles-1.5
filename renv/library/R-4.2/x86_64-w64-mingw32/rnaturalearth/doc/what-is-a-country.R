## ---- include = FALSE---------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ---- eval=TRUE, echo=TRUE, message=FALSE-------------------------------------
library(rnaturalearth)
library(sp)

## ---- eval=TRUE, echo=TRUE, message=FALSE-------------------------------------
# countries, UK undivided
sp::plot(ne_countries(country = "united kingdom", type = "countries"))
# map_units, UK divided into England, Scotland, Wales and Northern Ireland
sp::plot(ne_countries(country = "united kingdom", type = "map_units"))
# map_units, select by geounit to plot Scotland alone
sp::plot(ne_countries(geounit = "scotland", type = "map_units"))
# sovereignty, Falkland Islands included in UK
sp::plot(ne_countries(country = "united kingdom", type = "sovereignty"), col = "red")
sp::plot(ne_coastline(scale = 110), col = "lightgrey", lty = 3, add = TRUE)

# France, country includes French Guiana
sp::plot(ne_countries(country = "france"))
# France map_units includes French Guiana too
sp::plot(ne_countries(country = "france", type = "map_units"))
# France filter map_units by geounit to exclude French Guiana
sp::plot(ne_countries(geounit = "france", type = "map_units"))
# France sovereignty includes South Pacicic islands
sp::plot(ne_countries(country = "france", type = "sovereignty"), col = "red")
sp::plot(ne_coastline(scale = 110), col = "lightgrey", lty = 3, add = TRUE)

## ---- eval=FALSE, echo=TRUE, message=FALSE------------------------------------
#  # countries, large scale
#  sp::plot(ne_countries(country = "united kingdom", scale = "large"))
#  
#  # countries, medium scale
#  sp::plot(ne_countries(country = "united kingdom", scale = "medium"))
#  
#  # countries, small scale
#  sp::plot(ne_countries(country = "united kingdom", scale = "small"))

## ---- eval=FALSE, echo=TRUE, message=FALSE------------------------------------
#  # states country='united kingdom'
#  sp::plot(ne_states(country = "united kingdom"))
#  # states geounit='england'
#  sp::plot(ne_states(geounit = "england"))
#  
#  # states country='france'
#  sp::plot(ne_states(country = "france"))
#  # states geounit='france'
#  sp::plot(ne_states(geounit = "france"))

