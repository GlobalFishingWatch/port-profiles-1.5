## ---- include = FALSE---------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ---- eval=TRUE, echo=TRUE, message=FALSE-------------------------------------
library(rnaturalearth)
library(sp)

## ---- eval=TRUE, echo=TRUE, message=FALSE-------------------------------------
# world at small scale (low resolution)
sp::plot(ne_countries(type = "countries", scale = "small"))

# countries, UK undivided
sp::plot(ne_countries(country = "united kingdom", type = "countries"))
# map_units, UK divided into England, Scotland, Wales and Northern Ireland
sp::plot(ne_countries(country = "united kingdom", type = "map_units"))

# countries, small scale
sp::plot(ne_countries(country = "united kingdom", scale = "small"))

# countries, medium scale
sp::plot(ne_countries(country = "united kingdom", scale = "medium"))

## ---- eval=FALSE, echo=TRUE, message=FALSE------------------------------------
#  # not evaluated because rely on rnaturalearthhires data which are on rOpenSci so CRAN check likely to fail
#  
#  # countries, large scale
#  sp::plot(ne_countries(country = "united kingdom", scale = "large"))
#  
#  # states country='united kingdom'
#  sp::plot(ne_states(country = "united kingdom"))
#  # states geounit='england'
#  sp::plot(ne_states(geounit = "england"))
#  
#  # states country='france'
#  sp::plot(ne_states(country = "france"))

## ---- eval=TRUE, echo=TRUE, message=FALSE-------------------------------------
# coastline of the world
# subsetting of coastline is not possible because the Natural Earth data are not attributed in that way
sp::plot(ne_coastline())

## ---- eval=FALSE, echo=TRUE, message=FALSE------------------------------------
#  # lakes
#  lakes110 <- ne_download(scale = 110, type = "lakes", category = "physical")
#  sp::plot(lakes110, col = "blue")
#  
#  # rivers
#  rivers110 <- ne_download(scale = 110, type = "rivers_lake_centerlines", category = "physical")
#  sp::plot(rivers110, col = "blue")

## ----echo = FALSE, results = 'asis'-------------------------------------------
knitr::kable(df_layers_physical, caption = "category='physical' vector data available via ne_download()")

## ----echo = FALSE, results = 'asis'-------------------------------------------
knitr::kable(df_layers_cultural, caption = "category='cultural' vector data available via ne_download()")

