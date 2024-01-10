-- MS 10 January 2023
-- using proto messages table to create AIS coverage
-- taken from Tylers example query https://globalfishingwatch.slack.com/archives/CHBNB2JAE/p1704812991196769?thread_ts=1704771418.254269&cid=CHBNB2JAE

---SET your dates of interest
CREATE TEMP FUNCTION minimum() AS (TIMESTAMP({start_date}));
CREATE TEMP FUNCTION maximum() AS (TIMESTAMP({end_date}));
CREATE TEMP FUNCTION min_lat() AS ({min_lat});
CREATE TEMP FUNCTION max_lat() AS ({max_lat});
CREATE TEMP FUNCTION min_lon() AS ({min_lon});
CREATE TEMP FUNCTION max_lon() AS ({max_lon});

SELECT
  type,
  FLOOR(lat * 10) / 10  as lat_bin,
  FLOOR(lon * 10) / 10 as lon_bin,
  COUNTIF(satellite_pos > 0) / COUNT(*) as satellite_reception,
  COUNTIF(terrestrial_pos > 0) / COUNT(*) as terrestrial_reception
FROM `world-fishing-827.pipe_production_v20201001.proto_messages_interpolated`
WHERE
    TIMESTAMP_TRUNC(timestamp, DAY) BETWEEN minimum() AND maximum()
    AND lat BETWEEN min_lat() AND max_lat()
    AND lon BETWEEN min_lon() AND max_lon()
  AND type = ('A','B')
GROUP BY type, lat_bin, lon_bin
ORDER BY terrestrial_reception DESC
