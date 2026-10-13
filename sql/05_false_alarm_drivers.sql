-- 05 · What drives false alarms?
-- Question: in patients who never develop sepsis, which vital pushes the full score to 5+?
-- For every no-sepsis hour at score >= 5, count each vital that contributes >= 2 points.
SELECT
    COUNT(*)                                 AS high_hours,
    AVG((hr_pts   >= 2)::INT)                AS hr_share,
    AVG((rr_pts   >= 2)::INT)                AS rr_share,
    AVG((spo2_pts >= 2)::INT)                AS spo2_share,
    AVG((sbp_pts  >= 2)::INT)                AS sbp_share,
    AVG((temp_pts >= 2)::INT)                AS temp_share
FROM hourly_scores
WHERE grp = 'no_sepsis' AND score_full >= 5
