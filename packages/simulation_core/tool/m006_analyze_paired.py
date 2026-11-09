import argparse
import csv
import hashlib
import json
import math
import random
from pathlib import Path
from scipy import stats

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def holm_step_down(p_values_dict, alpha=0.05):
    """
    Correct dynamic Holm-Bonferroni step-down procedure.
    p_values_dict: dict of {name: p_value}
    Sorts p-values ascending and stops rejecting at first non-rejection.
    """
    K = len(p_values_dict)
    sorted_items = sorted(p_values_dict.items(), key=lambda x: x[1])

    results = {}
    stopped = False
    for rank_0, (name, p_val) in enumerate(sorted_items):
        rank = rank_0 + 1
        threshold = alpha / (K - rank + 1)
        if not stopped and p_val <= threshold:
            rejected = True
        else:
            rejected = False
            stopped = True

        results[name] = {
            "p_value": p_val,
            "sorted_rank": rank,
            "alpha_threshold": threshold,
            "rejected": rejected,
        }
    return results

def main():
    parser = argparse.ArgumentParser(description="M006 Confirmatory Paired Analysis Tool")
    parser.add_argument("--v6", required=True, help="Path to v6 results JSON")
    parser.add_argument("--v7", required=True, help="Path to v7 results JSON")
    parser.add_argument("--manifest", required=True, help="Path to manifest CSV")
    parser.add_argument("--paired-csv", required=True, help="Path to output paired seeds CSV")
    parser.add_argument("--context", choices=["A", "B"], default="A", help="Evaluation context (A or B)")
    parser.add_argument("--bootstrap-seed", type=int, default=20261109, help="PRNG seed for bootstrap")
    parser.add_argument("--bootstrap-rounds", type=int, default=10000, help="Number of bootstrap resamples")
    args = parser.parse_args()

    v6_games = json.loads(Path(args.v6).read_text())
    v7_games = json.loads(Path(args.v7).read_text())

    assert len(v6_games) == len(v7_games), "Game count mismatch"
    N = len(v6_games)

    v6_by_seed = {g["seed"]: g for g in v6_games}
    v7_by_seed = {g["seed"]: g for g in v7_games}

    with open(args.manifest, newline="") as mf:
        manifest_rows = list(csv.DictReader(mf))
    manifest_seeds = [int(r["seed"]) for r in manifest_rows]

    # Check reducer and accounting validity
    v6_valid = all(g.get("accountingConsistent", False) for g in v6_games)
    v7_valid = all(g.get("accountingConsistent", False) for g in v7_games)

    fieldnames = [
        "seed", "gameId",
        "v6_pts", "v7_pts", "diff_pts",
        "v6_poss", "v7_poss", "diff_poss",
        "v6_efg", "v7_efg", "diff_efg",
        "v6_fga", "v7_fga", "diff_fga",
        "v6_3pa", "v7_3pa", "diff_3pa",
        "v6_3p_share", "v7_3p_share", "diff_3p_share",
        "v6_tov100", "v7_tov100", "diff_tov100",
        "v6_fta", "v7_fta", "diff_fta",
        "v6_primary_share", "v7_primary_share", "diff_primary_share",
        "v6_secondary_share", "v7_secondary_share", "diff_secondary_share",
        "v6_neutral_share", "v7_neutral_share", "diff_neutral_share",
        "v6_weak_3p_share", "v7_weak_3p_share", "diff_weak_3p_share", "weak_eligible",
        "v6_stretch_3p_share", "v7_stretch_3p_share", "diff_stretch_3p_share", "stretch_eligible",
    ]

    paired_rows = []
    for seed in manifest_seeds:
        g6 = v6_by_seed[seed]
        g7 = v7_by_seed[seed]

        w_diff = None
        if g6["weakShooterThreePointShare"] is not None and g7["weakShooterThreePointShare"] is not None:
            w_diff = g7["weakShooterThreePointShare"] - g6["weakShooterThreePointShare"]

        s_diff = None
        if g6["stretchBigThreePointShare"] is not None and g7["stretchBigThreePointShare"] is not None:
            s_diff = g7["stretchBigThreePointShare"] - g6["stretchBigThreePointShare"]

        paired_rows.append({
            "seed": seed,
            "gameId": g6["gameId"],
            "v6_pts": g6["totalPoints"],
            "v7_pts": g7["totalPoints"],
            "diff_pts": g7["totalPoints"] - g6["totalPoints"],
            "v6_poss": g6["possessions"],
            "v7_poss": g7["possessions"],
            "diff_poss": g7["possessions"] - g6["possessions"],
            "v6_efg": f"{g6['eFG']:.5f}",
            "v7_efg": f"{g7['eFG']:.5f}",
            "diff_efg": f"{g7['eFG'] - g6['eFG']:.5f}",
            "v6_fga": g6["fga"],
            "v7_fga": g7["fga"],
            "diff_fga": g7["fga"] - g6["fga"],
            "v6_3pa": g6["threePa"],
            "v7_3pa": g7["threePa"],
            "diff_3pa": g7["threePa"] - g6["threePa"],
            "v6_3p_share": f"{g6['threePointShare']:.5f}",
            "v7_3p_share": f"{g7['threePointShare']:.5f}",
            "diff_3p_share": f"{g7['threePointShare'] - g6['threePointShare']:.5f}",
            "v6_tov100": f"{g6['turnoversPer100']:.5f}",
            "v7_tov100": f"{g7['turnoversPer100']:.5f}",
            "diff_tov100": f"{g7['turnoversPer100'] - g6['turnoversPer100']:.5f}",
            "v6_fta": g6["fta"],
            "v7_fta": g7["fta"],
            "diff_fta": g7["fta"] - g6["fta"],
            "v6_primary_share": f"{g6['primaryShare']:.5f}",
            "v7_primary_share": f"{g7['primaryShare']:.5f}",
            "diff_primary_share": f"{g7['primaryShare'] - g6['primaryShare']:.5f}",
            "v6_secondary_share": f"{g6['secondaryShare']:.5f}",
            "v7_secondary_share": f"{g7['secondaryShare']:.5f}",
            "diff_secondary_share": f"{g7['secondaryShare'] - g6['secondaryShare']:.5f}",
            "v6_neutral_share": f"{g6['neutralShare']:.5f}",
            "v7_neutral_share": f"{g7['neutralShare']:.5f}",
            "diff_neutral_share": f"{g7['neutralShare'] - g6['neutralShare']:.5f}",
            "v6_weak_3p_share": f"{g6['weakShooterThreePointShare']:.5f}" if g6['weakShooterThreePointShare'] is not None else "",
            "v7_weak_3p_share": f"{g7['weakShooterThreePointShare']:.5f}" if g7['weakShooterThreePointShare'] is not None else "",
            "diff_weak_3p_share": f"{w_diff:.5f}" if w_diff is not None else "",
            "weak_eligible": "1" if (g6["weakEligible"] and g7["weakEligible"]) else "0",
            "v6_stretch_3p_share": f"{g6['stretchBigThreePointShare']:.5f}" if g6['stretchBigThreePointShare'] is not None else "",
            "v7_stretch_3p_share": f"{g7['stretchBigThreePointShare']:.5f}" if g7['stretchBigThreePointShare'] is not None else "",
            "diff_stretch_3p_share": f"{s_diff:.5f}" if s_diff is not None else "",
            "stretch_eligible": "1" if (g6["stretchEligible"] and g7["stretchEligible"]) else "0",
        })

    paired_csv_path = Path(args.paired_csv)
    paired_csv_path.parent.mkdir(parents=True, exist_ok=True)
    with open(paired_csv_path, "w", newline="") as out_f:
        writer = csv.DictWriter(out_f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(paired_rows)

    manifest_sha = sha256_file(args.manifest)
    v6_sha = sha256_file(args.v6)
    v7_sha = sha256_file(args.v7)
    paired_sha = sha256_file(args.paired_csv)

    print("M006 CONFIRMATORY EVALUATION AUDIT:")
    print(f"Context: {args.context} (N={N})")
    print(f"Manifest: {args.manifest} (SHA-256: {manifest_sha})")
    print(f"v6 Export: {args.v6} (SHA-256: {v6_sha})")
    print(f"v7 Export: {args.v7} (SHA-256: {v7_sha})")
    print(f"Paired CSV: {args.paired_csv} (SHA-256: {paired_sha})")
    print(f"Accounting & Reducer Validity: v6={v6_valid}, v7={v7_valid}")

    # Primary Endpoints Evaluation
    # Context A has Endpoints 1, 2, 4; Context B has Endpoint 3
    if args.context == "A":
        # Extract per-game differences for all defined pairs
        def get_diffs(key):
            diffs = []
            for g6, g7 in zip(v6_games, v7_games):
                v6_val = g6[key]
                v7_val = g7[key]
                if v6_val is not None and v7_val is not None:
                    diffs.append(v7_val - v6_val)
            return diffs

        p1_diffs = get_diffs("primaryShare")
        p2_diffs = get_diffs("weakShooterThreePointShare")
        p4_diffs = get_diffs("secondaryShare")

        # Insufficiency check
        weak_exposure_count = sum(1 for g6, g7 in zip(v6_games, v7_games) if g6["weakEligible"] and g7["weakEligible"])
        print(f"\nContext A Insufficiency Checks:")
        print(f"  Defined weak-shooter games: {len(p2_diffs)} / {N} (requirement: >= 600/750)")
        print(f"  Paired weak FGA >= 20 exposure: {weak_exposure_count} / {N} (requirement: >= 600/750)")

        # One-sided paired t-tests
        # Endpoint 1: H0: delta <= +0.030, H1: delta > +0.030
        mean_p1 = sum(p1_diffs) / len(p1_diffs)
        sd_p1 = stats.tstd(p1_diffs)
        se_p1 = sd_p1 / math.sqrt(len(p1_diffs))
        t_p1 = (mean_p1 - 0.030) / se_p1
        df_p1 = len(p1_diffs) - 1
        pval_p1 = 1 - stats.t.cdf(t_p1, df=df_p1)

        # Endpoint 2: H0: delta >= -0.035, H1: delta < -0.035
        mean_p2 = sum(p2_diffs) / len(p2_diffs)
        sd_p2 = stats.tstd(p2_diffs)
        se_p2 = sd_p2 / math.sqrt(len(p2_diffs))
        t_p2 = (mean_p2 - (-0.035)) / se_p2
        df_p2 = len(p2_diffs) - 1
        pval_p2 = stats.t.cdf(t_p2, df=df_p2)

        # Endpoint 4: H0: delta <= +0.005, H1: delta > +0.005
        mean_p4 = sum(p4_diffs) / len(p4_diffs)
        sd_p4 = stats.tstd(p4_diffs)
        se_p4 = sd_p4 / math.sqrt(len(p4_diffs))
        t_p4 = (mean_p4 - 0.005) / se_p4
        df_p4 = len(p4_diffs) - 1
        pval_p4 = 1 - stats.t.cdf(t_p4, df=df_p4)

        print("\nContext A Primary Endpoints (Paired Student's t-test):")
        print(f"  Primary Creator Share: mean_diff={mean_p1*100:+.2f} pp, t={t_p1:.3f}, p={pval_p1:.4e} (H0: delta <= +3.0 pp)")
        print(f"  Weak-Shooter 3PA Share: mean_diff={mean_p2*100:+.2f} pp, t={t_p2:.3f}, p={pval_p2:.4e} (H0: delta >= -3.5 pp)")
        print(f"  Secondary Creator Share: mean_diff={mean_p4*100:+.2f} pp, t={t_p4:.3f}, p={pval_p4:.4e} (H0: delta <= +0.5 pp)")

        # TOST Guardrails (alpha=0.05, 90% CI)
        guardrails = [
            ("totalPoints", "Points per game", 2.5),
            ("possessions", "Pace (possessions)", 1.5),
            ("eFG", "eFG%", 0.010),
            ("turnoversPer100", "Turnovers per 100", 0.75),
            ("fta", "Free throw attempts", 1.75),
        ]
        print("\nContext A Macroeconomic Guardrails (TOST Equivalence at alpha=0.05 / 90% CI):")
        all_guard_passed = True
        df_guard = N - 1
        t_crit_90 = stats.t.ppf(0.95, df=df_guard)
        for key, label, delta in guardrails:
            diffs = get_diffs(key)
            m = sum(diffs) / len(diffs)
            s = stats.tstd(diffs)
            se = s / math.sqrt(len(diffs))
            ci_low = m - t_crit_90 * se
            ci_high = m + t_crit_90 * se
            passed = ci_low >= -delta and ci_high <= delta
            all_guard_passed &= passed
            print(f"  {label:<22}: diff={m:+.4f}, 90% CI=[{ci_low:+.4f}, {ci_high:+.4f}], bounds=[{-delta:+.4f}, {+delta:+.4f}] => {'PASS' if passed else 'FAIL'}")

        print(f"\nAll Guardrails Passed: {all_guard_passed}")

    elif args.context == "B":
        # Context B has Endpoint 3: Stretch-Big 3PA Share non-inferiority
        p3_diffs = []
        for g6, g7 in zip(v6_games, v7_games):
            v6_val = g6["stretchBigThreePointShare"]
            v7_val = g7["stretchBigThreePointShare"]
            if v6_val is not None and v7_val is not None:
                p3_diffs.append(v7_val - v6_val)

        stretch_exposure_count = sum(1 for g6, g7 in zip(v6_games, v7_games) if g6["stretchEligible"] and g7["stretchEligible"])
        print(f"\nContext B Insufficiency Checks:")
        print(f"  Defined stretch-center games: {len(p3_diffs)} / {N} (requirement: >= 200/250)")
        print(f"  Paired stretch FGA >= 10 exposure: {stretch_exposure_count} / {N} (requirement: >= 160/250)")

        # One-sided non-inferiority t-test
        # H0: delta <= -0.015, H1: delta > -0.015
        mean_p3 = sum(p3_diffs) / len(p3_diffs)
        sd_p3 = stats.tstd(p3_diffs)
        se_p3 = sd_p3 / math.sqrt(len(p3_diffs))
        t_p3 = (mean_p3 - (-0.015)) / se_p3
        df_p3 = len(p3_diffs) - 1
        pval_p3 = 1 - stats.t.cdf(t_p3, df=df_p3)

        print("\nContext B Primary Endpoint (Paired Student's t-test):")
        print(f"  Stretch-Big 3PA Share (Non-Inf): mean_diff={mean_p3*100:+.2f} pp, t={t_p3:.3f}, p={pval_p3:.4e} (H0: delta <= -1.5 pp)")

if __name__ == "__main__":
    main()
