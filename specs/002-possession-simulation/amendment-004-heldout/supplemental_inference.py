#!/usr/bin/env python3
"""Amendment 004 held-out SUPPLEMENTAL inference (manifest-conforming DOF correction).

WHY THIS EXISTS. The frozen `analyze_heldout.py` (protocol commit 0c7d552) computes
two-way Cameron-Gelbach-Miller variance WITHOUT the per-component small-sample
correction required by `amendment-003-seed-provenance-manifest.md` section 4
(`G/(G-1) * (N-1)/(N-K)` applied to each component), and it substitutes
`max(V_seed, V_matchup)` when the combined variance is non-positive. See
`PROTOCOL-DEVIATION.md`. The frozen script is left untouched; this script re-derives
ONLY the uncertainty intervals under the governing formula.

Fixed before it was written (not outcome-driven):
  * component corrections exactly as the manifest states, K = 1 (ratio estimator
    linearized to a mean of per-game scores);
  * G = number of clusters in that component: seeds 600, matchups 56, intersection
    cells 1120 (= N);
  * 95% normal intervals (1.96), as in the manifest;
  * NO fallback: a non-positive combined variance is reported as undefined (null);
  * point estimates, gate envelopes, verdict rule and G9 are NOT recomputed here.

Run from this directory: python supplemental_inference.py
"""
import json
import math
import os

import numpy as np

import analyze_heldout as frozen

HERE = os.path.dirname(os.path.abspath(__file__))
K = 1


def corrected_var(u, sid, mid):
    n = len(u)

    def comp(ids):
        groups = np.unique(ids)
        g = len(groups)
        v = sum(float(u[ids == x].sum()) ** 2 for x in groups)
        return v * (g / (g - 1)) * ((n - 1) / (n - K))

    v_s = comp(sid)
    v_m = comp(mid)
    cells = np.arange(n)  # (matchup, seed) is unique -> each game is its own cell
    v_i = comp(cells)
    return v_s + v_m - v_i, v_s, v_m, v_i


def interval(point, v, d):
    if v <= 0:
        return {"value": point, "se": None, "ci95": None, "note": "combined variance <= 0; undefined"}
    se = math.sqrt(v) / d
    return {"value": point, "se": se, "ci95": [point - 1.96 * se, point + 1.96 * se]}


def main():
    v3 = frozen.load("v3-heldout-raw.json")["rows"]
    v4 = frozen.load("v4-heldout-raw.json")["rows"]
    sid = frozen.col(v4, "seed").astype(int)
    mid = frozen.col(v4, "matchupIndex").astype(int)
    m3, m4 = frozen.arm_metrics(v3), frozen.arm_metrics(v4)

    arm, delta, undefined = {"v3": {}, "v4": {}}, {}, []
    for tag, mm in (("v3", m3), ("v4", m4)):
        for k, e in mm.items():
            v, *_ = corrected_var(e.u, sid, mid)
            arm[tag][k] = interval(e.r, v, e.d)
            if arm[tag][k]["ci95"] is None:
                undefined.append(f"{tag}:{k}")
    for k in m3:
        z = m4[k].u / m4[k].d - m3[k].u / m3[k].d
        v, *_ = corrected_var(z, sid, mid)
        d = m4[k].r - m3[k].r
        if v <= 0:
            delta[k] = {"delta": d, "se": None, "ci95": None, "note": "undefined"}
            undefined.append(f"delta:{k}")
        else:
            se = math.sqrt(v)
            delta[k] = {"delta": d, "se": se, "ci95": [d - 1.96 * se, d + 1.96 * se]}

    frozen_summary = json.load(open(os.path.join(HERE, "heldout-summary.json"), "rb"))
    comparison = {}
    for k in delta:
        a = frozen_summary["pairedDeltas_v4_minus_v3"][k]
        b = delta[k]
        if b["se"] is not None and a["se"]:
            comparison[k] = {"frozen_se": a["se"], "corrected_se": b["se"],
                             "se_ratio": b["se"] / a["se"],
                             "delta_ci_excludes_zero_frozen": not (a["ci95"][0] <= 0 <= a["ci95"][1]),
                             "delta_ci_excludes_zero_corrected": not (b["ci95"][0] <= 0 <= b["ci95"][1])}
    out = {
        "purpose": "manifest-conforming DOF-corrected uncertainty; point estimates and verdicts unchanged",
        "formula": "V = sum over {seed, matchup, cell} of sign * G/(G-1) * (N-1)/(N-K) * sum_g (sum_{i in g} u_i)^2; sign +,+,-; K=1; normal 95% CI",
        "clusters": {"seed": int(len(np.unique(sid))), "matchup": int(len(np.unique(mid))), "cell": len(v4)},
        "armMetrics": arm,
        "pairedDeltas_v4_minus_v3": delta,
        "undefinedIntervals": undefined,
        "frozenVsCorrected": comparison,
    }
    with open(os.path.join(HERE, "heldout-summary-supplemental-dof.json"), "wb") as f:
        f.write((json.dumps(out, indent=2, sort_keys=True) + "\n").encode())

    print("undefined intervals:", undefined or "none")
    for k in ("OF_per_team_game", "OF_share_of_tov", "TOV_per_100_completed", "SC_per_game",
              "poss_per_team_game", "3PA_per_FGA", "eFG", "points_per_team_game",
              "FGA_per_team_game", "OF_per_100_completed"):
        a, d = arm["v4"][k], delta[k]
        print(f"{k:26s} v4={a['value']:.4f} ci={[round(x, 4) for x in a['ci95']]} | "
              f"d={d['delta']:+.4f} ci={[round(x, 4) for x in d['ci95']]}")
    flips = {k: (v["delta_ci_excludes_zero_frozen"], v["delta_ci_excludes_zero_corrected"])
             for k, v in comparison.items()
             if v["delta_ci_excludes_zero_frozen"] != v["delta_ci_excludes_zero_corrected"]}
    print("delta-CI zero-exclusion flips (frozen, corrected):", flips or "none")
    print("SE ratio range:", min(v["se_ratio"] for v in comparison.values()),
          max(v["se_ratio"] for v in comparison.values()))


if __name__ == "__main__":
    main()
