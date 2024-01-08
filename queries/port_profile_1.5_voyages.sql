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
  --    is at least 24 hours
  -- 4. voyages where the longest port visit
  --    stop/gap is "long enough" (3
  --    hours currently)
CREATE TEMP FUNCTION  start_date() AS (TIMESTAMP('2021-01-01 00:00:00 UTC'));
CREATE TEMP FUNCTION  start_year() AS (2021);
  # voyages will be truncated to this end timestamp, if needed
CREATE TEMP FUNCTION  end_date() AS (TIMESTAMP('2023-12-31 23:59:59 UTC'));
CREATE TEMP FUNCTION  end_year() AS (2023);

--------------------------------------
WITH

----------------------------------------------------------
  -- Define lists of high/med/low confidence for all fishing related vessels
  -- and join each list to voyages within the time period of interest
  ----------------------------------------------------------

  ----------------------------------------------------------
  -- high/med/low confidence fishing vessels
  ----------------------------------------------------------

  -- HIGH: MMSI in the fishing_vessels_ssvid table.
  -- These are vessels on our best fishing list and that have reliable AIS data
  -- pulling in the vessel_name, IRCS, IMO from ssvid_by_year_table

  high_conf_fishing AS (
     SELECT DISTINCT
       ssvid,
       year,
       best_flag AS vessel_iso3,
       '1' as class_confidence,
       'fishing' AS vessel_class,
       best_vessel_class AS gear
     FROM
      `world-fishing-827.gfw_research.fishing_vessels_ssvid_v20231201` -- **** update to pipe 3 when released ******
     WHERE
      year >= start_year() AND year <= end_year()
     ),

  -- MED: All MMSI on our best fishing list not included in the high category.
  -- These are likely fishing vessels that primarily get excluded due to data issues
  -- (e.g. spoofing, offsetting, low activity)

  med_conf_fishing AS (
    SELECT DISTINCT
      ssvid,
      year,
      IFNULL(best.best_flag, ais_identity.flag_mmsi) AS vessel_iso3,
      '2' as class_confidence,
      'fishing' AS vessel_class,
      IFNULL(IFNULL(best.best_vessel_class, ARRAY_TO_STRING(registry_info.best_known_vessel_class,'')), inferred.inferred_vessel_class_ag) AS gear
    FROM
      `gfw_research.vi_ssvid_byyear_v20231201` AS vi_table -- **** update to pipe 3 when released ******
    WHERE on_fishing_list_best AND
    year >= start_year() AND year <= end_year()
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
      IFNULL(best.best_flag, ais_identity.flag_mmsi) AS vessel_iso3,
      '3' as class_confidence,
      'fishing' AS vessel_class,
      IFNULL(IFNULL(best.best_vessel_class, ARRAY_TO_STRING(registry_info.best_known_vessel_class,'')), inferred.inferred_vessel_class_ag) AS gear
    FROM
      `gfw_research.vi_ssvid_byyear_v20231201` AS vi_table -- **** update to pipe 3 when released ******
    WHERE (
      on_fishing_list_nn
      OR on_fishing_list_known
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
      *
    FROM (
      SELECT
        *,
        EXTRACT(year FROM trip_end) AS year
      FROM
        pipe_ais_v3_alpha_published.voyages_c3
        -- pipe_ais_v3_alpha_internal.voyages_c2
      WHERE
        trip_end >= start_date() AND trip_start <= end_date()
        )
    LEFT JOIN fishing_vessels
    USING
      (ssvid, year)
    WHERE
      vessel_iso3 IS NOT NULL
      AND vessel_iso3 != 'UNK'),

  ----------------------------------------------------------
  -- Define lists of high/med/low confidence bunker vessels
  ----------------------------------------------------------

  nn_bunkers_high_confidence AS (
    SELECT DISTINCT
      ssvid,
      IFNULL(best.best_flag, ais_identity.flag_mmsi) AS vessel_iso3,
      '1' as class_confidence,
      'bunker' AS vessel_class,
      IFNULL(IFNULL(best.best_vessel_class, ARRAY_TO_STRING(registry_info.best_known_vessel_class,'')), inferred.inferred_vessel_class_ag) AS gear,
      activity.first_timestamp,
      activity.last_timestamp
    FROM
      `gfw_research.vi_ssvid_v20231201` -- **** update to pipe 3 when released ******
    WHERE
      TIMESTAMP(activity.first_timestamp) <= end_date() AND
      TIMESTAMP(activity.last_timestamp) >= start_date() AND
      best.best_vessel_class IN (
        "bunker",
        "bunker_or_tanker" )
      AND ssvid IN (SELECT ssvid FROM `pipe_ais_v3_alpha_published.identity_core_v20231001` WHERE is_bunker = TRUE)
  ),

  ---------------------------------------------------------------
  -- nn bunkers not in vessel database
  ---------------------------------------------------------------
  nn_bunkers_med_confidence AS (
    SELECT DISTINCT
      ssvid,
      IFNULL(best.best_flag, ais_identity.flag_mmsi) AS vessel_iso3,
      '2' as class_confidence,
      'bunker' AS vessel_class,
      IFNULL(IFNULL(best.best_vessel_class, ARRAY_TO_STRING(registry_info.best_known_vessel_class,'')), inferred.inferred_vessel_class_ag) AS gear,
      activity.first_timestamp,
      activity.last_timestamp
    FROM
      `gfw_research.vi_ssvid_v20231201` -- **** update to pipe 3 when released ******
    WHERE
      TIMESTAMP(activity.first_timestamp) <= end_date() AND
      TIMESTAMP(activity.last_timestamp) >= start_date() AND
      best.best_vessel_class IN (
        "bunker",
        "bunker_or_tanker" )
      AND ssvid NOT IN (SELECT ssvid FROM `pipe_ais_v3_alpha_published.identity_core_v20231001` WHERE is_bunker = TRUE)
  ),

  ---------------------------------------------------------------
  -- List of carriers and bunkers according to vessel registries
  ---------------------------------------------------------------
  reg_bunkers AS (
    SELECT DISTINCT -- generics for flag and gear as there are duplicates in v database which will duplicate voyages
      ssvid,
      'flag' AS vessel_iso3,
      '3' AS class_confidence,
      'bunker' AS vessel_class,
      'geartype' AS gear,
      first_timestamp,
      last_timestamp
    FROM
      `pipe_ais_v3_alpha_published.identity_core_v20231001`
    WHERE
      TIMESTAMP(first_timestamp) <= end_date() AND
      TIMESTAMP(last_timestamp) >= start_date() AND
      is_bunker = TRUE
      AND ssvid NOT IN (SELECT ssvid FROM nn_bunkers_high_confidence)
      AND ssvid NOT IN (SELECT ssvid FROM nn_bunkers_med_confidence)
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
        bunkers.gear
      FROM (
        SELECT
          *,
          EXTRACT(year FROM trip_end) AS year
        FROM
          pipe_ais_v3_alpha_published.voyages_c3
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
      ssvid,
      'flag' AS vessel_iso3,
      '1' AS class_confidence,
      'carrier' AS vessel_class,
      'geartype' AS gear,
      first_timestamp,
      last_timestamp
    FROM
      `pipe_ais_v3_alpha_published.identity_core_v20231001` -- update to latest v
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
      best.best_vessel_class AS gear,
      activity.first_timestamp,
      activity.last_timestamp
    FROM `gfw_research.vi_ssvid_v20231201`
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
      best.best_vessel_class AS gear,
      activity.first_timestamp,
      activity.last_timestamp
    FROM `gfw_research.vi_ssvid_v20231201`
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
        carriers.gear
      FROM (
        SELECT
          *,
          EXTRACT(year FROM trip_end) AS year
        FROM
          pipe_ais_v3_alpha_published.voyages_c3
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
    -- ) select * from initial_voyages  /*
    -- ) select * from initial_voyages where trip_id IN ('900380585-201595d5f-f4bc-bb34-b739-c53e80bc365b-018055d43808', '366899490-acd73a672-2f4a-cf6f-707b-780028b06e64-0182b85ea7fe', '412364192-06f0cdec5-59ac-87ad-6f89-abf40c05a111-0189d02f7b40', '273569400-cf2ecce11-119f-80fe-d997-3ade30f368c7-0183d9c05888') order by class_confidence /*
    -- ) select trip_id, count(*) as n from initial_voyages group by trip_id order by n desc /*

  --------------------------------------
  -- Remove any duplicates between categories (fishing, bunker, carrier) by
  -- selecting duplicate vessel with the higher confidence level
  -- note if vessel has the same conf level
  --------------------------------------

  voyage_duplicates AS(
    SELECT DISTINCT
      year,
      ssvid,
      vessel_id,
      FIRST_VALUE (vessel_iso3) OVER (
        PARTITION BY trip_id
        ORDER BY class_confidence ASC, vessel_class) AS vessel_iso3,
      FIRST_VALUE (class_confidence) OVER (
        PARTITION BY trip_id
        ORDER BY class_confidence ASC, vessel_class) AS class_confidence,
      FIRST_VALUE (vessel_class) OVER (
        PARTITION BY trip_id
        ORDER BY class_confidence ASC, vessel_class) AS vessel_class,
      FIRST_VALUE (gear) OVER (
        PARTITION BY trip_id
        ORDER BY class_confidence ASC, vessel_class) AS gear,
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

  /*

*/
