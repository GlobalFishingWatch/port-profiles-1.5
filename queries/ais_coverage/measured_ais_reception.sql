-- MS 10 January 2023
-- using masured ais coverage
-- taken from Tylers example query https://globalfishingwatch.slack.com/archives/CHBNB2JAE/p1704812991196769?thread_ts=1704771418.254269&cid=CHBNB2JAE

---SET your dates of interest
CREATE TEMP FUNCTION startdate() AS (TIMESTAMP({start_date}));
CREATE TEMP FUNCTION enddate() AS (TIMESTAMP({end_date}));
CREATE TEMP FUNCTION min_lat() AS ({min_lat});
CREATE TEMP FUNCTION max_lat() AS ({max_lat});
CREATE TEMP FUNCTION min_lon() AS ({min_lon});
CREATE TEMP FUNCTION max_lon() AS ({max_lon});


--
WITH
--
good_ssvid AS (
  SELECT
    ssvid
  FROM `world-fishing-827.gfw_research.vi_ssvid_v20231201`
  WHERE best.best_vessel_class NOT IN  ("gear", "squid_jigger", "pole_and_line")
  AND NOT activity.offsetting
  AND activity.active_positions > 1000
  AND best.best_vessel_class IS NOT NULL
),
--
-- Satellite positions for all vessels during time period
--
sat_ssvid as (
  SELECT
    ssvid,
    satellite_pos as sat_positions,
    terrestrial_pos as ter_positions,
    lat,
    lon,
    EXTRACT(HOUR FROM timestamp) as hour,
    TIMESTAMP_ADD(
         TIMESTAMP_TRUNC(timestamp, HOUR),
         INTERVAL 30 MINUTE
      ) as hour_midpoint,
    interpolated_speed_knots,
    DATE(timestamp) date,
    type
  -- Use table grouped by segid
  FROM `pipe_production_v20201001.proto_messages_interpolated`
  WHERE timestamp >= startdate()
    AND timestamp <= enddate()
    AND lat BETWEEN min_lat() AND max_lat()
    AND lon BETWEEN min_lon() AND max_lon()
    AND ssvid IN (SELECT ssvid FROM good_ssvid)
    -- Use good segments
    AND seg_id IN (
        SELECT
        seg_id
        FROM `world-fishing-827.pipe_production_v20201001.research_segs`
        WHERE good_seg
        AND NOT overlapping_and_short
    )
),
--
-- Summarize position counts by hour midpoint and AIS class
--
sat_ssvid_final AS (
  SELECT
      ssvid,
      SUM(sat_positions) as sat_positions,
      SUM(ter_positions) as ter_positions,
      AVG(lat) as lat,
      AVG(lon) as lon,
      hour,
      hour_midpoint,
      AVG(interpolated_speed_knots) as interpolated_speed_knots,
      SUM(IF(type = 'A', sat_positions, 0)) as A_messages,
      SUM(IF(type = 'B', sat_positions, 0)) as B_messages,
      SUM(IF(type = 'A', ter_positions, 0)) as A_ter_messages,
      SUM(IF(type = 'B', ter_positions, 0)) as B_ter_messages,
      date
  FROM sat_ssvid
  GROUP BY ssvid, hour, hour_midpoint, date
),
--
-- Calculate positions per half day
--
by_half_day AS (
  SELECT
    ssvid,
    AVG(interpolated_speed_knots) avg_interpolated_speed_knots,
    MIN(interpolated_speed_knots) min_interpolated_speed_knots,
    MAX(interpolated_speed_knots) max_interpolated_speed_knots,
    SUM(sat_positions)/COUNT(*) sat_pos_per_hour,
    SUM(ter_positions)/COUNT(*) ter_pos_per_hour,
    FLOOR(hour/12) day_half,
    SUM(A_messages) A_messages,
    SUM(B_messages) B_messages,
    SUM(A_ter_messages) A_ter_messages,
    SUM(B_ter_messages) B_ter_messages,
    date
  FROM sat_ssvid_final
  GROUP BY ssvid, date, day_half
),
--
-- Calculate reception quality
--
reception_quality AS (
  SELECT
      FLOOR(a.lat * 10) / 10  as lat_bin,
      FLOOR(a.lon * 10) / 10 as lon_bin,
      IF(by_half_day.A_messages > 0, "A", "B") as class,
      COUNT(*) as hours,
      AVG(sat_pos_per_hour) * 24 as sat_pos_per_day,
      AVG(ter_pos_per_hour) * 24 as ter_pos_per_day
    FROM sat_ssvid_final a
    JOIN by_half_day
      ON a.ssvid = by_half_day.ssvid
      AND FLOOR(a.hour/12) = by_half_day.day_half
      AND a.date = by_half_day.date
      -- if Class A, moving at the speed to ping once every 10 seconds
      AND (
           (
            by_half_day.A_messages > 0
            AND min_interpolated_speed_knots > 0.5
            AND max_interpolated_speed_knots < 14
            )
           OR (
            by_half_day.B_messages > 0
            AND min_interpolated_speed_knots > 2
            )
          )
      -- make sure it is just class A or class B... this might make it fail
      -- for the vessels that are both A and B...
      AND NOT (
        by_half_day.A_messages > 0
        AND by_half_day.B_messages > 0
        )
      AND max_interpolated_speed_knots < 30 -- eliminate some weird noise
    GROUP BY lat_bin, lon_bin, class
)
--
-- Return final table and add start and end date range
--
SELECT
  class as ais_class,
  startdate() as reception_start_date,
  enddate() as reception_end_date,
  * EXCEPT (class)
FROM reception_quality
