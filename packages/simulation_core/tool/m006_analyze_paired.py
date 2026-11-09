import argparse
import csv
import hashlib
import json
import math
import random
from pathlib import Path

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def main():
    parser = argparse.ArgumentParser(description="M006 Version-Neutral Paired Analysis Tool")
    parser.add_argument("--v6", required=True, help="Path to v6 results JSON")
    parser.add_argument("--v7", required=True, help="Path to v7 results JSON")
    parser.add_argument("--manifest", required=True, help="Path to manifest CSV")
    parser.add_argument("--paired-csv", required=True, help="Path to output paired seeds CSV")
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

    # Generate paired seeds CSV
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
    paired_csv_path.parent.createSync(recursive=True) if hasattr(paired_csv_path, 'createSync') else paired_csv_path.parent.mkdir(parents=True, exist_ok=True)
    with open(paired_csv_path, "w", newline="") as out_f:
        writer = csv.DictWriter(out_f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(paired_rows)

    # Checksums
    manifest_sha = sha256_file(args.manifest)
    v6_sha = sha256_file(args.v6)
    v7_sha = sha256_file(args.v7)
    paired_sha = sha256_file(args.paired_csv)

    print("REPRODUCIBILITY AUDIT RESULTS:")
    print(f"Manifest: {args.manifest} (SHA-256: {manifest_sha})")
    print(f"v6 Export: {args.v6} (SHA-256: {v6_sha})")
    print(f"v7 Export: {args.v7} (SHA-256: {v7_sha})")
    print(f"Paired CSV: {args.paired_csv} (SHA-256: {paired_sha})")

    # Bootstrap
    metrics_to_stat = [
        ("primaryShare", "Primary creator share", None),
        ("secondaryShare", "Secondary creator share", None),
        ("neutralShare", "Neutral player share", None),
        ("weakShooterThreePointShare", "Weak-shooter 3PA share (eligible)", lambda g6, g7: g6["weakEligible"] and g7["weakEligible"]),
        ("stretchBigThreePointShare", "Stretch-big 3PA share (eligible)", lambda g6, g7: g6["stretchEligible"] and g7["stretchEligible"]),
        ("totalPoints", "Points per game", None),
        ("possessions", "Possessions per game", None),
        ("eFG", "eFG%", None),
        ("threePointShare", "Team 3PA/FGA share", None),
        ("turnoversPer100", "Turnovers per 100", None),
        ("fta", "Free throw attempts", None),
    ]

    rng = random.Random(args.bootstrap_seed)
    B = args.bootstrap_rounds

    print("\nREPRODUCED METRIC ESTIMATES:")
    print(f"{'Metric':<36} {'v6 Mean':<10} {'v7 Mean':<10} {'Diff':<10} {'SD':<10} {'Median':<10} {'95% Bootstrap CI'}")
    print("-" * 105)

    for key, label, elig_filter in metrics_to_stat:
        v6_list = []
        v7_list = []
        diffs = []
        for g6, g7 in zip(v6_games, v7_games):
            if elig_filter and not elig_filter(g6, g7):
                continue
            val6 = g6[key]
            val7 = g7[key]
            if val6 is not None and val7 is not None:
                v6_list.append(val6)
                v7_list.append(val7)
                diffs.append(val7 - val6)

        n = len(diffs)
        mean_v6 = sum(v6_list) / n
        mean_v7 = sum(v7_list) / n
        mean_diff = sum(diffs) / n
        var_diff = sum((d - mean_diff) ** 2 for d in diffs) / (n - 1) if n > 1 else 0
        sd_diff = math.sqrt(var_diff)
        diffs_sorted = sorted(diffs)
        med_diff = diffs_sorted[n // 2] if n % 2 != 0 else (diffs_sorted[n // 2 - 1] + diffs_sorted[n // 2]) / 2

        boot_means = []
        for _ in range(B):
            sample = [diffs[rng.randrange(n)] for _ in range(n)]
            boot_means.append(sum(sample) / n)
        boot_means.sort()
        ci_low = boot_means[int(0.025 * B)]
        ci_high = boot_means[int(0.975 * B)]

        print(f"{label:<36} {mean_v6:<10.5f} {mean_v7:<10.5f} {mean_diff:<10.5f} {sd_diff:<10.5f} {med_diff:<10.5f} [{ci_low:.5f}, {ci_high:.5f}] (N={n})")

if __name__ == "__main__":
    main()
