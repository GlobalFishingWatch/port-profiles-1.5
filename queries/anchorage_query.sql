
----------------------------------
-- generic anchorage query for pulling anchorage info and visualizing in geoviz for port profiles
----------------------------------

## for bigquery
SELECT
  s2id,
  iso3,
  label,
  sublabel,
  lat,
  lon,
  dock,
  distance_from_shore_m
FROM `anchorages.named_anchorages_v20240117`
WHERE iso3 = "MDG"

## for geoviz
SELECT
  ST_GEOGPOINT(lon, lat) aS WKT,
  s2id,
  iso3,
  label,
  sublabel,
  dock,
  distance_from_shore_m
FROM `world-fishing-827.anchorages.named_anchorages_v20230925`
WHERE iso3 = 'MDG'
