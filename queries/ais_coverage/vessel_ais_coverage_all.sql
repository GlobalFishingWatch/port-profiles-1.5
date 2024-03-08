-- Query to get AIS coverage by vessel for vessels visiting port of interest
-- Example from Dakar
-- 23 Nov 2023
-- MS

WITH vessels AS (
 SELECT
  vessel_id
 FROM
  `world-fishing-827.scratch_hannah.tmt_voyages_sen_all`
),

trawl AS (
  SELECT
    ssvid,
    cov.vessel_id,
    date,
    cov.trip_start,
    cov.trip_end,
    n_voyage_hours,
    n_ais_hours,
    geartype,
    shipname,
    flag,
  FROM `world-fishing-827.scratch_nate.ais_trawl_coverage_2017_2022_daily` cov
  INNER JOIN (SELECT * FROM vessels ) ves ON(
    cov.vessel_id = ves.vessel_id
  )
  WHERE
    trip_start >= TIMESTAMP('2019-01-01')
    AND trip_end <= TIMESTAMP('2022-01-01')
),

carrier AS (
  SELECT
    ssvid,
    cov.vessel_id,
    date,
    cov.trip_start,
    cov.trip_end,
    n_voyage_hours,
    n_ais_hours,
    'carrier' AS geartype,
    shipname,
    flag,
  FROM `world-fishing-827.scratch_nate.ais_carrier_coverage_2017_2022_daily` cov
   INNER JOIN (SELECT * FROM vessels ) ves ON(
    cov.vessel_id = ves.vessel_id
  )
  WHERE
    trip_start >= TIMESTAMP('2019-01-01')
    AND trip_end <= TIMESTAMP('2022-01-01')
),

tuna AS (
  SELECT
    ssvid,
    cov.vessel_id,
    date,
    cov.trip_start,
    cov.trip_end,
    n_voyage_hours,
    n_ais_hours,
    geartype,
    shipname,
    flag,
  FROM `world-fishing-827.scratch_nate.ais_dl_tps_coverage_2017_2022_daily` cov
    INNER JOIN (SELECT * FROM vessels ) ves ON(
    cov.vessel_id = ves.vessel_id
  )
  WHERE
    trip_start >= TIMESTAMP('2019-01-01')
    AND trip_end <= TIMESTAMP('2022-01-01')
),

relevant_vessels_cov AS (
 SELECT * FROM tuna

 UNION ALL

 SELECT * FROM carrier

 UNION ALL

 SELECT * FROM trawl
)

SELECT
  DISTINCT
    *
  FROM relevant_vessels_cov
  WHERE
    flag != 'SEN'
