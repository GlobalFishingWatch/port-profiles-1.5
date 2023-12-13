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
CREATE TEMP FUNCTION  start_date() AS (TIMESTAMP('2023-09-01 00:00:00 UTC'));
CREATE TEMP FUNCTION  end_date() AS (TIMESTAMP('2023-09-30 23:59:59 UTC'));
CREATE TEMP FUNCTION port() AS ('DAKAR');
CREATE TEMP FUNCTION country() AS ('SEN');
-- voyages will be truncated to this end timestamp, if needed

--------------------------------------
--------------------------------------
WITH
  --------------------------------------
  -- Get all voyages -
  --------------------------------------
  all_voyages AS (
  SELECT
     * ,
    TIMESTAMP_DIFF(trip_end, trip_start, DAY) AS trip_duration_days,
    EXTRACT(year FROM trip_end) AS year
  FROM `world-fishing-827.pipe_ais_v3_alpha_internal.voyages_c2`
    WHERE
      trip_start > '2020-01-01'
      AND trip_end BETWEEN start_date() AND end_date()),


  -- find FV
  fv AS (
    SELECT
    DISTINCT
      identity.ssvid AS identity_ssvid,
      identity.n_shipname AS vessel_name,
      identity.flag AS flag,
      'fishing' AS vessel_class,
      feature_geartype AS gear,
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

  all_anchorages AS (
    SELECT
      s2id,
      iso3,
      label,
      sublabel,
    FROM `world-fishing-827.anchorages.named_anchorages_v20230925`
  ),

  dak_anchorages AS (
    SELECT
      s2id,
      iso3,
      label,
      sublabel,
    FROM `world-fishing-827.anchorages.named_anchorages_v20230925`
    WHERE
      iso3 = country()
      AND label = port()
  ),

 voyages_oi AS (
     SELECT
      DISTINCT *
    FROM all_voyages voyages
    INNER JOIN fv fv ON voyages.ssvid = fv.identity_ssvid
    LEFT JOIN (SELECT s2id, iso3 AS start_iso3, label AS start_lab, sublabel AS start_sublab FROM all_anchorages) s_anc ON voyages.trip_start_anchorage_id = s_anc.s2id
    LEFT JOIN (SELECT s2id, iso3 AS end_iso3, label AS end_lab, sublabel AS end_sublab FROM all_anchorages) anc ON voyages.trip_end_anchorage_id = anc.s2id
    WHERE
      trip_end_anchorage_id IN (SELECT s2id FROM dak_anchorages)
      AND end_iso3 = country()
      AND end_lab = port()
    ORDER by trip_end
  ),


--------------------------------------
  -- Identify how many encounters occurred
  -- on each voyage
  --------------------------------------
  encounters AS (
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
      voyages_oi)
  USING
    (vessel_id)
  WHERE
    event_start BETWEEN trip_start
    AND trip_end
  GROUP BY
    1,
    2 ),

  --------------------------------------
  -- Identify the number of loitering
  -- events occurred on each voyage
  --------------------------------------
  loitering AS (
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
      `pipe_production_v20201001.published_events_loitering`
    WHERE
      seg_id IN (
      SELECT
        seg_id
      FROM
        gfw_research.pipe_v20201001_segs
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
      voyages_oi) b
  USING
    (vessel_id)
  WHERE
    event_start BETWEEN trip_start
    AND trip_end
  GROUP BY
    1,
    2 ),

  --------------------------------------
  -- Identify the number of fishing events
  -- that occurred on each voyage
  --------------------------------------
  fishing AS(
  SELECT
    vessel_id,
    trip_id,
    COUNT(*) AS num_fishing
  FROM (
    SELECT
      vessel_id,
      event_start,
      event_end
    FROM
     --- pipe_production_v20201001.proto_events_fishing) a --- proto events fishing changed to published in june 2023
      pipe_production_v20201001.published_events_fishing) a
  INNER JOIN (
    SELECT
      vessel_id,
      trip_id,
      trip_start,
      trip_end
    FROM
      voyages_oi)
  USING
    (vessel_id)
  WHERE
    event_start BETWEEN trip_start AND trip_end
  GROUP BY
    1,
    2 ),

  --------------------------------------
  -- Identify the number of fishing events
  -- that occurred on each voyage
  --------------------------------------
   gaps AS (
  SELECT
     vessel_id,
     count(*) AS num_gaps,
  FROM (
    SELECT
      vessel_id,
      event_start,
      event_end
    FROM
      pipe_production_v20201001.proto_published_events_ais_gaps
    WHERE
      start_distance_from_shore_km > 9.26
      AND end_distance_from_shore_km > 9.26) a
  INNER JOIN (
    SELECT
      vessel_id,
      trip_id,
      trip_start,
      trip_end
    FROM
      voyages_oi)
  USING
    (vessel_id)
  WHERE
    event_start BETWEEN trip_start AND trip_end
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
    voyages_oi AS a
  LEFT JOIN
    encounters b
  USING
    (vessel_id,
      trip_id)
  GROUP BY
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26, 27),

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
    loitering d
  USING
    (vessel_id,
      trip_id)
  GROUP BY
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29),

  --------------------------------------
  -- label voyage if it had at least
  -- one fishing event
  --------------------------------------
  add_fishing AS (
  SELECT
    e.*,
    f.num_fishing,
  IF
    (f.num_fishing > 0, TRUE, FALSE) AS had_fishing
  FROM
    add_loitering AS e
  LEFT JOIN
    fishing f
  USING
    (vessel_id,
      trip_id)
  GROUP BY
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31),

  --------------------------------------
  -- label voyage if it had at least
  -- one fishing event
  --------------------------------------
  add_gaps AS (
  SELECT
    e.*,
    f.num_gaps,
  IF
    (f.num_gaps > 0, TRUE, FALSE) AS had_gaps
  FROM
    add_fishing AS e
  LEFT JOIN
    gaps f
  USING
  -- this will not be robust to vssels with two trips in the month
    (vessel_id)
  GROUP BY
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33),

--------------------------------------
  -- label if voyages represents a 'real'
  -- voyage
  --
  -- 'real': TRUE
  -- if the start and end
  -- 'port' are different and the voyage
  -- is longer than 1 hour
  -- OR
  -- if the start end end 'port' are the
  -- the same, but the voyage had an
  -- encounter, loitering event, or fishing
  -- event
  -- OR
  -- if the start and end 'port are the
  -- same, but the voyage is at least 24
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
        WHEN CONCAT(start_lab, start_iso3) != CONCAT(end_lab, end_iso3) AND TIMESTAMP_DIFF(trip_end, trip_start, SECOND)/3600 > 1 THEN TRUE
        WHEN CONCAT(start_lab, start_iso3) = CONCAT(end_lab, end_iso3)
      AND (had_encounter IS TRUE
        OR had_loitering IS TRUE
        OR had_fishing IS TRUE)
      AND TIMESTAMP_DIFF(trip_end, trip_start, SECOND)/3600 > 2 THEN TRUE
        WHEN CONCAT(start_lab, start_iso3) = CONCAT(end_lab, end_iso3) AND TIMESTAMP_DIFF(trip_end, trip_start, SECOND)/3600 > 24 THEN TRUE
      ELSE
      FALSE
    END
      AS true_voyage
    FROM
      add_gaps)
  WHERE
    true_voyage IS TRUE )

SELECT
  ssvid,
  vessel_name,
  gear,
  trip_start,
  trip_end,
  lon,
  lat,
  timestamp,
  speed_knots,
  heading,
  nnet_score,
  hours,
FROM
  `world-fishing-827.pipe_ais_v3_alpha_published.messages`
INNER JOIN (
  SELECT vessel_name, gear, ssvid, trip_start, trip_end
  FROM initial_true_voyages) USING (ssvid)
WHERE
  timestamp BETWEEN TIMESTAMP('2020-01-01 00:00:00 UTC') AND TIMESTAMP('2023-09-30 23:59:59 UTC')
  AND timestamp BETWEEN trip_start AND trip_end
