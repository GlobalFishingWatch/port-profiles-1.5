
-- Identify overlapping voyages from port profile dataset
WITH AllEvents AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY ssvid, trip_start) AS unique_id, -- first give unique id
        ROW_NUMBER() OVER (PARTITION BY ssvid ORDER BY trip_start) AS rn_start,
        ROW_NUMBER() OVER (PARTITION BY ssvid ORDER BY trip_end) AS rn_end,
        *
    FROM
        `scratch_joef.voyages_conakry_2020-22_pipe25`
        -- WHERE ssvid IN ("412440271") --
),

-- Select the overlapping events
OverlappingEvents AS(
SELECT
    unique_id,
    rn_start,
    rn_end,
    ssvid,
    vessel_id,
    vessel_flag_best,
    trip_start,
    trip_end
FROM
    AllEvents
WHERE
    EXISTS (
        SELECT 1
        FROM AllEvents as InnerEvents
        WHERE
            -- first filter for events that are overlapping w diff timestamps
            (AllEvents.ssvid = InnerEvents.ssvid
            AND AllEvents.rn_start - InnerEvents.rn_end = 0
            AND AllEvents.unique_id != InnerEvents.unique_id)
            OR -- some events overlap bc of same start and/or end timestamps
            ((AllEvents.ssvid = InnerEvents.ssvid
            AND AllEvents.unique_id != InnerEvents.unique_id) AND
            (AllEvents.trip_start = InnerEvents.trip_start
            OR AllEvents.trip_end = InnerEvents.trip_end))
    ) ORDER BY ssvid, rn_start )

    SELECT
    distinct ssvid
    from OverlappingEvents

