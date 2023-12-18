--------------------------------------------------------------------------------
-- Query: AIS gap events and associated vessel info
--
-- Date: 08 Sep 2023
--------------------------------------------------------------------------------

CREATE TEMP FUNCTION minimum() AS (DATE("2023-01-01"));
CREATE TEMP FUNCTION maximum() AS (DATE("2023-01-07"));
CREATE TEMP FUNCTION min_lat() AS (-6);
CREATE TEMP FUNCTION max_lat() AS (22);
CREATE TEMP FUNCTION min_lon() AS (-30);
CREATE TEMP FUNCTION max_lon() AS (20);

WITH

  ----------------------------------------------------------
  -- Define lists of high/med/low confidence fishing vessels
  ----------------------------------------------------------

  vessel_database AS(
    SELECT
      identity.ssvid,
      identity.flag,
      identity.imo,
      identity.n_callsign,
      identity.n_shipname,
      is_fishing,
      is_carrier,
      is_bunker,
      activity.first_timestamp,
      activity.last_timestamp
    FROM
      `world-fishing-827.vessel_database.all_vessels_v20230701`
    LEFT JOIN UNNEST(activity) as activity
    WHERE
       activity.first_timestamp <= TIMESTAMP(maximum())
      AND activity.last_timestamp >= TIMESTAMP(minimum())
      ),


  ------------------------------------------------------------------------
  -- Select gaps in AOI
  ------------------------------------------------------------------------
  gaps AS (
  SELECT
      *,
      EXTRACT(year from gap_start) as year,
  FROM
    `world-fishing-827.pipe_production_v20201001.proto_ais_gap_events`
  WHERE
  -- limit to gap events longer than 12 hours as satellite reception can vary considerably over shorter timeframes
      gap_hours >= 12
  -- spatial filter for distance to shore - set to 10 nm to exclude gaps near port
      -- AND (gap_start_distance_from_shore_m > 1852*10 AND gap_end_distance_from_shore_m > 1852*10)
  -- restrict to vessels with 5 or more positions per day to exclude poor transmission
   -- AND (positions_per_day_off > 5 AND positions_per_day_on > 5)

  -- restrict to gaps that started and ended in period of interest
  AND DATE(gap_start) BETWEEN minimum() AND maximum()
  AND gap_start_lat BETWEEN min_lat() AND max_lat()
  AND gap_start_lon BETWEEN min_lon() AND max_lon()

  -- restrict to gap events where the vessel had transmitted on AIS at least 19 times in the 12 hours before the gap
  -- event occurred. This was identified as threshold for potential AIS disabling
      AND positions_12_hours_before_sat >= 19

  ),

  ------------------------------------------------------------------------
  -- Append vessel info to gaps
  ------------------------------------------------------------------------
  gaps_vessel_info AS (
      SELECT
       *
      FROM
        gaps
      JOIN vessel_database USING(ssvid)
  )

------------------------------------------------------------------------
-- Return gaps
------------------------------------------------------------------------
SELECT
  DISTINCT(gap_id) AS uniq,
  ssvid,
  -- n_shipname AS vessel_name,
  -- is_fishing,
  -- is_carrier,
  -- is_bunker,
  -- imo,
  -- n_callsign AS ircs,
  -- flag,
  gap_start AS gap_start_timestamp,
  gap_end AS gap_end_timestamp,
  gap_hours,
  gap_distance_m,
  gap_start_distance_from_shore_m,
  gap_implied_speed_knots,
  gap_start_lat,
  gap_start_lon,
  gap_end_lat,
  gap_end_lon,
  gap_start_receiver_type,
  gap_end_receiver_type,
  is_closed,
FROM
  gaps

