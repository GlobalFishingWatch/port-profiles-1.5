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
CREATE TEMP FUNCTION  start_date() AS (TIMESTAMP('2022-01-01 00:00:00 UTC'));
CREATE TEMP FUNCTION  start_year() AS (2022);
  # voyages will be truncated to this end timestamp, if needed
CREATE TEMP FUNCTION  end_date() AS (TIMESTAMP('2022-12-31 23:59:59 UTC'));
CREATE TEMP FUNCTION  end_year() AS (2022);

  --------------------------------------
WITH
  --------------------------------------
  -- Get carrier voyages -
  --------------------------------------
  c4_voyages_carrier AS (
  SELECT
    DISTINCT *
  FROM (
    SELECT
      voyages.*,
      vessels.vessel_iso3,
      vessels.vessel_class
    FROM (
      SELECT
        *,
        EXTRACT(year
        FROM
          trip_end) AS year
      FROM
        pipe_production_v20201001.proto_voyages_c4
      WHERE
        trip_end BETWEEN start_date()
        AND end_date() ) voyages
    INNER JOIN (
      SELECT
        identity.ssvid,
        identity.flag AS vessel_iso3,
        'carrier' AS vessel_class,
        first_timestamp,
        last_timestamp
      FROM
        pipe_ais_v3_alpha_published.identity_all_vessels_v20231001,
        UNNEST(activity),
        UNNEST(feature.geartype) AS feature_geartype
      WHERE
        MATCHED IS TRUE
        AND is_carrier IS TRUE
        AND feature_geartype IN ('reefer', 'specialized_reefer')
      ) vessels
    ON voyages.ssvid = vessels.ssvid
      AND voyages.trip_end
      BETWEEN vessels.first_timestamp AND vessels.last_timestamp
    WHERE
      vessel_iso3 IS NOT NULL ))
      SELECT * FROM c4_voyages_carrier


