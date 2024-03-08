--------------------------------------------------------------------------------
--- Data for fishing events from Mombasa port catchment area
--- This is version 2 leverage the existing tables in scratch_hannah
-- This approach was taken from 'fishing_before_tema.sql' and adapted for Mombasa
-- MS 18Sep23
--------------------------------------------------------------------------------


WITH
----------------------------------
-- Fishing events involving MOM, KEN
----------------------------------
fishing_ssvid as(
SELECT
*,
vessel_id as fish_vid,
FROM
-- scratch_hannah.fishing_events_tema_042622),
`scratch_hannah.fishing_events_ken_051022`),
----------------------------------
-- voyages ending in TEMA, GHA
----------------------------------
 vessels_oi AS (
SELECT
vessel_id as main_vid,
trip_start,
trip_end,
trip_id,
vi_ssvid,
flag,
shipname
FROM
--`scratch_hannah.tmt_voyages_tema_all`
`scratch_hannah.tmt_voyages_ken_all`
WHERE
type != "carrier"
AND end_anchorage_iso3 = 'KEN'
AND end_anchorage_label = 'MOMBASA'
AND flag != 'KEN'
),
----------------------------------
-- Fishing on voyages that end in
-- MOM, KEN
----------------------------------
fishing_clean as(
SELECT
* EXCEPT(regions_mean_position)
FROM(
SELECT
*
FROM
fishing_ssvid)a
JOIN(
   SELECT
      *
    FROM
      vessels_oi)b
  ON
    a.fish_vid=SAFE_CAST(b.main_vid AS STRING)
    AND a.event_start BETWEEN b.trip_start
    AND b.trip_end
    AND a.event_end BETWEEN b.trip_start
    AND b.trip_end)
----------------------------------
-- Pull data
----------------------------------
SELECT * EXCEPT(event_info, event_vessels) FROM fishing_clean
--SELECT * FROM fishing_ssvid LIMIT 10
