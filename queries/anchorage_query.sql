
----------------------------------
-- generic anchorage query for pulling anchorage info and visualizing in geoviz for port profiles
----------------------------------

## for bigquery - including joining to TMT corrected anchorages
SELECT
  *
FROM(
  SELECT
    s2id,
    iso3,
    label,
    sublabel,
    lat,
    lon,
    dock,
    distance_from_shore_m
  FROM `world-fishing-827.anchorages.named_anchorages_v20230925`
  WHERE iso3 = 'NGA' )
LEFT JOIN (
  SELECT
    s2id,
    label AS tmt_label,
    sublabel AS tmt_sublabel,
    -- lat,
    -- lon,
    PSMA_Use,
    Use
  FROM `world-fishing-827.scratch_joef.NGA_anchorages_corrected`
)
USING (s2id)
-- WHERE iso3 = 'NGA'

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
