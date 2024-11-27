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
      gfw_sublabel,
      tmt_sublabel,
      anchorage_id,
      port_distance_from_shore_m,
      at_dock,
      port_or_anchorage,
      GhanaEEZ,
      confidence AS port_confidence
    FROM `world-fishing-827.pipe_ais_v3_published.port_visits`
    LEFT JOIN UNNEST (events)
    LEFT JOIN (
      SELECT
        s2id,
        iso3,
        label AS port_label,
        gfw_sublabel,
        tmt_sublabel,
        port_or_anchorage,
        GhanaEEZ,
        dock AS at_dock,
        distance_from_shore_m AS port_distance_from_shore_m
      FROM `world-fishing-827.PortsProgramme.TGO_anchorages_TMTreviewed`)
      -- USING (s2id) )
    ON anchorage_id = s2id

    WHERE end_timestamp >= TIMESTAMP('2021-01-01 00:00:00 UTC')
        AND timestamp >= start_date() AND timestamp <= end_date()
        AND ssvid IN ("200000001", "657215900", "708500000", "377877000", "412000002",
                    "627000000", "671032300", "671033300", "627000029", "671046300",
                    "671070300", "671233100", "725001553", "799180816")
        AND iso3 IN ("TGO")
        AND visit_id NOT IN (SELECT event_id FROM `world-fishing-827.PortsProgramme.TGO_masterlist_2021-23`)

