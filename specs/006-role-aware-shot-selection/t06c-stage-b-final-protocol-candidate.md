# M006-T06C — Stage B Confirmatory Protocol (CANDIDATE FOR OWNER FREEZE)

- **Date:** 2026-11-09
- **Status:** CANDIDATE PROTOCOL FOR OWNER REVIEW (Stage B is NOT frozen; Stage C is NOT authorized).
- **Task:** M006-T06C — Final confirmatory protocol candidate.
- **Baseline:** `impl/m006-t06c-protocol-finalization` at `4e0177bea881813d8cf583646558acfbbdcf50ee`.
- **Governing Freeze:** `d5f9f7d16372cb523f149d3536d972ed5f83e36b` (`verification-plan.md` §5).
- **Statistical Corrections Document:** `specs/006-role-aware-shot-selection/t06c-statistical-corrections.md`.

---

## 1. Architectural Design: Two Separated Evaluation Contexts

To guarantee that confirmatory testing evaluates both weak-shooter suppression and genuine stretch-five retention without selection artifacts, the evaluation is partitioned into **two distinct, non-overlapping contexts**:

```
+---------------------------------------------------------------------------------+
|                               STAGE B EVALUATION                                |
+----------------------------------------------------+----------------------------+
| Context A: Main Generated League Cohort            | Context B: Constructed     |
| Matchup: team-1 vs team-2 (seed 20261028)          | Matchup: team-1 vs team-2  |
| Seeds: 10001–10500 (N = 500 paired games)          | Seeds: 11001–11250 (N=250) |
| - Primary Creator Shot Share (Endpoint 1)          | - Stretch-Big 3PA Share    |
| - Weak-Shooter 3PA Share (Endpoint 2)              |   (Endpoint 3, non-inf)    |
| - Secondary Creator Shot Share (Endpoint 4)        |                            |
| - Macroeconomic Guardrails (TOST Equivalence)      | - Positional Opportunity   |
+----------------------------------------------------+----------------------------+
       \                                                      /
        \                                                    /
         v                                                  v
     [ Four Primary Endpoints Tested Jointly under Holm Step-Down (alpha = 0.05) ]
```

Data from Context A and Context B are evaluated independently and must **never be pooled**.

---

## 2. The Four Primary Endpoints and Multiplicity Control

The confirmatory family consists of exactly **four pre-specified directional hypothesis tests**. Familywise error rate is strictly controlled at $\alpha = 0.05$ using the **Holm-Bonferroni step-down procedure**:

### The Four Hypotheses
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
yielding exact one-sided $p$-values $p_1, p_2, p_3, p_4$.

### Holm-Bonferroni Decision Procedure
1. Sort the four observed $p$-values in ascending order:
   $$p_{(1)} \le p_{(2)} \le p_{(3)} \le p_{(4)}$$
2. Evaluate step-down rejections sequentially:
   - If $p_{(1)} \le \frac{0.05}{4} = 0.0125$, reject $H_{0,(1)}$ and test $p_{(2)}$. Else stop: accept all nulls.
   - If $p_{(2)} \le \frac{0.05}{3} \approx 0.01667$, reject $H_{0,(2)}$ and test $p_{(3)}$. Else stop: accept remaining nulls.
   - If $p_{(3)} \le \frac{0.05}{2} = 0.0250$, reject $H_{0,(3)}$ and test $p_{(4)}$. Else stop: accept remaining nulls.
   - If $p_{(4)} \le \frac{0.05}{1} = 0.0500$, reject $H_{0,(4)}$. Else accept $H_{0,(4)}$.
3. **Verdict:** Confirmatory evidence is declared **PASSED** only if all four primary hypotheses are rejected ($p_{(k)} \le \alpha / (5 - k)$ for all $k = 1, 2, 3, 4$) and all guardrails pass equivalence testing.

---

## 3. Context A: Main Generated-League Cohort Specification

- **Cohort Size:** $N = 500$ paired games.
- **Proposed Held-Out Seeds:** Integer seeds `10001` through `10500` inclusive.
- **Matchup:** `team-1` (Aurora Comets, home) vs `team-2` (Ironvale Forge, away).
- **Roster:** Canonical M001 league `seed: 20261028` (unmodified).
- **Starting Lineup:** Canonical default five (`CourtLineup.defaultFor(team)`).
- **Rotation Plan:** `RotationPreset.balanced` expanded under `GameRules.standard`.
- **Primary Estimands (Estimand A):** Mean paired per-game proportion difference:
  $$\bar{d}_i = \frac{1}{N_{\text{defined}}} \sum_{g=1}^{N_{\text{defined}}} \left( r_{v7,i}(g) - r_{v6,i}(g) \right)$$
  - Evaluated over all games where the denominator is positive in both arms.
  - Zero-denominator games are omitted from the per-game vector and reported.
  - No post-hoc filtering based on intermediate attempt counts.
- **Insufficiency Stop Rule:** Context A is declared **INSUFFICIENT** if games with positive weak-shooter attempts fall below $400 / 500$ (80%).
- **Complementary Descriptive Estimand:** Pooled attempt-weighted difference ($\hat{\theta}_{\text{pooled}}$).

---

## 4. Context B: Constructed Stretch-Five Cohort Specification

- **Cohort Size:** $N = 250$ paired games.
- **Proposed Held-Out Seeds:** Integer seeds `11001` through `11250` inclusive (verified disjoint from development and Context A ranges).
- **Matchup:** `team-1` (home) vs `team-2` (away).
- **Roster Construction:** Canonical league `seed: 20261028` modified deterministically at starting Center only:
  - **Team 1 (`player-1-8`, Slot 4 C):** `threePoint: 80, insideScoring: 75, midrange: 55, freeThrow: 75, passing: 60, ballHandling: 55, perimeterDefense: 50, interiorDefense: 65, rebounding: 70, athleticism: 60, stamina: 70, basketballIQ: 62`.
  - **Team 2 (`player-2-5`, Slot 4 C):** `threePoint: 78, insideScoring: 70, midrange: 65, freeThrow: 75, passing: 55, ballHandling: 50, perimeterDefense: 50, interiorDefense: 65, rebounding: 70, athleticism: 65, stamina: 70, basketballIQ: 60`.
  - All other 22 players remain identical to M001 generation.
- **Starting Lineup:** Canonical default five with modified Centers starting in Slot 4 (Center).
- **Rotation Plan:** `RotationPreset.balanced` expanded under `GameRules.standard`.
- **Primary Estimand (Endpoint 3):** Mean paired difference in stretch-center 3PA share across defined games.
- **Insufficiency Stop Rule:** Context B is declared **INSUFFICIENT** if games with positive stretch-center attempts fall below $160 / 250$ (64.0%).

---

## 5. Macroeconomic Guardrails (Equivalence Testing)

All guardrails in Context A are evaluated using **Two One-Sided Tests (TOST)** at significance level $\alpha = 0.05$ (equivalent to requiring the 90% confidence interval $[\bar{d} - 1.645 \cdot \text{SE}, \bar{d} + 1.645 \cdot \text{SE}]$ to fall strictly inside $[-\Delta, +\Delta]$).

### Owner Decision on Equivalence Margins
The owner must select between two pre-calculated options:

| Guardrail Metric | Option A: Initial Draft Margins | Option D: Recommended Refined Margins | Rationale for Refinement |
|---|---|---|---|
| **Points per game** | $[ -2.5, +2.5 ]$ pts | **$[ -3.0, +3.0 ]$ pts** | $\pm 3.0$ pts is only $1.3\%$ of 224 total game points |
| **Pace (Possessions)** | $[ -1.5, +1.5 ]$ poss | **$[ -1.75, +1.75 ]$ poss** | Accommodates minor transition timing variation |
| **eFG%** | $[ -1.0\text{ pp}, +1.0\text{ pp} ]$ | **$[ -1.0\text{ pp}, +1.0\text{ pp} ]$** | Preserves exact shooting efficiency standard |
| **Turnovers per 100** | $[ -0.75, +0.75 ]$ | **$[ -0.75, +0.75 ]$** | Preserves ball security standard |
| **Free Throw Attempts** | $[ -1.75, +1.75 ]$ FTA | **$[ -2.25, +2.25 ]$ FTA** | $\pm 2.25$ FTA is $6.4\%$ of 35 game attempts |
| **Joint Guardrail Power ($N = 500$)** | **$72.2\%$** | **$96.2\%$** | **Avoids spurious failure on uncorrelated FTA variance** |

**Recommendation:** Adopt **Option D**. It prevents a $28\%$ chance of a false rejection caused by FTA sample variance while maintaining strict basketball realism guardrails.

---

## 6. Simulation Invariants and Validity Rules

1. **Reducer Validation:** 100.0% of generated ledgers in both arms must pass `GameEventReducer.validate(input, ledger)`. Any failure represents an engine defect and halts evaluation.
2. **Accounting Reconciliation:** 100.0% of games must reconcile points, field goals, three-pointers, free throws, turnovers, and player minutes against authoritative box scores.
3. **No Retuning or Re-baselining:** Simulation version 7, rules 3, schema 3, fingerprint 5, and duration model 2 remain invariant. No parameter tuning is permitted.

---

## 7. Explicit Owner Approvals Required to Freeze Stage B

Before executing Stage C confirmatory simulations, the human owner must formally sign off on:
1. **Approval 1 (Two-Context Separation):** Approval to partition evaluation into Context A (500 games, generated league) and Context B (250 games, constructed stretch-five).
2. **Approval 2 (Guardrail Margin Selection):** Selection of Option D ($[\pm 3.0, \pm 1.75, \pm 1.0\%, \pm 0.75, \pm 2.25]$) or Option A.
3. **Approval 3 (Seed Authorization):** Formal authorization to release held-out seeds `10001–10500` (Context A) and `11001–11250` (Context B).
4. **Approval 4 (Model Boundary Acceptance):** Acknowledgment of Kasimir Valdez's volume expansion (+318 FGA at 37.6% 3PA) as an accepted design boundary of M006 role independence.
