-- NGA anchorages correction
-- the anchorages dataset shared with TMT was missing a few relevant anchorages in the
-- port harcourt or "rivers complex" area. Here I take all Lagos anchorages and any in that
-- rivers complex from GFW data and join on the available TMT notes. The anchorages missed by GFW
-- for ONNE and OKRIKA are joined by label name, as we TMT didnt have s2ids to match to.

-- NGA_anchorages_corrected -- this must be saved in scratch from anchorages with TMT notes, joined to GFW anchorages filtered to Lagos and Rivers Complex

CREATE TABLE `world-fishing-827.scratch_joef.NGA_anchorages_corrected_matched` AS

WITH

## select anchorages for LAGOS and some of river complex (not onne and okrika)
first_match AS (
SELECT
  *
FROM(
  SELECT
    s2id,
    iso3,
    CASE WHEN label IN ("BONNY", "PORT HARCOURT", "NGA-82", "NGA-75") THEN "RIVERS COMPLEX" ELSE label END AS label,
    sublabel,
    lat,
    lon,
    dock,
    distance_from_shore_m
  FROM `world-fishing-827.anchorages.named_anchorages_v20240117`
  WHERE iso3 = 'NGA' AND label IN ("BONNY", "LAGOS", "PORT HARCOURT", "NGA-82", "NGA-75") )
LEFT JOIN (
  SELECT
    s2id,
    label AS tmt_label,
    tmt_sublabel,
    psma_use,
    tmt_notes
  FROM `world-fishing-827.scratch_joef.NGA_anchorages_corrected`
)
USING (s2id)
),

# select onne and okrika separately and match based on labels
second_match AS (
  SELECT
    *
  FROM(
    SELECT
      s2id,
      iso3,
      CASE WHEN label IN ("OKRIKA", "ONNE") THEN "RIVERS COMPLEX" ELSE label END AS label,
      sublabel,
      lat,
      lon,
      dock,
      distance_from_shore_m
    FROM `world-fishing-827.anchorages.named_anchorages_v20240117`
    WHERE iso3 = 'NGA' AND label IN ("OKRIKA", "ONNE") )
  LEFT JOIN (
    SELECT
      -- s2id,
      DISTINCT
      label AS tmt_label,
      tmt_sublabel,
      psma_use,
      tmt_notes
    FROM `world-fishing-827.scratch_joef.NGA_anchorages_corrected` )
  ON sublabel = tmt_sublabel )

# then join s2id version with onne and okrika
  SELECT
    *
  FROM
    first_match
  UNION ALL
  SELECT
    *
  FROM
    second_match
