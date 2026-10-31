# Amendment 004 Held-Out — Protocol Deviation D1 (inference method)

> **Date:** 2026-10-31
> **Status:** DISCLOSED. Raw evidence untouched. The frozen script and protocol are not edited.

## What was wrong

The frozen protocol (`amendment-004-heldout-protocol.md` §5, commit `0c7d552`) and `analyze_heldout.py` compute the two-way Cameron–Gelbach–Miller variance as `V = V_seed + V_matchup − V_game` using **uncorrected** component sums, and substitute `max(V_seed, V_matchup)` when the result is non-positive.

The governing pre-registered method, `amendment-003-seed-provenance-manifest.md` §4 (line 93), requires small-sample DOF adjustments `G/(G−1) · (N−1)/(N−K)` **applied to each component**. The frozen protocol therefore does not conform to the pre-registered inference method, and its statement that it uses "the pre-registered methodology" was inaccurate. The defect was found by an external review note after aggregation had been run once locally; it was not found by me before execution.

Aggregation (`analyze_heldout.py`) had already been executed and its outputs viewed before the defect was raised, so the correction below is **not blind to outcomes**. That is stated rather than hidden.

## What is and is not affected

| Item | Affected? | Why |
|---|---|---|
| Raw v3/v4/T014-fresh evidence | No | Produced before and independent of any analysis |
| G1–G8 verdicts | No | Frozen verdict rule (§4/§6) uses the **point estimate** against the envelope; no variance enters |
| G9-fresh verdict | No | T014 protocol uses its own bootstrap/permutation procedure, not CGM |
| Rollback triggers | No | Point estimates of v4 level and v4−v3 shift |
| Reported 95% intervals and "effect size with uncertainty" | **Yes** | Variance estimator differs |
| Median-FGA interval | No | Pigeonhole bootstrap, no DOF term |

## Remedy (mechanical, not outcome-driven)

`supplemental_inference.py` re-derives **only** the intervals under the manifest formula: `G/(G−1)·(N−1)/(N−K)` per component with `K = 1`, `G` = 600 seeds, 56 matchups, 1,120 intersection cells, normal 95% intervals, **no fallback** (a non-positive variance is reported as undefined). Output: `heldout-summary-supplemental-dof.json`. It does not touch point estimates, envelopes, or verdicts.

The formula was fixed by the pre-existing manifest, not chosen after seeing results. Both analyses are preserved and labeled:

- `heldout-summary.json`, `heldout-paired.csv` — **as frozen** (non-conforming variance, correct point estimates).
- `heldout-summary-supplemental-dof.json` — **manifest-conforming intervals**; use these for uncertainty claims.

## Observed effect of the correction

Corrected standard errors are 0.73%–0.91% larger than the frozen ones across all 22 metrics. No paired-delta interval changes whether it excludes zero. The only undefined intervals are `SC_fresh_per_game` (v3, v4, delta): fresh phases start at a 24 s shot clock and the longest duration bracket is 22 s, so fresh-phase violations are identically zero and the variance is zero.

## Consequence for the verdict

**Overall verdict: INCONCLUSIVE — EVIDENCE OR EXECUTION ISSUE.**

The owner required the pre-registered crossed-cluster method and uncertainty reporting. The executed analysis did not conform to it, the defect was handled after outcomes had been viewed, and a corrected supplement cannot make the executed analysis retroactively conform. The result is therefore not presented as a clean pre-registered pass, and no waiver is requested.

What the evidence does show, stated without relabeling the verdict: every frozen gate G1–G8 and G9-fresh passes by point estimate, no rollback trigger fires, and the DOF-corrected intervals change no conclusion (§ above). The raw cohort is preserved and cannot be re-drawn without spending the fresh seeds, so the remaining decision is the owner's: accept `heldout-summary-supplemental-dof.json` as the intended analysis, or order a new pre-registered cohort.

Not repaired here, deliberately: the frozen protocol text and script, which stay at their committed bytes as the historical record.
