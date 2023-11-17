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
  -- Get fishing vessel voyages - using vi_ssvid fishing_list_best
  --------------------------------------
  c4_voyages_fishing AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      EXTRACT(year
      FROM
        trip_end) AS year
    FROM
      pipe_ais_v3_alpha_published.voyages_c4
    WHERE
      trip_end BETWEEN start_date()
      AND end_date() AND
      trip_start <= end_date())
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
        gfw_research.vi_ssvid_byyear_v20231001 -- update to latest v (and pipe3 when released)
      WHERE
        (on_fishing_list_best)
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
  -- Get carrier voyages - note this version uses
  -- vessel database/all vessels to id carriers instead
  -- of annual carrier list
  --------------------------------------
  c4_voyages_carrier AS (
  SELECT
    *
  FROM (
    SELECT
    DISTINCT
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
        pipe_ais_v3_alpha_published.voyages_c4
      WHERE
        trip_end BETWEEN TIMESTAMP('2022-01-01 00:00:00 UTC')
        AND TIMESTAMP('2022-12-31 23:59:59 UTC')
        AND trip_start <= end_date()) voyages
    INNER JOIN (
      SELECT
        ssvid,
        'flag' AS vessel_iso3, -- placeholder for flag to avoid duplicates
        'carrier' AS vessel_class,
        first_timestamp,
        last_timestamp
      FROM
        pipe_ais_v3_alpha_published.identity_core_v20231001
        AS vessels -- update to latest v
      WHERE
        is_carrier IS TRUE
        AND geartype IN ('reefer', 'specialized_reefer')
        -- AND flag IS NOT NULL --
      ) vessels
    ON voyages.ssvid = vessels.ssvid
      AND voyages.trip_end
      BETWEEN vessels.first_timestamp AND vessels.last_timestamp
      )
  INNER JOIN (
    SELECT
      year,
      ssvid,
    FROM
      gfw_research.vi_ssvid_byyear_v20230601 )
  USING
    (ssvid,
      year) ),

  --------------------------------------
  -- Combine carrier and fishing voyages
  --------------------------------------
  c4_voyages AS (
  SELECT
    *
  FROM
    c4_voyages_fishing
  UNION ALL
  SELECT
    *
  FROM
    c4_voyages_carrier ),

  --------------------------------------
  -- Anchorage names
  --------------------------------------
  anchorage_names AS (
  SELECT
    s2id,
    label,
    iso3
  FROM
    anchorages.named_anchorages_v20230925
    ),

  --------------------------------------
  -- Add names to voyages (start and end)
  --------------------------------------
  named_voyages AS (
  SELECT
    * EXCEPT(s2id,
      label,
      iso3),
    c.label AS end_label,
    c.iso3 AS end_iso3
  FROM (
    SELECT
      * EXCEPT(s2id,
        label,
        iso3),
      b.label AS start_label,
      b.iso3 AS start_iso3
    FROM
      c4_voyages
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

-- **** consider whether to add same logic for other straits or canals
-------------------------------------------------------------------

  ------------------------------------------------
  -- anchorage ids that represent the Panama Canal

  -- note the named_anchorages table was updated without
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
    vessel_class,
    start_label,
    start_iso3,
    end_label,
    end_iso3,
    trip_id,
    trip_start,
    trip_end,
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
    -- IF (current_start_is_panama, NULL, trip_start) AS block_start,
    -- IF (current_end_is_panama, NULL, trip_end) AS block_end
    -- IF (prev_end_is_panama, NULL, trip_start) AS block_start,
    -- IF (current_end_is_panama, NULL, trip_end) AS block_end
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
    FIRST_VALUE (vessel_class) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS vessel_class,
    FIRST_VALUE (trip_id) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS trip_id,
    FIRST_VALUE (start_iso3) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS start_iso3,
    FIRST_VALUE (start_label) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS start_label,
    FIRST_VALUE (trip_start_anchorage_id) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS trip_start_anchorage_id,
    FIRST_VALUE (trip_start_visit_id) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_start ASC) AS trip_start_visit_id,
    FIRST_VALUE (end_iso3) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_end DESC) AS end_iso3,
    FIRST_VALUE (end_label) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_end DESC) AS end_label,
    FIRST_VALUE (trip_end_anchorage_id) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_end DESC) AS trip_end_anchorage_id,
    FIRST_VALUE (trip_end_visit_id) OVER (
      PARTITION BY block_start, block_end, ssvid
      ORDER BY trip_end DESC) AS trip_end_visit_id,
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
    vessel_class,
    trip_id,
    block_start AS trip_start,
    block_end AS trip_end,
    start_iso3,
    start_label,
    trip_start_anchorage_id,
    trip_start_visit_id,
    end_iso3,
    end_label,
    trip_end_anchorage_id,
    trip_end_visit_id,
    FROM blocks_to_be_collapsed_down
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
      `pipe_production_v20201001.published_events_encounters_v2_v20231116`) a
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
      `pipe_production_v20201001.published_events_loitering_v2_v20231116`
    WHERE
      seg_id IN (
      SELECT
        seg_id
      FROM
        gfw_research.research_segs
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
      pipe_production_v20201001.published_events_fishing_v2_v20231116) a
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
    1,
    2 ),

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
    encounters b
  USING
    (vessel_id,
      trip_id)
  GROUP BY
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17),

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
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19),

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
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21),

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
  -- involve 'good' vessel_ids, and
  -- end between 2013 and 2022
  --------------------------------------
  good_vessel_voyages AS (
  SELECT
    *,
    TIMESTAMP_DIFF(trip_end, trip_start, DAY) AS trip_duration_days
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
      proj_pew_ports.gfw_ports_database_v20230424 ) AS ports
  USING
    (trip_end_anchorage_id) ),

  --------------------------------------
  -- Add end anchorage information from GFW ports
  --------------------------------------
  fishing_vessel_voyages2 AS (
  SELECT
    *
  FROM
    fishing_vessel_voyages
  LEFT JOIN (
    SELECT
      s2id AS trip_end_anchorage_id,
      distance_from_shore_m,
      dock
    FROM
      `anchorages.named_anchorages_v20230925` ) -- may need to update
  USING
    (trip_end_anchorage_id)),

  --------------------------------------
  -- Add end timestamp to end port visits
  --------------------------------------
  add_visit_end AS (
  SELECT
    *
  FROM
    fishing_vessel_voyages2
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
      TIMESTAMP_DIFF(next_timestamp, timestamp, SECOND)/3600 AS event_duration_hr
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
    vessel_iso3,
  IF
    (vessel_class = 'carrier', 'carrier', 'fishing') AS vessel_class,
    trip_start,
    trip_end,
    trip_duration_days,
    trip_id,
    start_iso3 AS start_port_iso3,
    start_label AS start_port_label,
    port_iso3 AS end_port_iso3,
    port_label AS end_port_label,
    port_id AS end_port_id,
    trip_end_anchorage_id,
    distance_from_shore_m,
    dock,
    trip_end_visit_id,
    start_visit_starttimestamp,
    end_visit_endtimestamp,
    start_latitude,
    start_longitude,
    num_encounters,
    num_loitering,
    num_fishing
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
  *
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
  ---AND end_port_iso3 IN ("PER",'CHL','COL','ECU', 'ARG', 'URY', 'PAN', 'NIC', 'GTM', 'HND', 'SLV','BRA', 'CRI','MEX')
  ---AND end_port_iso3 IN ("ARG", "BEL", "BRA", "CHL", "COL", "CRI", "ECU", "SLV", "GTM", "GUF", "GUY", "HND", "MEX", "NIC", "PAN", "PER", "SUR", "URY", "VEN")
  AND end_port_iso3 IN ("CHL", "COL", "CRI", "ECU", "SLV", "GTM", "HND", "MEX", "NIC", "PAN", "PER")
  AND ssvid NOT IN ("334455660","100001001","721","23456","345","100000016","100000008") -- wrong MMSI number associate with Peru
  ),
-- filter for ports of interest

  --------------------------------------
  -- add vessel id info from ssvid by year table
  --------------------------------------
add_ssvid_info AS (
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
      `gfw_research.vi_ssvid_byyear_v20230901`) -- update to latest v
  USING
    (ssvid, year))

SELECT
  ssvid,
  vessel_iso3 as vessel_flag,
  shipname as vessel_shipname,
  vessel_class,
  best_label as vessel_label,
  year,
  trip_start,
  trip_end,
  trip_duration_days,
  -- trip_id,
  start_port_iso3,
  start_port_label,
  end_port_iso3,
  end_port_label,
  end_port_id,
  trip_end_anchorage_id,
  distance_from_shore_m,
  dock,
  trip_end_visit_id,
  num_encounters,
  num_loitering,
  num_fishing,
  start_latitude,
  start_longitude,
  start_visit_starttimestamp,
  end_visit_endtimestamp,
  -- (TIMESTAMP_DIFF(end_visit_endtimestamp, start_visit_starttimestamp, minute)/60) AS port_event_duration_hr,
  ((TIMESTAMP_DIFF(end_visit_endtimestamp, start_visit_starttimestamp, minute)/60)/24) AS port_event_duration_days
  FROM
    add_ssvid_info

*/
