  -- Query to quantify foreign fishing and carrier vessel visits to
  --  ports of interest.
  --  Adapted from Joe Fader port profile code by Max Schofield 17Oct2024
  --
  --  NOTE This script doesn't have the Panama canal voyage connector to try have the AIS coverage run in the same script
  --  NOTE this script does not include bunker vessel which could be PSMA relevant
  --
  -- This code starts with identifying vessels which are relevant for carrier and fishing vessels
  -- Then identifying foreign flagged voyages to the focal point
  -- Then identifying the activity (fishing, loitering, encounters)
  -- Then identifying AIS coverage on the voyage
  --


## set time frame of interest
CREATE TEMP FUNCTION  start_date() AS (TIMESTAMP({start_date}));
CREATE TEMP FUNCTION  end_date() AS (TIMESTAMP({end_date}));
CREATE TEMP FUNCTION  year() AS ({year});
CREATE TEMP FUNCTION  start_year() AS ({start_year});
CREATE TEMP FUNCTION  end_year() AS ({end_year});

## set port and country (iso) of interest
CREATE TEMP FUNCTION port_label()
RETURNS ARRAY<STRING> AS (
    [{port_label}]
);
CREATE TEMP FUNCTION port_iso() AS (CAST({port_iso} AS STRING));

CREATE TABLE {temp_table}
OPTIONS (
  expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
) AS

WITH

----------------------------------------------------------
-- add in vessels missing from analysis e.g. identified by TMT QA or local partner insights
----------------------------------------------------------

  -- additional_vessels AS(
  --   SELECT DISTINCT
  --     ssvid,
  --     year,
  --     IFNULL(IFNULL(gfw_best_flag, core_flag), mmsi_flag) AS vessel_iso3,
  --     '4' as class_confidence,
  --     'added_TMT' AS vessel_class,
  --     prod_geartype AS gear_type
  --    FROM
  --     `pipe_production_v20201001.all_vessels_byyear_v2_v20231201` -- **** update to pipe 3 when released ******
  --    WHERE
  --     year <= year()
  --     AND ssvid IN ("412209169", "412209178", "412209208", "412329514", "412331135", "412331136", "412440647", "412660240", "636013651", "412549434", "416007496", "271073172", "412420882", "412440842", "654000012") -- add additional vessels here
  --    ),

----------------------------------------------------------
-- Define lists of high/med/low confidence for all fishing-related vessels
-- and join each list to voyages within the time period of interest
----------------------------------------------------------

----------------------------------------------------------
-- high/med/low confidence fishing vessels
----------------------------------------------------------

-- HIGH: MMSI in the fishing_vessels_ssvid table.
-- These are vessels on our best fishing list and that have reliable AIS data

  high_conf_fishing AS (
     SELECT DISTINCT
       ssvid,
       year,
      --  best_flag AS vessel_iso3,
      IFNULL(IFNULL(gfw_best_flag, core_flag), mmsi_flag) AS vessel_iso3,
       '1' as class_confidence,
       'fishing' AS vessel_class,
       prod_geartype AS gear_type
     FROM
      -- `pipe_production_v20201001.all_vessels_byyear_v2_v20240401` -- **** update to pipe 3 when released ****** 187112
      `pipe_ais_v3_published.product_vessel_info_summary` -- pipe 3 v is >100K more vessels... 292042
     WHERE
      year >= start_year() AND year <= end_year()
      AND prod_shiptype IN ("fishing")
      AND on_fishing_list_best
     ),

-- MED: All MMSI on our best fishing list not included in the high category.
-- These are likely fishing vessels that primarily get excluded due to data issues
-- (e.g. spoofing, offsetting, low activity)

  med_conf_fishing AS (
    SELECT DISTINCT
      ssvid,
      year,
      -- IFNULL(best.best_flag, ais_identity.flag_mmsi) AS vessel_iso3,
      IFNULL(IFNULL(gfw_best_flag, core_flag), mmsi_flag) AS vessel_iso3,
      '2' as class_confidence,
      'fishing' AS vessel_class,
      prod_geartype AS gear_type
    FROM
      `pipe_ais_v3_published.product_vessel_info_summary` AS vi_table
    WHERE
    year >= start_year() AND year <= end_year()
    AND prod_shiptype IN ("fishing")
    AND on_fishing_list_sr
    AND
    -- anti join to get vessels that don't match high conf list by ssvid or year:
    NOT EXISTS (
      SELECT ssvid, year
      FROM high_conf_fishing
      WHERE vi_table.ssvid = high_conf_fishing.ssvid AND vi_table.year = high_conf_fishing.year
    )
    ),


-- LOW: MMSI that are on one of our three source fishing lists (registry, neural net, self-reported)
-- but not included in either the med or high list. These are MMSI for which we have minimal
-- or conflicting evidence that they are a fishing vessel.

   low_conf_fishing AS (
    SELECT DISTINCT
      ssvid,
      year,
      IFNULL(IFNULL(gfw_best_flag, core_flag), mmsi_flag) AS vessel_iso3,
      '3' as class_confidence,
      'fishing' AS vessel_class,
      prod_geartype AS gear_type
    FROM
      `pipe_ais_v3_published.product_vessel_info_summary` AS vi_table
    WHERE (
      prod_shiptype = 'fishing'
      OR prod_shiptype = 'discrepancy'
      OR potential_fishing
      OR on_fishing_list_sr
      )
    AND year >= start_year() AND year <= end_year()
    -- anti joins to get vessels that don't match high/med conf list by ssvid or year:
    AND NOT EXISTS (
      SELECT ssvid, year
      FROM high_conf_fishing
      WHERE vi_table.ssvid = high_conf_fishing.ssvid AND vi_table.year = high_conf_fishing.year
    )
    AND NOT EXISTS (
      SELECT ssvid, year
      FROM med_conf_fishing
      WHERE vi_table.ssvid = med_conf_fishing.ssvid AND vi_table.year = med_conf_fishing.year
    )
    ),


----------------------------------------------------------
-- combined fishing vessel table info
----------------------------------------------------------
  fishing_vessels AS (
    -- SELECT
    --   *
    -- FROM
    --   additional_vessels
    -- UNION ALL

    SELECT
      *
    FROM
      high_conf_fishing
    UNION ALL

    SELECT
      *
    FROM
      med_conf_fishing
    UNION ALL

    SELECT
      *
    FROM
      low_conf_fishing
  ),
----------------------------------------------------------
-- voyages for all identified fishing vessels
----------------------------------------------------------
fishing_voyages AS (
    SELECT
      voyages.ssvid,
      voyages.year,
      voyages.vessel_id,
      voyages.trip_start,
      voyages.trip_end,
      voyages.trip_start_anchorage_id,
      voyages.trip_end_anchorage_id,
      voyages.trip_start_visit_id,
      voyages.trip_end_visit_id,
      voyages.trip_start_confidence,
      voyages.trip_end_confidence,
      voyages.trip_id,
      fv.vessel_iso3,
      fv.class_confidence,
      fv.vessel_class,
      fv.gear_type
    FROM (
      SELECT
        *,
        EXTRACT(year FROM trip_end) AS year
      FROM
         `pipe_ais_v3_internal.voyages_c2`
      WHERE
        trip_end BETWEEN start_date() AND end_date()
        AND trip_start < end_date()
        ) voyages
    INNER JOIN fishing_vessels fv
    USING
      (ssvid, year)
      ),


---------------------------------------------------------------
-- List of carriers according to vessel registries - high confidence
---------------------------------------------------------------
  reg_carriers AS (
    SELECT DISTINCT -- generics for flag and gear as there are duplicates in v database which will duplicate voyages
      ssvid,
      'flag' AS vessel_iso3,
      '1' AS class_confidence,
      'carrier' AS vessel_class,
      'geartype' AS gear_type,
      first_timestamp,
      last_timestamp
    FROM
      `pipe_ais_v3_published.identity_core`
    WHERE
      TIMESTAMP(first_timestamp) <= end_date() AND
      TIMESTAMP(last_timestamp) >= start_date() AND
      is_carrier = TRUE AND
      geartype IN ("reefer","specialized_reefer") AND
      n_shipname IS NOT NULL AND
      flag IS NOT NULL
  ),

---------------------------------------------------------------
-- nn carriers capable of transshipping at sea - not included in is_carrier
---------------------------------------------------------------
  nn_carriers_med_confidence AS (
    SELECT DISTINCT
      ssvid,
      best.best_flag AS vessel_iso3,
      '2' AS class_confidence,
      'carrier' AS vessel_class,
      best.best_vessel_class AS gear_type,
      activity.first_timestamp,
      activity.last_timestamp
    FROM
      `pipe_ais_v3_published.vi_ssvid_byyear_v`
    WHERE
      TIMESTAMP(activity.first_timestamp) <= end_date() AND
      TIMESTAMP(activity.last_timestamp) >= start_date() AND
      best.best_vessel_class IN ("specialized_reefer", "reefer") AND
      ssvid NOT IN(SELECT ssvid FROM reg_carriers)
  ),

---------------------------------------------------------------
-- other carriers not included in is_carrier
---------------------------------------------------------------
  nn_carriers_low_confidence AS (
    SELECT DISTINCT
      ssvid,
      best.best_flag AS vessel_iso3,
      '3' AS class_confidence,
      'carrier' AS vessel_class,
      best.best_vessel_class AS gear_type,
      activity.first_timestamp,
      activity.last_timestamp
    FROM
      `pipe_ais_v3_published.vi_ssvid_byyear_v`
    WHERE
      TIMESTAMP(activity.first_timestamp) <= end_date() AND
      TIMESTAMP(activity.last_timestamp) >= start_date() AND
      best.best_vessel_class IN ("container_reefer", "cargo_or_reefer") AND
      ssvid NOT IN (SELECT ssvid FROM reg_carriers) AND
      ssvid NOT IN (SELECT ssvid FROM nn_carriers_med_confidence)
  ),

----------------------------------------------------------
-- combined carrier table info
----------------------------------------------------------
  carrier_vessels AS (
    SELECT
      *
    FROM
      reg_carriers
    UNION ALL

    SELECT
      *
    FROM
      nn_carriers_med_confidence
    UNION ALL

    SELECT
      *
    FROM
      nn_carriers_low_confidence
  ),

----------------------------------------------------------
-- voyages for all identified carriers
----------------------------------------------------------
  carrier_voyages AS (
    SELECT
      *
    FROM (
      SELECT DISTINCT
        voyages.ssvid,
        voyages.year,
        voyages.vessel_id,
        voyages.trip_start,
        voyages.trip_end,
        voyages.trip_start_anchorage_id,
        voyages.trip_end_anchorage_id,
        voyages.trip_start_visit_id,
        voyages.trip_end_visit_id,
        voyages.trip_start_confidence,
        voyages.trip_end_confidence,
        voyages.trip_id,
        carriers.vessel_iso3,
        carriers.class_confidence,
        carriers.vessel_class,
        carriers.gear_type
      FROM (
        SELECT
          *,
          EXTRACT(year FROM trip_end) AS year
        FROM
         `pipe_ais_v3_internal.voyages_c2`
      WHERE
        trip_end BETWEEN start_date() AND end_date()
        AND trip_start < end_date()
          ) voyages
    INNER JOIN carrier_vessels AS carriers
      ON voyages.ssvid = carriers.ssvid
      -- filtering for trips that end within active phase of vessel id
      -- note that if end_date of period of interest is less than 2 months past vi_ssvid date, some voyages will be missed due to GFW dataset timing
        AND voyages.trip_end >= carriers.first_timestamp AND voyages.trip_end <= carriers.last_timestamp
        )
        ),

--------------------------------------
-- Combine fishing, bunker, and carrier voyages
--------------------------------------
  initial_voyages AS (
    SELECT
      *
    FROM
      fishing_voyages
    UNION ALL

    SELECT
      *
    FROM
      carrier_voyages
  ),

--------------------------------------
-- Remove any duplicates between categories (fishing, bunker, carrier) by
-- selecting duplicate vessel with the higher confidence level
-- note if vessels have the same conf level, (arbitrarily) selecting fishing, then carrier, then bunker...
--------------------------------------
  total_voyages AS(
    SELECT DISTINCT
      year,
      ssvid,
      vessel_id,
      FIRST_VALUE (vessel_iso3) OVER (
        PARTITION BY trip_id
        ORDER BY class_confidence ASC, vessel_class DESC) AS vessel_iso3,
      FIRST_VALUE (class_confidence) OVER (
        PARTITION BY trip_id
        ORDER BY class_confidence ASC, vessel_class DESC) AS class_confidence,
      FIRST_VALUE (vessel_class) OVER (
        PARTITION BY trip_id
        ORDER BY class_confidence ASC, vessel_class DESC) AS vessel_class,
      FIRST_VALUE (gear_type) OVER (
        PARTITION BY trip_id
        ORDER BY class_confidence ASC, vessel_class DESC) AS gear_type,
      trip_id,
      trip_start,
      trip_end,
      trip_start_anchorage_id,
      trip_end_anchorage_id,
      trip_start_visit_id,
      trip_end_visit_id,
      trip_start_confidence,
      trip_end_confidence,
  FROM initial_voyages
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
-- Identify how many encounters occurred on each voyage
--------------------------------------

num_encounters AS (
  SELECT
    vessel_id,
    trip_id,
    COUNT(*) AS num_encounters
  FROM (
    SELECT
      vessel_id,
      event_start,
      event_end
    FROM `pipe_ais_v3_published.product_events_encounter_v*`) enc
    INNER JOIN (
      SELECT
        vessel_id,
        trip_id,
        trip_start,
        trip_end
      FROM
        named_voyages) voyages
    USING (vessel_id)
      WHERE event_start BETWEEN trip_start AND trip_end
    GROUP BY
       vessel_id, trip_id
    ),

--------------------------------------
-- Identify how many loitering events occurred on each voyage
--------------------------------------
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
        `pipe_ais_v3_published.product_events_loitering_v*`
      WHERE
        seg_id IN (
        SELECT
          seg_id
        FROM
          `pipe_ais_v3_published.segs_activity`
        WHERE
          good_seg IS TRUE
          AND overlapping_and_short IS FALSE)
          AND SAFE_CAST(JSON_QUERY(event_info,"$.avg_distance_from_shore_km") AS FLOAT64) > 37.04 -- to match 20 nm rule used in map
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
      vessel_id, trip_id
      ),

--------------------------------------
-- Identify how many fishing events occurred on each voyage
--------------------------------------

  num_fishing AS(
    SELECT
      vessel_id,
      trip_id,
      STRING_AGG(DISTINCT high_seas, ', ') as high_seas,
      STRING_AGG(DISTINCT rfmo,', ') as rfmos,
      STRING_AGG(DISTINCT ISO_TER1,', ') as eezs,
      COUNT(*) AS num_fishing,
      SUM(TIMESTAMP_DIFF(event_end, event_start, SECOND) / 3600) AS fishing_hours,
    FROM (
      SELECT
        vessel_id,
        event_start,
        event_end,
        high_seas,
        rfmo,
        eez,
        ISO_TER1,
      FROM
        `pipe_ais_v3_published.product_events_fishing_v*`
      LEFT JOIN UNNEST (regions_mean_position.high_seas) AS high_seas
      LEFT JOIN UNNEST (regions_mean_position.rfmo) AS rfmo
      LEFT JOIN UNNEST (regions_mean_position.eez) AS eez
      LEFT JOIN (SELECT MRGID, ISO_TER1 FROM `world-fishing-827.ocean_shapefiles_all_purpose.marine_regions_v11`) ON (eez=CAST(MRGID AS string)))
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
      1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21),

--------------------------------------
-- label voyage if it had at least
-- one loitering event
--------------------------------------
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
      1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23),

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
      1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29),

--------------------------------------
-- label if voyages represents a 'real' voyage
-- 'real': TRUE if the start and end
-- 'port' are different and the voyage
-- is longer than x hour
-- OR
-- if the start end end 'port' are the
-- the same, but the voyage had an
-- encounter, loitering event, or fishing event
-- and is > x h
-- OR
-- if the start and end 'port are the
-- same, but the voyage is at least x
-- hours
-- FALSE: all other voyages
--------------------------------------
  initial_true_voyages AS (
    SELECT
      *
    FROM (
      SELECT
        *,
        CASE
          WHEN CONCAT(start_label, start_iso3) != CONCAT(end_label, end_iso3) AND TIMESTAMP_DIFF(trip_end, trip_start, SECOND)/3600 > 1 THEN TRUE
          WHEN CONCAT(start_label, start_iso3) = CONCAT(end_label, end_iso3)
          AND (had_encounter IS TRUE
          OR had_loitering IS TRUE
          OR had_fishing IS TRUE)
          AND TIMESTAMP_DIFF(trip_end, trip_start, SECOND)/3600 > 2 THEN TRUE
          WHEN CONCAT(start_label, start_iso3) = CONCAT(end_label, end_iso3) AND TIMESTAMP_DIFF(trip_end, trip_start, SECOND)/3600 > 3 THEN TRUE
        ELSE
        FALSE
      END
        AS true_voyage
      FROM
        add_fishing)
    WHERE
      true_voyage IS TRUE ),

--------------------------------------
-- Identify vessel ids with less than
-- one position per two days and
-- no identity information.
--
-- Justification: there are some
-- vessels that have vessel_ids with
-- no identity information, but which
-- represent a quality track.
--------------------------------------
  poor_vessel_ids AS (
    SELECT
      *,
    IF
      (SAFE_DIVIDE(pos_count,TIMESTAMP_DIFF(last_timestamp, first_timestamp, DAY)) < 0.5
        AND (shipname.value IS NULL
          AND callsign.value IS NULL
          AND imo.value IS NULL), TRUE, FALSE) AS poor_id
    FROM
      `pipe_ais_v3_published.vessel_info` ),

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
      initial_true_voyages
    WHERE
      EXTRACT(YEAR
      FROM
        trip_end) >= year()
      AND EXTRACT(YEAR
      FROM
        trip_end) <= year()
      AND vessel_id IN (
      SELECT
        vessel_id
      FROM
        poor_vessel_ids
      WHERE
        poor_id IS FALSE) ),

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

--------------------------------------
-- Add end timestamp to end port visits
--------------------------------------
  add_visit_end_2 AS (
    SELECT
      *
    FROM
      add_visit_end_1
    INNER JOIN (
      SELECT
        visit_id AS trip_end_visit_id,
        start_timestamp AS start_portvisit_timestamp,
        end_timestamp AS end_portvisit_timestamp,
        ROUND(start_lat, 2) AS start_latitude,
        ROUND(start_lon, 2) AS start_longitude,
        ROUND(end_lat, 2) AS end_latitude,
        ROUND(end_lon, 2) AS end_longitude
      FROM
        `pipe_ais_v3_published.port_visits`
      WHERE
        EXTRACT(YEAR
        FROM
          end_timestamp) >= start_year()
      )
    USING
      (trip_end_visit_id)
      ),

--------------------------------------
-- List of visits that have at least a
-- minimum event duration
-- Used to remove visits where the port
-- stop or port gap are not long enough
--------------------------------------
  has_long_enough_event AS (
    SELECT
      trip_end_visit_id,
      MAX(event_duration_hr) AS longest_event
    FROM (
      SELECT
        *,
        TIMESTAMP_DIFF(next_timestamp, timestamp, SECOND)/3600 AS event_duration_hr
      FROM (
        SELECT
          visit_id AS trip_end_visit_id,
          event_type,
          timestamp,
          LEAD(timestamp) OVER(PARTITION BY visit_id ORDER BY timestamp) AS next_timestamp
        FROM
        `pipe_ais_v3_published.port_visits`,
          UNNEST(events)
        WHERE
          EXTRACT(YEAR
          FROM
            end_timestamp) >= start_year()
          AND event_type NOT IN ('PORT_ENTRY') )
      WHERE
        event_type IN ('PORT_STOP_BEGIN',
          'PORT_GAP_BEGIN') )
    GROUP BY
      1
    HAVING
      longest_event > 0 ),

--------------------------------------
-- all qualifying voyages
--------------------------------------
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
      start_portvisit_timestamp,
      end_portvisit_timestamp,
      ROUND(TIMESTAMP_DIFF(end_portvisit_timestamp, start_portvisit_timestamp, minute)/60/24, 1) AS port_event_duration_days,
      distance_from_shore_m,
      dock,
      trip_end_visit_id,
      start_latitude,
      start_longitude,
      num_encounters,
      num_loitering,
      num_fishing,
      high_seas,
      eezs,
      rfmos,
      fishing_hours,
    FROM
      add_visit_end_2
    WHERE
      trip_end_visit_id IN (
      SELECT
        trip_end_visit_id
      FROM
        has_long_enough_event)
        ),

--------------------------------------
-- label EU boats
--------------------------------------
  is_eu_iso3 AS (
    SELECT
      DISTINCT iso3
    FROM
      `world-fishing-827.gfw_research.country_codes`
    WHERE
      is_EU ),

--------------------------------------
-- Only include truly foreign visits - EU visiting EU is not foreign
-- and select port(s) of interest
--------------------------------------
  foreign_voyages AS (
    SELECT
      *
    FROM
      all_voyages
    WHERE
      end_port_iso3 != vessel_iso3
      AND NOT (end_port_iso3 IN (
        SELECT
          iso3
        FROM
          is_eu_iso3)
        AND vessel_iso3 IN (
        SELECT
          iso3
        FROM
          is_eu_iso3))
  # filter for ports of interest
      AND end_port_label IN UNNEST(port_label()) -- using parameters set at top of code for port and iso
      AND end_port_iso3 IN (port_iso())
      ),

--------------------------------------
-- add vessel info from all_vessels table

-- note, depending on specific query, there may be
-- additional vessels dropped here that are not
-- present in all_vessels_byyear (compare to previous subquery)
--------------------------------------
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
      start_latitude,
      start_longitude,
      num_encounters,
      num_loitering,
      num_fishing,
      high_seas,
      eezs,
      rfmos,
      fishing_hours
    FROM foreign_voyages )
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
        `pipe_ais_v3_published.product_vessel_info_summary_v20240501`)
      USING
        (vessel_id, year)),

--------------------------------------
-- clean vessel info so consistent for ssvid/year
-- using DESC to select non-null value if present
--------------------------------------
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
      start_latitude,
      start_longitude,
      num_encounters,
      num_loitering,
      num_fishing,
      high_seas,
      eezs,
      rfmos,
      fishing_hours
    FROM add_vessel_info)

--------------------------------------
-- pull voyages ending in port visit in POI
-- comment this block out if want vessel info/list
--------------------------------------
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
  start_latitude,
  start_longitude,
  num_encounters,
  num_loitering,
  num_fishing,
  high_seas,
  eezs,
  rfmos,
  fishing_hours
FROM clean_info
WHERE
  vessel_flag_best != port_iso()
