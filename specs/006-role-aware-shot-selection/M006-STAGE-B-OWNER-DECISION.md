# M006-STAGE-B-OWNER-DECISION — Stage B Confirmatory Protocol Freeze

- **Date:** 2026-11-09
- **Status:** FROZEN — OWNER APPROVED.
- **Repository:** `Faraeael/Ballgorithm`
- **Branch:** `impl/m006-t06d-stage-b-freeze`
- **Base Baseline:** `impl/m006-t06c-protocol-finalization` (`98927cb6bc7aaabf2f6b27a4f8b01aa16a0c2009`).
- **Governing Freeze:** `d5f9f7d16372cb523f149d3536d972ed5f83e36b` (`verification-plan.md` §5).
- **Frozen Protocol Document:** `specs/006-role-aware-shot-selection/t06d-stage-b-confirmatory-protocol-frozen.md`.

---

## 1. Owner Decisions Recorded

The human repository owner formally authorized and approved the following specifications for the M006 Stage B confirmatory protocol:

1. **Two-Context Architecture Approved:**
   - Partition the confirmatory evaluation into two non-overlapping cohorts:
     - **Context A:** Main generated-league cohort ($N = 750$ paired games, seeds 10001–10750).
     - **Context B:** Constructed stretch-five cohort ($N = 250$ paired games, seeds 11001–11250).
   - Data between Context A and Context B must **never be pooled**.
2. **Option B Guardrail Margins Selected:**
   - The owner selected **Option B**, preserving the original stricter guardrail margins while expanding the Context A cohort size to $N = 750$ paired games to ensure $\ge 90\%$ joint guardrail power:
     - Combined Points: $\pm 2.5$ points ($[-\Delta, +\Delta] = [-2.5, +2.5]$).
     - Pace (Possessions): $\pm 1.5$ possessions ($[-\Delta, +\Delta] = [-1.5, +1.5]$).
     - eFG%: $\pm 1.0$ percentage point ($[-\Delta, +\Delta] = [-0.010, +0.010]$).
     - Turnovers per 100: $\pm 0.75$ ($[-\Delta, +\Delta] = [-0.75, +0.75]$).
     - Free Throw Attempts: $\pm 1.75$ FTA ($[-\Delta, +\Delta] = [-1.75, +1.75]$).
   - Evaluated using Two One-Sided Tests (TOST) at $\alpha = 0.05$ (90% Student's $t$ confidence interval strictly inside bounds).
3. **Four Primary Hypotheses Locked:**
   - Evaluated as one-sided paired Student's $t$-tests ($df = N_{\text{defined}} - 1$).
   - Multiplicity controlled via dynamic Holm-Bonferroni step-down on sorted observed $p$-values:
     - Step 1: $p_{(1)} \le 0.0125$
     - Step 2: $p_{(2)} \le 0.0166667$
     - Step 3: $p_{(3)} \le 0.0250$
     - Step 4: $p_{(4)} \le 0.0500$
   - Hypotheses:
     1. Primary Creator Share (Context A): $H_0: \delta_{\text{prim}} \le +0.030$ vs. $H_1: \delta_{\text{prim}} > +0.030$.
     2. Weak-Shooter 3PA Share (Context A): $H_0: \delta_{\text{weak}} \ge -0.035$ vs. $H_1: \delta_{\text{weak}} < -0.035$.
     3. Genuine Stretch-Big 3PA Share (Context B, Non-Inferiority): $H_0: \delta_{\text{stretch}} \le -0.015$ vs. $H_1: \delta_{\text{stretch}} > -0.015$.
     4. Secondary Creator Share (Context A): $H_0: \delta_{\text{sec}} \le +0.005$ vs. $H_1: \delta_{\text{sec}} > +0.005$.
4. **Estimand Separation and Safeguards:**
   - Primary inference uses **Estimand A** (Mean Paired Per-Game Proportion Difference across all defined games with positive denominators in both arms).
   - Zero-denominator games are counted, reported, and omitted from per-game ratio averaging without replacement.
   - Games with positive attempts are **never filtered post-hoc** based on intermediate attempt counts.
5. **Cohort Evidence-Sufficiency Gates:**
   - Context A: Declared **INSUFFICIENT** if defined weak-shooter games $< 600 / 750$ (80%) or paired combined weak FGA $\ge 20$ games $< 600 / 750$ (80%).
   - Context B: Declared **INSUFFICIENT** if defined stretch-center games $< 200 / 250$ (80%) or paired Center FGA $\ge 10$ games $< 160 / 250$ (64%).
6. **Corrected Unconditional Stretch-Big Variance:**
   - Unconditional defined sample ($N = 200$): Mean difference $+0.01890$ ($+1.89$ pp), $s_d = 0.08346$.
   - Filtered sample ($N = 138$): Mean difference $+0.02356$ ($+2.36$ pp), $s_d = 0.07032$ (recorded as historical feasibility diagnostic only).
   - Confirmatory power for Endpoint 3 under unconditional $s_d = 0.08346$ at $N = 250$ is $> 99.99\%$.
7. **Known Realism Boundary (Kasimir Valdez):**
   - Kasimir Valdez (`3PT = 39`, `Cr = 321`) expanding total shot volume (+318 FGA at 37.6% 3PA) is acknowledged as an intentional consequence of M006 decoupling creation opportunity from shooting preference.
   - No tuning, coupling, or coefficient modifications are permitted.
8. **Explicit Stage C Prohibition:**
   - **NO AUTHORIZATION** is granted to execute either held-out cohort (Context A seeds 10001–10750 or Context B seeds 11001–11250) at this time.
   - Stage C execution requires a separate, explicit owner authorization command.

---

## 2. Commit and Manifest Identifiers

- **Historical v6 Checkpoint:** `68018db98cd033b3008513ff7e6d174eaa81f09f`
- **Active v7 Checkpoint:** `ac187b08db45e5a38c6031bc5c41d6bcc8cf1d08` (T05 baseline)
- **Context A Manifest:** `specs/006-role-aware-shot-selection/t06d-context-a-confirmatory-manifest.csv` (SHA-256: `b9bd863af7a6cbd26ee0c8359d015a6e2088d7dfa1ef3d7ceb31a667a7fe9dd2`)
- **Context B Manifest:** `specs/006-role-aware-shot-selection/t06d-context-b-confirmatory-manifest.csv` (SHA-256: `c48c008b4d74887b2b3f35000437221c6ab28848e4b9798a537604bb6f878235`)
- **Simulation Contract Versions:** Simulation 7, Rules 3, Schema 3, Fingerprint 5, Duration Model 2.
