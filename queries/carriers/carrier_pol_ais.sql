--  Download carrier AIS data for pattern of life analysis.
--
-- 23Jan2024
-- MS

-- set variables for table query
CREATE TEMP FUNCTION start_date() AS (TIMESTAMP({start_date}));
CREATE TEMP FUNCTION end_date() AS (TIMESTAMP({end_date}));


WITH activity AS (
  SELECT
    ssvid,
    timestamp,
    lat,
    lon,
    speed_knots,
    heading,
    course,
    nnet_score,
    source,
    type,
  FROM
    `pipe_production_v20201001.research_messages`
  WHERE
  -- filter to date period of interest
  _partitiontime BETWEEN start_date() AND end_date()
  -- filter to voi currently using carriers from scatch hannah but will move to another source
  AND ssvid IN (
              SELECT ssvid
              FROM `world-fishing-827.scratch_hannah.tmt_port_visits_sen_all`
              WHERE vessel_class = 'carrier'
            )
  AND seg_id IN (
    SELECT
      seg_id
    FROM
      `pipe_production_v20201001.research_segs`
    WHERE
       good_seg = TRUE
      AND overlapping_and_short = FALSE
  )
)

SELECT * FROM activity
