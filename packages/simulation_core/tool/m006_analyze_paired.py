import argparse
import csv
import hashlib
import json
import math
import sys
from pathlib import Path
import numpy as np
from scipy import stats

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def fail(msg, code=1):
    sys.stderr.write(f"VALIDATION ERROR: {msg}\n")
    sys.exit(code)

def main():
    parser = argparse.ArgumentParser(description="M006 Hardened Paired Analysis Tool")
    parser.add_argument("--v6", required=True, help="Path to v6 results JSON")
    parser.add_argument("--v7", required=True, help="Path to v7 results JSON")
    parser.add_argument("--manifest", required=True, help="Path to manifest CSV")
    parser.add_argument("--paired-csv", required=True, help="Path to output paired seeds CSV")
    parser.add_argument("--context", choices=["A", "B"], required=True, help="Evaluation context (A or B)")
    parser.add_argument("--summary-out", required=True, help="Path to output context summary JSON")
    parser.add_argument("--expected-manifest-sha", help="Expected SHA-256 of manifest")
    parser.add_argument("--expected-size", type=int, help="Expected number of games in cohort")
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    if not manifest_path.exists():
        fail(f"Manifest not found: {args.manifest}")

    manifest_sha = sha256_file(manifest_path)
    if args.expected_manifest_sha and manifest_sha != args.expected_manifest_sha:
        fail(f"Manifest SHA mismatch: got {manifest_sha}, expected {args.expected_manifest_sha}")

    # Read manifest
    with open(manifest_path, newline="") as mf:
        manifest_rows = list(csv.DictReader(mf))

    N_manifest = len(manifest_rows)
    if args.expected_size and N_manifest != args.expected_size:
        fail(f"Manifest row count {N_manifest} != expected {args.expected_size}")

    manifest_seeds = []
    manifest_by_seed = {}
    for r in manifest_rows:
        try:
            s = int(r["seed"])
        except (ValueError, KeyError):
            fail(f"Invalid seed in manifest row: {r}")
        if s in manifest_by_seed:
            fail(f"Duplicate seed in manifest: {s}")
        manifest_seeds.append(s)
        manifest_by_seed[s] = r

    # Load exports
    v6_path = Path(args.v6)
    v7_path = Path(args.v7)
    if not v6_path.exists():
        fail(f"v6 export not found: {args.v6}")
    if not v7_path.exists():
        fail(f"v7 export not found: {args.v7}")

    v6_sha = sha256_file(v6_path)
    v7_sha = sha256_file(v7_path)

    try:
        v6_games = json.loads(v6_path.read_text())
    except Exception as e:
        fail(f"Failed to parse v6 JSON: {e}")

    try:
        v7_games = json.loads(v7_path.read_text())
    except Exception as e:
        fail(f"Failed to parse v7 JSON: {e}")

    if len(v6_games) != N_manifest:
        fail(f"v6 export has {len(v6_games)} games, expected {N_manifest}")
    if len(v7_games) != N_manifest:
        fail(f"v7 export has {len(v7_games)} games, expected {N_manifest}")

    # Index by seed and validate uniqueness
    v6_by_seed = {}
    for g in v6_games:
        s = g.get("seed")
        if s is None or not isinstance(s, int):
            fail(f"Missing or non-integer seed in v6 export: {g}")
        if s in v6_by_seed:
            fail(f"Duplicate seed in v6 export: {s}")
        v6_by_seed[s] = g

    v7_by_seed = {}
    for g in v7_games:
        s = g.get("seed")
        if s is None or not isinstance(s, int):
            fail(f"Missing or non-integer seed in v7 export: {g}")
        if s in v7_by_seed:
            fail(f"Duplicate seed in v7 export: {s}")
        v7_by_seed[s] = g

    # Validate exact seed set equality
    manifest_set = set(manifest_seeds)
    if set(v6_by_seed.keys()) != manifest_set:
        diff = manifest_set.symmetric_difference(v6_by_seed.keys())
        fail(f"v6 export seed set mismatch with manifest. Symmetric diff: {diff}")
    if set(v7_by_seed.keys()) != manifest_set:
        diff = manifest_set.symmetric_difference(v7_by_seed.keys())
        fail(f"v7 export seed set mismatch with manifest. Symmetric diff: {diff}")

    # Verify per-game integrity and pair by seed
    paired_rows = []
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
        "v6_center_3p_share", "v7_center_3p_share", "diff_center_3p_share",
        "center_exposure_any", "center_exposure_same",
        "v6_reg_center_big_3p_share", "v7_reg_center_big_3p_share", "diff_reg_center_big_3p_share",
        "reg_center_big_exposure_any", "reg_center_big_exposure_same",
    ]

    all_v6_accounting_valid = True
    all_v7_accounting_valid = True

    for s in manifest_seeds:
        g6 = v6_by_seed[s]
        g7 = v7_by_seed[s]
        m_row = manifest_by_seed[s]

        # Verify matching game ID
        m_gid = m_row.get("gameId")
        if g6.get("gameId") != m_gid or g7.get("gameId") != m_gid:
            fail(f"Game ID mismatch for seed {s}: manifest={m_gid}, v6={g6.get('gameId')}, v7={g7.get('gameId')}")

        # Accounting validation
        if not g6.get("accountingConsistent", False):
            all_v6_accounting_valid = False
            fail(f"v6 accounting inconsistent for seed {s}")
        if not g7.get("accountingConsistent", False):
            all_v7_accounting_valid = False
            fail(f"v7 accounting inconsistent for seed {s}")

        # Metrics pairing
        w6 = g6.get("weakShooterThreePointShare")
        w7 = g7.get("weakShooterThreePointShare")
        w_diff = (w7 - w6) if (w6 is not None and w7 is not None) else None

        s6 = g6.get("stretchBigThreePointShare")
        s7 = g7.get("stretchBigThreePointShare")
        s_diff = (s7 - s6) if (s6 is not None and s7 is not None) else None

        c6 = g6.get("stretchCenterThreePointShare")
        c7 = g7.get("stretchCenterThreePointShare")
        c_diff = (c7 - c6) if (c6 is not None and c7 is not None) else None

        # Population B: Registered Center across PF/C slots
        rcb6 = g6.get("registeredCenterBigThreePointShare")
        rcb7 = g7.get("registeredCenterBigThreePointShare")
        rcb_diff = (rcb7 - rcb6) if (rcb6 is not None and rcb7 is not None) else None

        # Genuine center exposure checks (Pop A: C slot only)
        c1_6 = g6.get("center1Fga", 0)
        c1_7 = g7.get("center1Fga", 0)
        c2_6 = g6.get("center2Fga", 0)
        c2_7 = g7.get("center2Fga", 0)
        center_exposure_any = 1 if ((c1_6 >= 10 or c2_6 >= 10) and (c1_7 >= 10 or c2_7 >= 10)) else 0
        center_exposure_same = 1 if ((c1_6 >= 10 and c1_7 >= 10) or (c2_6 >= 10 and c2_7 >= 10)) else 0

        # Population B exposure checks (Registered Centers in PF/C slots)
        c1_big_6 = g6.get("regCenter1BigFga", 0)
        c1_big_7 = g7.get("regCenter1BigFga", 0)
        c2_big_6 = g6.get("regCenter2BigFga", 0)
        c2_big_7 = g7.get("regCenter2BigFga", 0)
        reg_b_exp_any = 1 if ((c1_big_6 >= 10 or c2_big_6 >= 10) and (c1_big_7 >= 10 or c2_big_7 >= 10)) else 0
        reg_b_exp_same = 1 if ((c1_big_6 >= 10 and c1_big_7 >= 10) or (c2_big_6 >= 10 and c2_big_7 >= 10)) else 0
        paired_rows.append({
            "seed": s,
            "gameId": m_gid,
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
            "v6_weak_3p_share": f"{w6:.5f}" if w6 is not None else "",
            "v7_weak_3p_share": f"{w7:.5f}" if w7 is not None else "",
            "diff_weak_3p_share": f"{w_diff:.5f}" if w_diff is not None else "",
            "weak_eligible": "1" if (g6.get("weakEligible", False) and g7.get("weakEligible", False)) else "0",
            "v6_stretch_3p_share": f"{s6:.5f}" if s6 is not None else "",
            "v7_stretch_3p_share": f"{s7:.5f}" if s7 is not None else "",
            "diff_stretch_3p_share": f"{s_diff:.5f}" if s_diff is not None else "",
            "stretch_eligible": "1" if (g6.get("stretchEligible", False) and g7.get("stretchEligible", False)) else "0",
            "v6_center_3p_share": f"{c6:.5f}" if c6 is not None else "",
            "v7_center_3p_share": f"{c7:.5f}" if c7 is not None else "",
            "diff_center_3p_share": f"{c_diff:.5f}" if c_diff is not None else "",
            "center_exposure_any": str(center_exposure_any),
            "center_exposure_same": str(center_exposure_same),
            "v6_reg_center_big_3p_share": f"{rcb6:.5f}" if rcb6 is not None else "",
            "v7_reg_center_big_3p_share": f"{rcb7:.5f}" if rcb7 is not None else "",
            "diff_reg_center_big_3p_share": f"{rcb_diff:.5f}" if rcb_diff is not None else "",
            "reg_center_big_exposure_any": str(reg_b_exp_any),
            "reg_center_big_exposure_same": str(reg_b_exp_same),
        })

    paired_csv_path = Path(args.paired_csv)
    paired_csv_path.parent.mkdir(parents=True, exist_ok=True)
    with open(paired_csv_path, "w", newline="") as out_f:
        writer = csv.DictWriter(out_f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(paired_rows)

    paired_sha = sha256_file(paired_csv_path)

    # Statistical Evaluation
    summary_data = {
        "context": args.context,
        "cohort_size": N_manifest,
        "manifest_path": str(manifest_path),
        "manifest_sha256": manifest_sha,
        "v6_export_path": str(v6_path),
        "v6_export_sha256": v6_sha,
        "v7_export_path": str(v7_path),
        "v7_export_sha256": v7_sha,
        "paired_csv_path": str(paired_csv_path),
        "paired_csv_sha256": paired_sha,
        "all_v6_accounting_valid": all_v6_accounting_valid,
        "all_v7_accounting_valid": all_v7_accounting_valid,
        "endpoints": {},
        "guardrails": {},
        "sufficiency": {},
        "valid": True,
    }

    def calc_t_test(diffs, delta0, direction="upper"):
        n = len(diffs)
        if n < 2:
            return None
        m = float(np.mean(diffs))
        s = float(np.std(diffs, ddof=1))
        se = s / math.sqrt(n)
        if se == 0:
            return None
        t = (m - delta0) / se
        df = n - 1
        if direction == "upper":
            p = float(1 - stats.t.cdf(t, df=df))
        elif direction == "lower":
            p = float(stats.t.cdf(t, df=df))
        else:
            raise ValueError(direction)
        return {
            "n": n,
            "mean_diff": m,
            "sd_diff": s,
            "se_diff": se,
            "delta0": delta0,
            "t_stat": t,
            "df": df,
            "p_value": p,
        }

    if args.context == "A":
        # Context A: Endpoints 1 (Primary), 2 (Weak 3P), 4 (Secondary)
        # Helper to get diffs
        def diffs_for(key):
            d_list = []
            for s in manifest_seeds:
                g6 = v6_by_seed[s]
                g7 = v7_by_seed[s]
                v6_val = g6.get(key)
                v7_val = g7.get(key)
                if v6_val is not None and v7_val is not None:
                    d_list.append(v7_val - v6_val)
            return d_list

        prim_diffs = diffs_for("primaryShare")
        sec_diffs = diffs_for("secondaryShare")
        weak_diffs = diffs_for("weakShooterThreePointShare")

        # Insufficiency gates
        weak_defined_count = len(weak_diffs)
        weak_exposure_count = sum(int(r["weak_eligible"]) for r in paired_rows)

        weak_defined_suff = weak_defined_count >= int(0.80 * N_manifest)
        weak_exposure_suff = weak_exposure_count >= int(0.80 * N_manifest)

        summary_data["sufficiency"] = {
            "weak_defined_count": weak_defined_count,
            "weak_defined_required": int(0.80 * N_manifest),
            "weak_defined_pass": weak_defined_suff,
            "weak_exposure_count": weak_exposure_count,
            "weak_exposure_required": int(0.80 * N_manifest),
            "weak_exposure_pass": weak_exposure_suff,
            "context_sufficient": weak_defined_suff and weak_exposure_suff,
        }

        # T-tests
        summary_data["endpoints"]["primaryCreatorShare"] = calc_t_test(prim_diffs, 0.030, "upper")
        summary_data["endpoints"]["weakShooterThreePointShare"] = calc_t_test(weak_diffs, -0.035, "lower")
        summary_data["endpoints"]["secondaryCreatorShare"] = calc_t_test(sec_diffs, 0.005, "upper")

        # Guardrails: TOST at alpha=0.05 (90% CI)
        guardrail_specs = [
            ("totalPoints", "points", 2.5),
            ("possessions", "pace", 1.5),
            ("eFG", "efg", 0.010),
            ("turnoversPer100", "tov100", 0.75),
            ("fta", "fta", 1.75),
        ]

        df_g = N_manifest - 1
        t_crit_90 = float(stats.t.ppf(0.95, df=df_g))

        all_guards_pass = True
        for key, name, delta in guardrail_specs:
            g_diffs = diffs_for(key)
            m = float(np.mean(g_diffs))
            s = float(np.std(g_diffs, ddof=1))
            se = s / math.sqrt(len(g_diffs))
            ci_low = m - t_crit_90 * se
            ci_high = m + t_crit_90 * se
            passed = ci_low >= -delta and ci_high <= delta
            all_guards_pass &= passed
            summary_data["guardrails"][name] = {
                "metric_key": key,
                "n": len(g_diffs),
                "mean_diff": m,
                "sd_diff": s,
                "se": se,
                "delta": delta,
                "ci_90_low": ci_low,
                "ci_90_high": ci_high,
                "passed": passed,
            }
        summary_data["guardrails_all_passed"] = all_guards_pass

    elif args.context == "B":
        # Context B: Endpoint 3 (Stretch-Big / Stretch-Center 3PA Share Non-Inferiority)
        def diffs_for(key):
            d_list = []
            for s in manifest_seeds:
                g6 = v6_by_seed[s]
                g7 = v7_by_seed[s]
                v6_val = g6.get(key)
                v7_val = g7.get(key)
                if v6_val is not None and v7_val is not None:
                    d_list.append(v7_val - v6_val)
            return d_list

        c_diffs = diffs_for("stretchCenterThreePointShare")
        sb_diffs = diffs_for("stretchBigThreePointShare")
        diffs_pop_a = diffs_for("stretchCenterThreePointShare")
        diffs_pop_b = diffs_for("registeredCenterBigThreePointShare")
        diffs_pop_c = diffs_for("stretchBigThreePointShare")

        pop_b_defined_count = len(diffs_pop_b)
        pop_b_exp_any = sum(int(r["reg_center_big_exposure_any"]) for r in paired_rows)
        pop_b_exp_same = sum(int(r["reg_center_big_exposure_same"]) for r in paired_rows)
        pop_a_exp_any = sum(int(r["center_exposure_any"]) for r in paired_rows)
        pop_c_exp = sum(int(r["stretch_eligible"]) for r in paired_rows)

        pop_b_defined_suff = pop_b_defined_count >= int(0.80 * N_manifest)
        pop_b_exposure_suff = pop_b_exp_any >= int(0.64 * N_manifest) # 160 / 250 = 64.0%

        summary_data["sufficiency"] = {
            "population_b_defined_count": pop_b_defined_count,
            "population_b_defined_required": int(0.80 * N_manifest),
            "population_b_defined_pass": pop_b_defined_suff,
            "population_b_exposure_any_count": pop_b_exp_any,
            "population_b_exposure_same_count": pop_b_exp_same,
            "population_b_exposure_required": int(0.64 * N_manifest),
            "population_b_exposure_pass": pop_b_exposure_suff,
            "population_a_exposure_count": pop_a_exp_any,
            "population_c_exposure_count": pop_c_exp,
            "context_sufficient": pop_b_defined_suff and pop_b_exposure_suff,
        }

        # T-tests for Populations A, B, and C
        summary_data["endpoints"]["populationA_stretchCenterThreePointShare"] = calc_t_test(diffs_pop_a, -0.015, "upper")
        summary_data["endpoints"]["populationB_registeredCenterBigThreePointShare"] = calc_t_test(diffs_pop_b, -0.015, "upper")
        summary_data["endpoints"]["populationC_stretchBigThreePointShare"] = calc_t_test(diffs_pop_c, -0.015, "upper")
        # Primary binding alias for Corrigendum Option 1
        summary_data["endpoints"]["genuineCenterThreePointShare"] = summary_data["endpoints"]["populationB_registeredCenterBigThreePointShare"]

    summary_out_path = Path(args.summary_out)
    summary_out_path.parent.mkdir(parents=True, exist_ok=True)
    summary_out_path.write_text(json.dumps(summary_data, indent=2))
    print(f"Context {args.context} analysis complete. Wrote summary to {summary_out_path}")

if __name__ == "__main__":
    main()
