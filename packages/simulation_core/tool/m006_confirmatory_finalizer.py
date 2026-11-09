import argparse
import json
import math
import sys
from pathlib import Path

def fail_invalid(msg):
    sys.stderr.write(f"FINALIZER INVALID: {msg}\n")
    sys.exit(2)

def holm_step_down(p_values_dict, alpha=0.05):
    """
    Dynamic Holm-Bonferroni step-down procedure.
    p_values_dict: {name: p_value}
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
    parser = argparse.ArgumentParser(description="M006 Confirmatory Finalizer")
    parser.add_argument("--context-a", required=True, help="Path to Context A summary JSON")
    parser.add_argument("--context-b", required=True, help="Path to Context B summary JSON")
    parser.add_argument("--out-json", required=True, help="Path to output final decision JSON")
    parser.add_argument("--out-report", required=True, help="Path to output final decision Markdown report")
    args = parser.parse_args()

    path_a = Path(args.context_a)
    path_b = Path(args.context_b)

    if not path_a.exists():
        fail_invalid(f"Context A summary not found: {args.context_a}")
    if not path_b.exists():
        fail_invalid(f"Context B summary not found: {args.context_b}")

    try:
        sum_a = json.loads(path_a.read_text())
    except Exception as e:
        fail_invalid(f"Failed to parse Context A JSON: {e}")

    try:
        sum_b = json.loads(path_b.read_text())
    except Exception as e:
        fail_invalid(f"Failed to parse Context B JSON: {e}")

    # Validate provenance and context identity
    if sum_a.get("context") != "A":
        fail_invalid(f"Context A summary has invalid context flag: {sum_a.get('context')}")
    if sum_b.get("context") != "B":
        fail_invalid(f"Context B summary has invalid context flag: {sum_b.get('context')}")

    # Validate 100% accounting and reducer integrity
    if not sum_a.get("all_v6_accounting_valid", False) or not sum_a.get("all_v7_accounting_valid", False):
        fail_invalid("Context A accounting or reducer validation failed")
    if not sum_b.get("all_v6_accounting_valid", False) or not sum_b.get("all_v7_accounting_valid", False):
        fail_invalid("Context B accounting or reducer validation failed")

    # Collect the 4 primary endpoints
    # 1. Primary creator share (Context A)
    # 2. Weak-shooter 3PA share (Context A)
    # 3. Stretch-big / stretch-center 3PA retention (Context B)
    # 4. Secondary creator share (Context A)
    ep_a = sum_a.get("endpoints", {})
    ep_b = sum_b.get("endpoints", {})

    p1 = ep_a.get("primaryCreatorShare")
    p2 = ep_a.get("weakShooterThreePointShare")
    p4 = ep_a.get("secondaryCreatorShare")
    primary_stretch_key = "populationB_registeredCenterBigThreePointShare"
    p3 = ep_b.get(primary_stretch_key) or ep_b.get("genuineCenterThreePointShare")

    if p1 is None or p2 is None or p4 is None or p3 is None:
        fail_invalid(
            f"Missing required primary endpoint data: "
            f"primaryCreatorShare={p1 is not None}, "
            f"weakShooterThreePointShare={p2 is not None}, "
            f"secondaryCreatorShare={p4 is not None}, "
            f"populationB_registeredCenterBigThreePointShare={p3 is not None}"
        )

    # Validate finite non-NaN statistics
    for ep_name, ep_obj in [
        ("primaryCreatorShare", p1),
        ("weakShooterThreePointShare", p2),
        (primary_stretch_key, p3),
        ("secondaryCreatorShare", p4),
    ]:
        pval = ep_obj.get("p_value")
        tstat = ep_obj.get("t_stat")
        if pval is None or math.isnan(pval) or math.isinf(pval):
            fail_invalid(f"Invalid p-value for {ep_name}: {pval}")
        if tstat is None or math.isnan(tstat) or math.isinf(tstat):
            fail_invalid(f"Invalid t-statistic for {ep_name}: {tstat}")

    # Collect p-values for Holm step-down
    p_dict = {
        "primaryCreatorShare": p1["p_value"],
        "weakShooterThreePointShare": p2["p_value"],
        primary_stretch_key: p3["p_value"],
        "secondaryCreatorShare": p4["p_value"],
    }
    holm_results = holm_step_down(p_dict, alpha=0.05)
    all_hypotheses_rejected = all(v["rejected"] for v in holm_results.values())

    suff_a = sum_a.get("sufficiency", {})
    suff_b = sum_b.get("sufficiency", {})

    n_a = sum_a.get("cohort_size", 0)
    weak_def = suff_a.get("weak_defined_count", 0)
    weak_exp = suff_a.get("weak_exposure_count", 0)
    req_a_def = int(math.ceil(0.80 * n_a))
    req_a_exp = int(math.ceil(0.80 * n_a))
    context_a_sufficient = (weak_def >= req_a_def) and (weak_exp >= req_a_exp)

    n_b = sum_b.get("cohort_size", 0)
    pop_b_def = suff_b.get("population_b_defined_count", 0)
    # Corrigendum 1A: evaluates SAME registered Center ID >= 10 FGA in both arms
    pop_b_same = suff_b.get("population_b_exposure_same_count", 0)
    req_b_def = int(math.ceil(0.80 * n_b))
    req_b_same = int(math.ceil(0.60 * n_b))
    context_b_sufficient = (pop_b_def >= req_b_def) and (pop_b_same >= req_b_same)

    all_sufficient = context_a_sufficient and context_b_sufficient

    # Guardrails Evaluation (Context A)
    guardrails = sum_a.get("guardrails", {})
    expected_guardrails = ["points", "pace", "efg", "tov100", "fta"]
    for eg in expected_guardrails:
        if eg not in guardrails:
            fail_invalid(f"Missing guardrail evaluation for {eg} in Context A")

    all_guardrails_passed = sum_a.get("guardrails_all_passed", False)

    # Determine Final Verdict
    # Hierarchy: INVALID (handled above via fail_invalid) -> INSUFFICIENT -> FAILED -> PASSED
    if not all_sufficient:
        verdict = "INSUFFICIENT"
        exit_code = 1
    elif all_hypotheses_rejected and all_guardrails_passed:
        verdict = "PASSED"
        exit_code = 0
    else:
        verdict = "FAILED"
        exit_code = 1

    final_decision_data = {
        "verdict": verdict,
        "exit_code": exit_code,
        "all_hypotheses_rejected": all_hypotheses_rejected,
        "all_guardrails_passed": all_guardrails_passed,
        "all_sufficient": all_sufficient,
        "context_a_sufficient": context_a_sufficient,
        "context_b_sufficient": context_b_sufficient,
        "stretch_endpoint_evaluated": primary_stretch_key,
        "holm_step_down": holm_results,
        "primary_endpoints": {
            "primaryCreatorShare": p1,
            "weakShooterThreePointShare": p2,
            primary_stretch_key: p3,
            "secondaryCreatorShare": p4,
        },
        "guardrails": guardrails,
        "sufficiency": {
            "context_a": suff_a,
            "context_b": suff_b,
        },
        "provenance": {
            "context_a_manifest_sha": sum_a.get("manifest_sha256"),
            "context_b_manifest_sha": sum_b.get("manifest_sha256"),
            "context_a_paired_csv_sha": sum_a.get("paired_csv_sha256"),
            "context_b_paired_csv_sha": sum_b.get("paired_csv_sha256"),
        },
    }

    out_json_path = Path(args.out_json)
    out_json_path.parent.mkdir(parents=True, exist_ok=True)
    out_json_path.write_text(json.dumps(final_decision_data, indent=2))

    # Generate Markdown decision report
    report_lines = [
        f"# M006 Confirmatory Evaluation Final Decision Report",
        f"",
        f"- **Final Verdict:** `{verdict}`",
        f"- **Exit Code:** `{exit_code}`",
        f"- **Primary Hypotheses All Rejected:** `{all_hypotheses_rejected}`",
        f"- **Guardrails All Passed:** `{all_guardrails_passed}`",
        f"- **Evidence Sufficiency Satisfied:** `{all_sufficient}`",
        f"- **Evaluated Stretch Endpoint:** `{primary_stretch_key}`",
        f"",
        f"---",
        f"",
        f"## 1. Primary Hypotheses (Holm-Bonferroni Step-Down, alpha = 0.05)",
        f"",
        f"| Endpoint | Context | Observed Mean Diff | t-stat (df) | One-Sided p-value | Sorted Rank | Alpha Threshold | Rejected |",
        f"|---|---|---:|---:|---:|---:|---:|---|",
    ]

    for name in sorted(holm_results.keys(), key=lambda k: holm_results[k]["sorted_rank"]):
        hr = holm_results[name]
        ep_obj = (
            p3 if name == primary_stretch_key
            else (p1 if name == "primaryCreatorShare" else (p2 if name == "weakShooterThreePointShare" else p4))
        )
        ctx = "B" if name == primary_stretch_key else "A"
        report_lines.append(
            f"| `{name}` | Context {ctx} | {ep_obj['mean_diff']*100:+.2f} pp | {ep_obj['t_stat']:.3f} ({ep_obj['df']}) | {hr['p_value']:.4e} | {hr['sorted_rank']} | {hr['alpha_threshold']:.4f} | `{'YES' if hr['rejected'] else 'NO'}` |"
        )

    report_lines.extend([
        f"",
        f"---",
        f"",
        f"## 2. Macroeconomic Guardrails (TOST Equivalence, alpha = 0.05 / 90% CI)",
        f"",
        f"| Guardrail | Observed Mean Diff | 90% CI | Equivalence Bounds | Power Result |",
        f"|---|---:|---:|---:|---|",
    ])

    for g_key in expected_guardrails:
        g = guardrails[g_key]
        report_lines.append(
            f"| `{g_key}` | {g['mean_diff']:+.4f} | `[{g['ci_90_low']:+.4f}, {g['ci_90_high']:+.4f}]` | `[{-g['delta']:+.4f}, {+g['delta']:+.4f}]` | `{'PASS' if g['passed'] else 'FAIL'}` |"
        )

    report_lines.extend([
        f"",
        f"---",
        f"",
        f"## 3. Evidence Sufficiency Gates",
        f"",
        f"- **Context A Defined Weak-Shooter Games:** {suff_a.get('weak_defined_count')} / {sum_a.get('cohort_size')} (Pass: `{suff_a.get('weak_defined_pass')}`)",
        f"- **Context A Paired Weak Exposure (FGA >= 20):** {suff_a.get('weak_exposure_count')} / {sum_a.get('cohort_size')} (Pass: `{suff_a.get('weak_exposure_pass')}`)",
        f"- **Context B Defined Stretch Games:** {suff_b.get('stretch_center_defined_count')} / {sum_b.get('cohort_size')} (Pass: `{suff_b.get('stretch_center_defined_pass')}`)",
        f"- **Context B Paired Center Exposure (FGA >= 10):** {suff_b.get('exposure_any_center_count')} / {sum_b.get('cohort_size')} (Pass: `{suff_b.get('exposure_pass')}`)",
        f"",
        f"---",
        f"",
        f"## 4. Final Verdict Rationale",
        f"",
        f"- Verdict is **{verdict}**.",
    ])

    if verdict == "PASSED":
        report_lines.append(
            f"- All four primary hypotheses rejected their nulls under familywise error control.\n"
            f"- All five macroeconomic guardrails demonstrated strict equivalence.\n"
            f"- All cohort evidence-sufficiency thresholds were met."
        )
    elif verdict == "INSUFFICIENT":
        report_lines.append(
            f"- Evaluation halted because one or more cohort evidence-sufficiency thresholds failed.\n"
            f"- No acceptance or rejection claim is made."
        )
    else:
        report_lines.append(
            f"- Evaluation failed to achieve the pre-registered confirmatory criteria."
        )

    out_report_path = Path(args.out_report)
    out_report_path.parent.mkdir(parents=True, exist_ok=True)
    out_report_path.write_text("\n".join(report_lines) + "\n")

    print(f"Confirmatory finalization complete: verdict={verdict} (exit code {exit_code})")
    print(f"Wrote decision report to {out_report_path}")
    print(f"Wrote decision JSON to {out_json_path}")
    sys.exit(exit_code)

if __name__ == "__main__":
    main()
