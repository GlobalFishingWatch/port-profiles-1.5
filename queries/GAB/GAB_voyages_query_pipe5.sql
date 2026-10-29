--------------------------------------
  -- Query to quantify foreign fishing, bunker, and carrier vessel visits and unique vessels visiting Gabon.
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

## set time frame of interest
CREATE TEMP FUNCTION  start_date() AS (TIMESTAMP({start_date}));
CREATE TEMP FUNCTION  end_date() AS (TIMESTAMP({end_date}));
CREATE TEMP FUNCTION  prev_visit_search_date() AS (TIMESTAMP({prev_visit_search_date}));
CREATE TEMP FUNCTION  start_year() AS ({start_year});
CREATE TEMP FUNCTION  end_year() AS ({end_year});

  ## voyages will be truncated to this end timestamp, if needed
--CREATE TEMP FUNCTION  end_date() AS (TIMESTAMP('2024-12-31 23:59:59 UTC'));

## set port and country (iso) of interest
-- CREATE TEMP FUNCTION port_label() AS (CAST("CONAKRY" AS STRING));
CREATE TEMP FUNCTION port_iso() AS (CAST({port_iso} AS STRING));

CREATE TEMP FUNCTION extra_ids()
RETURNS ARRAY<STRING> AS (
    [{missing_ssvids}]
);

## save table
-- CREATE OR REPLACE TABLE {voyage_table}
--OPTIONS (
--  expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
--)
-- AS
--------------------------------------
WITH

----------------------------------------------------------
-- Define lists of high/med/low confidence for all fishing-related vessels
-- and join each list to voyages within the time period of interest
----------------------------------------------------------

----------------------------------------------------------
-- add in vessels not present on vessel list (ie TMT flagged)
----------------------------------------------------------

additional_vessels AS(
 SELECT DISTINCT
   ssvid,
   year,
   IFNULL(IFNULL(gfw_best_flag, registry_flag), self_reported_mmsi_flag) AS vessel_iso3,
   '4' as class_confidence,
   'added_TMT' AS vessel_class,
   prod_geartype AS gear_type
  FROM
    `global-fishing-watch.pipe_ais_identity_v5_published.product_vessel_info_summary`
  WHERE
   year >= start_year() AND year <= end_year()
  AND ssvid IN UNNEST(extra_ids()) -- add additional vessels here
  ),

----------------------------------------------------------
-- high/med/low confidence fishing vessels
----------------------------------------------------------

-- HIGH: FVs according to product, rf, AND with high source agreement
 high_conf_fishing AS (
     SELECT DISTINCT
      ssvid,
      year,
      gfw_best_flag AS vessel_iso3,
      '1' as class_confidence,
      'fishing' AS vessel_class,
      prod_geartype AS gear_type
     FROM
      `global-fishing-watch.pipe_ais_identity_v5_published.product_vessel_info_summary`
     WHERE
      year >= start_year() AND year <= end_year()
      AND prod_shiptype IN ("fishing")
      AND vessel_class_source_agreement IN ("high")
      AND fishing_source_agreement IN ("high")
      AND on_fishing_list_rf
      AND NOT registry_is_carrier AND NOT registry_is_bunker
     ),

-- MED: product FVs that are also rf FV or on a registry
  med_conf_fishing AS (
    SELECT DISTINCT
      ssvid,
      year,
      gfw_best_flag AS vessel_iso3,
      '2' as class_confidence,
      'fishing' AS vessel_class,
      prod_geartype AS gear_type
    FROM
      `global-fishing-watch.pipe_ais_identity_v5_published.product_vessel_info_summary` AS vi_table
    WHERE
      year >= start_year() AND year <= end_year()
      AND prod_shiptype IN ("fishing")
      AND (on_fishing_list_rf OR ssvid IN (
        SELECT ssvid FROM `global-fishing-watch.pipe_ais_identity_v4_published.identity_authorization`))
      AND NOT registry_is_carrier AND NOT registry_is_bunker
      AND
    -- anti join to get vessels that don't match high conf list by ssvid or year:
    NOT EXISTS (
      SELECT ssvid, year
      FROM high_conf_fishing
      WHERE vi_table.ssvid = high_conf_fishing.ssvid AND vi_table.year = high_conf_fishing.year
    )
    ),

-- LOW: MMSI that are on one of our three source fishing lists (registry, rf, self-reported)
-- but not included in either the med or high list. These are MMSI for which we have minimal
-- or conflicting evidence that they are a fishing vessel.

  low_conf_fishing AS (
    SELECT DISTINCT
      ssvid,
      year,
      gfw_best_flag AS vessel_iso3,
      '3' as class_confidence,
      'fishing' AS vessel_class,
      prod_geartype AS gear_type
    FROM
      `global-fishing-watch.pipe_ais_identity_v5_published.product_vessel_info_summary` AS vi_table
    WHERE
    year >= start_year() AND year <= end_year()
    AND
    ( prod_shiptype = 'fishing'
      OR on_fishing_list_rf
      OR on_fishing_list_sr
      -- OR on_fishing_list_nn
       )
    AND NOT registry_is_carrier AND NOT registry_is_bunker
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
    SELECT
      *
    FROM
      additional_vessels
    UNION ALL

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
      fv.vessel_iso3,
      fv.class_confidence,
      fv.vessel_class,
      fv.gear_type
    FROM (
      SELECT
        *,
        EXTRACT(year FROM trip_end) AS year
      FROM
         `global-fishing-watch.pipe_ais_v5_published.voyages_c3`
      WHERE
        trip_end >= start_date() AND trip_start <= end_date()
        ) voyages
    INNER JOIN fishing_vessels fv
    USING
      (ssvid, year)
      ),

----------------------------------------------------------
-- Define lists of high/med/low confidence bunker vessels
----------------------------------------------------------
  high_conf_bunker AS (
    SELECT DISTINCT -- generics for flag and gear to avoid duplicates
      ssvid,
      'flag' AS vessel_iso3,
      '1' AS class_confidence,
      'bunker' AS vessel_class,
      'bunker' AS gear_type,
      first_timestamp,
      last_timestamp
    FROM `global-fishing-watch.pipe_ais_identity_v5_published.identity_core`
    WHERE
      TIMESTAMP(first_timestamp) <= end_date() AND
      TIMESTAMP(last_timestamp) >= start_date() AND
      is_bunker = TRUE
      AND
      (geartype LIKE ("%bunker%") OR geartype LIKE ("%tanker%"))
  ),

-- med conf carrier - capturing all with gear type or class from registry or product as bunker/tanker and rfmo registered
  med_conf_bunker AS (
     SELECT DISTINCT
      ssvid,
      IFNULL(IFNULL(gfw_best_flag, registry_flag), self_reported_mmsi_flag) AS vessel_iso3,
      '2' as class_confidence,
      'bunker' AS vessel_class,
      'bunker' AS gear_type,
      TIMESTAMP(DATETIME(CAST(year AS INT64), 1, 1, 0, 0, 0)) AS first_timestamp,
      TIMESTAMP(DATETIME(CAST(year AS INT64), 12, 31, 23, 59, 59)) AS last_timestamp
     FROM
      `global-fishing-watch.pipe_ais_identity_v5_published.product_vessel_info_summary` AS vi_table
     WHERE
      year >= start_year() AND year <= end_year()
      AND (registry_is_bunker
      OR vi_ssvid_registry_class LIKE ("%bunker%") OR registry_geartype LIKE ("%bunker%")
      OR vi_ssvid_registry_class LIKE ("%tanker%") OR registry_geartype LIKE ("%tanker%")
      OR prod_shiptype LIKE ("%bunker%") OR prod_geartype LIKE ("%bunker%")
      OR prod_shiptype LIKE ("%tanker%") OR prod_geartype LIKE ("%tanker%")
      )
      AND self_reported_imo IN(
        SELECT imo FROM `global-fishing-watch.pipe_ais_identity_v4_published.identity_authorization`
      )
      AND ssvid NOT IN (SELECT ssvid FROM high_conf_bunker)
  ),

-- low conf carrier -
  low_conf_bunker AS (
     SELECT DISTINCT
      ssvid,
      IFNULL(IFNULL(gfw_best_flag, registry_flag), self_reported_mmsi_flag) AS vessel_iso3,
      '1' as class_confidence,
      'bunker' AS vessel_class,
      'bunker' AS gear_type,
      TIMESTAMP(DATETIME(CAST(year AS INT64), 1, 1, 0, 0, 0)) AS first_timestamp,
      TIMESTAMP(DATETIME(CAST(year AS INT64), 12, 31, 23, 59, 59)) AS last_timestamp
     FROM
      `global-fishing-watch.pipe_ais_identity_v5_published.product_vessel_info_summary` AS vi_table
     WHERE
      year >= start_year() AND year <= end_year()
      AND (registry_is_bunker -- all registry_is_bunkers that aren't in identity_authorization, OR bunker/tankers that match rf bunker/tanker
      OR ((vi_ssvid_registry_class LIKE ("%bunker%") OR registry_geartype LIKE ("%bunker%")
      OR vi_ssvid_registry_class LIKE ("%tanker%") OR registry_geartype LIKE ("%tanker%")
      OR prod_shiptype LIKE ("%bunker%") OR prod_geartype LIKE ("%bunker%")
      OR prod_shiptype LIKE ("%tanker%") OR prod_geartype LIKE ("%tanker%"))
      AND (rf_vessel_class IN ("bunker", "bunker_or_tanker") OR rf_atomic_class IN ("bunker", "bunker_or_tanker")))
      )
      AND ssvid NOT IN (SELECT ssvid FROM high_conf_bunker)
      AND ssvid NOT IN (SELECT ssvid FROM med_conf_bunker)
  ),

----------------------------------------------------------
-- combined bunker table info
----------------------------------------------------------
  bunker_vessels AS (
    SELECT
      *
    FROM
      high_conf_bunker
    UNION ALL

    SELECT
      *
    FROM
      med_conf_bunker
    UNION ALL

    SELECT
      *
    FROM
      low_conf_bunker
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
          `global-fishing-watch.pipe_ais_v5_published.voyages_c3`
        WHERE
        trip_end >= start_date() AND trip_start <= end_date()
          ) voyages
    INNER JOIN bunker_vessels AS bunkers
      ON voyages.ssvid = bunkers.ssvid
      -- filtering for trips that end within active phase of vessel id
        AND voyages.trip_end >= bunkers.first_timestamp AND voyages.trip_end <= bunkers.last_timestamp
        )
        ),

---------------------------------------------------------------
-- List of carriers according to vessel registries - high confidence -- focus on specialized reefers on gfw carrier list
---------------------------------------------------------------
  high_conf_carrier AS (
    SELECT DISTINCT -- generics for flag and gear to avoid duplicates
      ssvid,
      'flag' AS vessel_iso3,
      '1' AS class_confidence,
      'carrier' AS vessel_class,
      'carrier' AS gear_type,
      first_timestamp,
      last_timestamp
    FROM `global-fishing-watch.pipe_ais_identity_v5_published.identity_core`
    WHERE
      TIMESTAMP(first_timestamp) <= end_date() AND
      TIMESTAMP(last_timestamp) >= start_date() AND
      is_carrier = TRUE
      AND geartype IN ("reefer", "specialized_reefer", "container_reefer")
  ),

 -- expanding to all on gfw carrier list (includes well_boats, fish_tenders, etc) or vessels on a registry with class or rf including "reefer"
 med_conf_carrier AS (
     SELECT DISTINCT
      ssvid,
      IFNULL(IFNULL(gfw_best_flag, registry_flag), self_reported_mmsi_flag) AS vessel_iso3,
      '2' as class_confidence,
      'carrier' AS vessel_class,
      'carrier' AS gear_type,
      TIMESTAMP(DATETIME(CAST(year AS INT64), 1, 1, 0, 0, 0)) AS first_timestamp,
      TIMESTAMP(DATETIME(CAST(year AS INT64), 12, 31, 23, 59, 59)) AS last_timestamp
     FROM
      `global-fishing-watch.pipe_ais_identity_v5_published.product_vessel_info_summary` AS vi_table
     WHERE
      year >= start_year() AND year <= end_year()
      AND
      (registry_is_carrier
      OR
      ((vi_ssvid_registry_class LIKE ("%reefer%") OR registry_geartype LIKE ("%reefer%")
      OR prod_shiptype LIKE ("%reefer%") OR prod_geartype LIKE ("%reefer%")
      OR rf_vessel_class LIKE ("%reefer%") OR rf_atomic_class LIKE ("%reefer%"))
      AND
      self_reported_imo IN(
        SELECT imo FROM `global-fishing-watch.pipe_ais_identity_v4_published.identity_authorization`)
      )
      AND NOT registry_is_bunker)
      AND ssvid NOT IN (SELECT ssvid FROM high_conf_carrier)
  ),

-- low conf carrier - expanding to any vessel with registry, product, or rf that == "reefer", "specialized_reefer", or "container_reefer"
  low_conf_carrier AS (
     SELECT DISTINCT
      ssvid,
      IFNULL(IFNULL(gfw_best_flag, registry_flag), self_reported_mmsi_flag) AS vessel_iso3,
      '1' as class_confidence,
      'carrier' AS vessel_class,
      'carrier' AS gear_type,
      TIMESTAMP(DATETIME(CAST(year AS INT64), 1, 1, 0, 0, 0)) AS first_timestamp,
      TIMESTAMP(DATETIME(CAST(year AS INT64), 12, 31, 23, 59, 59)) AS last_timestamp
     FROM
      `global-fishing-watch.pipe_ais_identity_v5_published.product_vessel_info_summary` AS vi_table
     WHERE
      year >= start_year() AND year <= end_year()
      AND --
      (vi_ssvid_registry_class IN ("reefer", "specialized_reefer", "container_reefer") OR registry_geartype IN ("reefer", "specialized_reefer", "container_reefer")
      OR prod_shiptype IN ("reefer", "specialized_reefer", "container_reefer") OR prod_geartype IN ("reefer", "specialized_reefer", "container_reefer")
      OR rf_vessel_class IN ("reefer", "specialized_reefer", "container_reefer") OR rf_atomic_class IN ("reefer", "specialized_reefer", "container_reefer"))
      AND ssvid NOT IN (SELECT ssvid FROM high_conf_carrier)
      AND ssvid NOT IN (SELECT ssvid FROM med_conf_carrier)
  ),

----------------------------------------------------------
-- combined carrier table info
----------------------------------------------------------
  carrier_vessels AS (
    SELECT
      *
    FROM
      high_conf_carrier
    UNION ALL

    SELECT
      *
    FROM
      med_conf_carrier
    UNION ALL

    SELECT
      *
    FROM
      low_conf_carrier
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
          `global-fishing-watch.pipe_ais_v5_published.voyages_c3`
        WHERE
        trip_end >= start_date() AND trip_start <= end_date()
          ) voyages
    INNER JOIN carrier_vessels AS carriers
      ON voyages.ssvid = carriers.ssvid
      -- filtering for trips that end within active phase of vessel id
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
    `global-fishing-watch.anchorages.named_anchorages`
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

----------------------------------------------------------
-- add in CTE of manual voyages if applicable
----------------------------------------------------------
-- manual_voyage_cte, -- note can't comment out, one bracket to include manual voyage (and uncomment in next subquery)

plus_manual_voyages AS (
  SELECT *
  FROM named_voyages
--  UNION ALL
--  SELECT * FROM manual_voyage_data
),

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
      event_end,
      JSON_EXTRACT_SCALAR(event_vessels, "$[0].type") as product_shiptype,
      -- ## encountered vessel information
      JSON_EXTRACT_SCALAR(event_vessels, "$[1].type") as enc_product_shiptype,
      JSON_EXTRACT_SCALAR(event_vessels, "$[1].id") as enc_product_vessel_id,
      JSON_EXTRACT_SCALAR(event_vessels, "$[1].ssvid") as enc_product_ssvid,
      start_distance_from_port_km
    FROM `global-fishing-watch.pipe_ais_v4_published.product_events_encounter`) enc
    INNER JOIN (
      SELECT
        vessel_id,
        trip_id,
        trip_start,
        trip_end
      FROM
        plus_manual_voyages) voyages
    USING (vessel_id)
      WHERE event_start BETWEEN trip_start AND trip_end
      AND  product_shiptype != 'gear' AND enc_product_shiptype != 'gear'
      AND start_distance_from_port_km > 10 -- matches map
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
        `global-fishing-watch.pipe_ais_v4_published.product_events_loitering`
      WHERE
        seg_id IN (
        SELECT
          seg_id
        FROM
          `global-fishing-watch.pipe_ais_v4_published.segs_activity`
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
        plus_manual_voyages) b
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
        `global-fishing-watch.pipe_ais_v4_published.product_events_fishing`
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
        plus_manual_voyages)
    USING
      (vessel_id)
    WHERE
      event_start BETWEEN trip_start AND trip_end
    GROUP BY
      vessel_id, trip_id
      ),

--------------------------------------
-- Identify how many intentional disabling events occurred on each voyage
--------------------------------------
  num_gaps AS(
    SELECT
      vessel_id,
      trip_id,
      COUNT(*) AS num_AISdisabling
    FROM (
      SELECT
        vessel_id,
        event_start,
        event_end
      FROM
        `global-fishing-watch.pipe_ais_v4_published.product_events_proto_ais_disabling`) a
    INNER JOIN (
      SELECT
        vessel_id,
        trip_id,
        trip_start,
        trip_end
      FROM
        plus_manual_voyages)
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
      (b.num_encounters > 0, TRUE, FALSE) AS encounter
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
      (d.num_loitering > 0, TRUE, FALSE) AS loitering
    FROM
      add_encounters c
    LEFT JOIN
      num_loitering d
    USING
      (vessel_id,
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
      (f.num_fishing > 0, TRUE, FALSE) AS fishing
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
-- label voyage if it had at least one gap event
--------------------------------------
  add_gaps AS (
    SELECT
      g.*,
      h.num_AISdisabling,
    IF
      (h.num_AISdisabling > 0, TRUE, FALSE) AS AISdisabling
    FROM
      add_fishing AS g
    LEFT JOIN
      num_gaps h
    USING
      (vessel_id,
        trip_id)
    GROUP BY
      1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31),

--------------------------------------
-- label if voyages represents a 'real' voyage
-- 'real': TRUE if the start and end
-- 'port' are different and the voyage
-- is longer than 1 hour
-- OR
-- if the start end end 'port' are the
-- the same, but the voyage had an
-- encounter, loitering event, or fishing event
-- and is > 2 h
-- OR
-- if the start and end 'port are the
-- same, but the voyage is at least 3
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
          AND (encounter IS TRUE
          OR loitering IS TRUE
          OR fishing IS TRUE)
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
      `global-fishing-watch.pipe_ais_v5_published.vessel_info` ),

--------------------------------------
-- Filter the voyages to those that
-- involve 'good' vessel_ids, and
-- end between time range of interest
--------------------------------------
  good_vessel_voyages AS (
    SELECT
      *,
      ROUND(TIMESTAMP_DIFF(trip_end, trip_start, HOUR)/24, 2) AS trip_duration_days
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
        at_dock
      FROM
        `global-fishing-watch.anchorages.named_anchorages` )
    USING
      (trip_end_anchorage_id)),

--------------------------------------
-- create list of anchorages where the vessel has stopped in the visit
--------------------------------------
  anchorage_stops AS (
    SELECT
      v.*,
      s.stop_anchorage_ids
    FROM
      add_visit_end_1 v
    LEFT JOIN (
    -- 1. Aggregate ALL port stops by visit_id (set time something before period of interest)
      SELECT
        visit_id AS trip_end_visit_id,
        STRING_AGG(DISTINCT e.anchorage_id, ', ') AS stop_anchorage_ids
      FROM
        `global-fishing-watch.pipe_ais_v5_published.port_visits`,
        UNNEST(events) AS e
      WHERE
        end_timestamp > start_date()
    -- 2. join to visits table - note REMOVED the 'IN (SELECT...)' filter here from previous approach
      GROUP BY visit_id
    ) s ON v.trip_end_visit_id = s.trip_end_visit_id
  ),

--------------------------------------
-- Add end timestamp to end port visits
--------------------------------------
  add_visit_end_2 AS (
    SELECT
      *
    FROM
      anchorage_stops
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
        `global-fishing-watch.pipe_ais_v5_published.port_visits`
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
  -- has_long_enough_event AS (
  --   SELECT
  --     trip_end_visit_id,
  --     MAX(event_duration_hr) AS longest_event
  --   FROM (
  --     SELECT
  --       *,
  --       TIMESTAMP_DIFF(next_timestamp, timestamp, SECOND)/3600 AS event_duration_hr
  --     FROM (
  --       SELECT
  --         visit_id AS trip_end_visit_id,
  --         event_type,
  --         timestamp,
  --         LEAD(timestamp) OVER(PARTITION BY visit_id ORDER BY timestamp) AS next_timestamp
  --       FROM
  --       `global-fishing-watch.pipe_ais_v4_published.port_visits`,
  --         UNNEST(events)
  --       WHERE
  --         EXTRACT(YEAR
  --         FROM
  --           end_timestamp) >= start_year()
  --         AND event_type NOT IN ('PORT_ENTRY') )
  --     WHERE
  --       event_type IN ('PORT_STOP_BEGIN',
  --         'PORT_GAP_BEGIN') )
  --   GROUP BY
  --     1
  --   HAVING
  --     longest_event > 0 ),

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
      at_dock,
      trip_end_visit_id,
      stop_anchorage_ids,
      start_latitude,
      start_longitude,
      num_encounters,
      num_loitering,
      num_fishing,
      num_AISdisabling,
      encounter,
      loitering,
      fishing,
      AISdisabling,
      high_seas,
      eezs,
      rfmos,
      fishing_hours,
    FROM
      add_visit_end_2
-- turning the below off to ensure any manual added voyage included
    -- WHERE
    --   trip_end_visit_id IN (
    --   SELECT
    --     trip_end_visit_id
    --   FROM
    --     has_long_enough_event)
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
      (end_port_iso3 != vessel_iso3
      AND NOT (end_port_iso3 IN (
        SELECT
          iso3
        FROM
          is_eu_iso3)
        AND vessel_iso3 IN (
        SELECT
          iso3
        FROM
          is_eu_iso3)))
      -- AND end_port_label IN (port_label()) -- using parameters set at top of code for port and iso
      AND end_port_iso3 IN (port_iso())
      ),

--------------------------------------
-- add vessel info from all_vessels table

-- note, depending on specific query, there may be
-- additional vessels dropped here that are not
-- present in pvis (compare to previous subquery)
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
      at_dock,
      trip_end_visit_id,
      stop_anchorage_ids,
      start_latitude,
      start_longitude,
      num_encounters,
      num_loitering,
      num_fishing,
      num_AISdisabling,
      encounter,
      loitering,
      fishing,
      AISdisabling,
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
        self_reported_shipname AS shipname,
        self_reported_callsign AS callsign,
        self_reported_imo AS imo,
        gfw_best_flag AS vessel_flag_best,
        prod_shiptype AS vessel_class_best,
        prod_geartype AS geartype_best
      FROM
        `global-fishing-watch.pipe_ais_identity_v5_published.product_vessel_info_summary`)
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
      at_dock,
      trip_end_visit_id,
      stop_anchorage_ids,
      start_latitude,
      start_longitude,
      num_encounters,
      num_loitering,
      num_fishing,
      num_AISdisabling,
      encounter,
      loitering,
      fishing,
      AISdisabling,
      high_seas,
      eezs,
      rfmos,
      fishing_hours
    FROM add_vessel_info),

--------------------------------------
-- pull final voyages (optional to add anchorage list)
--------------------------------------
clean_voyages AS(
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
    at_dock,
    trip_end_visit_id,
    stop_anchorage_ids,
    start_latitude,
    start_longitude,
    CASE WHEN num_encounters IS NULL THEN 0 ELSE num_encounters END AS num_encounters,
    CASE WHEN num_loitering IS NULL THEN 0 ELSE num_loitering END AS num_loitering,
    CASE WHEN num_fishing IS NULL THEN 0 ELSE num_fishing END AS num_fishing,
    CASE WHEN num_AISdisabling IS NULL THEN 0 ELSE num_AISdisabling END AS num_AISdisabling,
    encounter,
    loitering,
    fishing,
    AISdisabling,
    high_seas,
    eezs,
    rfmos,
    CASE WHEN fishing_hours IS NULL THEN 0 ELSE fishing_hours END AS fishing_hours
  FROM clean_info),
--  WHERE trip_end_anchorage_id IN(
--    SELECT
--      s2id
--    FROM `scratch_joef.MDG_anchorages_reviewed`
--  )
-- )

--------------------------------------
-- add last known visit to same port
-- first pull all port visits for vessel_ids in voyages table
-- changed to join approach from using ssvid IN
--------------------------------------
port_events AS (
  SELECT DISTINCT
    p.visit_id,
    p.ssvid,
    p.vessel_id,
    p.end_timestamp,
    p.end_anchorage_id
  FROM `global-fishing-watch.pipe_ais_v5_published.port_visits` AS p
  -- This replaces the "ssvid IN (...)" subquery
  INNER JOIN (
    SELECT DISTINCT ssvid
    FROM clean_voyages
  ) AS manual_ssvids ON p.ssvid = manual_ssvids.ssvid
  WHERE
    p.end_timestamp > prev_visit_search_date()
    ),

--------------------------------------
-- Add names to all port events
--------------------------------------
name_events AS(
  SELECT
    * EXCEPT(s2id, label, iso3),
    c.label AS end_label,
    c.iso3 AS end_iso3
  FROM port_events
  LEFT JOIN
    anchorage_names c
  ON
    end_anchorage_id = s2id
  ),

--------------------------------------
-- inner join all visits for same vessel_id in time period
-- set any in future to null to allow sorting in next step
--------------------------------------
join_visits AS(
  SELECT
    *,
    IF (end_timestamp >= end_portvisit_timestamp, NULL, end_timestamp) AS prev_visit_ts
  FROM
  (SELECT *
    FROM clean_voyages AS voyages
    LEFT JOIN
      (SELECT
        -- visit_id,
        vessel_id as ves_id,
        ssvid as visits_ssvid,
        end_anchorage_id,
        end_label,
        end_iso3,
        end_timestamp
      FROM name_events
      WHERE end_iso3 = port_iso()) AS visits
      --ON voyages.vessel_id = visits.ves_id
      ON voyages.ssvid = visits.visits_ssvid
      AND voyages.end_port_label = visits.end_label
    )
)

--------------------------------------
-- collapse back down to each individual voyage,
-- keeping just most recent previous visit to same port label
--------------------------------------
SELECT DISTINCT
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
  at_dock,
  trip_end_visit_id,
  stop_anchorage_ids,
  start_latitude,
  start_longitude,
  num_encounters,
  num_loitering,
  num_fishing,
  num_AISdisabling,
  encounter,
  loitering,
  fishing,
  AISdisabling,
  high_seas,
  eezs,
  rfmos,
  fishing_hours,
  FIRST_VALUE (prev_visit_ts) OVER (
    PARTITION BY trip_id
    ORDER BY prev_visit_ts DESC) AS prev_visit_timestamp,
FROM join_visits


/*
--------------------------------------
-- pull vessel list entering POI
-- comment this block out if want voyages
--------------------------------------
  SELECT
    DISTINCT
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
    count(*) as visits_in_timeperiod,
    count(num_encounters) AS total_encounters,
    count(num_loitering) AS total_loitering,
    count(num_fishing) AS total_fishing,
    count(num_AISdisabling) AS total_AISdisabling
  FROM pull_by_anchorage
  GROUP BY 1,2,3,4,5,6,7,8,9,10


*/
