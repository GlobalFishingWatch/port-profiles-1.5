# 31/01/2025
#  events for the missing voyages table

CREATE TABLE {temp_table2}
OPTIONS (
  expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
) AS

WITH

----------------------------------------------------------
-- pull relevant voyage info from starting table
----------------------------------------------------------
voyages AS (
  SELECT
    vessel_id,
    ssvid,
    shipname,
    vessel_flag_best,
    callsign,
    imo,
    vessel_class_best,
    geartype_best,
    vessel_class_initial,
    class_confidence_initial,
    trip_id,
    trip_start,
    trip_end,
 FROM  {temp_table}
  ),

----------------------------------------------------------
-- pull encounters and associated info for voyages
----------------------------------------------------------
encounters AS (
  SELECT
    "Encounter" AS event_type,
    enc.event_id,
    voyages.ssvid,
    voyages.shipname,
    voyages.vessel_flag_best,
    voyages.callsign,
    voyages.imo,
    voyages.vessel_class_best,
    voyages.geartype_best,
    voyages.vessel_class_initial,
    voyages.class_confidence_initial,
    voyages.trip_id,
    enc.event_start,
    enc.event_end,
    enc.event_duration_hrs,
    ROUND(enc.lat_mean, 2) AS lat_mean,
    ROUND(enc.lon_mean, 2) AS lon_mean,
    CAST(NULL AS numeric) AS lat_start,
    CAST(NULL AS numeric) AS lon_start,
    CAST(NULL AS numeric) AS lat_end,
    CAST(NULL AS numeric) AS lon_end,
    ROUND(CAST(enc.distance_km AS numeric), 1) AS distance_km,
    ROUND(CAST(enc.speed_knots AS numeric), 1) AS speed_knots,
    eez,
    enc.major_fao,
    enc.high_seas,
    enc.rfmo,
    ROUND(enc.start_distance_from_shore_km, 1) AS start_distance_from_shore_km,
    ROUND(enc.end_distance_from_shore_km, 1) AS end_distance_from_shore_km,
    ROUND(enc.start_distance_from_port_km, 1) AS start_distance_from_port_km,
    ROUND(enc.end_distance_from_port_km, 1) AS end_distance_from_port_km,
    CAST(NULL AS numeric)  AS positions_12_hours_before,
    enc.encountered_ssvid,
    enc.encountered_vessel_id
  FROM(
    SELECT
      event_id,
      vessel_id,
      ## extract information on vessel ssvid and vessel type
      JSON_EXTRACT_SCALAR(event_vessels, "$[0].ssvid") as ssvid,
      JSON_EXTRACT_SCALAR(event_vessels, "$[1].ssvid") as encountered_ssvid,
      JSON_EXTRACT_SCALAR(event_vessels, "$[1].id") as encountered_vessel_id,
      event_start,
      event_end,
      ROUND(TIMESTAMP_DIFF(event_end, event_start, minute) / 60, 3) AS event_duration_hrs,
      lat_mean,
      lon_mean,
      JSON_EXTRACT_SCALAR(event_info, "$.median_distance_km") as distance_km,
      JSON_EXTRACT_SCALAR(event_info, "$.median_speed_knots") as speed_knots,
      ## pull out event regions
      -- ARRAY_TO_STRING(regions_mean_position.eez, ", ") AS eez,
      regions_mean_position.eez AS eez,
      ARRAY_TO_STRING(regions_mean_position.major_fao, ", ") AS major_fao,
      ARRAY_TO_STRING(regions_mean_position.high_seas, ", ") AS high_seas,
      ARRAY_TO_STRING(regions_mean_position.rfmo, ", ") AS rfmo,
      -- regions_mean_position.rfmo AS rfmo,
      start_distance_from_shore_km,
      end_distance_from_shore_km,
      start_distance_from_port_km,
      end_distance_from_port_km
      ## code to pull out authorizations information if needed - nb this does not unnest completely
      ## if event happened in eez (eg field is not empty) then authorization is not populated
      ## as we don't have national registries in our database
      -- JSON_EXTRACT_ARRAY(event_vessels, "$[0].public_authorizations") as auth,
      -- JSON_EXTRACT_ARRAY(event_vessels, "$[1].public_authorizations") as encountered_auth,
      -- JSON_EXTRACT_SCALAR(event_info, "$.potential_risk") as potential_risk,
      FROM `pipe_production_v20201001.published_events_encounters_v2`
      ) enc
    INNER JOIN voyages
      ON
    enc.event_start BETWEEN voyages.trip_start AND voyages.trip_end
    AND voyages.vessel_id = enc.vessel_id ),

----------------------------------------------------------
-- pull loitering events and associated info for voyages
----------------------------------------------------------
loitering AS(
  SELECT
    "Loitering" AS event_type,
    loit.event_id,
    voyages.ssvid,
    voyages.shipname,
    voyages.vessel_flag_best,
    voyages.callsign,
    voyages.imo,
    voyages.vessel_class_best,
    voyages.geartype_best,
    voyages.vessel_class_initial,
    voyages.class_confidence_initial,
    voyages.trip_id,
    loit.event_start,
    loit.event_end,
    loit.event_duration_hrs,
    ROUND(loit.lat_mean, 2) AS lat_mean,
    ROUND(loit.lon_mean, 2) AS lon_mean,
    CAST(NULL AS numeric) AS lat_start,
    CAST(NULL AS numeric) AS lon_start,
    CAST(NULL AS numeric) AS lat_end,
    CAST(NULL AS numeric) AS lon_end,
    ROUND(CAST(loit.distance_km AS numeric), 1) AS distance_km,
    ROUND(CAST(loit.speed_knots AS numeric), 1) AS speed_knots,
    eez,
    loit.major_fao,
    loit.high_seas,
    loit.rfmo,
    ROUND(loit.start_distance_from_shore_km, 1) AS start_distance_from_shore_km,
    ROUND(loit.end_distance_from_shore_km, 1) AS end_distance_from_shore_km,
    ROUND(loit.start_distance_from_port_km, 1) AS start_distance_from_port_km,
    ROUND(loit.end_distance_from_port_km, 1) AS end_distance_from_port_km,
    CAST(NULL AS numeric) AS positions_12_hours_before,
    CAST(NULL AS string) AS encountered_ssvid,
    CAST(NULL AS string) AS encountered_vessel_id
  FROM(
    SELECT
      event_id,
      vessel_id,
      ## extract information on vessel ssvid and vessel type
      JSON_EXTRACT_SCALAR(event_vessels, "$[0].ssvid") as ssvid,
      JSON_EXTRACT_SCALAR(event_vessels, "$[0].type") as vessel_type,
      event_start,
      event_end,
      ROUND(TIMESTAMP_DIFF(event_end, event_start, minute) / 60, 3) AS event_duration_hrs,
      lat_mean,
      lon_mean,
      JSON_EXTRACT_SCALAR(event_info, "$.total_distance_km") as distance_km,
      JSON_EXTRACT_SCALAR(event_info, "$.avg_speed_knots") as speed_knots,
      ## pull out event regions
      -- ARRAY_TO_STRING(regions_mean_position.eez, ", ") AS eez,
      regions_mean_position.eez AS eez,
      ARRAY_TO_STRING(regions_mean_position.major_fao, ", ") AS major_fao,
      ARRAY_TO_STRING(regions_mean_position.high_seas, ", ") AS high_seas,
      ARRAY_TO_STRING(regions_mean_position.rfmo, ", ") AS rfmo,
      -- regions_mean_position.rfmo AS rfmo,
      start_distance_from_shore_km,
      end_distance_from_shore_km,
      start_distance_from_port_km,
      end_distance_from_port_km
      FROM `pipe_production_v20201001.published_events_loitering_v2`
      WHERE
        seg_id IN (
        SELECT
          seg_id
        FROM `gfw_research.pipe_v20201001_segs` -- pipe2.5
        WHERE
          good_seg IS TRUE
          AND overlapping_and_short IS FALSE)
          AND SAFE_CAST(JSON_QUERY(event_info,"$.avg_distance_from_shore_km") AS FLOAT64) > 20
          AND SAFE_CAST(JSON_QUERY(event_info,"$.loitering_hours") AS FLOAT64) > 2
          AND SAFE_CAST(JSON_QUERY(event_info,"$.avg_speed_knots") AS FLOAT64) < 2
      ) loit
    INNER JOIN voyages
      ON
    loit.event_start BETWEEN voyages.trip_start AND voyages.trip_end
    AND voyages.vessel_id = loit.vessel_id),

----------------------------------------------------------
-- pull fishing events and associated info for voyages
----------------------------------------------------------
fishing AS(
  SELECT
    "Fishing" AS event_type,
    fish.event_id,
    voyages.ssvid,
    voyages.shipname,
    voyages.vessel_flag_best,
    voyages.callsign,
    voyages.imo,
    voyages.vessel_class_best,
    voyages.geartype_best,
    voyages.vessel_class_initial,
    voyages.class_confidence_initial,
    voyages.trip_id,
    fish.event_start,
    fish.event_end,
    fish.event_duration_hrs,
    ROUND(fish.lat_mean, 2) AS lat_mean,
    ROUND(fish.lon_mean, 2) AS lon_mean,
    CAST(NULL AS numeric) AS lat_start,
    CAST(NULL AS numeric) AS lon_start,
    CAST(NULL AS numeric) AS lat_end,
    CAST(NULL AS numeric) AS lon_end,
    ROUND(CAST(fish.distance_km AS numeric), 1) AS distance_km,
    ROUND(CAST(fish.speed_knots AS numeric), 1) AS speed_knots,
    eez,
    fish.major_fao,
    fish.high_seas,
    fish.rfmo,
    ROUND(fish.start_distance_from_shore_km, 1) AS start_distance_from_shore_km,
    ROUND(fish.end_distance_from_shore_km, 1) AS end_distance_from_shore_km,
    ROUND(fish.start_distance_from_port_km, 1) AS start_distance_from_port_km,
    ROUND(fish.end_distance_from_port_km, 1) AS end_distance_from_port_km,
    CAST(NULL AS numeric) AS positions_12_hours_before,
    CAST(NULL AS string) AS encountered_ssvid,
    CAST(NULL AS string) AS encountered_vessel_id
  FROM(
    SELECT
      event_id,
      vessel_id,
      ## extract information on vessel ssvid and vessel type
      JSON_EXTRACT_SCALAR(event_vessels, "$[0].ssvid") as ssvid,
      JSON_EXTRACT_SCALAR(event_vessels, "$[0].type") as vessel_type,
      event_start,
      event_end,
      ROUND(TIMESTAMP_DIFF(event_end, event_start, minute) / 60, 3) AS event_duration_hrs,
      lat_mean,
      lon_mean,
      JSON_EXTRACT_SCALAR(event_info, "$.distance_km") as distance_km,
      JSON_EXTRACT_SCALAR(event_info, "$.avg_speed_knots") as speed_knots,
      ## pull out event regions
      -- ARRAY_TO_STRING(regions_mean_position.eez, ", ") AS eez,
      regions_mean_position.eez AS eez,
      ARRAY_TO_STRING(regions_mean_position.major_fao, ", ") AS major_fao,
      ARRAY_TO_STRING(regions_mean_position.high_seas, ", ") AS high_seas,
      ARRAY_TO_STRING(regions_mean_position.rfmo, ", ") AS rfmo,
      -- regions_mean_position.rfmo AS rfmo,
      start_distance_from_shore_km,
      end_distance_from_shore_km,
      start_distance_from_port_km,
      end_distance_from_port_km
      FROM `pipe_production_v20201001.published_events_fishing_v2`
      ) fish
    INNER JOIN voyages
      ON
    fish.event_start BETWEEN voyages.trip_start AND voyages.trip_end
    AND voyages.vessel_id = fish.vessel_id  ),

----------------------------------------------------------
-- pull gap events and associated info for voyages
-- Note not filtering for 'disabling events' but including all gaps
----------------------------------------------------------
gaps AS(
  SELECT
    "Gap" AS event_type,
    gaps.event_id,
    voyages.ssvid,
    voyages.shipname,
    voyages.vessel_flag_best,
    voyages.callsign,
    voyages.imo,
    voyages.vessel_class_best,
    voyages.geartype_best,
    voyages.vessel_class_initial,
    voyages.class_confidence_initial,
    voyages.trip_id,
    gaps.event_start,
    gaps.event_end,
    gaps.event_duration_hrs,
    CAST(NULL AS numeric) AS lat_mean,
    CAST(NULL AS numeric) AS lon_mean,
    ROUND(gaps.lat_start, 2) AS lat_start,
    ROUND(gaps.lon_start, 2) AS lon_start,
    ROUND(gaps.lat_end, 2) AS lat_end,
    ROUND(gaps.lon_end, 2) AS lon_end,
    ROUND(gaps.distance_km, 1) AS distance_km,
    ROUND(gaps.speed_knots, 1) AS speed_knots,
    -- CAST(gaps.eez AS string) AS eez,
    eez,
    CAST(NULL AS string) AS major_fao,
    CAST(NULL AS string) AS high_seas,
    gaps.rfmo,
    ROUND(gaps.start_distance_from_shore_km, 1) AS start_distance_from_shore_km,
    ROUND(gaps.end_distance_from_shore_km, 1) AS end_distance_from_shore_km,
    ROUND(gaps.start_distance_from_port_km, 1) AS start_distance_from_port_km,
    ROUND(gaps.end_distance_from_port_km, 1) AS end_distance_from_port_km,
    gaps.positions_12_hours_before,
    CAST(NULL AS string) AS encountered_ssvid,
    CAST(NULL AS string) AS encountered_vessel_id
  FROM(
    SELECT
      gap_id AS event_id,
      ssvid,
      gap_start AS event_start,
      gap_end AS event_end,
      ROUND(gap_hours, 3) AS event_duration_hrs,
      gap_start_lat AS lat_start,
      gap_start_lon AS lon_start,
      gap_end_lat AS lat_end,
      gap_end_lon AS lon_end,
      gap_distance_m / 1000 AS distance_km,
      gap_implied_speed_knots AS speed_knots,
      -- ARRAY_TO_STRING(gap_start_eez, ", ") AS eez,
      gap_start_eez AS eez,
      gap_start_rfmo AS rfmo,
      gap_start_distance_from_shore_m / 1000 AS start_distance_from_shore_km,
      gap_end_distance_from_shore_m / 1000 AS end_distance_from_shore_km,
      gap_start_distance_from_port_m / 1000 AS start_distance_from_port_km,
      gap_end_distance_from_port_m / 1000 AS end_distance_from_port_km,
      positions_12_hours_before
      FROM `pipe_production_v20201001.proto_ais_gap_events`
      ) gaps
    INNER JOIN voyages
      ON
    gaps.event_start BETWEEN voyages.trip_start AND voyages.trip_end
    AND voyages.ssvid = gaps.ssvid),

----------------------------------------------------------
-- union 4 event types into one table
----------------------------------------------------------
all_events AS (
  SELECT
    *
  FROM
    encounters
  UNION ALL

  SELECT
    *
  FROM
    loitering
  UNION ALL

  SELECT
    *
  FROM
    fishing
  UNION ALL

  SELECT
    *
  FROM
    gaps
  ),

----------------------------------------------------------
-- for encounters, add vessel info for encountered vessels
----------------------------------------------------------
encounter_v_info AS(
  SELECT
    events.*,
    vi.shipname AS encountered_shipname,
    vi.callsign AS encountered_callsign,
    vi.imo AS encountered_imo,
    vi.vessel_iso3 AS encountered_flag,
    vi.vessel_class_best AS encountered_vessel_class,
    vi.geartype AS encountered_geartype,
  FROM(
    SELECT
      *,
      EXTRACT(year FROM event_end) AS year
    FROM all_events) events
    LEFT JOIN (
      SELECT
        vessel_id,
        ssvid,
        year,
        shipname,
        callsign,
        imo,
        IFNULL(IFNULL(gfw_best_flag, core_flag), mmsi_flag) AS vessel_iso3,
        prod_shiptype AS vessel_class_best,
        prod_geartype AS geartype
      FROM
        `pipe_production_v20201001.all_vessels_byyear_v2_v20241205`) vi -- update to pipe3
      ON
        events.encountered_vessel_id = vi.vessel_id AND events.year = vi.year),

----------------------------------------------------------
-- create column of eez isos that allows for joint/disputed areas w/ >1 eez per code
----------------------------------------------------------
eez_names AS (
  SELECT
    eez_id,
    CASE
      WHEN eez3 IS NOT NULL AND eez2 IS NOT NULL THEN CONCAT(eez1, "/", eez2, "/", eez3)
      WHEN eez2 IS NOT NULL THEN CONCAT(eez1, "/", eez2)
      ELSE eez1 END AS eez_name
  FROM(
    SELECT
      CAST(eez_id AS STRING) AS eez_id,
      sovereign1_iso3 AS eez1,
      CASE WHEN sovereign2_iso3 = "NA" THEN null ELSE sovereign2_iso3 END AS eez2,
      CASE WHEN sovereign3_iso3 = "NA" THEN null ELSE sovereign3_iso3 END AS eez3
      -- reporting_name AS eez_name
    FROM `gfw_research.eez_info`)),

----------------------------------------------------------
-- join eez info to codes in event table
----------------------------------------------------------
add_eez_info AS(
  SELECT
    encs.event_type,
    encs.event_id,
    encs.ssvid,
    encs.shipname,
    encs.vessel_flag_best,
    encs.callsign,
    encs.imo,
    encs.vessel_class_best,
    encs.geartype_best,
    encs.vessel_class_initial,
    encs.class_confidence_initial,
    encs.trip_id,
    encs.event_start,
    encs.event_end,
    encs.event_duration_hrs,
    encs.lat_mean,
    encs.lon_mean,
    encs.lat_start,
    encs.lon_start,
    encs.lat_end,
    encs.lon_end,
    encs.distance_km,
    encs.speed_knots,
    -- encs.eez,
    -- eez_id,
    ARRAY_TO_STRING(ARRAY_AGG(eez_name ORDER BY eez_name), ", ") AS eez,
    encs.major_fao,
    encs.high_seas,
    encs.rfmo,
    encs.start_distance_from_shore_km,
    encs.end_distance_from_shore_km,
    encs.start_distance_from_port_km,
    encs.end_distance_from_port_km,
    encs.positions_12_hours_before,
    encs.encountered_ssvid,
    encs.encountered_vessel_id,
    encs.year,
    encs.encountered_shipname,
    encs.encountered_callsign,
    encs.encountered_imo,
    encs.encountered_flag,
    encs.encountered_vessel_class,
    encs.encountered_geartype
  FROM encounter_v_info AS encs
  LEFT JOIN UNNEST (eez) AS eez_id
  LEFT JOIN eez_names
  USING (eez_id)
  GROUP BY
    event_type,
    event_id,
    ssvid,
    shipname,
    vessel_flag_best,
    callsign,
    imo,
    vessel_class_best,
    geartype_best,
    vessel_class_initial,
    class_confidence_initial,
    trip_id,
    event_start,
    event_end,
    event_duration_hrs,
    lat_mean,
    lon_mean,
    lat_start,
    lon_start,
    lat_end,
    lon_end,
    distance_km,
    speed_knots,
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
    year,
    encountered_shipname,
    encountered_callsign,
    encountered_imo,
    encountered_flag,
    encountered_vessel_class,
    encountered_geartype
)

----------------------------------------------------------
-- split rfmo strings into arrays, sort, then re-concatenate as strings
----------------------------------------------------------
SELECT
  event_type,
    event_id,
    ssvid,
    shipname,
    vessel_flag_best,
    callsign,
    imo,
    vessel_class_best,
    geartype_best,
    vessel_class_initial,
    class_confidence_initial,
    trip_id,
    event_start,
    event_end,
    event_duration_hrs,
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
    ARRAY_TO_STRING(ARRAY(select rfmos from UNNEST(rfmo) rfmos ORDER BY rfmos), ", ") AS rfmo,
    start_distance_from_shore_km,
    end_distance_from_shore_km,
    start_distance_from_port_km,
    end_distance_from_port_km,
    positions_12_hours_before,
    encountered_ssvid,
    encountered_vessel_id,
    year,
    encountered_shipname,
    encountered_callsign,
    encountered_imo,
    encountered_flag,
    encountered_vessel_class,
    encountered_geartype
  FROM(
  SELECT
    event_type,
    event_id,
    ssvid,
    shipname,
    vessel_flag_best,
    callsign,
    imo,
    vessel_class_best,
    geartype_best,
    vessel_class_initial,
    class_confidence_initial,
    trip_id,
    event_start,
    event_end,
    event_duration_hrs,
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
    SPLIT(rfmo,', ') AS rfmo,
    start_distance_from_shore_km,
    end_distance_from_shore_km,
    start_distance_from_port_km,
    end_distance_from_port_km,
    positions_12_hours_before,
    encountered_ssvid,
    encountered_vessel_id,
    year,
    encountered_shipname,
    encountered_callsign,
    encountered_imo,
    encountered_flag,
    encountered_vessel_class,
    encountered_geartype
  FROM add_eez_info
  )




