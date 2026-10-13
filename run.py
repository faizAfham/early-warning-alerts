"""Runs every sql/*.sql file on DuckDB, then the matched-alert-load comparison and charts.

Usage:  ./download_data.sh   (once)   then   python run.py
Each SQL file's result is registered as a table named after the file
(e.g. 03_rule_grid.sql -> rule_grid) so later files can build on it. Results with up to
5,000 rows are also saved to results/<file>.csv (the hourly table is too big to keep).
"""
import json
import os
from pathlib import Path

import duckdb
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).parent
RES, CH = ROOT / "results", ROOT / "charts"
RES.mkdir(exist_ok=True); CH.mkdir(exist_ok=True)
NAVY, GREY, DARK, GRID = "#1f3a5f", "#9aa3ad", "#1b1f24", "#dfe2e6"
PARTIAL = os.environ.get("PARTIAL") == "1"   # dev runs on a half-downloaded data folder

# ---------------------------------------------------------------- SQL
con = duckdb.connect()
con.sql(f"CREATE TABLE raw AS SELECT * FROM read_csv('{ROOT}/data/vitals.psv', delim='|', header=true, nullstr='NaN')")
r = {}
for f in sorted((ROOT / "sql").glob("*.sql")):
    name = f.stem.split("_", 1)[1]
    con.sql(f"CREATE OR REPLACE TABLE {name} AS {f.read_text().strip().rstrip(';')}")
    n = con.sql(f"SELECT COUNT(*) FROM {name}").fetchone()[0]
    if n <= 5000:
        r[name] = con.sql(f"SELECT * FROM {name}").df()
        r[name].to_csv(RES / f"{f.stem}.csv", index=False)
    print(f"{f.name:28s} {n:>9,} rows")

cohort = con.sql("SELECT grp, COUNT(*) AS n, SUM(hours) AS hours FROM cohort GROUP BY grp").df().set_index("grp")
n_raw_rows = con.sql("SELECT COUNT(*) FROM raw").fetchone()[0]
n_pat = int(cohort.n.sum())
grid, gaps, drivers = r["rule_grid"], r["measurement_gaps"].iloc[0], r["false_alarm_drivers"].iloc[0]

# ---------------------------------------------------------------- sanity checks
if not PARTIAL:
    assert n_pat == 40_336, n_pat                     # 20,336 (set A) + 20,000 (set B), per PhysioNet
    assert n_raw_rows == 1_552_210, n_raw_rows        # one row per ICU hour across all 40,336 stays
assert int(cohort.hours.sum()) == n_raw_rows          # every row belongs to exactly one stay
n_sepsis = int(cohort.n.get("sepsis", 0))
assert (grid.sepsis_patients == n_sepsis).all()       # every rule is scored on the same cohort
for (s, p), g in grid.groupby(["score_name", "persistence"]):
    g = g.sort_values("threshold")                    # a stricter rule can only catch fewer and fire less
    assert g.sensitivity.is_monotonic_decreasing, (s, p)
    assert g.alarm_hour_share.is_monotonic_decreasing, (s, p)
    assert g[g.threshold >= 3].alerts_per_patient_day.is_monotonic_decreasing, (s, p)   # below 3 the alarm saturates
assert grid.ppv.between(0, 1).all() and grid.sensitivity.between(0, 1).all()
hours_scored = con.sql("SELECT COUNT(*) FROM hourly_scores").fetchone()[0]
assert hours_scored < n_raw_rows                      # post-onset and septic-on-arrival hours removed

# ---------------------------------------------------------------- matched alert load
def curve(score, persistence):
    g = grid[(grid.score_name == score) & (grid.persistence == persistence) & (grid.threshold >= 3)]
    g = g.sort_values("alerts_per_patient_day")      # >= 3: where alert load falls as the bar rises
    return g.alerts_per_patient_day.to_numpy(), g.sensitivity.to_numpy()

def sens_at(score, persistence, load):
    x, y = curve(score, persistence)
    return float(np.interp(load, x, y))

def pick(score, threshold, persistence):
    row = grid[(grid.score_name == score) & (grid.threshold == threshold) & (grid.persistence == persistence)]
    return row.iloc[0].to_dict()

ref = pick("full", 5, 1)                              # NEWS2 "medium" trigger, the ward standard
ref_p2 = pick("full", 5, 2)
load = ref["alerts_per_patient_day"]
summary = {
    "patients": n_pat, "hours": int(n_raw_rows), "hours_scored": int(hours_scored),
    "sepsis": n_sepsis, "septic_on_arrival": int(cohort.n.get("septic_on_arrival", 0)),
    "no_sepsis": int(cohort.n.get("no_sepsis", 0)),
    "news2_5": ref, "news2_5_persist2": ref_p2,
    "persist2_load_cut": 1 - ref_p2["alerts_per_patient_day"] / ref["alerts_per_patient_day"],
    "persist2_sens_drop_pts": 100 * (ref["sensitivity"] - ref_p2["sensitivity"]),
    "alt_4_persist2": pick("full", 4, 2),               # lower bar + 2-hour persistence
    "alt_4_persist2_load_cut": 1 - pick("full", 4, 2)["alerts_per_patient_day"] / load,
    "hr_rr_sens_at_news2_5_load": sens_at("hr_rr", 1, load),
    "hr_rr_sens_at_news2_5_p2_load": sens_at("hr_rr", 1, ref_p2["alerts_per_patient_day"]),
    "full_sens_at_news2_5_load": ref["sensitivity"],
    "hr_rr_rules": {int(t): pick("hr_rr", t, 1) for t in range(1, 7)},
    "fresh_share": {k: float(gaps[f"{k}_fresh_share"]) for k in ["hr", "rr", "spo2", "sbp", "temp"]},
    "false_alarm_drivers": {k: float(drivers[f"{k}_share"]) for k in ["hr", "rr", "spo2", "sbp", "temp"]},
}
assert abs(summary["alt_4_persist2"]["sensitivity"] - ref["sensitivity"]) < 0.01   # same catch rate as NEWS2 >= 5
(RES / "summary.json").write_text(json.dumps(summary, indent=2, default=float))

# ---------------------------------------------------------------- charts
plt.rcParams.update({"font.family": "Helvetica", "font.size": 9, "axes.edgecolor": GREY,
                     "axes.labelcolor": DARK, "xtick.color": DARK, "ytick.color": DARK})

def style(ax):
    ax.spines[["top", "right"]].set_visible(False)
    ax.grid(color=GRID, lw=0.6); ax.set_axisbelow(True)

# 1 · catch rate vs alert load, full vs HR+RR
fig, ax = plt.subplots(figsize=(6.4, 3.4))
for score, colour, label, dy in [("full", NAVY, "All 5 vitals (charted NEWS2)", 7), ("hr_rr", GREY, "HR + RR only (contactless)", -12)]:
    g = grid[(grid.score_name == score) & (grid.persistence == 1) & (grid.threshold >= 3)].sort_values("threshold")
    ax.plot(g.alerts_per_patient_day, 100 * g.sensitivity, "-o", color=colour, ms=4, lw=1.8, label=label)
    for _, row in g.iterrows():
        ax.annotate(f"≥{int(row.threshold)}", (row.alerts_per_patient_day, 100 * row.sensitivity),
                    textcoords="offset points", xytext=(-4 if dy > 0 else 4, dy), fontsize=7, color=colour,
                    ha="right" if dy > 0 else "left")
ax.axvline(load, color=DARK, lw=0.8, ls="--")
ax.text(load * 1.04, 3, "NEWS2 ≥5\nalert load", fontsize=7, color=DARK)
ax.set_xscale("log")
ax.set_xlabel("Alerts per patient-day (log scale)")
ax.set_ylabel("Sepsis patients alerted\nin the 12 h before onset (%)")
ax.legend(frameon=False, loc="upper left"); style(ax)
fig.tight_layout(); fig.savefig(CH / "1_catch_vs_load.png", dpi=200); plt.close(fig)

# 2 · persistence rule: what 2 hours of patience buys
fig, ax = plt.subplots(figsize=(6.4, 3.0))
g1 = grid[(grid.score_name == "full") & (grid.persistence == 1)].set_index("threshold")
g2 = grid[(grid.score_name == "full") & (grid.persistence == 2)].set_index("threshold")
ts = [3, 4, 5, 6, 7]
xi = np.arange(len(ts))
ax.bar(xi - 0.2, g1.loc[ts].alerts_per_patient_day, 0.4, color=NAVY, label="Fire on first high hour")
ax.bar(xi + 0.2, g2.loc[ts].alerts_per_patient_day, 0.4, color=GREY, label="Fire after 2 high hours")
ax.set_xticks(xi, [f"Score ≥{t}" for t in ts]); ax.set_ylabel("Alerts per patient-day")
ax.legend(frameon=False); style(ax)
fig.tight_layout(); fig.savefig(CH / "2_persistence.png", dpi=200); plt.close(fig)

# 3 · what drives false alarms
fig, ax = plt.subplots(figsize=(6.4, 2.4))
names = ["Resp. rate", "Systolic BP", "SpO2", "Heart rate", "Temperature"]
keys = ["rr", "sbp", "spo2", "hr", "temp"]
vals = [100 * summary["false_alarm_drivers"][k] for k in keys]
ax.barh(names[::-1], vals[::-1], color=[NAVY if k == "rr" else GREY for k in keys][::-1])
for i, v in enumerate(vals[::-1]):
    ax.text(v + 1, i, f"{v:.0f}%", va="center", fontsize=8)
ax.set_xlim(0, 100); ax.set_xlabel("Share of false high-score hours (score ≥5, no sepsis) where this vital adds ≥2 points (%)")
style(ax)
fig.tight_layout(); fig.savefig(CH / "3_false_alarm_drivers.png", dpi=200); plt.close(fig)

print(json.dumps({k: v for k, v in summary.items() if k != "hr_rr_rules"}, indent=1, default=float))
