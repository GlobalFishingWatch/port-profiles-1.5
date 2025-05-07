############################################################
##### PART 2: Add AIS coverage per trip
############################################################

--# use a temp table for storage
--CREATE TEMP FUNCTION  temp_table() AS ({temp_table});

# voyages will be truncated to this start timestamp, if needed
CREATE TEMP FUNCTION  start_date() AS (TIMESTAMP({start_date}));
--
# voyages will be truncated to this end timestamp, if needed
CREATE TEMP FUNCTION  end_date() AS (TIMESTAMP({end_date}));


WITH
------------------------------------------------------------
-- take voyage info from the voyage table, removing some known noise
------------------------------------------------------------
  trip_ids AS (
    SELECT
      trip_id,
      vessel_id,
      ssvid,
      trip_start,
      trip_end,
      start_portvisit_timestamp,
      end_portvisit_timestamp
    --FROM  temp_table()
    FROM   {temp_table}
    WHERE trip_start != '0001-02-03 00:00:00 UTC'
        AND trip_end BETWEEN start_date() AND end_date()
        AND trip_start < end_date()
    GROUP BY 1,2,3,4,5,6,7
    ),

------------------------------------------------------------
-- adjust trip_start and trip_end to be within the time-range selected
-- for trips that start before or end after the time-range selected
------------------------------------------------------------

  voyages_filtered AS (
    SELECT
      ssvid,
      vessel_id,
      trip_id,
      end_portvisit_timestamp,
      start_portvisit_timestamp,
      GREATEST (trip_start, start_date()) AS trip_start,
      LEAST (trip_end, end_date()) AS trip_end,
    FROM trip_ids
    WHERE trip_end >= start_date()
  ),

---------------------------------------------------------------------
-- Pull positions for the vessel within the time range of interest
-- Note using good_seg to just look at good segments
-- Add vessel_id based on seg_id (assumes each seg_id corresponds to only 1 vessel_id --> TRUE? YES! I checked segment_info table)
-- Calculation of AIS coverage will be based on vessel_id
---------------------------------------------------------------------
  messages AS (
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
 --   seg_id IN
   --   (SELECT seg_id
     --   FROM `pipe_ais_v3_published.segs_activity`
       -- WHERE good_seg
      --  AND NOT overlapping_and_short
      --  )
    --AND timestamp BETWEEN start_date() AND end_date()
     timestamp BETWEEN start_date() AND end_date()
    AND a.vessel_id IN (SELECT vessel_id FROM trip_ids)
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
      trip_start,
      trip_end,
      date,
      COUNT(DISTINCT(hour)) AS n_voyage_hours
    FROM (
    SELECT
      vessel_id,
      ssvid,
      trip_id,
      trip_start,
      trip_end,
      hour_series,
      timestamp,
      EXTRACT(HOUR FROM hour_series) as hour,
      EXTRACT(DATE FROM hour_series) AS date
    FROM
      voyage_messages,
      UNNEST(GENERATE_TIMESTAMP_ARRAY(TIMESTAMP_TRUNC(trip_start, HOUR), TIMESTAMP_TRUNC(trip_end, HOUR), INTERVAL 1 HOUR)) AS hour_series
    GROUP BY 1,2,3,4,5,6,7
      )
    GROUP BY 1,2,3,4,5,6
  ),

-------------------------------------------------------------------------
-- add ais hours by day
-------------------------------------------------------------------------
  voyages_ais_hours AS (
    SELECT
      vessel_id,
      ssvid,
      trip_id,
      trip_start,
      trip_end,
      EXTRACT(DATE FROM timestamp) AS date,
      COUNT(DISTINCT(TIMESTAMP_TRUNC(timestamp,HOUR))) as n_ais_hours,
    FROM
      voyage_messages
    GROUP BY 1,2,3,4,5,6
  ),


-------------------------------------------------------------------------
-- join voyage hours with ais hours and group by voyage for by voyage metrics
-- note use of LEFT JOIN important for accurate total voyage hours (as opposed to INNER JOIN)
-------------------------------------------------------------------------

ais_coverage AS(
  SELECT
    vessel_id,
    ssvid,
    trip_id,
    trip_start,
    trip_end,
    sum(n_voyage_hours) AS total_voyage_h,
    sum(n_ais_hours) AS total_ais_h,
    ROUND(sum(n_ais_hours) / sum(n_voyage_hours) * 100, 1) as percent_ais_voyage,
  FROM(
    SELECT
      *
    FROM
      voyages_daily_hours
    LEFT JOIN
      voyages_ais_hours
    USING (vessel_id, ssvid, trip_id, trip_start, trip_end, date)
    )
  GROUP BY 1,2,3,4,5)


SELECT
  vessel_id,
  ssvid,
  year,
  shipname,
  vessel_flag_best,
  mmsi_flag,
  callsign,
  imo,
  vessel_class_best,
  geartype_best,
  vessel_class_initial,
  class_confidence_initial,
  trip_id,
  trip_start,
  start_port_iso3,
  start_port_label,
  trip_start_confidence,
  trip_end,
  end_port_iso3,
  end_port_label,
  end_port_sublabel,
  trip_end_anchorage_id,
  trip_end_confidence,
  trip_duration_days,
  start_portvisit_timestamp,
  end_portvisit_timestamp,
  port_event_duration_days,
  distance_from_shore_m,
  dock,
  trip_end_visit_id,
  stop_anchorage_ids,
  start_latitude,
  start_longitude,
  num_encounters,
  num_loitering,
  num_fishing,
  high_seas,
  eezs,
  rfmos,
  fishing_hours,
  total_voyage_h,
  total_ais_h,
  percent_ais_voyage,
--FROM temp_table()
FROM {temp_table}
LEFT JOIN (
 SELECT vessel_id, ssvid, trip_id, trip_start, trip_end, percent_ais_voyage, total_voyage_h, total_ais_h,
 FROM ais_coverage) USING (vessel_id, ssvid, trip_id, trip_start, trip_end)


