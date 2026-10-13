# Early-Warning Alerts vs Alert Fatigue

How many deteriorating patients does a vital-sign alert rule catch, how early, and how many alarms does the ward pay for it? This is a SQL-first analysis of 40,336 ICU stays (1,552,210 patient-hours) from the PhysioNet/CinC Challenge 2019, using sepsis onset as the "getting worse" event.

Report: `case-study.html` → `ews-case-study.pdf` (5 A4 pages). Author: Mohammad Faiz Ahmad, IIT Patna.

## Findings (all from `results/summary.json` and `results/03_rule_grid.csv`)
- **NEWS2 ≥ 5** (the ward standard) alerts 59.7% of sepsis patients in the 12 h before onset, with a median lead of 10 h. It costs 1.26 alarms per patient-day, and only 2.9% of alarms come before a sepsis case (about 34 alarms per true warning).
- **Persistence:** firing only after 2 high hours at threshold 5 cuts alarms 58% but loses 18.8 points of catch rate. At **threshold 4 + 2 hours**, the catch rate is the same (59.6%) with **28% fewer alarms**.
- **HR + RR only** (what a contactless sensor reads): at the NEWS2 ≥ 5 alarm load it catches 57.6% vs 59.7%, which is 96% of the five-vital detection.
- **False alarms:** breathing rate adds 2+ points in 83% of no-sepsis hours with a score of 5+.

## Limitations
ICU, not ward or home data. Sepsis stands in for deterioration, so precision is a lower bound. Scoring is retrospective on charted values with last observation carried forward. Modified NEWS2 (no consciousness or oxygen fields). No Dozee data is used.

## Reproduce
```sh
python3 -m venv .venv && .venv/bin/pip install duckdb pandas matplotlib numpy
./download_data.sh          # ~40k small files from PhysioNet's open S3 mirror -> data/vitals.psv
.venv/bin/python run.py     # ~1 min: results/*.csv, results/summary.json, charts/*.png
```

## Layout
`sql/` five numbered queries · `run.py` pipeline + assert checks + charts · `results/` CSVs + `summary.json` · `charts/` 3 PNGs · `case-study.html`, `ews-case-study.pdf`.

Data: Reyna MA et al., *Crit Care Med* 2020;48(2):210–217. PhysioNet, CC BY 4.0.
