--------------------------------------
  -- Query to quantify foreign fishing
  -- and carrier vessel visits to
  -- global ports.
  --
  -- there is a need to identify visits
  -- that follow significant voyages
  -- meaning voyages on which some activity
  -- occured rather than situations where a
  -- vessel leaves a port and then immediately
  -- returns. This is currently identified in
  -- several ways...
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
CREATE TEMP FUNCTION start_date() AS (TIMESTAMP('2012-01-01 00:00:00 UTC'));
CREATE TEMP FUNCTION start_year() As (2012);
# voyages will be truncated to this end timestamp, if needed
CREATE TEMP FUNCTION end_date() AS (TIMESTAMP('2023-12-31 23:59:59 UTC'));
CREATE TEMP FUNCTION end_year() AS (2023);

  --------------------------------------
WITH
  --------------------------------------
  -- Get fishing vessel voyages
  --------------------------------------
  c2_voyages_fishing AS (
  SELECT
    *
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
      AND end_date() )
  LEFT JOIN (
    SELECT
      year,
      ssvid,
    IF
      (ssvid = '601111111', 'ZAF',vessel_iso3) AS vessel_iso3,
      vessel_class
    FROM (
      SELECT
        year,
        ssvid,
        IFNULL(best.best_flag, ais_identity.flag_mmsi) AS vessel_iso3,
        IFNULL(IFNULL(best.best_vessel_class, ARRAY_TO_STRING(registry_info.best_known_vessel_class,'')), inferred.inferred_vessel_class_ag) AS vessel_class
      FROM
        gfw_research.vi_ssvid_byyear_v20230101
      WHERE
        (--on_fishing_list_sr OR
          --on_fishing_list_nn OR
          on_fishing_list_best)
        AND activity.offsetting IS FALSE
        AND activity.overlap_hours_multinames < 24
        --AND activity.frac_spoofing < 0.01
        ) )
  USING
    (ssvid,
      year)
  WHERE
    vessel_iso3 IS NOT NULL
    AND vessel_iso3 != 'UNK'),
  --------------------------------------
  -- Get carrier voyages
  --------------------------------------
  c2_voyages_carrier AS (
  SELECT
    *
  FROM (
    SELECT
      *
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
        AND end_date() )
    INNER JOIN (
      SELECT
        year,
        mmsi AS ssvid,
        flag AS vessel_iso3,
        'carrier' AS vessel_class
      FROM
        vessel_database.carrier_vessels_byyear_v20230101
      WHERE
        vessel_class IN ('reefer',
          'specialized_reefer') )
    USING
      (ssvid,
        year)
    WHERE
      vessel_iso3 IS NOT NULL )
  INNER JOIN (
    SELECT
      year,
      ssvid,
    FROM
      gfw_research.vi_ssvid_byyear_v20230101 )
  USING
    (ssvid,
      year) ),
  --------------------------------------
  -- Combine carrier and fishing voyages
  --------------------------------------
  c2_voyages AS (
  SELECT
    *
  FROM
    c2_voyages_fishing
  UNION ALL
  SELECT
    *
  FROM
    c2_voyages_carrier ),
  --------------------------------------
  -- Anchorage names
  --------------------------------------
  anchorage_names AS (
  SELECT
    point_id,
    port_label AS label,
    iso3
  FROM
    proj_pew_ports.gfw_ports_database_v20230214 ),
  --------------------------------------
  -- Add names to voyages (start and end)
  --------------------------------------
  named_voyages AS (
  SELECT
    * EXCEPT(point_id,
      label,
      iso3),
    c.label AS end_label,
    c.iso3 AS end_iso3
  FROM (
    SELECT
      * EXCEPT(point_id,
        label,
        iso3),
      b.label AS start_label,
      b.iso3 AS start_iso3
    FROM
      c2_voyages
    LEFT JOIN
      anchorage_names b
    ON
      trip_start_anchorage_id = point_id)
  LEFT JOIN
    anchorage_names c
  ON
    trip_end_anchorage_id = point_id),
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
  -- Identify the number of loitering
  -- events occurred on each voyages
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
  -- Identify the number of fishing events
  -- that occurred on each voyages
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
      pipe_production_v20201001.proto_events_fishing) a
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
  -- label voyage if it had at least
  -- one encounter event
  --------------------------------------
  add_encounters AS (
  SELECT
    a.*,
  IF
    (b.num_encounters > 0, TRUE, FALSE) AS had_encounter
  FROM
    named_voyages AS a
  LEFT JOIN
    encounters b
  USING
    (vessel_id,
      trip_id)
  GROUP BY
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19),
  --------------------------------------
  -- label voyage if it had at least
  -- one loitering event
  --------------------------------------
  add_loitering AS (
  SELECT
    c.*,
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
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20 ),
  --------------------------------------
  -- label voyage if it had at least
  -- one fishing event
  --------------------------------------
  add_fishing AS (
  SELECT
    e.*,
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
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21 ),
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
        WHEN CONCAT(start_label, start_iso3) != CONCAT(end_label, end_iso3) AND TIMESTAMP_DIFF(trip_end, trip_start, SECOND)/3600 > 1 THEN TRUE
        WHEN CONCAT(start_label, start_iso3) = CONCAT(end_label, end_iso3)
      AND (had_encounter IS TRUE
        OR had_loitering IS TRUE
        OR had_fishing IS TRUE)
      AND TIMESTAMP_DIFF(trip_end, trip_start, SECOND)/3600 > 2 THEN TRUE
        WHEN CONCAT(start_label, start_iso3) = CONCAT(end_label, end_iso3) AND TIMESTAMP_DIFF(trip_end, trip_start, SECOND)/3600 > 24 THEN TRUE
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
    pipe_production_v20201001.vessel_info ),
  --------------------------------------
  -- Filter the voyages to those that
  -- involve 'good' vessel_ids,and
  -- end between 2015 and 2020
  --------------------------------------
  good_vessel_voyages AS (
  SELECT
    *,
    TIMESTAMP_DIFF(trip_end, trip_start, DAY) AS time_diff
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
  -- Add end anchorage information
  --------------------------------------
  fishing_vessel_voyages AS (
  SELECT
    *
  FROM
    good_vessel_voyages AS voyages
  LEFT JOIN (
    SELECT
      point_id AS trip_end_anchorage_id,
      port_id,
      cluster_id,
      port_label,
      iso3 AS port_iso3,
      cluster_label,
      point_label,
      port_locode
    FROM
      proj_pew_ports.gfw_ports_database_v20230214 ) AS ports
  USING
    (trip_end_anchorage_id) ),
  --------------------------------------
  -- Add end timestamp to end port visits
  --------------------------------------
  add_visit_end AS (
  SELECT
    *
  FROM
    fishing_vessel_voyages
  INNER JOIN (
    SELECT
      visit_id AS trip_end_visit_id,
      end_timestamp AS end_visit_endtimestamp,
      start_timestamp AS start_visit_starttimestamp,
      start_lat as start_latitude,
      start_lon as start_longitude
    FROM
      pipe_production_v20201001.proto_port_visits
    WHERE
      EXTRACT(YEAR
      FROM
        end_timestamp) >= start_year()
      AND EXTRACT(YEAR
      FROM
        end_timestamp) <= end_year() )
  USING
    (trip_end_visit_id) ),
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
      TIMESTAMP_DIFF(next_timestamp,timestamp, SECOND)/3600 AS event_duration_hr
    FROM (
      SELECT
        visit_id AS trip_end_visit_id,
        event_type,
        timestamp,
        LEAD(timestamp) OVER(PARTITION BY visit_id ORDER BY timestamp) AS next_timestamp
      FROM
        pipe_production_v20201001.proto_port_visits,
        UNNEST(events)
      WHERE
        EXTRACT(YEAR
        FROM
          end_timestamp) >= start_year()
        AND EXTRACT(YEAR
        FROM
          end_timestamp) <= end_year()
        AND event_type NOT IN ('PORT_ENTRY') )
    WHERE
      event_type IN ('PORT_STOP_BEGIN',
        'PORT_GAP_BEGIN') )
  GROUP BY
    1
  HAVING
    longest_event > 3 ),
--------------------------------------
--------------------------------------
  total AS (
  SELECT
    EXTRACT(YEAR
    FROM
      trip_end) AS year,
    ssvid,
    port_id AS end_port_id,
    vessel_iso3,
    port_label AS end_port_label,
    port_iso3 AS end_port_iso3,
  IF
    (vessel_class = 'carrier', 'carrier','fishing') AS vessel_class,
    trip_end_visit_id,
    end_visit_endtimestamp,
    start_visit_starttimestamp,
    start_latitude,
    start_longitude
  FROM
    add_visit_end
  WHERE
    trip_end_visit_id IN (
    SELECT
      trip_end_visit_id
    FROM
      has_long_enough_event) ),
  --------------------------------------
  --------------------------------------
  is_eu_iso3 AS (
  SELECT
    DISTINCT iso3
  FROM
    `world-fishing-827.gfw_research.country_codes`
  WHERE
    is_EU ),
  --------------------------------------
  -- Only include truly foreign visits
  -- EU visiting EU is not foreign
  --------------------------------------
vessels_end_port_iso AS (
 SELECT
  year,
  end_port_id,
  end_port_label,
  end_port_iso3,
  ssvid,
  vessel_iso3,
  vessel_class,
  trip_end_visit_id,
  end_visit_endtimestamp,
  start_visit_starttimestamp,
  start_latitude,
  start_longitude
FROM
  total
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
  AND end_port_iso3 IN ("PER",'CHL','COL','ECU', 'ARG', 'URY', 'PAN', 'NIC', 'GTM', 'HND', 'SLV','BRA', 'CRI','MEX')
  AND ssvid NOT IN ("334455660","100001001","721","23456","345","100000016","100000008")), -- wrong MMSI number associate with Peru
-- filter for ports of interest

final_list AS (

SELECT
  *
FROM vessels_end_port_iso

JOIN (
    SELECT
      ssvid,
      year,
      ais_identity.shipname_mostcommon.value AS shipname,
      best.best_vessel_class AS best_label,
    FROM
      `gfw_research.vi_ssvid_byyear_v20230101`)
  USING
    (ssvid, year))

 SELECT
end_port_id,
end_port_label,
end_port_iso3,
ssvid,
shipname as vessel_shipname,
vessel_iso3 as vessel_flag,
vessel_class,
best_label as vessel_label,
trip_end_visit_id,
start_latitude,
start_longitude,
start_visit_starttimestamp,
end_visit_endtimestamp,
(TIMESTAMP_DIFF(end_visit_endtimestamp, start_visit_starttimestamp, minute)/60) AS event_duration_hr,
 ((TIMESTAMP_DIFF(end_visit_endtimestamp, start_visit_starttimestamp, minute)/60)/24) AS event_duration_day,
year
FROM
  final_list
