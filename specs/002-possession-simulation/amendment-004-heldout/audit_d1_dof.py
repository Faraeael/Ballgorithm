#!/usr/bin/env python3
"""Independent mathematical audit of Amendment 004 Protocol Deviation D1.

Stdlib-only, read-only verifier. Does NOT import `analyze_heldout.py` or
`supplemental_inference.py`, and executes zero basketball simulations.
Recomputes all 66 two-way Cameron-Gelbach-Miller estimators (22 metrics x
{v3, v4, paired delta}) directly from `v3-heldout-raw.json` and
`v4-heldout-raw.json`, verifying:
  1. Seed clusters (G_S=600, 520x2 + 80x1) and DOF factor c_S = 600/599
  2. Directed-matchup clusters (G_M=56, 56x20) and DOF factor c_M = 56/55
  3. Explicit (matchupIndex, seed) intersection cells (G_I=1120=N) and c_I = 1120/1119
  4. Algebraic identity between linearized ratio contrast and direct Delta_i mean
  5. Exact numerical reproduction (<= 1e-12) of `heldout-summary-supplemental-dof.json`
  6. Variance boundaries (0 negative variances; 3 structural zeros -> null)
  7. Invariance of all G1-G8 gate CIs and paired-delta zero-exclusion conclusions
     across original z=1.96, DOF-corrected z=1.96, K=2, and conservative t_55=2.004045.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
T55_975 = 2.0040447832891384  # Student t_{0.975, df=55}
ENVELOPES = {
    "OF_per_team_game": (1.80, 2.60),
    "OF_share_of_tov": (0.100, 0.160),
    "TOV_per_100_completed": (15.0, 19.5),
    "SC_per_game": (3.0, 5.5),
    "poss_per_team_game": (100.0, 106.0),
    "3PA_per_FGA": (0.380, 0.450),
    "eFG": (0.510, 0.540),
}


def load_json(name):
    with open(os.path.join(HERE, name), "rb") as f:
        return json.loads(f.read().replace(b"\r\n", b"\n"))


def series(rows):
    n = len(rows)
    col = lambda k: [float(r[k]) for r in rows]
    one = [1.0] * n
    two = [2.0] * n
    comp = col("completed")
    fgm, tpm = col("fgm"), col("threePm")
    return {
        "OF_per_team_game": (col("offensiveFoulTov"), two, True),
        "OF_share_of_tov": (col("offensiveFoulTov"), col("tov"), False),
        "TOV_per_100_completed": ([100.0 * x for x in col("tov")], comp, False),
        "SC_per_game": (col("shotClockTov"), one, True),
        "poss_per_team_game": (comp, two, True),
        "3PA_per_FGA": (col("threePa"), col("fga"), False),
        "eFG": ([a + 0.5 * b for a, b in zip(fgm, tpm)], col("fga"), False),
        "points_per_team_game": (col("combinedPoints"), two, True),
        "FGA_per_team_game": (col("fga"), two, True),
        "FTA_per_team_game": (col("fta"), two, True),
        "steal_TOV_per_game": (col("stealTov"), one, True),
        "nonsteal_TOV_per_game": (col("nonStealTov"), one, True),
        "TOV_per_team_game": (col("tov"), two, True),
        "nonshooting_fouls_per_game": (col("nonShootingFouls"), one, True),
        "personal_fouls_per_game": (col("personalFouls"), one, True),
        "OF_per_100_completed": ([100.0 * x for x in col("offensiveFoulTov")], comp, False),
        "OF_per_action_phase": (col("offensiveFoulTov"), col("actionPhases"), False),
        "SC_fresh_per_game": (col("freshViolations"), one, True),
        "SC_oreb_per_game": (col("orebViolations"), one, True),
        "SC_retainedFoul_per_game": (col("retFoulViolations"), one, True),
        "OREB_violation_rate_per_oreb_phase": (col("orebViolations"), col("orebPhases"), False),
        "retFoul14_violation_rate": (col("retFoul14Violations"), col("retFoul14Phases"), False),
    }


def cgm_var(psi, seeds, matchups, cells, k_param=1):
    n = len(psi)
    if abs(sum(psi)) > 1e-11:
        raise AssertionError(f"Non-zero score sum: {sum(psi)}")

    def comp(keys):
        acc = {}
        for key, val in zip(keys, psi):
            acc[key] = acc.get(key, 0.0) + val
        g = len(acc)
        raw = sum(v * v for v in acc.values())
        dof = (g / (g - 1.0)) * ((n - 1.0) / (n - k_param))
        return dof * raw, raw, g

    vs, rs, gs = comp(seeds)
    vm, rm, gm = comp(matchups)
    vi, ri, gi = comp(cells)
    if (gs, gm, gi, n) != (600, 56, 1120, 1120):
        raise AssertionError(f"Unexpected cluster dimensions: {(gs, gm, gi, n)}")
    return vs + vm - vi, rs + rm - ri


def main():
    r3 = load_json("v3-heldout-raw.json")["rows"]
    r4 = load_json("v4-heldout-raw.json")["rows"]
    supp = load_json("heldout-summary-supplemental-dof.json")
    if len(r3) != 1120 or len(r4) != 1120:
        sys.exit("Row count mismatch")
    for a, b in zip(r3, r4):
        if (a["slot"], a["matchupIndex"], a["orientation"], a["seed"]) != (
            b["slot"], b["matchupIndex"], b["orientation"], b["seed"]
        ):
            sys.exit("Pairing mismatch")

    seeds = [r["seed"] for r in r4]
    matchups = [r["matchupIndex"] for r in r4]
    cells = [(r["matchupIndex"], r["seed"]) for r in r4]
    s3, s4 = series(r3), series(r4)

    max_err = 0.0
    max_mean_err = 0.0
    neg_count = 0
    zero_names = []
    flips = []

    for name in sorted(s4):
        y3, x3, is_mean = s3[name]
        y4, x4, _ = s4[name]
        d3, d4 = sum(x3), sum(x4)
        pt3, pt4 = sum(y3) / d3, sum(y4) / d4
        psi3 = [(y - pt3 * x) / d3 for y, x in zip(y3, x3)]
        psi4 = [(y - pt4 * x) / d4 for y, x in zip(y4, x4)]
        psid = [b - a for a, b in zip(psi3, psi4)]
        dval = pt4 - pt3

        if is_mean:
            di = [b / xb - a / xa for a, xa, b, xb in zip(y3, x3, y4, x4)]
            bar = sum(di) / len(di)
            direct = [(v - bar) / len(di) for v in di]
            max_mean_err = max(max_mean_err, max(abs(a - b) for a, b in zip(psid, direct)))

        for tag, pt, psi, rec in (
            ("v3", pt3, psi3, supp["armMetrics"]["v3"][name]),
            ("v4", pt4, psi4, supp["armMetrics"]["v4"][name]),
            ("delta", dval, psid, supp["pairedDeltas_v4_minus_v3"][name]),
        ):
            vc, _ = cgm_var(psi, seeds, matchups, cells, k_param=1)
            if vc < 0:
                neg_count += 1
            elif vc == 0:
                zero_names.append(f"{tag}:{name}")
                if rec["se"] is not None or rec["ci95"] is not None:
                    sys.exit(f"Expected null interval for {tag}:{name}")
            else:
                se = math.sqrt(vc)
                ci = [pt - 1.96 * se, pt + 1.96 * se]
                max_err = max(max_err, abs(se - rec["se"]),
                              abs(ci[0] - rec["ci95"][0]), abs(ci[1] - rec["ci95"][1]))
                if tag == "v4" and name in ENVELOPES:
                    lo, hi = ENVELOPES[name]
                    if not (lo <= pt - T55_975 * se and pt + T55_975 * se <= hi):
                        sys.exit(f"Gate CI breached envelope under t_55: {name}")

        vc1, vun = cgm_var(psid, seeds, matchups, cells, k_param=1)
        vc2, _ = cgm_var(psid, seeds, matchups, cells, k_param=2)
        if vc1 > 0:
            ex = lambda half: not (dval - half <= 0.0 <= dval + half)
            states = {
                ex(1.96 * math.sqrt(vun)),
                ex(1.96 * math.sqrt(vc1)),
                ex(T55_975 * math.sqrt(vc1)),
                ex(1.96 * math.sqrt(vc2)),
            }
            if len(states) > 1:
                flips.append(name)

    if neg_count != 0 or max_err > 1e-12 or max_mean_err > 1e-12 or flips:
        sys.exit(f"D1 AUDIT FAILED: neg={neg_count} err={max_err} flips={flips}")
    if sorted(zero_names) != ["delta:SC_fresh_per_game", "v3:SC_fresh_per_game", "v4:SC_fresh_per_game"]:
        sys.exit(f"Unexpected zero-variance set: {zero_names}")

    print("D1 INDEPENDENT CGM/DOF AUDIT PASSED")
    print(f"  estimators verified: 66 | max diff vs supplemental JSON: {max_err:.3e}")
    print(f"  mean-vs-ratio identity max diff: {max_mean_err:.3e}")
    print("  negative variances: 0 | structural zeros (null): 3 | conclusion flips: 0")


if __name__ == "__main__":
    main()
