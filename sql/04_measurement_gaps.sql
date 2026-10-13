-- 04 · How often is each vital actually measured?
-- Question: a charted score is only as fresh as its slowest input. What share of hours has a
-- fresh reading for each vital, and how stale is the carried-forward value?
SELECT
    AVG(hr_measured::INT)    AS hr_fresh_share,
    AVG(rr_measured::INT)    AS rr_fresh_share,
    AVG(spo2_measured::INT)  AS spo2_fresh_share,
    AVG(sbp_measured::INT)   AS sbp_fresh_share,
    AVG(temp_measured::INT)  AS temp_fresh_share,
    AVG((temp IS NULL)::INT) AS temp_never_yet_share,
    COUNT(*)                 AS hours
FROM hourly_scores
