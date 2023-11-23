--------------------------------------
  -- Query to quantify foreign carrier vessel visits port program ports
  --
  -- 22 November 2023
  -- code ported from updated_port_profile_query_draft
  --

CREATE TEMP FUNCTION  start_date() AS (TIMESTAMP({start_date}));
CREATE TEMP FUNCTION  end_date() AS (TIMESTAMP({end_date}));
CREATE TEMP FUNCTION port() AS ({port_name});
CREATE TEMP FUNCTION country() AS ({country_iso3});
-- voyages will be truncated to this end timestamp, if needed


  --------------------------------------
WITH
  --------------------------------------
  -- Get all voyages -
  --------------------------------------
  all_voyages AS (
  SELECT
     * ,
    EXTRACT(year FROM trip_end) AS year
  FROM `world-fishing-827.pipe_ais_v3_alpha_internal.voyages_c2`
    WHERE
      trip_start > '2020-01-01'
      AND trip_end BETWEEN start_date() AND end_date()),


  -- find FV
  fv AS (
    SELECT
    DISTINCT
      identity.ssvid,
      identity.n_shipname AS vessel_name,
      identity.flag AS flag,
      identity.flag AS flag,
      'fishing' AS vessel_class,
      first_timestamp,
      last_timestamp
    FROM
      pipe_ais_v3_alpha_published.identity_all_vessels_v20231001,
      UNNEST(activity),
      UNNEST(registry),
      UNNEST(feature.geartype) AS feature_geartype
    WHERE
      MATCHED IS TRUE
      AND is_fishing IS TRUE
      AND first_timestamp < end_date()
      AND last_timestamp > start_date()
      AND flag != country()
    ),

  anchorages AS (
    SELECT
      *
    FROM `world-fishing-827.anchorages.named_anchorages_v20230925`
    WHERE
      iso3 = country()
      AND label = port()
  ),


  final_voyages AS (
  SELECT
    DISTINCT *
  FROM all_voyages voyages
  INNER JOIN fv fv ON voyages.ssvid = fv.ssvid
  WHERE
    trip_end_anchorage_id IN (SELECT s2id FROM anchorages)
  ORDER by trip_end),

gaps AS (
  SELECT
    *
  FROM `world-fishing-827.pipe_ais_v3_alpha_published.encounters` e
  INNER JOIN (SELECT vessel_id, trip_start, trip_end FROM final_voyages) vi
      ON(
          e.vessel_1_id = vi.vessel_id
          AND e.start_time > vi.trip_start
          AND e.end_time < vi.trip_end
        )
  WHERE
    start_time > '2023-01-01'
  )

SELECT * FROM encounters

--
