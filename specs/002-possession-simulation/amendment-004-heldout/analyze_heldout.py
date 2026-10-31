#!/usr/bin/env python3
"""Amendment 004 fresh held-out analysis (frozen before execution).

Usage (from this directory):
    python analyze_heldout.py

Reads v3-heldout-raw.json, v4-heldout-raw.json, t014-v4-fresh-raw.json and
writes heldout-paired.csv and heldout-summary.json (LF bytes). Thresholds are the
frozen Amendment 004 section 3.2 envelopes; nothing here is tunable.

Uncertainty: two-way (seed x matchup) cluster-robust variance
(Cameron-Gelbach-Miller) on linearized ratio estimators. Intersection
clusters are single games because (matchup, seed) is unique. The median FGA
uses a pigeonhole (independent seed/matchup cluster) bootstrap, fixed RNG seed.
"""
import csv
import io
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
N_EXPECTED = 1120

ENVELOPES = {
    "G1": ("offensive fouls per team-game", 1.80, 2.60),
    "G2": ("offensive-foul share of turnovers", 0.100, 0.160),
    "G3": ("turnovers per 100 completed possessions", 15.0, 19.5),
    "G4": ("shot-clock violations per game", 3.0, 5.5),
    "G5": ("completed possessions per team-game", 100.0, 106.0),
    "G6": ("team median FGA", 88.0, 95.0),
    "G7": ("3PA/FGA", 0.380, 0.450),
    "G8": ("eFG%", 0.510, 0.540),
}


def load(name):
    with open(os.path.join(HERE, name), "rb") as f:
        return json.loads(f.read().replace(b"\r\n", b"\n"))


def col(rows, key):
    return np.array([r[key] for r in rows], dtype=float)


def cluster_var(u, seed_ids, matchup_ids):
    """Two-way CGM variance of sum(u); intersection = individual rows."""
    v_s = sum(float(u[seed_ids == s].sum()) ** 2 for s in np.unique(seed_ids))
    v_m = sum(float(u[matchup_ids == m].sum()) ** 2 for m in np.unique(matchup_ids))
    v = v_s + v_m - float((u ** 2).sum())
    return v if v > 0 else max(v_s, v_m)


class Ratio:
    """Ratio estimator sum(num)/sum(den) with per-row score u = num - R*den."""

    def __init__(self, num, den):
        self.num, self.den = num, den
        self.r = float(num.sum() / den.sum())
        self.u = num - self.r * den
        self.d = float(den.sum())


def ci_ratio(est, sid, mid):
    se = math.sqrt(cluster_var(est.u, sid, mid)) / est.d
    return se, est.r - 1.96 * se, est.r + 1.96 * se


def ci_delta(e3, e4, sid, mid):
    z = e4.u / e4.d - e3.u / e3.d
    se = math.sqrt(cluster_var(z, sid, mid))
    d = e4.r - e3.r
    return d, se, d - 1.96 * se, d + 1.96 * se


def pigeonhole_median(a, b, sid, mid, reps=2000, seed=20261031):
    """Cluster bootstrap CI of the median of team-game FGA (home+away values)."""
    rng = np.random.default_rng(seed)
    su, mu = np.unique(sid), np.unique(mid)
    s_idx = {s: np.where(sid == s)[0] for s in su}
    m_idx = {m: np.where(mid == m)[0] for m in mu}
    out = []
    for _ in range(reps):
        sw = np.bincount(rng.integers(0, len(su), len(su)), minlength=len(su))
        mw = np.bincount(rng.integers(0, len(mu), len(mu)), minlength=len(mu))
        w = np.zeros(len(a))
        for k, s in enumerate(su):
            w[s_idx[s]] += sw[k]
        w2 = np.zeros(len(a))
        for k, m in enumerate(mu):
            w2[m_idx[m]] += mw[k]
        w = w * w2  # row multiplicity = seed-draw x matchup-draw
        vals = np.concatenate([a, b])
        ww = np.concatenate([w, w])
        order = np.argsort(vals, kind="stable")
        cw = np.cumsum(ww[order])
        out.append(float(vals[order][np.searchsorted(cw, cw[-1] / 2.0)]))
    return float(np.percentile(out, 2.5)), float(np.percentile(out, 97.5))


def arm_metrics(rows):
    n = len(rows)
    c = lambda k: col(rows, k)
    one = np.ones(n)
    comp = c("completed")
    ratios = {
        "OF_per_team_game": Ratio(c("offensiveFoulTov"), 2 * one),
        "OF_share_of_tov": Ratio(c("offensiveFoulTov"), c("tov")),
        "TOV_per_100_completed": Ratio(100 * c("tov"), comp),
        "SC_per_game": Ratio(c("shotClockTov"), one),
        "poss_per_team_game": Ratio(comp, 2 * one),
        "3PA_per_FGA": Ratio(c("threePa"), c("fga")),
        "eFG": Ratio(c("fgm") + 0.5 * c("threePm"), c("fga")),
        "points_per_team_game": Ratio(c("combinedPoints"), 2 * one),
        "FGA_per_team_game": Ratio(c("fga"), 2 * one),
        "FTA_per_team_game": Ratio(c("fta"), 2 * one),
        "steal_TOV_per_game": Ratio(c("stealTov"), one),
        "nonsteal_TOV_per_game": Ratio(c("nonStealTov"), one),
        "TOV_per_team_game": Ratio(c("tov"), 2 * one),
        "nonshooting_fouls_per_game": Ratio(c("nonShootingFouls"), one),
        "personal_fouls_per_game": Ratio(c("personalFouls"), one),
        "OF_per_100_completed": Ratio(100 * c("offensiveFoulTov"), comp),
        "OF_per_action_phase": Ratio(c("offensiveFoulTov"), c("actionPhases")),
        "SC_fresh_per_game": Ratio(c("freshViolations"), one),
        "SC_oreb_per_game": Ratio(c("orebViolations"), one),
        "SC_retainedFoul_per_game": Ratio(c("retFoulViolations"), one),
        "OREB_violation_rate_per_oreb_phase": Ratio(c("orebViolations"), c("orebPhases")),
        "retFoul14_violation_rate": Ratio(c("retFoul14Violations"), c("retFoul14Phases")),
    }
    return ratios


def main():
    v3 = load("v3-heldout-raw.json")
    v4 = load("v4-heldout-raw.json")
    t14 = load("t014-v4-fresh-raw.json")
    r3, r4 = v3["rows"], v4["rows"]
    problems = []
    if len(r3) != N_EXPECTED or len(r4) != N_EXPECTED:
        problems.append(f"row counts {len(r3)}/{len(r4)} != {N_EXPECTED}")
    for a, b in zip(r3, r4):
        if (a["slot"], a["matchupIndex"], a["orientation"], a["seed"], a["gameId"]) != (
            b["slot"], b["matchupIndex"], b["orientation"], b["seed"], b["gameId"]
        ):
            problems.append(f"pairing mismatch at slot {a['slot']}")
            break
    if {r["simulationVersion"] for r in r3} != {3} or {r["simulationVersion"] for r in r4} != {4}:
        problems.append("simulationVersion not 3/4")
    if problems:
        print("EXECUTION PROBLEMS:", problems)
        sys.exit(2)

    sid = col(r4, "seed").astype(int)
    mid = col(r4, "matchupIndex").astype(int)
    m3, m4 = arm_metrics(r3), arm_metrics(r4)

    arm = {}
    for tag, mm in (("v3", m3), ("v4", m4)):
        arm[tag] = {}
        for k, est in mm.items():
            se, lo, hi = ci_ratio(est, sid, mid)
            arm[tag][k] = {"value": est.r, "se": se, "ci95": [lo, hi]}
    delta = {}
    for k in m3:
        d, se, lo, hi = ci_delta(m3[k], m4[k], sid, mid)
        delta[k] = {"delta": d, "se": se, "ci95": [lo, hi],
                    "relative": d / m3[k].r if m3[k].r else None}

    fga3 = np.concatenate([col(r3, "homeFga"), col(r3, "awayFga")])
    fga4 = np.concatenate([col(r4, "homeFga"), col(r4, "awayFga")])
    med3, med4 = float(np.median(fga3)), float(np.median(fga4))
    med_ci = pigeonhole_median(col(r4, "homeFga"), col(r4, "awayFga"), sid, mid)

    values = {
        "G1": arm["v4"]["OF_per_team_game"]["value"],
        "G2": arm["v4"]["OF_share_of_tov"]["value"],
        "G3": arm["v4"]["TOV_per_100_completed"]["value"],
        "G4": arm["v4"]["SC_per_game"]["value"],
        "G5": arm["v4"]["poss_per_team_game"]["value"],
        "G6": med4,
        "G7": arm["v4"]["3PA_per_FGA"]["value"],
        "G8": arm["v4"]["eFG"]["value"],
    }
    cis = {
        "G1": arm["v4"]["OF_per_team_game"]["ci95"],
        "G2": arm["v4"]["OF_share_of_tov"]["ci95"],
        "G3": arm["v4"]["TOV_per_100_completed"]["ci95"],
        "G4": arm["v4"]["SC_per_game"]["ci95"],
        "G5": arm["v4"]["poss_per_team_game"]["ci95"],
        "G6": list(med_ci),
        "G7": arm["v4"]["3PA_per_FGA"]["ci95"],
        "G8": arm["v4"]["eFG"]["ci95"],
    }
    gates = {}
    for g, (name, lo, hi) in ENVELOPES.items():
        v = values[g]
        gates[g] = {"metric": name, "envelope": [lo, hi], "value": v,
                    "ci95": cis[g], "verdict": "PASS" if lo <= v <= hi else "FAIL"}

    fresh = {s["id"]: s["verdict"] for s in t14["summaries"]}
    g9_fresh_pass = (
        t14.get("seedOffset") == 10000
        and t14.get("simulationVersion") == 4
        and len(fresh) == 6
        and all(v == "PASSED" for v in fresh.values())
    )
    gates["G9"] = {
        "metric": "T014 E1-E6 attribute sensitivity (fresh seeds 10001-10200, simulation v4)",
        "evidence": "NEW independent run on fresh seeds; development evidence is separate",
        "experiments": {s["id"]: {"verdict": s["verdict"], "meanDifference": s["meanDifference"],
                                   "pValue": s["pValue"], "holmAdjustedP": s["holmAdjustedP"]}
                        for s in t14["summaries"]},
        "verdict": "PASS" if g9_fresh_pass else "FAIL",
    }

    rollback = {
        "OF_per_team_game_not_below_3.0": arm["v4"]["OF_per_team_game"]["value"] >= 3.0,
        "OF_share_above_18pct": arm["v4"]["OF_share_of_tov"]["value"] > 0.18,
        "3PA_rate_shift_pp_over_2.0": abs(delta["3PA_per_FGA"]["delta"]) * 100 > 2.0,
        "eFG_shift_pp_over_1.5": abs(delta["eFG"]["delta"]) * 100 > 1.5,
    }
    rollback_fired = {k: v for k, v in rollback.items() if v}

    all_pass = all(g["verdict"] == "PASS" for g in gates.values()) and not rollback_fired
    summary = {
        "task": "Amendment 004 fresh held-out validation",
        "games": {"v3": len(r3), "v4": len(r4), "total": len(r3) + len(r4)},
        "uniqueSeeds": int(len(np.unique(sid))),
        "frozenGates": gates,
        "rollbackTriggersFired": rollback_fired,
        "median_FGA": {"v3": med3, "v4": med4, "v4_ci95_pigeonhole": list(med_ci)},
        "armMetrics": arm,
        "pairedDeltas_v4_minus_v3": delta,
        "frozenRuleVerdict": "ALL FROZEN GATES PASS" if all_pass else "AT LEAST ONE FROZEN GATE OR ROLLBACK TRIGGER FAILED",
        "statistics": "two-way (seed x matchup) CGM cluster-robust variance on linearized ratio estimators; pigeonhole bootstrap for median; 95% normal CIs",
    }
    with open(os.path.join(HERE, "heldout-summary.json"), "wb") as f:
        f.write((json.dumps(summary, indent=2, sort_keys=True) + "\n").encode())

    keys = ["homeScore", "awayScore", "combinedPoints", "completed", "fga", "fgm",
            "threePa", "threePm", "fta", "ftm", "tov", "offensiveFoulTov", "stealTov",
            "nonStealTov", "shotClockTov", "nonShootingFouls", "personalFouls",
            "freshViolations", "orebViolations", "retFoulViolations"]
    head = ["slot", "matchupIndex", "orientation", "seed"] + [f"v3_{k}" for k in keys] + [f"v4_{k}" for k in keys]
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(head)
    for a, b in zip(r3, r4):
        w.writerow([a["slot"], a["matchupIndex"], a["orientation"], a["seed"]]
                   + [a[k] for k in keys] + [b[k] for k in keys])
    with open(os.path.join(HERE, "heldout-paired.csv"), "wb") as f:
        f.write(buf.getvalue().encode())

    for g, v in gates.items():
        print(g, v["verdict"], v.get("value", ""))
    print("rollback fired:", rollback_fired or "none")
    print(summary["frozenRuleVerdict"])


if __name__ == "__main__":
    main()
