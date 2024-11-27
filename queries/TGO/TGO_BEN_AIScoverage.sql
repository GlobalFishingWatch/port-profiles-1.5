------------------------------------------------------------
/* AIS coverage for Vessel Voyages in port profile
Description:
- Calculates the AIS coverage per voyage per vessel_id
- Option to aggregate by year per vessel_id is commented out at the end
- voyages are truncated to the start_timestamp and/or end_timestamp if it starts and/or ends beyond these timestamps
*/
--
/* CAVEATS
- n_ais_hours and voyage_duration_hrs are calculated by counting the hour bins
- there could be a few hours difference compared with actual voyage duration calculated by subtracting start and end trip times
- for example, a trip_start of 06:34:08 UTC and a trip_end of 07:10:17 UTC would be counted as 2 voyage_duration hours since there are two hour-bins here (i.e., 06:00:00 and 07:00:00) although the actual difference between the start and end time is only 36 minutes.
*/
------------------------------------------------------------

------------------------------------------------------------
-- set parameters
------------------------------------------------------------

# voyages will be truncated to this start timestamp, if needed
CREATE TEMP FUNCTION start_timestamp() AS (TIMESTAMP('2021-01-01 00:00:00 UTC'));
--
# voyages will be truncated to this end timestamp, if needed
CREATE TEMP FUNCTION end_timestamp() AS (TIMESTAMP('2023-12-31 23:59:59 UTC'));
--
------------------------------------------------------------

CREATE TABLE `world-fishing-827.PortsProgramme.TGO_BEN_aiscoverage_2021-23_pipe3` AS

WITH

############################################################
##### PART 1: Get voyages
############################################################
--
------------------------------------------------------------
-- Raw data from the voyage table, doing TGO and BEN together to save costs on messages table
------------------------------------------------------------
  TGO_trip_ids AS (
    SELECT
      trip_id,
      vessel_id,
      CAST(ssvid AS STRING) AS ssvid,
      trip_start,
      trip_end,
      end_port_iso3
    FROM `world-fishing-827.PortsProgramme.TGO_voyages_2021-23`
    WHERE trip_start != '0001-02-03 00:00:00 UTC'
      AND trip_start <= end_timestamp()
      AND trip_end >= start_timestamp()
    GROUP BY 1,2,3,4,5,6
    ),

  BEN_trip_ids AS (
    SELECT
      trip_id,
      vessel_id,
      ssvid,
      trip_start,
      trip_end,
      end_port_iso3
    FROM `world-fishing-827.PortsProgramme.BEN_voyages_2021-23`
    WHERE trip_start != '0001-02-03 00:00:00 UTC'
      AND trip_start <= end_timestamp()
      AND trip_end >= start_timestamp()
    GROUP BY 1,2,3,4,5,6
    ),

----------------------------------------------------------
-- union TGO and BEN
----------------------------------------------------------
all_trips AS (
  SELECT
    *
  FROM
    TGO_trip_ids
  UNION ALL

  SELECT
    *
  FROM
    BEN_trip_ids
  ),


############################################################
##### PART 2: Add AIS coverage per trip
############################################################

------------------------------------------------------------
-- adjust trip_start and trip_end to be within the time-range selected
-- for trips that start before or end after the time-range selected
------------------------------------------------------------

voyages_filtered AS (
  SELECT
    ssvid,
    vessel_id,
    trip_id,
    GREATEST (trip_start, start_timestamp()) AS trip_start,
    LEAST (trip_end, end_timestamp()) AS trip_end,
    end_port_iso3
  FROM all_trips
  WHERE trip_end >= start_timestamp()
),

---------------------------------------------------------------------
-- Pull positions for the vessel within the time range of interest
-- Note using good_seg to just look at good segments
-- Add vessel_id based on seg_id (assumes each seg_id corresponds to only 1 vessel_id --> TRUE? YES! I checked segment_info table)
-- Calculation of AIS coverage will be based on vessel_id
---------------------------------------------------------------------
messages AS (
  SELECT
  --  *
  -- FROM `world-fishing-827.scratch_joef.messsages_goodsegs_2021-23`
    vessel_id,
    timestamp
  FROM `pipe_ais_v3_published.messages` a
  LEFT JOIN (
    SELECT seg_id FROM `pipe_ais_v3_published.segment_info`) b
  USING (seg_id)
  WHERE seg_id IN
    (SELECT seg_id
      FROM `pipe_ais_v3_published.segs_activity`
      WHERE good_seg
      AND NOT overlapping_and_short
      )
  AND timestamp BETWEEN start_timestamp() AND end_timestamp()
  AND vessel_id IN (SELECT vessel_id FROM all_trips)
),

-------------------------------------------------------------------------
-- Join messages to the voyages table
-------------------------------------------------------------------------
voyage_messages AS (
  SELECT *
  FROM voyages_filtered
  LEFT JOIN messages
  USING (vessel_id)
  -- filter for AIS messages between the voyage
  WHERE timestamp BETWEEN trip_start AND trip_end
),

-------------------------------------------------------------------------
-- get total voyage hours
-------------------------------------------------------------------------
voyages_daily_hours AS (
  SELECT
    vessel_id,
    ssvid,
    trip_id,
    end_port_iso3,
    trip_start,
    trip_end,
    date,
    COUNT(DISTINCT(hour)) AS n_voyage_hours
  FROM (
  SELECT
    vessel_id,
    ssvid,
    trip_id,
    end_port_iso3,
    trip_start,
    trip_end,
    hour_series,
    timestamp,
    EXTRACT(HOUR FROM hour_series) as hour,
    EXTRACT(DATE FROM hour_series) AS date
  FROM
    voyage_messages,
    UNNEST(GENERATE_TIMESTAMP_ARRAY(TIMESTAMP_TRUNC(trip_start, HOUR), TIMESTAMP_TRUNC(trip_end, HOUR), INTERVAL 1 HOUR)) AS hour_series
  GROUP BY 1,2,3,4,5,6,7,8
    )
  GROUP BY 1,2,3,4,5,6,7
),

-------------------------------------------------------------------------
-- add ais hours by day
-------------------------------------------------------------------------
voyages_ais_hours AS (
  SELECT
    vessel_id,
    ssvid,
    trip_id,
    end_port_iso3,
    trip_start,
    trip_end,
    EXTRACT(DATE FROM timestamp) AS date,
    COUNT(DISTINCT(TIMESTAMP_TRUNC(timestamp,HOUR))) as n_ais_hours,
  FROM
    voyage_messages
  GROUP BY 1,2,3,4,5,6,7
)

-------------------------------------------------------------------------
-- join voyage hours with ais hours and group by voyage for by voyage metrics
-- note use of LEFT JOIN important for accurate total voyage hours (as opposed to INNER JOIN)
-------------------------------------------------------------------------
SELECT
  vessel_id,
  ssvid,
  trip_id,
  end_port_iso3,
  trip_start,
  trip_end,
  sum(n_voyage_hours) AS total_voyage_h,
  sum(n_ais_hours) AS total_ais_h,
  ROUND(sum(n_ais_hours) / sum(n_voyage_hours) * 100, 1) as percent_ais_voyage
FROM(
  SELECT
    *
  FROM
    voyages_daily_hours
  LEFT JOIN
    voyages_ais_hours
  USING (vessel_id, ssvid, trip_id, end_port_iso3, trip_start, trip_end, date)
  )
  GROUP BY 1,2,3,4,5,6
-- JOIN vessels
-- USING (vessel_id)
-- ORDER BY ssvid, date

/*

*/

--
-- NEXT STEP:
-- Add % of voyage in poor reception areas (need to find a cut-off) --> but likely no AIS data points there
-- Add disabling events (can we count it? number of intentional disabling events?)
   -- NOTE: AIS disabling is only for 50km and beyond; filtered by an AIS reception threshold
   -- Summarize encounters and loitering with carrier activity, gaps, etc. --> check first
