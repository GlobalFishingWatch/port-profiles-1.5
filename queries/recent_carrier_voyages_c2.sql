--------------------------------------
  -- Query to quantify foreign carrier vessel visits port program ports
  --
  -- 14 November 2023
  -- code ported from updated_port_profile_query_draft
  --
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
  carriers AS (
    SELECT
    DISTINCT
      identity.ssvid,
      identity.n_shipname AS vessel_name,
      identity.flag AS flag,
      'carrier' AS vessel_class,
      first_timestamp,
      last_timestamp
    FROM
      pipe_ais_v3_alpha_published.identity_all_vessels_v20231001,
      UNNEST(activity),
      UNNEST(registry),
      UNNEST(feature.geartype) AS feature_geartype
    WHERE
      MATCHED IS TRUE
      AND is_carrier IS TRUE
      AND feature_geartype IN ('reefer', 'specialized_reefer')
      AND first_timestamp < end_date()
      AND last_timestamp > start_date()
    ),


  anchorages AS (
    SELECT
      *
    FROM `world-fishing-827.anchorages.named_anchorages_v20230925`
    WHERE
      iso3 = country()
      AND label = port()
  )


SELECT
  DISTINCT *
FROM all_voyages voyages
INNER JOIN carriers cv ON voyages.ssvid = cv.ssvid
WHERE
  trip_end_anchorage_id IN (SELECT s2id FROM anchorages)
ORDER by trip_end

