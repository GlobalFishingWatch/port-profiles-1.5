--------------------------------------
-- Query to find fishing events from voyages of interest
--
-- MS 02 May 2024
--
-- this requires an input table of big_query voyages of interest
-- should look at taking this from a R pulling into BQ
---------------------------------------

WITH trips AS (
  SELECT
    *
  FROM {voyages_table}
),

fishing AS(
  SELECT
    vessel_id,
    ssvid,
    vessel_class_best,
    event_start,
    event_end,
    lat_mean,
    lon_mean,
    SUM(TIMESTAMP_DIFF(event_end, event_start, SECOND) / 3600) AS fishing_hours,
  FROM (
    SELECT
      vessel_id,
      event_start,
      event_end,
      high_sea,
      rfmo,
      eez,
      ISO_TER1,
      lat_mean,
      lon_mean,
  FROM `world-fishing-827.pipe_ais_v3_published.fishing_events`
    LEFT JOIN UNNEST (regions_mean_position.high_seas) AS high_sea
    LEFT JOIN UNNEST (regions_mean_position.rfmo) AS rfmo
    LEFT JOIN UNNEST (regions_mean_position.eez) AS eez
    LEFT JOIN (SELECT MRGID, ISO_TER1 FROM `world-fishing-827.ocean_shapefiles_all_purpose.marine_regions_v11`) ON (eez=CAST(MRGID AS string))) a
  INNER JOIN (
    SELECT
      vessel_id,
      trip_id,
      trip_start,
      trip_end,
      vessel_class_best,
      ssvid
    FROM
      trips)
  USING
    (vessel_id)
  WHERE
    event_start BETWEEN trip_start AND trip_end
  GROUP BY
    vessel_id, trip_id, vessel_class_best, ssvid, lat_mean, lon_mean, event_start,
    event_end
    )

  SELECT * FROM fishing
