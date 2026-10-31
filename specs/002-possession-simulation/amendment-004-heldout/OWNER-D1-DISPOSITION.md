# Amendment 004 Held-Out — Owner Disposition on Protocol Deviation D1

> **Date:** 2026-10-31
> **Disposition:** `QUALIFIED HELD-OUT EVIDENCE ACCEPTED FOR FURTHER M002 REVIEW — D1 PROCEDURAL EXCEPTION RECORDED`
> **Baseline Commit (v3):** `9f8458ab345ea7c075f3b910b60d7ee964f1c5fe`
> **Audited Held-Out Evidence Commit (v4):** `483e8b526d968e0f0091c315e7ffc85bcd847027` (`develop/m002`)
> **Authority:** Owner Decision (*Ballgorithm M002 — Amendment 004 D1 Owner Disposition*)

---

## 1. Original Protocol Requirement and Exact D1 Deviation

- **Pre-Registered Requirement:** The owner's Amendment 004 fresh held-out authorization required evaluation of the 2,240-game paired held-out cohort (`1,120 v3 + 1,120 v4`, 600 fresh seeds in `[10001, 10600]`) using the pre-registered two-way crossed-cluster variance estimator specified in `specs/002-possession-simulation/amendment-003-seed-provenance-manifest.md` §4 (Cameron–Gelbach–Miller across `seed` and `matchup`, with per-component small-sample degrees-of-freedom adjustments $\frac{G}{G - 1} \cdot \frac{N - 1}{N - K}$ and 95% intervals $\pm 1.96 \cdot \text{SE}$).
- **Exact Deviation D1:** At protocol freeze (`0c7d552e7eaa915a003b31d6e1352f5b50d806ac`), `analyze_heldout.py` omitted the per-component $\frac{G}{G - 1} \cdot \frac{N - 1}{N - K}$ multipliers (`cluster_var` summed raw squared cluster totals $V_S + V_M - V_{S \cap M}$) and included an un-pre-registered `max(v_s, v_m)` fallback for non-positive variance. The defect was identified after `analyze_heldout.py` had been executed once and its outputs viewed.
- **Preserved Historical Verdict:** Because the executed frozen script did not conform to the governing inference specification and the supplemental correction (`supplemental_inference.py`) was not outcome-blind, the original held-out execution verdict was recorded and **remains preserved** in `PROTOCOL-DEVIATION.md` as:
  > **`INCONCLUSIVE — EVIDENCE OR EXECUTION ISSUE`**
- **Non-Concealment Guarantee:** Neither `amendment-004-heldout-protocol.md`, `analyze_heldout.py`, `heldout-summary.json`, nor `PROTOCOL-DEVIATION.md` has been edited to conceal D1. All frozen bytes from `0c7d552` and raw simulation bytes from `e68e3a4` remain intact.

---

## 2. Independent Mathematical and Evidence-Integrity Audit of D1

An independent, stdlib-only audit (`audit_d1_dof.py`, executing zero simulations and importing neither `analyze_heldout.py` nor `supplemental_inference.py`) recomputed all 66 estimators (`22 metrics × {v3, v4, paired delta}`) directly from `v3-heldout-raw.json` and `v4-heldout-raw.json`:

1. **Seed-Cluster Component ($\hat{V}_S$):** Verified $G_S = 600$ unique seeds in `[10001, 10600]` (520 appearing twice, 80 once across $N = 1,120$ slots) with multiplier $c_S = \frac{600}{599} \cdot \frac{1119}{1119} = \frac{600}{599} \approx 1.00166945$.
2. **Matchup-Cluster Component ($\hat{V}_M$):** Verified $G_M = 56$ directed matchups (each with 20 slots) with multiplier $c_M = \frac{56}{55} \cdot \frac{1119}{1119} = \frac{56}{55} \approx 1.01818182$.
3. **Intersection Adjustment ($-\hat{V}_{S \cap M}$):** Verified directly from `(matchupIndex, seed)` tuples that all $G_{S \cap M} = 1,120$ cells are singleton observations ($N = 1,120$), with multiplier $c_{S \cap M} = \frac{1120}{1119} \cdot \frac{1119}{1119} = \frac{1120}{1119} \approx 1.00089366$ (reducing to classical unbiased $\frac{1}{N(N-1)} \sum (y_i - \bar{y})^2$ on mean metrics).
4. **Linearized Ratio vs Direct Paired-Difference Identity:** Across all 14 constant-denominator metrics, linearized ratio difference scores $\psi_{4,i} - \psi_{3,i}$ equal direct paired-difference scores $(\Delta_i - \bar{\Delta})/N$ within $6.939 \times 10^{-18}$.
5. **Sample Size, Cluster Counts, and Parameter Count ($K$):** $N = 1,120$, $(G_S, G_M, G_{S \cap M}) = (600, 56, 1120)$, $K = 1$ scalar parameter per marginal ratio/mean equation. Sensitivity check with $K = 2$ (joint 2-parameter ratio contrast, $(N-1)/(N-2) = 1119/1118$) increases SE by $+0.045\%$ with zero conclusion changes.
6. **Numerical Variance Boundaries:** Across all 66 estimators, **0** produce strictly negative variance ($\hat{V}_{\text{multi}} < 0$). Exactly **3** produce exact zero variance ($\hat{V}_{\text{multi}} = 0$): `SC_fresh_per_game` (`v3`, `v4`, `delta`), which are structurally zero in every game (24 s fresh shot clock vs $\le 22$ s A1 duration bracket) and properly emitted as `null` without fallback.
7. **Confidence-Interval Construction & Sensitivity:** Manifest normal 95% CIs ($\pm 1.96 \cdot \text{SE}$) match `heldout-summary-supplemental-dof.json` within $5.551 \times 10^{-17}$ across all 63 non-degenerate estimators. Additional sensitivity checks using Student $t_{0.975, 55} = 2.004045$ and coarser 28-unordered-pair clustering (`pairIndex`, $G_P = 28, t_{0.975, 27} = 2.051831$) produce **zero** gate-envelope breaches and **zero** paired-delta sign/zero-exclusion flips.
8. **No Hidden Filtering or Selection:** All 1,120 paired slots and all 1,200 ordered `perSeed` records in `t014-v4-fresh-raw.json` are included without omission. `verify_heldout.py --git-ref 483e8b526d968e0f0091c315e7ffc85bcd847027` passed (`exit=0`) across all 12 checksummed blobs.

---

## 3. Original (Frozen Uncorrected) versus DOF-Corrected Inference

DOF correction enlarges standard errors by **$+0.64\%$ to $+0.91\%$**. **No statistical conclusion, gate verdict, or rollback trigger changes.**

| Metric (Paired $\Delta = \text{v4} - \text{v3}$) | $\Delta$ Point | Original SE | DOF SE ($\Delta\%$) | Original 95% CI | DOF-Corrected 95% CI | Conclusion Changed? |
|---|---|---|---|---|---|---|
| Offensive fouls / team-game | −3.0728 | 0.04875 | 0.04914 (+0.79%) | `[−3.1683, −2.9772]` | `[−3.1691, −2.9765]` | **No** (excludes 0) |
| Offensive-foul share of TOV | −0.1279 | 0.00182 | 0.00183 (+0.80%) | `[−0.1315, −0.1244]` | `[−0.1315, −0.1243]` | **No** (excludes 0) |
| TOV / 100 completed poss | −2.9825 | 0.09944 | 0.10031 (+0.87%) | `[−3.1775, −2.7876]` | `[−3.1792, −2.7859]` | **No** (excludes 0) |
| Shot-clock violations / game | +0.0795 | 0.06770 | 0.06825 (+0.82%) | `[−0.0532, +0.2122]` | `[−0.0543, +0.2132]` | **No** (includes 0) |
| Completed poss / team-game | −0.4460 | 0.13667 | 0.13787 (+0.88%) | `[−0.7139, −0.1781]` | `[−0.7162, −0.1758]` | **No** (excludes 0) |
| FGA / team-game | +2.8634 | 0.15936 | 0.16075 (+0.87%) | `[+2.5510, +3.1757]` | `[+2.5483, +3.1785]` | **No** (excludes 0) |
| FTA / team-game | +0.5522 | 0.18112 | 0.18263 (+0.83%) | `[+0.1972, +0.9072]` | `[+0.1943, +0.9102]` | **No** (excludes 0) |
| Points / team-game | +3.5205 | 0.31847 | 0.32116 (+0.84%) | `[+2.8963, +4.1447]` | `[+2.8911, +4.1500]` | **No** (excludes 0) |
| 3PA / FGA | +0.0000 | 0.00102 | 0.00102 (+0.88%) | `[−0.0020, +0.0020]` | `[−0.0020, +0.0020]` | **No** (includes 0) |
| eFG% | +0.0015 | 0.00123 | 0.00123 (+0.78%) | `[−0.0009, +0.0039]` | `[−0.0009, +0.0039]` | **No** (includes 0) |

### Frozen Amendment 004 Gate Verdicts (v4 Held-Out, Unchanged Thresholds)

Every gate G1–G8 passes by point estimate **and** has its entire DOF-corrected 95% CI strictly inside the frozen envelope:

| Gate | Metric | Frozen Envelope | Held-Out v4 | DOF-Corrected 95% CI | Verdict |
|---|---|---|---|---|---|
| G1 | Offensive fouls / team-game | `[1.80, 2.60]` | 2.2143 | `[2.1430, 2.2855]` | **PASS** |
| G2 | Offensive-foul share of TOV | `[0.100, 0.160]` | 0.1242 | `[0.1205, 0.1279]` | **PASS** |
| G3 | TOV / 100 completed poss | `[15.0, 19.5]` | 17.4285 | `[17.2218, 17.6353]` | **PASS** |
| G4 | Shot-clock violations / game | `[3.0, 5.5]` | 4.1714 | `[4.0387, 4.3042]` | **PASS** |
| G5 | Completed poss / team-game | `[100.0, 106.0]` | 102.2929 | `[101.9880, 102.5977]` | **PASS** |
| G6 | Team median FGA | `[88.0, 95.0]` | 92.0 | `[91.0, 92.0]` (pigeonhole) | **PASS** |
| G7 | 3PA / FGA | `[0.380, 0.450]` | 0.4134 | `[0.4106, 0.4161]` | **PASS** |
| G8 | eFG% | `[0.510, 0.540]` | 0.5230 | `[0.5187, 0.5274]` | **PASS** |
| G9 | T014 E1–E6 (fresh `10001–10200`) | Expected sign, Holm $p < 0.05$ | 6/6 PASSED | Exact xorshift32 Holm $p = 0.000600$ | **PASS** |

Rollback triggers (`amendment-004-turnover-calibration-spec.md` §3.3): **0 fired**.

---

## 4. Advisory JEV Judgment

Invoked `xd://jev_judge` (`typesafe/jev-latest`, resolved `jev-1.14.0`, 1 batched call) per `AGENTS.md` §6:
- `cgm_math_valid`: `noul = 0.81`
- `conclusions_invariant`: `noul = 0.92`
- `d1_disposition_verdict`: `choice = D1_EXCEPTION_ACCEPTED`, probability `0.97` (`D1_AUDIT_FAILED = 0.03`), confidence `0.94`.

Per governance policy, JEV is advisory; the deterministic from-scratch verification (`audit_d1_dof.py`) and frozen repository rules are authoritative.

---

## 5. Owner Conditional Acceptance, Retained Historical Failures & Remaining Gates

1. **Procedural Exception Scope:** Under the owner's conditional authorization, `heldout-summary-supplemental-dof.json` is accepted as **qualified held-out evidence for continued M002 review**, with D1 permanently recorded as a procedural exception. This does **not** certify the frozen `analyze_heldout.py` script as deviation-free, does **not** approve gameplay realism, and does **not** close M002.
2. **Explicit Limitations of Accepted Evidence:**
   - **Single league / eight rosters:** All 2,240 primary games and 1,400 fresh T014 simulations use M001 league seed `20261028`; fresh game seeds do not test generalization across unseen leagues or roster distributions.
   - **Unmeasured `[100, 1000]` bp clamp binding:** Frequency of offensive-foul floor (`100` bp) binding for high-IQ lineups is not measured in this cohort.
   - **Unmeasured inside-vs-midrange split:** Held-out rows record `FGA`/`FGM` and `3PA`/`3PM` only; 2PT inside-vs-midrange zone preservation is **NOT MEASURED**.
   - **Single-run reducer validation vs second-run replay:** Every game passed `GameEventReducer.validate` and `EventAccounting` reconciliation, but second-run byte-for-byte replay was not executed on the 2,240 held-out games.
   - **Cluster & provenance scope:** $G_M = 56$ directed matchups derive from 28 unordered team pairs; pre-manifest historical diagnostic runs outside repository records cannot be audited beyond tracked files.
   - **No NBA realism claim:** Total turnovers per 100 completed possessions ($17.43$) and shot-clock violations ($4.17$/game) remain above NBA descriptive benchmarks.
3. **Retained Historical Amendment 003 Guardrail Failures:**
   - Amendment 003 v3 pace increase delta ($+2.21\%$ dev / $+2.05\%$ held-out vs $+2.5\%$ minimum) remains **FAILED**.
   - Amendment 003 v3 offensive-foul turnover share ($26.02\%$ dev / $25.67\%$ A003 held-out / $25.21\%$ A004 v3 held-out vs $\le 24.0\%$ ceiling) remains **FAILED**.
   - `specs/002-possession-simulation/amendment-003-waiver-addendum.md` remains intact and unmodified.
4. **Pending Milestone Gates:**
   - **AC09** (historical v1 E4 inconclusive; later v2/v4 reruns passed) and **AC10** (calibration realism review) remain **NOT PASSED / PENDING FORMAL OWNER SIGN-OFF**.
   - **T016–T019** remain **UNAUTHORIZED** until separate, explicit owner authorization.
