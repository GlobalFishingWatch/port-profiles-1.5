--------------------------------------
  -- Query to quantify foreign fishing and carrier vessel visits to
  -- global ports.
  --
  -- there is a need to identify visits that follow significant voyages
  -- meaning voyages on which some activity occured rather than situations where a
  -- vessel leaves a port and then immediately returns. This is currently identified
  -- in several ways...

  -- 1. if the start and end 'port' are the
  --    the same, the voyage must have an
  --    encounter, loitering event, or fishing
  --    event
  -- 2. if the start and end port are different
  --    the voyage must be longer than 1 hour
  -- 3. if the start and end 'port are the
  --    same and there is no event the voyage
  --    is at least 12 hours
  -- 4. voyages where the longest port visit
  --    stop/gap is "long enough" (3
  --    hours currently)

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
-- CREATE TABLE `world-fishing-827.scratch_joef.vessel_list_conakry_2020-22_pipe25` AS

--------------------------------------
WITH

----------------------------------------------------------
-- Define lists of high/med/low confidence for all fishing-related vessels
-- and join each list to voyages within the time period of interest
----------------------------------------------------------

----------------------------------------------------------
-- add in vessels not present on vessel list (ie TMT flagged)
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
  --     `pipe_production_v20201001.all_vessels_byyear_v2_v20241205` -- **** update to pipe 3 when released ******
  --    WHERE
  --     year >= start_year() AND year <= end_year()
  --     AND ssvid IN ("412209169", "412209178", "412209208", "412329514", "412331135", "412331136", "412440647", "412660240", "636013651", "412549434", "416007496", "271073172", "412420882", "412440842", "654000012") -- add additional vessels here
  --    ),

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
      -- `world-fishing-827.gfw_research.fishing_vessels_ssvid_v20231201`
      `pipe_production_v20201001.all_vessels_byyear_v2_v20241205` -- **** update to pipe 3 when released ******
     WHERE
      year >= start_year() AND year <= end_year()
      AND prod_shiptype IN ("fishing")
      AND on_fishing_list_best
     ),

     -- 212632 og
     -- 214485 new

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
      -- IFNULL(IFNULL(best.best_vessel_class, ARRAY_TO_STRING(registry_info.best_known_vessel_class,'')), inferred.inferred_vessel_class_ag) AS gear_type
      prod_geartype AS gear_type
    FROM
      -- `gfw_research.vi_ssvid_byyear_v20231201` AS vi_table -- **** update to pipe 3 when released ******
      `pipe_production_v20201001.all_vessels_byyear_v2_v20241205` AS vi_table
    WHERE
    year >= start_year() AND year <= end_year()
    -- AND on_fishing_list_best -- vi_ssvid approach
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

    -- og 38382
    -- new 32520

-- LOW: MMSI that are on one of our three source fishing lists (registry, neural net, self-reported)
-- but not included in either the med or high list. These are MMSI for which we have minimal
-- or conflicting evidence that they are a fishing vessel.

  low_conf_fishing AS (
    SELECT DISTINCT
      ssvid,
      year,
      -- IFNULL(best.best_flag, ais_identity.flag_mmsi) AS vessel_iso3,
      IFNULL(IFNULL(gfw_best_flag, core_flag), mmsi_flag) AS vessel_iso3,
      '3' as class_confidence,
      'fishing' AS vessel_class,
      -- IFNULL(IFNULL(best.best_vessel_class, ARRAY_TO_STRING(registry_info.best_known_vessel_class,'')), inferred.inferred_vessel_class_ag) AS gear_type
      prod_geartype AS gear_type
    FROM
      -- `gfw_research.vi_ssvid_byyear_v20231201` AS vi_table -- **** update to pipe 3 when released ******
      `pipe_production_v20201001.all_vessels_byyear_v2_v20241205` AS vi_table
    WHERE (
      -- on_fishing_list_nn
      -- OR on_fishing_list_known
      -- OR on_fishing_list_sr
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

    -- og 148029
    -- new 208247

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

-- using allvesselsv2 results in 455,254 fvs (2020-22)
-- orig way using vissvid is 399043

----------------------------------------------------------
-- voyages for all identified fishing vessels
----------------------------------------------------------
  fishing_voyages AS (
    SELECT
      *
    FROM (
      SELECT
        *,
        EXTRACT(year FROM trip_end) AS year
      FROM
      `pipe_production_v20201001.proto_voyages_c2` -- note more voyages using pipe 3 but using 2.5 for consistency --9,861,609
        -- `pipe_ais_v3_alpha_published.voyages_c3` -- 10,024,183
        -- `pipe_ais_v3_alpha_internal.voyages_c2`
      WHERE
        trip_end >= start_date() AND trip_start <= end_date()
        )
    INNER JOIN fishing_vessels
    USING
      (ssvid, year)
      ),

----------------------------------------------------------
-- Define lists of high/med/low confidence bunker vessels
----------------------------------------------------------
  nn_bunkers_high_confidence AS (
    SELECT DISTINCT
      ssvid,
      IFNULL(IFNULL(best.best_flag, registry_info.best_known_flag), ais_identity.flag_mmsi) AS vessel_iso3,
      '1' as class_confidence,
      'bunker' AS vessel_class,
      IFNULL(IFNULL(best.best_vessel_class, ARRAY_TO_STRING(registry_info.best_known_vessel_class,'')), inferred.inferred_vessel_class_ag) AS gear_type,
      activity.first_timestamp,
      activity.last_timestamp
    FROM
      `gfw_research.vi_ssvid_v20241101` -- **** update to pipe 3 when released ******
    WHERE
      TIMESTAMP(activity.first_timestamp) <= end_date() AND
      TIMESTAMP(activity.last_timestamp) >= start_date() AND
      best.best_vessel_class IN (
        "bunker",
        "bunker_or_tanker" )
      AND ssvid IN (
        -- SELECT ssvid
        SELECT identity.ssvid -- pipe25
        -- FROM `pipe_ais_v3_alpha_published.identity_core_v20231001`
        FROM `vessel_database.all_vessels_v20241101` -- pipe25
        WHERE is_bunker = TRUE)
  ),

---------------------------------------------------------------
-- nn bunkers not in vessel database
---------------------------------------------------------------
  nn_bunkers_med_confidence AS (
    SELECT DISTINCT
      ssvid,
      IFNULL(IFNULL(best.best_flag, registry_info.best_known_flag), ais_identity.flag_mmsi) AS vessel_iso3,
      '2' as class_confidence,
      'bunker' AS vessel_class,
      IFNULL(IFNULL(best.best_vessel_class, ARRAY_TO_STRING(registry_info.best_known_vessel_class,'')), inferred.inferred_vessel_class_ag) AS gear_type,
      activity.first_timestamp,
      activity.last_timestamp
    FROM
      `gfw_research.vi_ssvid_v20241101` -- **** update to pipe 3 when released ******
    WHERE
      TIMESTAMP(activity.first_timestamp) <= end_date() AND
      TIMESTAMP(activity.last_timestamp) >= start_date() AND
      best.best_vessel_class IN (
        "bunker",
        "bunker_or_tanker" )
      AND ssvid NOT IN (
              -- SELECT ssvid
        SELECT identity.ssvid -- pipe25
        -- FROM `pipe_ais_v3_alpha_published.identity_core_v20231001`
        FROM `vessel_database.all_vessels_v20241101` -- pipe25
        WHERE is_bunker = TRUE)
  ),

---------------------------------------------------------------
-- List of carriers and bunkers according to vessel registries
---------------------------------------------------------------
  reg_bunkers AS (
    SELECT DISTINCT -- generics for flag and gear as there are duplicates in v database which will duplicate voyages
      -- ssvid, -- pipe3
      identity.ssvid AS ssvid,
      'flag' AS vessel_iso3,
      '3' AS class_confidence,
      'bunker' AS vessel_class,
      'geartype' AS gear_type,
      first_timestamp,
      last_timestamp
    FROM
      -- `pipe_ais_v3_alpha_published.identity_core_v20231001` -- pipe3
      `vessel_database.all_vessels_v20241101`, -- pipe25
      UNNEST(activity) -- pipe25
    WHERE
      TIMESTAMP(first_timestamp) <= end_date() AND
      TIMESTAMP(last_timestamp) >= start_date() AND
      is_bunker = TRUE
      AND identity.ssvid NOT IN (SELECT ssvid FROM nn_bunkers_high_confidence)
      -- AND ssvid NOT IN (SELECT ssvid FROM nn_bunkers_high_confidence) -- pipe3
      AND identity.ssvid NOT IN (SELECT ssvid FROM nn_bunkers_med_confidence)
      -- AND ssvid NOT IN (SELECT ssvid FROM nn_bunkers_med_confidence) -- pipe3
  ),

----------------------------------------------------------
-- combined bunker table info
----------------------------------------------------------
  bunker_vessels AS (
    SELECT
      *
    FROM
      nn_bunkers_high_confidence
    UNION ALL

    SELECT
      *
    FROM
      nn_bunkers_med_confidence
    UNION ALL

    SELECT
      *
    FROM
      reg_bunkers
  ),

----------------------------------------------------------
-- voyages for all identified bunkers
----------------------------------------------------------
  bunker_voyages AS (
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
        bunkers.vessel_iso3,
        bunkers.class_confidence,
        bunkers.vessel_class,
        bunkers.gear_type
      FROM (
        SELECT
          *,
          EXTRACT(year FROM trip_end) AS year
        FROM
          `pipe_production_v20201001.proto_voyages_c2` -- more voyages using pipe 3 but using 2.5 for consistency -- 386,920
          -- `pipe_ais_v3_alpha_published.voyages_c3` -- 395,636
          -- pipe_ais_v3_alpha_internal.voyages_c2
        WHERE
        trip_end >= start_date() AND trip_start <= end_date()
          ) voyages
    INNER JOIN bunker_vessels AS bunkers
      ON voyages.ssvid = bunkers.ssvid
      -- filtering for trips that end within active phase of vessel id
      -- note that if end_date of period of interest is less than 2 months past vi_ssvid date, some voyages will be missed due to GFW dataset timing
        AND voyages.trip_end >= bunkers.first_timestamp AND voyages.trip_end <= bunkers.last_timestamp
        )
        ),

---------------------------------------------------------------
-- List of carriers according to vessel registries - high confidence
---------------------------------------------------------------
  reg_carriers AS (
    SELECT DISTINCT -- generics for flag and gear as there are duplicates in v database which will duplicate voyages
      -- ssvid, -- pipe3
      identity.ssvid AS ssvid,
      'flag' AS vessel_iso3,
      '1' AS class_confidence,
      'carrier' AS vessel_class,
      'geartype' AS gear_type,
      first_timestamp,
      last_timestamp
    FROM
      -- `pipe_ais_v3_alpha_published.identity_core_v20231001` -- pipe3, update to latest v
      `vessel_database.all_vessels_v20241101`, -- pipe25
      UNNEST(activity), -- pipe25
      UNNEST(feature.geartype) AS geartype -- pipe25
    WHERE
      TIMESTAMP(first_timestamp) <= end_date() AND
      TIMESTAMP(last_timestamp) >= start_date() AND
      is_carrier = TRUE AND
      geartype IN ("reefer","specialized_reefer") AND
      identity.n_shipname IS NOT NULL AND
      -- n_shipname IS NOT NULL AND
      identity.flag IS NOT NULL
      -- flag IS NOT NULL
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
    FROM `gfw_research.vi_ssvid_v20241101` -- update to pipe3
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
    FROM `gfw_research.vi_ssvid_v20241101` -- update to pipe3
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
          `pipe_production_v20201001.proto_voyages_c2` -- more voyages using pipe 3 but using 2.5 for consistency --382,571
          -- `pipe_ais_v3_alpha_published.voyages_c3` -- 387,387
          -- pipe_ais_v3_alpha_internal.voyages_c2
        WHERE
        trip_end >= start_date() AND trip_start <= end_date()
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
      bunker_voyages
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

-------------------------------------------------------------------
-- The following bit of code is intended to splice together voyages
-- that pass through the Panama Canal into a single voyage, so as not to inflate assigned
-- port visits to Panama when the vessel is only using the Canal for transit
-------------------------------------------------------------------

-- **** consider whether to add same logic for other straits or canals

------------------------------------------------
-- anchorage ids that represent the Panama Canal

-- JF - note the named_anchorages table was updated without
-- the Panama Canal sublabels so these are saved in a
-- separate table for now
------------------------------------------------
  panama_canal_ids AS (
    SELECT s2id AS anchorage_id
    FROM `world-fishing-827.anchorages.panama_canal_v20231004`
    WHERE sublabel="PANAMA CANAL" -- not strictly necessary as this table filtered to canal already..
  ),

-------------------------------------------------------------------
-- Mark whether start anchorage or end anchorage is in Panama canal
-------------------------------------------------------------------
  is_end_port_panama AS (
    SELECT
    ssvid,
    vessel_id,
    vessel_iso3,
    class_confidence,
    vessel_class,
    gear_type,
    trip_id,
    trip_start,
    trip_end,
    start_iso3,
    start_label,
    end_iso3,
    end_label,
    trip_start_confidence,
    trip_end_confidence,
    trip_start_visit_id,
    trip_end_visit_id,
    trip_start_anchorage_id,
    trip_end_anchorage_id,
    IF (trip_start_anchorage_id IN (
      SELECT anchorage_id FROM panama_canal_ids),
      TRUE, FALSE) current_start_is_panama,
    IF (trip_end_anchorage_id IN (
      SELECT anchorage_id FROM panama_canal_ids),
      TRUE, FALSE) current_end_is_panama,
    FROM named_voyages
  ),

------------------------------------------------
-- Add information about
-- whether previous and next ports are in Panama
------------------------------------------------
  add_prev_next_port AS (
    SELECT
    *,
    IFNULL (
      LAG (trip_start, 1) OVER (
        PARTITION BY ssvid
        ORDER BY trip_start ASC ),
      TIMESTAMP ("2000-01-01") ) AS prev_trip_start,
    -- note as structured the prev trip id will be null for each vessels' first voyage in the time period
    LAG (trip_id, 1) OVER (
      PARTITION BY ssvid
      ORDER BY trip_start ASC ) AS prev_trip_id,
    IFNULL (
      LEAD (trip_end, 1) OVER (
        PARTITION BY ssvid
        ORDER BY trip_start ASC ),
      TIMESTAMP ("2100-01-01") ) AS next_trip_end,
    LAG (current_end_is_panama, 1) OVER (
      PARTITION BY ssvid
      ORDER BY trip_start ASC ) AS prev_end_is_panama,
    LEAD (current_end_is_panama, 1) OVER (
      PARTITION BY ssvid
      ORDER BY trip_start ASC ) AS next_end_is_panama,
    LAG (current_start_is_panama, 1) OVER(
      PARTITION BY ssvid
      ORDER BY trip_start ASC ) AS prev_start_is_panama,
    LEAD (current_start_is_panama, 1) OVER(
      PARTITION BY ssvid
      ORDER BY trip_start ASC ) AS next_start_is_panama,
    FROM is_end_port_panama
  ),

---------------------------------------------------------------------------------
-- Mark the start and end of the block. The start of the block is the anchorage
-- just before Panama canal, and the end of the block is the anchorage just after
-- Panama canal (all consecutive trips within Panama canal will be ignored later).
-- If there is no Panama canal involved in a trip, the start/end of the block are
-- the trip start/end of that trip.

-- note there are some trips in which the arrival port is diff than the next departure
-- (ie one is a canal port and the other not), which makes just classifying based on
-- current start and end fail - this query requires both current and prev start/end
---------------------------------------------------------------------------------
  block_start_end AS (
    SELECT
    *,
          IF (current_start_is_panama AND prev_end_is_panama, NULL, trip_start) AS block_start,
          IF (current_end_is_panama AND next_start_is_panama, NULL, trip_end) AS block_end
    FROM add_prev_next_port
  ),

-------------------------------------------
-- Find the closest non-Panama ports
-- by looking ahead and back of the records
-------------------------------------------
  look_back_and_ahead AS (
    SELECT
    * EXCEPT(block_start, block_end),
    LAST_VALUE (block_start IGNORE NULLS) OVER (
      PARTITION BY ssvid
      ORDER BY trip_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS block_start,
    FIRST_VALUE (block_end IGNORE NULLS) OVER (
      PARTITION BY ssvid
      ORDER BY trip_start
      ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS block_end
    FROM block_start_end
  ),

-------------------------------------------------------------------
-- Within a block, all trips will have the same information
-- about their block (start / end of the block, anchorage start/end)
-------------------------------------------------------------------
  blocks_to_be_collapsed_down AS (
    SELECT
    ssvid,
    block_start,
    block_end,
    FIRST_VALUE (vessel_id) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS vessel_id,
    FIRST_VALUE (vessel_iso3) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS vessel_iso3,
    FIRST_VALUE (class_confidence) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS class_confidence,
    FIRST_VALUE (vessel_class) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS vessel_class,
    FIRST_VALUE (gear_type) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS gear_type,
    FIRST_VALUE (trip_id) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS trip_id,
    FIRST_VALUE (start_iso3) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS start_iso3,
    FIRST_VALUE (start_label) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS start_label,
    FIRST_VALUE (end_iso3) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_end DESC) AS end_iso3,
    FIRST_VALUE (end_label) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_end DESC) AS end_label,
    FIRST_VALUE (trip_start_visit_id) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS trip_start_visit_id,
    FIRST_VALUE (trip_end_visit_id) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_end DESC) AS trip_end_visit_id,
    FIRST_VALUE (trip_start_anchorage_id) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS trip_start_anchorage_id,
    FIRST_VALUE (trip_end_anchorage_id) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_end DESC) AS trip_end_anchorage_id,

    FIRST_VALUE (trip_start_confidence) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS trip_start_confidence,
    FIRST_VALUE (trip_end_confidence) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_end DESC) AS trip_end_confidence,
    FROM look_back_and_ahead
  ),

---------------------------------------------------------------------
-- Blocks get collapsed down to one row, which means a block of trips
-- becomes a complete trip
---------------------------------------------------------------------
  updated_pan_voyages AS (
    SELECT
      ssvid,
      vessel_id,
      vessel_iso3,
      class_confidence,
      vessel_class,
      gear_type,
      trip_id,
      block_start AS trip_start,
      block_end AS trip_end,
      start_iso3,
      start_label,
      end_iso3,
      end_label,
      trip_start_visit_id,
      trip_end_visit_id,
      trip_start_anchorage_id,
      trip_end_anchorage_id,
      trip_start_confidence,
      trip_end_confidence,
      CASE -- adding flag if voyages is collapsed bc of PAN crossing
        WHEN count(*) > 1 THEN 1
        WHEN count(*) = 1 THEN 0
        END AS pan_crossing
    FROM blocks_to_be_collapsed_down
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
  ),

--------------------------------------
-- Identify how many encounters occurred on each voyage
-- both pipe 2.5 and 3 approaches here, note almost double the encounters in 3 vs 2 (577K vs 300K for 2020-22)
--------------------------------------

-- this seems like a cleaner approach for num_encounters, but runtime is way too long (i may/probably have something wrong)
-- may revisit but for now using two-subquery approach below

-- pipe 3
-- num_encounters AS (
--   SELECT
--     vessel_id,
--     trip_id,
--     COUNT(*) AS num_encounters
--   FROM (
--     SELECT
--       vessel_1_id,
--       vessel_2_id,
--       start_time,
--       end_time
--     FROM `pipe_ais_v3_alpha_published.encounters`) enc
--   INNER JOIN (
--     SELECT
--       vessel_id,
--       trip_id,
--       trip_start,
--       trip_end
--     FROM
--       updated_pan_voyages) voyages
--   ON
--     start_time BETWEEN trip_start AND trip_end
--     AND(voyages.vessel_id IN (enc.vessel_1_id, enc.vessel_2_id) )
--     GROUP BY
--        vessel_id, trip_id
--     ) select * from num_encounters  /*

# using two subqueries:
# first union encounters into table with one column of encounters (ie, 2 rows per encounter bc 2 vessel ids)
--   all_encounters AS (
--     SELECT
--       encounter_id,
--       vessel_1_id AS vessel_id,
--       start_time,
--       end_time,
--     FROM `pipe_ais_v3_alpha_published.encounters`
--     WHERE start_time >= TIMESTAMP(DATE_ADD(DATE(start_date()), INTERVAL -3 YEAR)) # pull encounters x years before period of interest

--     UNION ALL

--     SELECT
--       encounter_id,
--       vessel_2_id as vessel_id,
--       start_time,
--       end_time,
--     FROM `pipe_ais_v3_alpha_published.encounters`
--     WHERE start_time >= TIMESTAMP(DATE_ADD(DATE(start_date()), INTERVAL -3 YEAR)) # pull encounters x years before period of interest
--   ),

-- # inner join encounter vessel_ids to voyage vessel_ids, filter by time and group to sum per trip_id
--   num_encounters AS (
--     SELECT
--       vessel_id,
--       trip_id,
--       COUNT(*) AS num_encounters
--     FROM (
--       SELECT
--         *
--       FROM
--         all_encounters)
--     INNER JOIN (
--       SELECT
--         vessel_id,
--         trip_id,
--         trip_start,
--         trip_end
--       FROM
--         updated_pan_voyages)
--     USING
--       (vessel_id)
--     WHERE
--       start_time BETWEEN trip_start
--       AND trip_end
--     GROUP BY
--       vessel_id, trip_id
--       ),

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
      updated_pan_voyages)
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
      updated_pan_voyages) b
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
        updated_pan_voyages)
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
        updated_pan_voyages)
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
      updated_pan_voyages AS a
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
        1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32),

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
        add_gaps)
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
      -- `pipe_ais_v3_alpha_published.vessel_info` ), -- pipe3
      `pipe_production_v20201001.vessel_info` ), -- pipe2.5

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
        trip_end) >= start_year()
      AND EXTRACT(YEAR
      FROM
        trip_end) <= end_year()
      AND vessel_id IN (
      SELECT
        vessel_id
      FROM
        poor_vessel_ids
      WHERE
        poor_id IS FALSE) ),

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
        ROUND(start_lon, 2) AS start_longitude
      FROM
        -- `pipe_ais_v3_alpha_published.port_visits` -- pipe3
        `pipe_production_v20201001.proto_port_visits` -- pipe2.5
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
          -- pipe_ais_v3_alpha_published.port_visits, -- pipe3
          `pipe_production_v20201001.proto_port_visits`,
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
      num_gaps,
      total_gap_hours,
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
      --AND ssvid NOT IN ("334455660","100001001","721","23456","345","100000016","100000008") -- wrong MMSI number associate with Peru
  # filter for ports of interest
      --AND end_port_label IN ("SUBIC", "SUBIC BAY VICINITY", "SEATRIAL", "PH SUBIC", "W IN SUBIC BAY ONLY","NAVOTAS", "MANILA", "NIUGAN") -- using parameters set at top of code for port and iso
      AND end_port_label IN UNNEST(port_label())
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
      fishing_hours,
      num_gaps,
      total_gap_hours
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
        `pipe_production_v20201001.all_vessels_byyear_v2_v20241205`) -- update to pipe3
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
      fishing_hours,
      num_gaps,
      total_gap_hours
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
  fishing_hours,
  num_gaps,
  total_gap_hours
FROM clean_info

--------------------------------------
-- pull vessel list entering POI
-- comment this block out if want voyages
--------------------------------------
  -- SELECT
  --   DISTINCT
  --   ssvid,
  --   year,
  --   shipname,
  --   vessel_flag_best,
  --   callsign,
  --   imo,
  --   vessel_class_best,
  --   geartype_best,
  --   vessel_class_initial,
  --   class_confidence_initial,
  --   count(*) as visits_in_timeperiod,
  --   count(num_encounters) AS total_encounters,
  --   count(num_loitering) AS total_loitering,
  --   count(num_fishing) AS total_fishing
  -- FROM clean_info
  -- GROUP BY 1,2,3,4,5,6,7,8,9,10

/*
*/
