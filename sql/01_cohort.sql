-- 01 · Cohort: one row per ICU stay
-- Question: who is in the data, who developed sepsis, and when?
-- PhysioNet shifts SepsisLabel 6 hours early, so onset = first labelled hour + 6.
-- Patients labelled on their first recorded hour were already septic on arrival:
-- there is nothing to warn about, so they are excluded from the alert analysis.
SELECT
    pid,
    split_part(pid, '_', 1)                                    AS hospital_set,
    COUNT(*)                                                   AS hours,
    MIN(ICULOS)                                                AS first_hour,
    MAX(ICULOS)                                                AS last_hour,
    MAX(SepsisLabel)                                           AS sepsis,
    MIN(CASE WHEN SepsisLabel = 1 THEN ICULOS END) + 6         AS onset_hour,
    CASE
        WHEN MAX(SepsisLabel) = 0                                         THEN 'no_sepsis'
        WHEN MIN(CASE WHEN SepsisLabel = 1 THEN ICULOS END) = MIN(ICULOS) THEN 'septic_on_arrival'
        ELSE 'sepsis'
    END                                                        AS grp
FROM raw
GROUP BY pid
