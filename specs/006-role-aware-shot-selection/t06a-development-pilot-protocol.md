# M006-T06 Stage A — Pre-Registered Development Pilot Protocol

- **Date:** 2026-11-09
- **Status:** PRE-REGISTERED DEVELOPMENT PILOT PROTOCOL (Stage A only).
- **Task:** M006-T06 Stage A — Pre-registered development pilot.
- **Baseline:** `impl/m006-t06a-development-pilot` at `ac187b08db45e5a38c6031bc5c41d6bcc8cf1d08`.
- **Frozen Specification:** `d5f9f7d16372cb523f149d3536d972ed5f83e36b` (`verification-plan.md` §5).
- **Owner Authorization:** Stage A development pilot ONLY. Seeds 2001–2200 inclusive. No Stage B freeze, no Stage C held-out evaluation, no seeds 10001–10500, no probability tuning, no role multiplier changes, no curve adjustments, no schema changes, no protected-branch merges.

---

## 1. Purpose and Non-Goals

### Purpose
Stage A estimates per-game variance, pooled-metric behaviour, eligibility counts, and required sample sizes for candidate confirmatory margins on predetermined development cases. It provides exploratory empirical evidence on basketball behaviour before any confirmatory protocol is frozen.

### Non-Goals and Explicit Restrictions
- **No confirmatory testing:** Stage A does not test held-out hypotheses or declare acceptance criteria met. No PASS/FAIL verdict is permitted at Stage A.
- **No tuning:** Results from this pilot may not be used to adjust role multipliers, zone preference curves, or shot success coefficients.
- **No held-out inspection:** Held-out seeds (10001–10500) remain strictly untouched.
- **Prior seed usage disclosure:** Seeds 1–200 were previously exercised in T013 structural tests; seed 42 was inspected in T05; seeds 1–400 were exercised in legacy sensitivity probes. To maintain diagnostic hygiene, the owner authorized development seeds 2001–2200 for this pilot.

---

## 2. Predetermined Paired Case Manifest

All 200 games are predetermined and fixed before execution. No case may be added, removed, replaced, or reseeded based on outcomes.

- **Game Seeds:** Integer seeds `2001` through `2200` inclusive (exactly 200 seeds).
- **League Seed:** `20261028` (canonical M001 league generator seed).
- **League Generation:** `GenerationConfig(seed: 20261028)` producing standard 8-team, 12-player rosters.
- **Matchup:** Home team `team-1`, away team `team-2`.
- **Lineups:** Canonical default starting five for each team (`CourtLineup.defaultFor(team)`: slot order PG, SG, SF, PF, C).
- **Rotation Plans:** `RotationPlan(home: balanced, away: balanced)` expanded from `RotationPreset.balanced` under the active rules.
- **Rules:** `GameRules.standard` (regulation 48 min, 24 s shot clock, 14 s offensive rebound reset, 5-foul bonus, 4-foul overtime bonus, 10-overtime cap).
- **Simulation Arms:**
  - **Historical v6 Arm:** Accepted M005 engine at commit `68018db98cd033b3008513ff7e6d174eaa81f09f` (simulation 6, rules 3, schema 3, fingerprint 4). Executed in an isolated, detached worktree.
  - **Activated v7 Arm:** Current T05 engine (simulation 7, rules 3, schema 3, fingerprint 5).
- **Offline Analysis:** Identical ledger-derived accounting and metrics formulas applied to both arms; box scores validated against respective event ledgers.

---

## 3. Metrics and Denominators

All metrics derive from the authoritative event ledger replayed in canonical sequence, reconciling with box score totals.

### Primary Metrics
1. **Weak-Shooter 3PA Share:**
   - Definition: `Σ 3PA / Σ FGA` for players with `threePoint < 40` within the game.
   - Denominator: Total FGA by eligible weak shooters.
   - Across-game pooled: Total weak 3PA / Total weak FGA across all games.
2. **Stretch-Big 3PA Share:**
   - Definition: `Σ 3PA / Σ FGA` for players with `threePoint ≥ 70` occupying PF or C court slots at shot time.
   - Denominator: Total FGA by eligible stretch-big occupants.
   - Across-game pooled: Total stretch 3PA / Total stretch FGA across all games.
3. **Primary Creator Shot Share:**
   - Definition: `primary FGA / team FGA` reconstructed at each field-goal attempt from the active on-court five.
   - Denominator: Team FGA.
   - v6 Arm: Evaluated with the identical position-free creation score ranking (`3×handling + passing + iq`) on the active five at shot time.
4. **Secondary Creator Shot Share:**
   - Definition: `secondary FGA / team FGA` reconstructed at each field-goal attempt from the active on-court five.
   - Denominator: Team FGA.
5. **Neutral Player Attempt Share:**
   - Definition: `neutral FGA / team FGA` reconstructed at each field-goal attempt from the active on-court five.
   - Denominator: Team FGA.

### Guardrails
- **Scoring:** Points per game (PTS) per team and combined.
- **Pace:** Possessions per game.
- **Shooting Efficiency:** Effective Field Goal Percentage (`eFG% = (FGM + 0.5 × 3PM) / FGA`).
- **Volume & Mix:** Team FGA, 3PA, and 3PA/FGA.
- **Ball Security:** Turnovers per 100 possessions (`TOV/100 = TOV × 100 / possessions`).
- **Free Throws:** Free throw attempts (FTA) per game.
- **Player Volume:** FGA/36 (`FGA × 2160 / secondsPlayed`) for players with `secondsPlayed ≥ 240`.
- **Integrity:** Reducer validation pass rate (100% required) and accounting consistency.

---

## 4. Zero-Denominator Handling & Eligibility

### Denominator-Zero Rules
- If a game has 0 attempts for an eligible bucket (e.g. 0 weak-shooter FGA), the per-game share for that game is **undefined (`null`)**.
- A game with an undefined metric in either arm yields an undefined paired difference `d_g = v7(g) - v6(g)`. It is excluded from the paired per-game difference distribution for that specific metric only, and the exclusion count is reported.
- No replacement seed is drawn.
- Across-game pooled proportions remain defined as long as the cohort total denominator is non-zero.

### Eligibility Criteria
- **Weak-Shooter Game Eligibility:** Combined weak-shooter FGA across both teams ≥ 20.
- **Stretch-Big Game Eligibility:** At least one PF/C occupant with `threePoint ≥ 70` records ≥ 10 FGA.
- **Insufficiency Reporting:** If eligible games fall below minimum expected thresholds (e.g. 160 of 200 in this pilot, corresponding to the 400/500 proposal), the metric is reported as **INSUFFICIENT**.
- **League Roster Note:** The generated M001 league with seed `20261028` may not contain a genuine stretch-five center. If stretch-big observations are sparse or zero, this is recorded as generated-league insufficiency; controlled synthetic archetype diagnostics are reported separately without mixing data.

---

## 5. Statistical Diagnostics & Estimation Method

1. **Paired Differences:**
   $$d_g = \text{metric}_{v7}(g) - \text{metric}_{v6}(g)$$
   for identical seed $g$.
2. **Descriptive Summaries:**
   Report mean, standard deviation (SD), variance, median, IQR, min, and max of $d_g$.
3. **Resampling for Uncertainty:**
   - Unit of resampling: **paired game $g$** (never individual shots or attempts, which are correlated within a game).
   - Bootstrap: 10,000 resamples over the paired games with replacement.
   - Report: Bootstrap standard error (SE) and 95% percentile confidence interval $[q_{0.025}, q_{0.975}]$.
   - Explicit prohibition: Independent-attempt binomial formulas (e.g. Wald, Wilson on total shots) are mathematically invalid and must not be used.
4. **Sample Size Estimation:**
   Using observed standard deviation $s_d$, estimate required sample size $N$ for candidate confirmatory half-margins $E$:
   $$N \approx \left(\frac{z_{\alpha/2} \cdot s_d}{E}\right)^2$$
   for provisional candidate margins at $\alpha = 0.05$ (two-sided).
5. **Multiplicity Framework (Informational for Stage B):**
   Record Holm-Bonferroni adjustment structure across the four primary metrics for future Stage B planning.

---

## 6. Pre-Registration Verification Rule

This protocol file MUST be committed to Git on branch `impl/m006-t06a-development-pilot` BEFORE any simulation results for seeds 2001–2200 are generated or analyzed.
