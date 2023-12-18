-- MS 18 December 2023
-- using proto messages table to create AIS coverage
-- this table has interpolated messages so captures the
-- missing values when positions aren't received.

---SET your dates of interest
CREATE TEMP FUNCTION minimum() AS (TIMESTAMP('2023-01-01'));
CREATE TEMP FUNCTION maximum() AS (TIMESTAMP('2023-03-01'));
CREATE TEMP FUNCTION min_lat() AS (-6);
CREATE TEMP FUNCTION max_lat() AS (22);
CREATE TEMP FUNCTION min_lon() AS (-30);
CREATE TEMP FUNCTION max_lon() AS (20);

WITH aoi AS (
  SELECT
    seg_id,
    ssvid,
    timestamp,
    lat,
    lon,
    is_fishing_vessel,
    type,
    terrestrial_pos,
    satellite_pos,
    min_to_prev,
    min_to_next,
    CASE WHEN satellite_pos > 0 THEN 1 ELSE 0 END AS sat_tf,
    CASE WHEN terrestrial_pos > 0 THEN 1 ELSE 0 END AS ter_tf,
    FLOOR(lat * 10) / 10  as lat_bin,
    FLOOR(lon * 10) / 10 as lon_bin,
  FROM
    `pipe_production_v20201001.proto_messages_interpolated`
  WHERE
    TIMESTAMP_TRUNC(timestamp, DAY) BETWEEN minimum() AND maximum()
    -- filter to voi
    AND lat BETWEEN min_lat() AND max_lat()
    AND lon BETWEEN min_lon() AND max_lon()
)

SELECT
  lat_bin,
  lon_bin,
  count(DISTINCT ssvid) AS vessels,
  sum(satellite_pos) AS sat_pos_ttl,
  sum(sat_tf) AS sat_pos,
  count(seg_id) AS segments,
  sum(terrestrial_pos) AS ter_pos,
  sum(terrestrial_pos) AS ter_pos_ttl,
FROM
  aoi
GROUP BY
  lat_bin, lon_bin


