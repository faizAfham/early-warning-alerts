-- 03 · Alert rules: early catch vs alert load
-- Question: for each alert rule, how many sepsis patients get an alert in the 12 hours before
-- onset, how early, and how many alerts does the ward pay for it?
-- Rule = (score, threshold, persistence). persistence 2 = score must stay at/above threshold
-- for 2 consecutive hours before the alarm fires (a simple suppression rule).
-- An alert EVENT = the alarm switching on (rising edge); a standing alarm is one event.
-- At very low thresholds the alarm is on almost all the time, so events can go DOWN as the
-- threshold drops; alarm_hour_share (share of hours in alarm) always rises.
WITH grid AS (
    SELECT * FROM (VALUES ('full'), ('hr_rr')) s(score_name)
    CROSS JOIN range(1, 10) t(threshold)
    CROSS JOIN (VALUES (1), (2)) p(persistence)
    WHERE NOT (score_name = 'hr_rr' AND threshold > 6)        -- HR+RR maxes out at 6 points
),
scored AS (
    SELECT g.score_name, g.threshold, g.persistence, h.pid, h.grp, h.hour, h.onset_hour, h.in_window,
        CASE WHEN g.score_name = 'full' THEN h.score_full ELSE h.score_hr_rr END >= g.threshold AS high
    FROM grid g CROSS JOIN hourly_scores h
),
alarm AS (
    SELECT *,
        high AND (persistence = 1 OR coalesce(lag(high) OVER w, FALSE)) AS on_
    FROM scored
    WINDOW w AS (PARTITION BY score_name, threshold, persistence, pid ORDER BY hour)
),
events AS (
    SELECT *, on_ AND NOT coalesce(lag(on_) OVER w, FALSE) AS event
    FROM alarm
    WINDOW w AS (PARTITION BY score_name, threshold, persistence, pid ORDER BY hour)
),
per_patient AS (
    SELECT score_name, threshold, persistence, pid, grp,
        COUNT(*)                                                  AS hours,
        SUM(event::INT)                                           AS events,
        SUM(on_::INT)                                             AS alarm_hours,
        SUM((event AND in_window)::INT)                           AS true_events,
        bool_or(on_ AND in_window)                                AS caught,
        MAX(onset_hour) - MIN(CASE WHEN on_ AND in_window THEN hour END) AS lead_hours
    FROM events
    GROUP BY ALL
)
SELECT score_name, threshold, persistence,
    COUNT(*) FILTER (WHERE grp = 'sepsis')                                   AS sepsis_patients,
    AVG(caught::INT) FILTER (WHERE grp = 'sepsis')                           AS sensitivity,
    MEDIAN(lead_hours) FILTER (WHERE grp = 'sepsis' AND caught)              AS median_lead_hours,
    SUM(events) / (SUM(hours) / 24.0)                                        AS alerts_per_patient_day,
    SUM(events) FILTER (WHERE grp = 'no_sepsis')
        / (SUM(hours) FILTER (WHERE grp = 'no_sepsis') / 24.0)               AS false_alerts_per_patient_day,
    SUM(alarm_hours)::DOUBLE / SUM(hours)                                    AS alarm_hour_share,
    SUM(true_events)::DOUBLE / NULLIF(SUM(events), 0)                        AS ppv,
    SUM(events)                                                              AS events
FROM per_patient
GROUP BY ALL
ORDER BY score_name, persistence, threshold
