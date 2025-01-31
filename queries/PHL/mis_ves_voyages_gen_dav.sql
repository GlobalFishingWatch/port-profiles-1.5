# 31/01/25 - creating voyages missed from GenSan and Davao port profile analysis
#  MS

# functions to set script up
# date times
CREATE TEMP FUNCTION  start_date() AS (TIMESTAMP({start_date}));
CREATE TEMP FUNCTION  end_date() AS (TIMESTAMP({end_date}));
CREATE TEMP FUNCTION  start_year() AS ({start_year});
CREATE TEMP FUNCTION  end_year() AS ({end_year});

# port labels
CREATE TEMP FUNCTION port_label()
RETURNS ARRAY<STRING> AS (
    [{port_labels}]
);

# port country
CREATE TEMP FUNCTION port_iso() AS ({port_iso});

# ssvid
CREATE TEMP FUNCTION missing_ssvids()
RETURNS ARRAY<STRING> AS (
    [{missing_ssvids}]
);

-- create temp table to store voyages within to input into next function
CREATE TABLE `world-fishing-827.scratch_max.phl_misves_gendav_voyages_temp`
OPTIONS (
  expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
) AS
--------------------------------------
WITH

----------------------------------------------------------
-- Define lists of high/med/low confidence for all fishing-related vessels
-- and join each list to voyages within the time period of interest
----------------------------------------------------------

----------------------------------------------------------
-- add in vessels not present on vessel list (ie TMT flagged)
----------------------------------------------------------

-- identify relavant anchorages
anchorages AS(
  SELECT
    s2id,
    label,
    iso3
  FROM
    `anchorages.named_anchorages_v20240117`
),

-- find the vessel_ids for the relevant vessels
ves_id AS (
  SELECT
    vessel_id,
    ssvid,
    FROM `world-fishing-827.pipe_ais_v3_published.vessel_info`
    WHERE
      ssvid IN UNNEST(missing_ssvids())
),

-- find the port visit information for vessels of interest
-- add rows to port visit table to
missing_vessel_visits AS(
  SELECT
    mv.vessel_id,
    ssvid,
    event_id AS visit_id,
    event_start,
    event_end,
    -- event_info,
    -- event_vessels,
    JSON_EXTRACT_SCALAR(event_info, "$.start_anchorage.anchorage_id") AS s2id,
    a.label,
    a.iso3 AS port_iso3,
    -- JSON_EXTRACT_SCALAR(event_vessels, "$[0].flag") AS iso3,
    -- JSON_EXTRACT_SCALAR(event_vessels, "$[0].type") AS vessel_type,
    ROW_NUMBER() OVER (PARTITION BY ssvid ORDER BY event_start) AS row_num,
  FROM `world-fishing-827.pipe_ais_v3_published.product_events_port_visit_v2` mv
  INNER JOIN ves_id vi ON mv.vessel_id = vi.vessel_id
  INNER JOIN anchorages a ON  JSON_EXTRACT_SCALAR(mv.event_info, "$.start_anchorage.anchorage_id") = a.s2id
  WHERE
    event_start BETWEEN start_date() AND end_date()
   -- AND mv.vessel_id = '094f7f36c-c770-f958-1bd4-38d7529d5dce'
),

-- identify visits to subic and navotas from missing vessels
missing_visits AS(
  SELECT
    *
  FROM missing_vessel_visits mvv
  WHERE
   label IN UNNEST(port_label())
),

-- identify previous port calls from visits of interest
visits AS (
  SELECT
    start_voyage.vessel_id AS start_vessel_id,
    end_voyage.vessel_id AS end_vessel_id,
    start_voyage.ssvid AS start_ssvid,
    end_voyage.ssvid AS end_ssvid,
    start_voyage.event_start AS voyage_start_entry_date,
    start_voyage.event_end AS voyage_start_exit_date,
    start_voyage.visit_id AS voyage_start_visit_id,
    start_voyage.s2id AS voyage_start_s2id,
    start_voyage.label AS voyage_start_port_label,
    start_voyage.port_iso3 AS voyage_start_port_iso3,
    end_voyage.event_start AS voyage_end_entry_date,
    end_voyage.event_end AS voyage_end_exit_date,
    end_voyage.visit_id AS voyage_end_visit_id,
    end_voyage.s2id AS voyage_end_s2id,
    end_voyage.label AS voyage_end_port_label,
    end_voyage.port_iso3 AS voyage_end_port_iso3,
  FROM
    missing_visits end_voyage
  LEFT JOIN
    missing_vessel_visits start_voyage
  ON
    end_voyage.ssvid = start_voyage.ssvid
    AND start_voyage.row_num = end_voyage.row_num - 1
),

-- recreate sudo voyages using port visit information
-- voyages need year, ssvid, vessel_id, vessel_iso3, class_confidence, vessel_class, gear_type, trip_id
-- trip_start,trip_end, trip_start_anchorage_id, trip_end_anchorage_id, trip_start_visit_id,
-- trip_end_visit_id, trip_start_confidence, trip_end_confidence
total_voyages AS (
    SELECT
    EXTRACT(YEAR FROM voyage_start_entry_date) AS year,
    start_ssvid AS ssvid,
    start_vessel_id AS vessel_id,
    '' AS vessel_iso3,
    'TMT_review' AS class_confidence,
    '' AS vessel_class,
    '' AS gear_type,
    voyage_start_exit_date AS trip_start,
    voyage_end_entry_date AS trip_end,
    voyage_start_s2id AS trip_start_anchorage_id,
    voyage_end_s2id AS trip_end_anchorage_id,
    voyage_start_visit_id AS trip_start_visit_id,
    voyage_end_visit_id AS trip_end_visit_id,
    voyage_end_entry_date,
    voyage_end_exit_date,
    'manual' AS trip_start_confidence,
    'manual' AS trip_end_confidence,
    (
      SELECT
        STRING_AGG(SUBSTR(alphabet, CAST(FLOOR(RAND() * LENGTH(alphabet) + 1) AS INT64), 1), '')
      FROM
        UNNEST(GENERATE_ARRAY(1, 10)) AS position
      CROSS JOIN (SELECT 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' AS alphabet)
    ) AS  trip_id,
  FROM
    visits
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
),

--------------------------------------
-- Anchorage names
--------------------------------------
  anchorage_names AS (
  SELECT
    s2id,
    label,
    iso3
  FROM
    `anchorages.named_anchorages_v20240117`
    ),

--------------------------------------
-- Add names to voyages (start and end)
--------------------------------------
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
      total_voyages
    LEFT JOIN
      anchorage_names b
    ON
      trip_start_anchorage_id = s2id)
  LEFT JOIN
    anchorage_names c
  ON
    trip_end_anchorage_id = s2id),



--------------------------------------
-- Add encounter to voyages (start and end)
--------------------------------------
-- pipe 2.5
  num_encounters AS (
  SELECT
    vessel_id,
    trip_id,
    COUNT(*) AS num_encounters
  FROM (
    SELECT
      vessel_id,
      event_start,
      event_end,
    FROM
      `pipe_production_v20201001.published_events_encounters`) a
  INNER JOIN (
    SELECT
      vessel_id,
      trip_id,
      trip_start,
      trip_end
    FROM
      named_voyages)
  USING
    (vessel_id)
  WHERE
    event_start BETWEEN trip_start
    AND trip_end
  GROUP BY
    1,
    2 ),

--------------------------------------
-- Identify how many loitering events occurred on each voyage
-- both 2.5 and 3 (952874 vs 1914575)
--------------------------------------
  -- pipe3
  -- num_loitering AS (
  --   SELECT
  --     ssvid,
  --     trip_id,
  --     COUNT(*) AS num_loitering
  --   FROM (
  --     SELECT
  --       ssvid,
  --       loitering_start_timestamp,
  --       loitering_end_timestamp,
  --     FROM
  --       `world-fishing-827.pipe_ais_v3_alpha_published.loitering`
  --     WHERE
  --       loitering_start_timestamp >= TIMESTAMP(DATE_ADD(DATE(start_date()), INTERVAL -3 YEAR))
  --       AND avg_distance_from_shore_nm > 10
  --       AND loitering_hours > 2
  --       AND avg_speed_knots < 2
  --       AND
  --       seg_id IN (
  --       SELECT
  --         seg_id
  --       FROM
  --         `pipe_ais_v3_alpha_published.segs_activity`
  --       WHERE
  --         good_seg IS TRUE
  --         AND overlapping_and_short IS FALSE)) a
  --   INNER JOIN (
  --     SELECT
  --       ssvid,
  --       trip_id,
  --       trip_start,
  --       trip_end,
  --       pan_crossing
  --     FROM
  --       updated_pan_voyages) b
  --   USING
  --     (ssvid)
  --   WHERE
  --     loitering_start_timestamp BETWEEN trip_start
  --     AND trip_end
  --   GROUP BY
  --     ssvid, trip_id
  --     ),

-- pipe2.5
  num_loitering AS (
  SELECT
    vessel_id,
    trip_id,
    COUNT(*) AS num_loitering
  FROM (
    SELECT
      vessel_id,
      event_start,
      event_end,
    FROM
      `pipe_production_v20201001.published_events_loitering` -- pipe2.5
    WHERE
      seg_id IN (
      SELECT
        seg_id
      FROM
        `gfw_research.pipe_v20201001_segs` -- pipe2.5
      WHERE
        good_seg IS TRUE
        AND overlapping_and_short IS FALSE)
        AND SAFE_CAST(JSON_QUERY(event_info,"$.avg_distance_from_shore_km") AS FLOAT64) > 20
        AND SAFE_CAST(JSON_QUERY(event_info,"$.loitering_hours") AS FLOAT64) > 2
        AND SAFE_CAST(JSON_QUERY(event_info,"$.avg_speed_knots") AS FLOAT64) < 2) a
  INNER JOIN (
    SELECT
      vessel_id,
      trip_id,
      trip_start,
      trip_end
    FROM
      named_voyages) b
  USING
    (vessel_id)
  WHERE
    event_start BETWEEN trip_start
    AND trip_end
  GROUP BY
    1,
    2 ),

--------------------------------------
-- Identify how many fishing events occurred on each voyage
--------------------------------------
-- pipe2.5
  num_fishing AS(
    SELECT
      vessel_id,
      trip_id,
      STRING_AGG(DISTINCT high_sea, ', ') as high_seas,
      STRING_AGG(DISTINCT rfmo,', ') as rfmos,
      STRING_AGG(DISTINCT ISO_TER1,', ') as eezs,
      COUNT(*) AS num_fishing,
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
      FROM
        `pipe_production_v20201001.published_events_fishing_v2`
      LEFT JOIN UNNEST (regions_mean_position.high_seas) AS high_sea
      LEFT JOIN UNNEST (regions_mean_position.rfmo) AS rfmo
      LEFT JOIN UNNEST (regions_mean_position.eez) AS eez
      LEFT JOIN (SELECT MRGID, ISO_TER1 FROM `world-fishing-827.ocean_shapefiles_all_purpose.marine_regions_v11`) ON (eez=CAST(MRGID AS string))) a
    INNER JOIN (
      SELECT
        vessel_id,
        trip_id,
        trip_start,
        trip_end
      FROM
        named_voyages)
    USING
      (vessel_id)
    WHERE
      event_start BETWEEN trip_start AND trip_end
    GROUP BY
      vessel_id, trip_id
      ),

  --------------------------------------
  -- Identify the number of fishing events
  -- that occurred on each voyage
  --------------------------------------
   gaps AS (
    SELECT
      ssvid,
      count(*) AS num_gaps,
      sum(gap_hours) AS total_gap_hours,
    FROM (
      SELECT
        ssvid,
        gap_start,
        gap_end,
        gap_hours,
      FROM
        `pipe_production_v20201001.proto_ais_gap_events`
      WHERE
        gap_start_distance_from_shore_m > 9260
        AND gap_end_distance_from_shore_m > 9260) a
    INNER JOIN (
      SELECT
        ssvid,
        trip_id,
        trip_start,
        trip_end
      FROM
        named_voyages)
    USING
      (ssvid)
    WHERE
      gap_start BETWEEN trip_start AND trip_end
    GROUP BY
      1),

  --------------------------------------
  -- label voyage if it had at least
  -- one encounter event
  --------------------------------------
  add_encounters AS (
    SELECT
      a.*,
      b.num_encounters,
    IF
      (b.num_encounters > 0, TRUE, FALSE) AS had_encounter
    FROM
      named_voyages AS a
    LEFT JOIN
      num_encounters b
    USING
      (vessel_id,
        trip_id)
    GROUP BY
      1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23),

-- --------------------------------------
-- -- label voyage if it had at least
-- -- one loitering event
-- --------------------------------------
  add_loitering AS (
    SELECT
      c.*,
      d.num_loitering,
    IF
      (d.num_loitering > 0, TRUE, FALSE) AS had_loitering
    FROM
      add_encounters c
    LEFT JOIN
      num_loitering d
    USING
      (vessel_id, -- pipe2.5
      -- (ssvid, -- pipe3
        trip_id)
    GROUP BY
      1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25),

--------------------------------------
-- label voyage if it had at least
-- one fishing event
--------------------------------------
  add_fishing AS (
    SELECT
      e.*,
      f.high_seas,
      f.rfmos,
      f.eezs,
      f.num_fishing,
      f.fishing_hours,
    IF
      (f.num_fishing > 0, TRUE, FALSE) AS had_fishing
    FROM
      add_loitering AS e
    LEFT JOIN
      num_fishing f
    USING
      (vessel_id,
        trip_id)
    GROUP BY
      1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31),

  --------------------------------------
  -- label voyage if it had at least
  -- one AIS gap event
  --------------------------------------
    add_gaps AS (
      SELECT
        e.*,
        f.num_gaps,
        f.total_gap_hours,
      IF
        (f.num_gaps > 0, TRUE, FALSE) AS had_gaps
      FROM
        add_fishing AS e
      LEFT JOIN
        gaps f
      USING
      -- this will not be robust to vssels with two trips in the month
        (ssvid)
      GROUP BY
        1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34),

--------------------------------------
-- Filter the voyages to those that
-- involve 'good' vessel_ids, and
-- end between time range of interest
--------------------------------------
  good_vessel_voyages AS (
    SELECT
      *,
      ROUND(TIMESTAMP_DIFF(trip_end, trip_start, HOUR)/24, 1) AS trip_duration_days
    FROM
      add_gaps
    WHERE
      EXTRACT(YEAR
      FROM
        trip_end) >= start_year()
      AND EXTRACT(YEAR
      FROM
        trip_end) <= end_year()
  ),

--------------------------------------
-- Add end anchorage information from Pew ports
-- **** leaving this out during port profile 1.5 update although can be added back if pew important
--------------------------------------
  -- fishing_vessel_voyages AS (
  -- SELECT
  --   *
  -- FROM
  --   good_vessel_voyages AS voyages
  -- LEFT JOIN (
  --   SELECT
  --     point_id AS trip_end_anchorage_id,
  --     port_id,
  --     cluster_id,
  --     port_label,
  --     iso3 AS port_iso3,
  --     cluster_label,
  --     point_label,
  --     port_locode
  --   FROM
  --     `proj_pew_ports.gfw_ports_database_v20230424` ) AS ports
  -- USING
  --   (trip_end_anchorage_id) ),

--------------------------------------
-- Add end anchorage information from GFW ports
--------------------------------------
  add_visit_end_1 AS (
    SELECT
      *
    FROM
      good_vessel_voyages
    LEFT JOIN (
      SELECT
        s2id AS trip_end_anchorage_id,
        sublabel AS end_port_sublabel,
        distance_from_shore_m,
        dock
      FROM
        `anchorages.named_anchorages_v20240117` )
    USING
      (trip_end_anchorage_id)),


-- --------------------------------------
-- -- all qualifying voyages
-- --------------------------------------
  all_voyages AS (
    SELECT
      EXTRACT(YEAR FROM trip_end) AS year,
      ssvid,
      vessel_id,
      vessel_iso3,
      class_confidence,
      vessel_class,
      gear_type,
      trip_id,
      trip_start,
      start_iso3 AS start_port_iso3,
      start_label AS start_port_label,
      trip_start_confidence,
      trip_end,
      end_iso3 AS end_port_iso3,
      end_label AS end_port_label,
      end_port_sublabel,
      trip_end_anchorage_id,
      trip_end_confidence,
      trip_duration_days,
      voyage_end_entry_date AS start_portvisit_timestamp,
      voyage_end_exit_date AS end_portvisit_timestamp,
      ROUND(TIMESTAMP_DIFF(voyage_end_exit_date, voyage_end_entry_date, minute)/60/24, 1) AS port_event_duration_days,
      distance_from_shore_m,
      dock,
      trip_end_visit_id,
      num_encounters,
      num_loitering,
      num_fishing,
      high_seas,
      eezs,
      rfmos,
      fishing_hours,
      num_gaps,
      total_gap_hours,
    FROM
      add_visit_end_1),

--SELECT * FROM all_voyages
--------------------------------------
-- -- add vessel info from all_vessels table

-- -- note, depending on specific query, there may be
-- -- additional vessels dropped here that are not
-- -- present in all_vessels_byyear (compare to previous subquery)
-- --------------------------------------
  add_vessel_info AS (
    SELECT * FROM(
    SELECT
      vessel_id,
      year,
      class_confidence AS class_confidence_initial,
      vessel_class AS vessel_class_initial,
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
      --start_latitude,
      --start_longitude,
      num_encounters,
      num_loitering,
      num_fishing,
      high_seas,
      eezs,
      rfmos,
      fishing_hours,
      num_gaps,
      total_gap_hours
    FROM all_voyages )
    JOIN (
      SELECT
        vessel_id,
        ssvid,
        year,
        shipname,
        callsign,
        imo,
        gfw_best_flag AS vessel_flag_best,
        prod_shiptype AS vessel_class_best,
        prod_geartype AS geartype_best
      FROM
        `pipe_production_v20201001.all_vessels_byyear_v2_v20241205`) -- update to pipe3
      USING
        (vessel_id, year)),

-- --------------------------------------
-- -- clean vessel info so consistent for ssvid/year
-- -- using DESC to select non-null value if present
-- --------------------------------------
  clean_info AS(
    SELECT
      vessel_id,
      ssvid,
      year,
      FIRST_VALUE (shipname) OVER (
        PARTITION BY ssvid, year
        ORDER BY shipname DESC) AS shipname,
      FIRST_VALUE (vessel_flag_best) OVER (
        PARTITION BY ssvid, year
        ORDER BY vessel_flag_best DESC) AS vessel_flag_best,
      FIRST_VALUE (callsign) OVER (
        PARTITION BY ssvid, year
        ORDER BY callsign DESC) AS callsign,
      FIRST_VALUE (imo) OVER (
        PARTITION BY ssvid, year
        ORDER BY imo DESC) AS imo,
      FIRST_VALUE (vessel_class_best) OVER (
        PARTITION BY ssvid, year
        ORDER BY vessel_class_best DESC) AS vessel_class_best,
      FIRST_VALUE (geartype_best) OVER (
        PARTITION BY ssvid, year
        ORDER BY geartype_best DESC) AS geartype_best,
      vessel_class_initial,
      CASE
        WHEN class_confidence_initial = "1" THEN "high"
        WHEN class_confidence_initial = "2" THEN "med"
        WHEN class_confidence_initial = "3" THEN "low"
        WHEN class_confidence_initial = "4" THEN "TMT"
        END AS class_confidence_initial,
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
     -- start_latitude,
      --start_longitude,
      num_encounters,
      num_loitering,
      num_fishing,
      high_seas,
      eezs,
      rfmos,
      fishing_hours,
      num_gaps,
      total_gap_hours
    FROM add_vessel_info)

-- --------------------------------------
-- -- pull voyages ending in port visit in POI
-- -- comment this block out if want vessel info/list
-- --------------------------------------
SELECT
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
  --start_latitude,
  --start_longitude,
  num_encounters,
  num_loitering,
  num_fishing,
  high_seas,
  eezs,
  rfmos,
  fishing_hours,
  num_gaps,
  total_gap_hours
FROM clean_info


