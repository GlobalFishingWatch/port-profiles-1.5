--------------------------------------------------------------------------------
-- Query: AIS gap events and associated vessel info
--
-- Date: 08 Sep 2023
--------------------------------------------------------------------------------

CREATE TEMP FUNCTION minimum() AS (TIMESTAMP({start_date}));
CREATE TEMP FUNCTION maximum() AS (TIMESTAMP({end_date}));
CREATE TEMP FUNCTION min_lat() AS ({min_lat});
CREATE TEMP FUNCTION max_lat() AS ({max_lat});
CREATE TEMP FUNCTION min_lon() AS ({min_lon});
CREATE TEMP FUNCTION max_lon() AS ({max_lon});

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
      registry.geartype,
      is_fishing,
      is_carrier,
      is_bunker,
      activity.first_timestamp,
      activity.last_timestamp
    FROM
      `world-fishing-827.vessel_database.all_vessels_v20230701`
    LEFT JOIN UNNEST(activity) as activity
    LEFT JOIN UNNEST(registry) as registry
    WHERE
       activity.first_timestamp <= maximum()
      AND activity.last_timestamp >= minimum()
      AND is_fishing
      ),


  ------------------------------------------------------------------------
  -- Select gaps in AOI
  ------------------------------------------------------------------------
  gaps AS (
  SELECT
      *,
      EXTRACT(year from gap_start) as year,
      off_eez,
      on_eez
  FROM
    `world-fishing-827.pipe_production_v20201001.proto_ais_gap_events`
    LEFT JOIN UNNEST(gap_start_eez) AS off_eez
    LEFT JOIN UNNEST(gap_end_eez) AS on_eez
  WHERE
  -- limit to gap events longer than 12 hours as satellite reception can vary considerably over shorter timeframes
      gap_hours >= 12
  -- spatial filter for distance to shore - set to 10 nm to exclude gaps near port
      -- AND (gap_start_distance_from_shore_m > 1852*10 AND gap_end_distance_from_shore_m > 1852*10)
  -- restrict to vessels with 5 or more positions per day to exclude poor transmission
   -- AND (positions_per_day_off > 5 AND positions_per_day_on > 5)

  -- restrict to gaps that started and ended in period of interest
  AND gap_start BETWEEN minimum() AND maximum()
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
  gap_id,
  ssvid,
  geartype,
  flag,
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
  gaps_vessel_info

