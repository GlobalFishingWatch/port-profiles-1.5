--------------------------------------------------
-- Query to add port visits for missing vessels identified
-- by TMT that have visits but do NOT have voyages associated with those visits
--------------------------------------------------

CREATE TEMP FUNCTION  start_date() AS (TIMESTAMP('2021-01-01 00:00:00 UTC'));
CREATE TEMP FUNCTION  end_date() AS (TIMESTAMP('2023-12-31 23:59:59 UTC'));

    SELECT
      ssvid,
      visit_id AS event_id,
      event_type AS port_event_type,
      iso3,
      start_timestamp AS start_visit_timestamp,
      end_timestamp AS end_visit_timestamp,
      timestamp AS port_event_timestamp,
      lat AS port_event_lat,
      lon AS port_event_lon,
      port_label,
      -- gfw_sublabel,
      tmt_sublabel,
      anchorage_id,
      port_distance_from_shore_m,
      at_dock,
      -- port_or_anchorage,
      -- GhanaEEZ,
      confidence AS port_confidence
    FROM `world-fishing-827.pipe_ais_v3_published.port_visits`
    LEFT JOIN UNNEST (events)
    LEFT JOIN (
      SELECT
        s2id,
        iso3,
        label AS port_label,
        sublabel AS gfw_sublabel,
        tmt_sublabel,
    -- a.trip_end_anchorage_id,
        -- port_or_anchorage,
        -- GhanaEEZ,
        dock AS at_dock,
        distance_from_shore_m AS port_distance_from_shore_m
      FROM `world-fishing-827.PortsProgramme.BEN_anchorages_TMTreviewed`)
      -- USING (s2id) )
    ON anchorage_id = s2id

    WHERE end_timestamp >= TIMESTAMP('2021-01-01 00:00:00 UTC')
        AND timestamp >= start_date() AND timestamp <= end_date()
        AND ssvid IN ("341032000", "412678562", "799180815", "799180816", "352002156") AND iso3 IN ("BEN")
        AND visit_id NOT IN (SELECT event_id FROM `world-fishing-827.PortsProgramme.BEN_masterlist_2021-23`)

