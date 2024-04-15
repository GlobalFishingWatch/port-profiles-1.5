
--------------------------------------------------
-- Query to combine voyages and events into one master table as requested by TMT
-- also adds AIS coverage metrics to voyages, adds all relevant port events,
-- and updates anchorages using TMT info
--------------------------------------------------

-- Name desired output table
CREATE TABLE `world-fishing-827.scratch_joef.masterlist_conakry_2020-22_pipe25` AS

WITH

----------------------------------------------------------
-- Join AIS coverage info to voyages and prep data fields for union to events
----------------------------------------------------------
voyages AS (
  SELECT
    a.trip_id,
    a.trip_end_visit_id AS event_id,
    "Port_Visit" AS event_type,
    a.year,
    a.vessel_id,
    a.ssvid,
    a.shipname,
    a.vessel_flag_best,
    a.callsign,
    a.imo,
    a.vessel_class_best,
    a.geartype_best,
    a.vessel_class_initial,
    a.class_confidence_initial AS class_confidence,
    a.trip_start,
    a.start_port_iso3,
    a.start_port_label,
    a.trip_end,
    a.end_port_iso3,
    a.end_port_label,
    -- a.end_port_sublabel,
    -- a.trip_end_anchorage_id,
    a.trip_duration_days AS total_voyage_days,
      -- b.total_voyage_h,
      -- b.total_ais_h,
      b.percent_ais_voyage,
    a.start_portvisit_timestamp AS event_start,
    a.end_portvisit_timestamp AS event_end,
    a.port_event_duration_days AS event_duration_d,
      CAST(NULL AS numeric) AS lat_mean,
      CAST(NULL AS numeric) AS lon_mean,
    a.start_latitude AS lat_start,
    a.start_longitude AS lon_start,
      CAST(NULL AS numeric) AS lat_end,
      CAST(NULL AS numeric) AS lon_end,
      CAST(NULL AS numeric) AS distance_km,
      CAST(NULL AS numeric) AS speed_knots,
      CAST(NULL AS string) AS eez,
      CAST(NULL AS string) AS major_fao,
      CAST(NULL AS string) AS high_seas,
      CAST(NULL AS string) AS rfmo,
    -- a.dock AS at_dock,
      CAST(NULL AS numeric) AS start_distance_from_shore_km,
      CAST(NULL AS numeric) AS end_distance_from_shore_km,
      CAST(NULL AS numeric) AS start_distance_from_port_km,
      CAST(NULL AS numeric) AS end_distance_from_port_km,
      CAST(NULL AS numeric) AS positions_12_hours_before,
      CAST(NULL AS string) AS encountered_ssvid,
      CAST(NULL AS string) AS encountered_vessel_id,
      CAST(NULL AS string) AS encountered_shipname,
      CAST(NULL AS string) AS encountered_callsign,
      CAST(NULL AS string) AS encountered_imo,
      CAST(NULL AS string) AS encountered_flag,
      CAST(NULL AS string) AS encountered_vessel_class,
      CAST(NULL AS string) AS encountered_geartype
  FROM `world-fishing-827.scratch_joef.voyages_conakry_2020-22_pipe25` AS a
  LEFT JOIN (
    SELECT
      trip_id,
      -- total_voyage_h,
      -- total_ais_h,
      percent_ais_voyage
    FROM `world-fishing-827.scratch_joef.aiscoverage_conakry_2020-22_pipe25`) AS b
  USING (trip_id)
  ),

----------------------------------------------------------
-- Add all associated port events to voyages
----------------------------------------------------------
add_port_events AS(
  SELECT
    * EXCEPT(visit_id)
  FROM voyages AS a
  LEFT JOIN (
    SELECT
      visit_id,
      event_type AS port_event_type,
      timestamp AS port_event_timestamp,
      lat AS port_event_lat,
      lon AS port_event_lon,
      anchorage_id,
      confidence AS port_confidence
    FROM `world-fishing-827.pipe_production_v20201001.proto_port_visits`
    LEFT JOIN UNNEST (events)
    WHERE end_timestamp >= TIMESTAMP('2020-01-01 00:00:00 UTC')
    ) AS b
    ON a.event_id = b.visit_id
  ),


----------------------------------------------------------
-- Update anchorage labels using TMT provided data
----------------------------------------------------------
add_anchorages AS(
  SELECT
    * EXCEPT (anchorage_id, name, s2id)
  FROM (
    SELECT
      *
    FROM add_port_events AS a
    LEFT JOIN (
      SELECT
        name,
        label AS port_label,
        sublabel,
        New_label AS tmt_port_label
      FROM `world-fishing-827.scratch_joef.conakry_anchorages_tmt`) as b
    ON a.anchorage_id = b.name) as c
  LEFT JOIN (
    SELECT
      s2id,
      distance_from_shore_m AS port_distance_from_shore_m,
      dock AS at_dock
    FROM `anchorages.named_anchorages_v20240117`) as d
    ON c.anchorage_id = d.s2id
  ),


----------------------------------------------------------
-- Pull events, join to voyages, and add/prep data fields
----------------------------------------------------------
events AS (
  SELECT
      b.trip_id,
    a.event_id,
    a.event_type,
    a.year,
      b.vessel_id,
      b.ssvid,
      b.shipname,
      b.vessel_flag_best,
      b.callsign,
      b.imo,
      b.vessel_class_best,
      b.geartype_best,
      b.vessel_class_initial,
      b.class_confidence,
      b.trip_start,
      b.start_port_iso3,
      b.start_port_label,
      b.trip_end,
      b.end_port_iso3,
      b.end_port_label,
      -- b.end_port_sublabel,
      -- b.trip_end_anchorage_id,
      b.total_voyage_days,
      -- b.total_voyage_h,
      -- b.total_ais_h,
      b.percent_ais_voyage,
    a.event_start,
    a.event_end,
    ROUND(a.event_duration_hrs / 24, 1) AS event_duration_d,
    a.lat_mean,
    a.lon_mean,
    a.lat_start,
    a.lon_start,
    a.lat_end,
    a.lon_end,
    a.distance_km,
    a.speed_knots,
    a.eez,
    a.major_fao,
    a.high_seas,
    a.rfmo,
      -- CAST(NULL AS bool) AS at_dock,
    a.start_distance_from_shore_km,
    a.end_distance_from_shore_km,
    a.start_distance_from_port_km,
    a.end_distance_from_port_km,
    a.positions_12_hours_before,
    a.encountered_ssvid,
    a.encountered_vessel_id,
    a.encountered_shipname,
    a.encountered_callsign,
    a.encountered_imo,
    a.encountered_flag,
    a.encountered_vessel_class,
    a.encountered_geartype,
    CAST(NULL AS string) AS port_event_type,
    CAST(NULL AS timestamp) AS port_event_timestamp,
    CAST(NULL AS numeric) AS port_event_lat,
    CAST(NULL AS numeric) AS port_event_lon,
    CAST(NULL AS string) AS port_label,
    CAST(NULL AS string) AS tmt_port_label,
    CAST(NULL AS string) AS sublabel,
    CAST(NULL AS numeric) AS port_distance_from_shore_m,
    CAST(NULL AS BOOL) AS at_dock,
    CAST(NULL AS int64) AS port_confidence
  FROM `world-fishing-827.scratch_joef.events_conakry_2020-22_pipe25` AS a
  LEFT JOIN (
    SELECT
      trip_id,
      vessel_id,
      ssvid,
      year,
      shipname,
      vessel_flag_best,
      callsign,
      imo,
      vessel_class_best,
      geartype_best,
      vessel_class_initial,
      class_confidence,
      trip_start,
      start_port_iso3,
      start_port_label,
      trip_end,
      end_port_iso3,
      end_port_label,
      total_voyage_days,
      -- total_voyage_h,
      -- total_ais_h,
      percent_ais_voyage
    FROM voyages) AS b
    USING (trip_id)
  ),

----------------------------------------------------------
-- Union voyages to events
----------------------------------------------------------
combined AS(
  SELECT
    trip_id,
    event_id,
    event_type,
    year,
    vessel_id,
    ssvid,
    shipname,
    vessel_flag_best,
    callsign,
    imo,
    vessel_class_best,
    geartype_best,
    vessel_class_initial,
    class_confidence,
    trip_start,
    start_port_iso3,
    start_port_label,
    trip_end,
    end_port_iso3,
    end_port_label,
    total_voyage_days,
    percent_ais_voyage,
    event_start,
    event_end,
    event_duration_d,
    lat_mean,
    lon_mean,
    lat_start,
    lon_start,
    lat_end,
    lon_end,
    distance_km,
    speed_knots,
    eez,
    major_fao,
    high_seas,
    rfmo,
    start_distance_from_shore_km,
    end_distance_from_shore_km,
    start_distance_from_port_km,
    end_distance_from_port_km,
    positions_12_hours_before,
    encountered_ssvid,
    encountered_vessel_id,
    encountered_shipname,
    encountered_callsign,
    encountered_imo,
    encountered_flag,
    encountered_vessel_class,
    encountered_geartype,
    port_event_type,
    port_event_timestamp,
    port_event_lat,
    port_event_lon,
    port_label,
    sublabel,
    tmt_port_label,
    port_distance_from_shore_m,
    at_dock,
    port_confidence
  FROM
    add_anchorages

  UNION ALL

  SELECT
    *
  FROM
    events
  ORDER BY event_start),


----------------------------------------------------------
-- Label ssvids with evidence of spoofing
----------------------------------------------------------
id_spoofers AS(
  SELECT ssvid
  FROM `world-fishing-827.gfw_research.vi_ssvid_byyear_v20240301`
  WHERE
      (year = 2020 OR year = 2021 OR year = 2022) AND
      # MMSI broadcast 2 or more names in overlapping segments for > 24 h, GFW criteria
      (activity.overlap_hours_multinames >= 24 OR
      # MMSI used by multiple vessels simultaneously for more than 3 days
      activity.overlap_hours >= 24*3 OR
      # MMSI offsetting position
      activity.offsetting IS TRUE)
  )

----------------------------------------------------------
-- select final table adding spoofing indicator (if ssvid spoofed in any of the 3 years of analysis)
----------------------------------------------------------
SELECT
  *,
  IF (ssvid IN (
      SELECT ssvid FROM id_spoofers),
      TRUE, FALSE) possible_spoofing
FROM combined
ORDER BY event_start

/*
*/
