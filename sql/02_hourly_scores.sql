-- 02 · Hourly modified NEWS2 score per patient
-- Question: what would a ward early-warning score have shown each hour?
-- Vitals are carried forward from the last measurement (last observation carried forward,
-- the value a bedside monitor would still be showing). Never-measured vitals score 0.
-- "Modified": the data has no consciousness (ACVPU) or supplemental-oxygen fields.
-- score_full  = HR + RR + SpO2 + SBP + Temp (what a nurse-charted NEWS2 sees)
-- score_hr_rr = HR + RR only (what a contactless under-mattress sensor reads)
-- Only hours that can still be warned about are kept: sepsis patients up to onset, and every
-- hour for no-sepsis patients. in_window = within the 12 hours before onset.
WITH filled AS (
    SELECT r.pid, r.ICULOS AS hour, c.grp, c.onset_hour,
        r.HR    IS NOT NULL AS hr_measured,
        r.Resp  IS NOT NULL AS rr_measured,
        r.O2Sat IS NOT NULL AS spo2_measured,
        r.SBP   IS NOT NULL AS sbp_measured,
        r.Temp  IS NOT NULL AS temp_measured,
        last_value(r.HR    IGNORE NULLS) OVER w AS hr,
        last_value(r.Resp  IGNORE NULLS) OVER w AS rr,
        last_value(r.O2Sat IGNORE NULLS) OVER w AS spo2,
        last_value(r.SBP   IGNORE NULLS) OVER w AS sbp,
        last_value(r.Temp  IGNORE NULLS) OVER w AS temp
    FROM raw r JOIN cohort c USING (pid)
    WHERE c.grp <> 'septic_on_arrival'
    WINDOW w AS (PARTITION BY r.pid ORDER BY r.ICULOS ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
),
points AS (
    SELECT *,
        CASE WHEN rr   IS NULL THEN 0 WHEN rr   <= 8    THEN 3 WHEN rr   <= 11   THEN 1
             WHEN rr   <= 20   THEN 0 WHEN rr   <= 24   THEN 2 ELSE 3 END                    AS rr_pts,
        CASE WHEN spo2 IS NULL THEN 0 WHEN spo2 <= 91   THEN 3 WHEN spo2 <= 93   THEN 2
             WHEN spo2 <= 95   THEN 1 ELSE 0 END                                             AS spo2_pts,
        CASE WHEN sbp  IS NULL THEN 0 WHEN sbp  <= 90   THEN 3 WHEN sbp  <= 100  THEN 2
             WHEN sbp  <= 110  THEN 1 WHEN sbp  <  220  THEN 0 ELSE 3 END                    AS sbp_pts,
        CASE WHEN hr   IS NULL THEN 0 WHEN hr   <= 40   THEN 3 WHEN hr   <= 50   THEN 1
             WHEN hr   <= 90   THEN 0 WHEN hr   <= 110  THEN 1 WHEN hr   <= 130  THEN 2 ELSE 3 END AS hr_pts,
        CASE WHEN temp IS NULL THEN 0 WHEN temp <= 35.0 THEN 3 WHEN temp <= 36.0 THEN 1
             WHEN temp <= 38.0 THEN 0 WHEN temp <= 39.0 THEN 1 ELSE 2 END                    AS temp_pts
    FROM filled
    WHERE grp = 'no_sepsis' OR hour < onset_hour
)
SELECT *,
    rr_pts + spo2_pts + sbp_pts + hr_pts + temp_pts       AS score_full,
    rr_pts + hr_pts                                        AS score_hr_rr,
    grp = 'sepsis' AND hour >= onset_hour - 12             AS in_window
FROM points
