# Amendment 003 — Procedural Waiver Addendum: Development Gate Failures

> **Date:** 2026-10-31  
> **Status:** APPROVED PROCEDURAL WAIVER — FOR HELD-OUT EVIDENCE COLLECTION ONLY  
> **Baseline Commit:** `0a0e1e4a43ca34e530680d995ae1ebcb235bd384` (`develop/m002`)  
> **Authority:** Owner Decision (Ballgorithm M002 Limited Held-Out Evaluation Authorization)

---

## 1. Explicit Record of Failed Development Gates

The Development-Cohort Evaluation (1,120 games on historical seeds $1 \dots 200$, Baseline v2 vs Candidate v3) formally **FAILED** two pre-registered quantitative guardrails specified in `amendment-003-seed-provenance-manifest.md` (§5):

| Guardrail Metric | Pre-Registered Threshold | Observed Value (v3 Dev) | Development Status | Cause & Nature |
|---|---|---|---|---|
| **Pace Increase Delta** | $+2.5\%$ to $+7.0\%$ ($+2.5 \dots +7.0$ poss/team-game) | **$+2.21\%$ ($+2.22$ poss/team-game)**, 95% CI $[+1.85, +2.59]$ | **FAILED** | Below pre-registered lower bound envelope. |
| **Offensive Foul Turnover Share** | $\le 24.0\%$ of total turnovers | **$26.02\%$** (10.88 OF / 41.82 total TOV) | **FAILED** | Exceeds upper bound due to total turnover denominator compression (−10.49 shot-clock TOVs). |

---

## 2. Terms and Boundaries of the Waiver

1. **Procedural Only:**
   - This waiver is granted strictly to permit execution of the 2,240-game held-out evaluation across Arm 2A (Baseline v2) and Arm 2B (Candidate v3).
   - This waiver does **NOT** convert either development failure into a PASS.
   - Both development gates remain recorded as formal **FAILURES** in all project records and milestone ledgers.
2. **No Realism or Production Sign-Off:**
   - This waiver does **NOT** constitute gameplay realism approval, statistical acceptance, or M002 milestone closure.
   - Offensive-foul frequency (10.06 to 10.88 fouls/game) remains an open, uncalibrated basketball-realism concern for owner review.
3. **Threshold and Parameter Freeze:**
   - Pre-registered thresholds in `amendment-003-seed-provenance-manifest.md` remain frozen. No threshold is altered.
   - Simulation parameters, probability coefficients, and duration brackets remain unmodified.
4. **Held-Out Integrity Guarantee:**
   - Any held-out cohort results that violate the pre-registered guardrails must be reported strictly as failures.
   - No post-hoc threshold adjustment, selective filtering, or cherry-picking of held-out seeds is permitted.
