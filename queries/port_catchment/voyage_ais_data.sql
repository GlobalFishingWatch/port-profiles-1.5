-------------------------------------------------------------------------
-- Script to get ten minute AIS data from carrier vessel voyages to focal port
-- Parameterised on start date, end date and voyage table
-- written by Max Schofield 27 June 2025
-------------------------------------------------------------------------

--CREATE TEMP FUNCTION  start_date() AS (TIMESTAMP('2021-01-01 00:00:00 UTC'));
--CREATE TEMP FUNCTION  end_date() AS (TIMESTAMP('2021-02-01 00:00:00 UTC'));
CREATE TEMP FUNCTION  start_date() AS (TIMESTAMP({start_date}));
CREATE TEMP FUNCTION  end_date() AS (TIMESTAMP({end_date}));

WITH

-------------------------------------------------------------------------
-- take voyages from port profile as starting point
-------------------------------------------------------------------------

pp_voyages AS (
  SELECT
    vessel_id,
    trip_start,
    trip_end,
    trip_id,
    start_port_iso3 AS start_iso3,
    start_port_label AS start_label,
    end_port_iso3 AS end_iso3,
    end_port_label AS end_label,
    'port_profile' AS colour
  FROM {voyage_table}
  WHERE vessel_class_best = 'carrier'
),


-------------------------------------------------------------------------
-- bring in anchorage data to label new voyages
-------------------------------------------------------------------------

anchorage_names AS (
  SELECT
    s2id,
    label,
    iso3
  FROM
    `anchorages.named_anchorages_v20240117`
  ),

-------------------------------------------------------------------------
-- identify all voyages in the focal period for vessels in the port profile
-------------------------------------------------------------------------

all_ves_voyages AS (
  SELECT DISTINCT
    *,
  FROM
    `pipe_ais_v3_internal.voyages_c2`
  WHERE
    trip_end BETWEEN start_date() AND end_date()
    AND trip_start > start_date()
    AND vessel_id IN (SELECT DISTINCT vessel_id FROM pp_voyages)
  ORDER BY ssvid, trip_start
),

-------------------------------------------------------------------------
-- add anchorage names to all voyages
-------------------------------------------------------------------------

named_voyages AS (
  SELECT
    * EXCEPT(s2id, label, iso3),
    c.label AS end_label,
    c.iso3 AS end_iso3
  FROM (
    SELECT
      * EXCEPT(s2id, label, iso3),
      b.label AS start_label,
      b.iso3 AS start_iso3
    FROM
      all_ves_voyages
    LEFT JOIN
      anchorage_names b
    ON
      trip_start_anchorage_id = s2id)
  LEFT JOIN
    anchorage_names c
  ON
    trip_end_anchorage_id = s2id),

-------------------------------------------------------------------------
-- order the full voyage dataset and add a row number to enable identify preceeding voyages
-------------------------------------------------------------------------

ordered_voyages AS (
  SELECT
    *,
    ROW_NUMBER() OVER (ORDER BY ssvid, trip_start) AS rn
  FROM named_voyages
    ORDER BY ssvid, trip_start),

-------------------------------------------------------------------------
-- identify voyages that were included in the port profile based on trip_id
-------------------------------------------------------------------------
targets AS (
  SELECT rn FROM ordered_voyages WHERE trip_id IN (SELECT trip_id FROM pp_voyages)
),

-------------------------------------------------------------------------
-- find the voyages that preceded the port profile voyages. Exclude the voyages in the port profile
-------------------------------------------------------------------------
preceding_rows AS (
  SELECT
    o.vessel_id,
    o.trip_start,
    o.trip_end,
    o.trip_id,
    o.start_iso3,
    o.start_label,
    o.end_iso3,
    o.end_label,
    'previous_voyage' AS colour
  FROM targets t
  JOIN ordered_voyages o
  ON o.rn IN (t.rn - 1, t.rn - 2)
  WHERE
    trip_id NOT IN (SELECT trip_id FROM pp_voyages)
  ORDER BY trip_start
),

-------------------------------------------------------------------------
-- merge the port profile voyages with a table of preceeding voyages
-------------------------------------------------------------------------
voyages_all AS (
    SELECT * FROM pp_voyages
  UNION ALL
    SELECT * FROM preceding_rows
),

-------------------------------------------------------------------------
-- Get AIS good segs for the vessels active in Togo
-------------------------------------------------------------------------

vessel_ais AS (
  SELECT
    a.vessel_id,
    lat,
    lon,
    timestamp
  FROM `pipe_ais_v3_published.messages` a
  LEFT JOIN (
      SELECT seg_id, vessel_id FROM `pipe_ais_v3_published.segment_info`) b
  USING (seg_id)
  WHERE
    seg_id IN
      (SELECT seg_id
      FROM `pipe_ais_v3_published.segs_activity`
      WHERE good_seg
      AND NOT overlapping_and_short)
    AND timestamp BETWEEN start_date() AND end_date()
    AND a.vessel_id IN (SELECT DISTINCT vessel_id FROM voyages_all)),


-------------------------------------------------------------------------
-- Join messages to the voyages table to get messages in the voyage
-------------------------------------------------------------------------

voyage_ais AS (
  SELECT *
  FROM voyages_all
  LEFT JOIN vessel_ais USING (vessel_id)
  -- filter for AIS messages between the voyage
  WHERE timestamp BETWEEN trip_start AND trip_end),

-------------------------------------------------------------------------
-- As we are plotting broad scale lines of the vessels we can thin the AIS data to reduce query size
-------------------------------------------------------------------------

ais_thinned AS (
  SELECT
    vessel_id,
    trip_id,
    -- truncate timestamp to 10-minute buckets
    TIMESTAMP_SECONDS(DIV(UNIX_SECONDS(timestamp), 600) * 600) AS interval_start,
    ARRAY_AGG(STRUCT(lat, lon, timestamp) ORDER BY timestamp ASC)[OFFSET(0)] AS first_msg_in_interval
  FROM voyage_ais
  GROUP BY vessel_id, trip_id, interval_start
)


SELECT
  a.vessel_id,
  a.trip_id,
  a.interval_start,
  a.first_msg_in_interval.lat AS lat,
  a.first_msg_in_interval.lon AS lon,
  a.first_msg_in_interval.timestamp AS timestamp,
  o.colour
FROM ais_thinned a
LEFT JOIN (SELECT trip_id, colour FROM voyages_all) o USING (trip_id)
ORDER BY vessel_id, timestamp;

