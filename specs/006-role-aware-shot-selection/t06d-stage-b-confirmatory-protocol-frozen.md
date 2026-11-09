# M006-T06D — Stage B Confirmatory Protocol (FROZEN — OWNER APPROVED)

- **Date:** 2026-11-09
- **Status:** FROZEN — OWNER APPROVED 2026-11-09.
- **Repository:** `Faraeael/Ballgorithm`
- **Branch:** `impl/m006-t06d-stage-b-freeze`
- **Governing Freeze:** `d5f9f7d16372cb523f149d3536d972ed5f83e36b` (`verification-plan.md` §5).
- **Owner Freeze Record:** `specs/006-role-aware-shot-selection/M006-STAGE-B-OWNER-DECISION.md`.
- **Methodology Audit:** `specs/006-role-aware-shot-selection/t06c-statistical-corrections.md`.
- **Execution Limitation:** Frozen for specification only. NO AUTHORIZATION to execute held-out cohorts.

---

## 1. Evaluation Architecture: Two Disjoint Contexts

Confirmatory evaluation is strictly partitioned into two non-overlapping contexts:

```
+---------------------------------------------------------------------------------+
|                         STAGE B CONFIRMATORY EVALUATION                         |
+----------------------------------------------------+----------------------------+
| Context A: Main Generated League Cohort            | Context B: Constructed     |
| Matchup: team-1 vs team-2 (seed 20261028)          | Matchup: team-1 vs team-2  |
| Seeds: 10001–10750 (N = 750 paired games)          | Seeds: 11001–11250 (N=250) |
| - Primary Creator Shot Share (Endpoint 1)          | - Stretch-Big 3PA Share    |
| - Weak-Shooter 3PA Share (Endpoint 2)              |   (Endpoint 3, non-inf)    |
| - Secondary Creator Shot Share (Endpoint 4)        |                            |
| - Strict Macro Guardrails (TOST Equivalence)       | - Positional Opportunity   |
+----------------------------------------------------+----------------------------+
       \                                                      /
        \                                                    /
         v                                                  v
     [ Four Primary Endpoints Tested Jointly under Holm Step-Down (alpha = 0.05) ]
```

Data from Context A and Context B must **never be pooled**.

---

## 2. The Four Primary Endpoints and Multiplicity Control

The confirmatory family comprises exactly **four pre-specified directional hypothesis tests**. Familywise error rate is strictly controlled at $\alpha = 0.05$ using the **Holm-Bonferroni step-down procedure**:

### The Four Primary Hypotheses
1. **Endpoint 1 (Context A): Primary Creator Shot Share**
   - $H_{0,1}: \delta_{\text{prim}} \le +0.030$ vs. $H_{1,1}: \delta_{\text{prim}} > +0.030$
2. **Endpoint 2 (Context A): Weak-Shooter 3PA Share**
   - $H_{0,2}: \delta_{\text{weak}} \ge -0.035$ vs. $H_{1,2}: \delta_{\text{weak}} < -0.035$
3. **Endpoint 3 (Context B): Stretch-Big 3PA Share (Non-Inferiority)**
   - $H_{0,3}: \delta_{\text{stretch}} \le -0.015$ vs. $H_{1,3}: \delta_{\text{stretch}} > -0.015$
4. **Endpoint 4 (Context A): Secondary Creator Shot Share**
   - $H_{0,4}: \delta_{\text{sec}} \le +0.005$ vs. $H_{1,4}: \delta_{\text{sec}} > +0.005$

### Authoritative Primary Test Statistic
Each endpoint is evaluated using a **paired-sample Student's $t$-test** on per-game differences:
$$t_i = \frac{\bar{d}_i - \delta_{0,i}}{s_{d,i} / \sqrt{N_{\text{defined},i}}}$$
yielding exact one-sided $p$-values $p_1, p_2, p_3, p_4$ with degrees of freedom $\nu_i = N_{\text{defined},i} - 1$.

### Dynamic Holm Step-Down Algorithm
1. Sort the four observed $p$-values in ascending order:
   $$p_{(1)} \le p_{(2)} \le p_{(3)} \le p_{(4)}$$
   recording the mapping $\pi(k)$ back to endpoint name.
2. Step-down decision:
   - **Step 1:** If $p_{(1)} \le \frac{0.05}{4} = 0.0125$, reject $H_{0,\pi(1)}$ and test $p_{(2)}$. Else stop: fail to reject all hypotheses.
   - **Step 2:** If $p_{(2)} \le \frac{0.05}{3} \approx 0.01667$, reject $H_{0,\pi(2)}$ and test $p_{(3)}$. Else stop: fail to reject remaining hypotheses.
   - **Step 3:** If $p_{(3)} \le \frac{0.05}{2} = 0.0250$, reject $H_{0,\pi(3)}$ and test $p_{(4)}$. Else stop: fail to reject remaining hypotheses.
   - **Step 4:** If $p_{(4)} \le \frac{0.05}{1} = 0.0500$, reject $H_{0,\pi(4)}$. Else fail to reject $H_{0,\pi(4)}$.
3. Rejection halts immediately at the first non-rejection.
4. **Verdict:** Confirmatory evidence is declared **PASSED** only if all four primary hypotheses are rejected and all guardrails pass equivalence testing.

---

## 3. Context A: Main Generated-League Cohort Specification

- **Cohort Size:** $N = 750$ paired games.
- **Predetermined Seeds:** Integer seeds `10001` through `10750` inclusive.
- **Manifest:** `specs/006-role-aware-shot-selection/t06d-context-a-confirmatory-manifest.csv`.
- **Matchup:** `team-1` (Aurora Comets, home) vs `team-2` (Ironvale Forge, away).
- **Roster:** Canonical M001 league `seed: 20261028` (unmodified).
- **Starting Lineup:** Canonical default five (`CourtLineup.defaultFor(team)`).
- **Rotation Plan:** `RotationPreset.balanced` expanded under `GameRules.standard`.
- **Primary Estimands (Estimand A):** Mean paired per-game proportion difference:
  $$\bar{d}_i = \frac{1}{N_{\text{defined}}} \sum_{g=1}^{N_{\text{defined}}} \left( \frac{Y_{v7,i}(g)}{M_{v7,i}(g)} - \frac{Y_{v6,i}(g)}{M_{v6,i}(g)} \right)$$
  - Evaluated over all games where the denominator is positive ($M_g > 0$) in both arms.
  - Zero-denominator games are counted, reported, and omitted from per-game ratio averaging without replacement.
  - No post-hoc attempt filtering of positive-denominator games is permitted.
- **Cohort Evidence-Sufficiency Gates:**
  - Gate 1: Defined weak-shooter games $\ge 600 / 750$ (80.0%).
  - Gate 2: Pre-declared combined weak-shooter FGA $\ge 20$ in both arms on at least $600 / 750$ paired games (80.0%).
  - Breaching either gate halts evaluation with verdict **INSUFFICIENT**.
- **Secondary Estimand (Estimand B):** Difference in pooled attempt-weighted proportions reported descriptively.

---

## 4. Context B: Constructed Stretch-Five Cohort Specification

- **Cohort Size:** $N = 250$ paired games.
- **Predetermined Seeds:** Integer seeds `11001` through `11250` inclusive (verified disjoint from prior ranges).
- **Manifest:** `specs/006-role-aware-shot-selection/t06d-context-b-confirmatory-manifest.csv`.
- **Matchup:** `team-1` (home) vs `team-2` (away).
- **Roster Construction:** Canonical league `seed: 20261028` modified deterministically at starting Center only:
  - **Team 1 (`player-1-8`, Slot 4 C):** `threePoint: 80, insideScoring: 75, midrange: 55, freeThrow: 75, passing: 60, ballHandling: 55, perimeterDefense: 50, interiorDefense: 65, rebounding: 70, athleticism: 60, stamina: 70, basketballIQ: 62`.
  - **Team 2 (`player-2-5`, Slot 4 C):** `threePoint: 78, insideScoring: 70, midrange: 65, freeThrow: 75, passing: 55, ballHandling: 50, perimeterDefense: 50, interiorDefense: 65, rebounding: 70, athleticism: 65, stamina: 70, basketballIQ: 60`.
  - All other 22 players remain identical to M001 generation.
- **Starting Lineup:** Canonical default five with modified Centers starting in Slot 4 (Center).
- **Rotation Plan:** `RotationPreset.balanced` expanded under `GameRules.standard`.
- **Primary Estimand (Endpoint 3):** Mean paired difference in stretch-center 3PA share across defined games.
  - Evaluated over all games where stretch-center FGA $> 0$ in both arms.
  - Development data confirmed 200/200 games had defined stretch-center attempts ($s_d = 0.08346$).
- **Cohort Evidence-Sufficiency Gates:**
  - Gate 1: Defined stretch-center games $\ge 200 / 250$ (80.0%).
  - Gate 2: At least one genuine Center records $\ge 10$ FGA while occupying Slot 4 in both simulator arms on at least $160 / 250$ paired games (64.0%).
  - Breaching either gate halts evaluation with verdict **INSUFFICIENT**.

---

## 5. Strict Macroeconomic Guardrails (Equivalence Testing)

All guardrails in Context A are evaluated using **Two One-Sided Tests (TOST)** at significance level $\alpha = 0.05$ (requiring the 90% Student's $t$ confidence interval $[\bar{d} - t_{0.05, 749} \cdot \text{SE}, \bar{d} + t_{0.05, 749} \cdot \text{SE}]$ to fall strictly inside $[-\Delta, +\Delta]$):

| Guardrail Metric | Equivalence Margin ($[-\Delta, +\Delta]$) | Rationale | Observed Development SD ($s_d$) | Marginal TOST Power ($N=750$) |
|---|---|---|---:|---:|
| **Points per game** | $[ -2.5, +2.5 ]$ pts | Preserves team scoring environment | $15.94$ | $99.05\%$ |
| **Pace (Possessions)** | $[ -1.5, +1.5 ]$ poss | Preserves game clock progression | $7.46$ | $99.12\%$ |
| **eFG%** | $[ -1.0\text{ pp}, +1.0\text{ pp} ]$ | Preserves overall shooting accuracy | $0.0338$ | $100.00\%$ |
| **Turnovers per 100** | $[ -0.75, +0.75 ]$ | Preserves ball handling security | $2.10$ | $100.00\%$ |
| **Free Throw Attempts** | $[ -1.75, +1.75 ]$ FTA | Preserves whistle frequency | $9.25$ | **$92.60\%$** |

**Joint Guardrail Power:** Simulating 100,000 draws from the empirical covariance matrix of the five guardrails confirms an estimated **$90.9\%$ joint probability of passing all five guardrails simultaneously**. This planning calculation is exploratory and does not guarantee acceptance.

---

## 6. Simulation Invariants and Validity Rules

1. **Reducer Validation:** 100.0% of generated ledgers in both arms must pass `GameEventReducer.validate(input, ledger)`. Any failure represents an engine defect and halts evaluation.
2. **Accounting Reconciliation:** 100.0% of games must reconcile points, field goals, three-pointers, free throws, turnovers, and player minutes against authoritative box scores.
3. **No Retuning or Re-baselining:** Simulation version 7, rules 3, schema 3, fingerprint 5, and duration model 2 remain invariant. No parameter tuning is permitted.

---

## 7. Execution Safeguards & Stop Rules

1. **Immutable Manifests:** Manifests `t06d-context-a-confirmatory-manifest.csv` and `t06d-context-b-confirmatory-manifest.csv` are committed and cannot be altered.
2. **Strict Non-Replacement:** No game may be excluded, substituted, or re-seeded post-simulation.
3. **Stage C Execution Gate:** Execution of Context A or Context B held-out seeds requires a separate, explicit owner authorization.
