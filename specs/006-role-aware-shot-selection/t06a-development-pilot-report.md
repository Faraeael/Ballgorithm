# M006-T06 Stage A — Pre-Registered Development Pilot Report

- **Date:** 2026-11-09
- **Status:** STAGE A DEVELOPMENT PILOT EVIDENCE ONLY (Exploratory diagnostics; no confirmatory acceptance).
- **Task:** M006-T06 Stage A — Pre-registered development pilot.
- **Branch:** `impl/m006-t06a-development-pilot`.
- **Baseline SHA:** `ac187b08db45e5a38c6031bc5c41d6bcc8cf1d08`.
- **Pre-Registered Protocol Commit SHA:** `f3627b6e4f03e5b03f9e6f266b6bbf285a34750f`.
- **Historical v6 Checkpoint:** `68018db98cd033b3008513ff7e6d174eaa81f09f` (M005 accepted).
- **Activated v7 Engine:** Current T05 implementation (`b2664f36016c93ff9b508925bd9cbdd9c9c77343`).
- **Development Seed Manifest:** Predetermined integer seeds `2001` through `2200` inclusive (200 paired games).
- **Machine-Readable Summary:** `specs/006-role-aware-shot-selection/t06a-development-pilot-summary.json`.

---

## 1. Executive Summary

Stage A evaluated 200 predetermined paired games on development seeds 2001–2200 under identical league generation (`seed: 20261028`), matchup (`team-1` vs `team-2`), balanced rotation plans, and standard rules. The historical v6 engine was executed in an isolated detached worktree (`68018db9`), and the activated v7 engine was executed from the T05 baseline. Results were analyzed through a version-neutral offline analysis layer verifying exact definitions and box score reconciliation in both arms.

### Key Observed Effects (v6 → v7)
1. **Primary creator shot volume rose significantly:** Primary creator attempt share increased by **+4.30 percentage points** (v6 23.06% → v7 27.36%; 95% bootstrap CI `[+3.85 pp, +4.77 pp]`, $p < 10^{-4}$). Secondary creator share rose by **+1.02 percentage points** (v6 22.56% → v7 23.58%; 95% CI `[+0.60 pp, +1.44 pp]`). Neutral player attempt share absorbed the offset, falling by **-5.33 percentage points** (v6 54.39% → v7 49.06%; 95% CI `[-5.85 pp, -4.82 pp]`).
2. **Weak-shooter perimeter attempts declined:** Across eligible games (combined weak-shooter FGA $\ge 20$, 199/200 games), weak-shooter 3PA share dropped by **-5.17 percentage points** (v6 36.25% → v7 31.08%; 95% bootstrap CI `[-6.31 pp, -4.02 pp]`, $p < 10^{-4}$). In total across 200 games, weak shooters attempted 368 fewer three-pointers (2445 → 2077).
3. **Guardrails remained stable:** Team scoring shifted by **+0.12 points** (223.89 → 224.01; 95% CI `[-2.04, +2.32]`). Effective Field Goal Percentage shifted by **+0.17 percentage points** (54.16% → 54.33%; 95% CI `[-0.29 pp, +0.64 pp]`). Turnovers per 100 possessions shifted by **+0.11** (16.80 → 16.91; 95% CI `[-0.18, +0.40]`). Free throw attempts shifted by **-0.70** (35.85 → 35.15; 95% CI `[-1.93, +0.58]`).
4. **100% integrity pass:** All 200 games in both arms passed reducer validation and maintained exact ledger-to-box-score accounting consistency.
5. **Sample Insufficiency Identified:** In the generated M001 league, neither team has a nominal Center or Power Forward with `threePoint >= 70`. Only 40 of 200 paired games qualified under the stretch-big eligibility rule (PF/C occupant taking $\ge 10$ FGA), populated entirely by non-big players shifted to PF in rotations. The generated league is confirmed **INSUFFICIENT** for confirmatory stretch-five evaluation without synthetic rosters.

---

## 2. Paired Comparison Results (200 Paired Games)

All per-game differences are $d_g = \text{metric}_{v7}(g) - \text{metric}_{v6}(g)$ on seed $g$. Uncertainty is estimated via **10,000 paired-game bootstrap resamples** (resampling whole games, not attempts).

| Metric | v6 Mean | v7 Mean | Mean Diff ($d_g$) | SD ($s_d$) | Median Diff | 95% Bootstrap CI | Bootstrap SE | Undefined Games |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **Primary creator share** | 23.06% | 27.36% | **+4.30 pp** | 0.0336 | +4.30 pp | `[+3.85 pp, +4.77 pp]` | 0.00237 | 0 |
| **Secondary creator share** | 22.56% | 23.58% | **+1.02 pp** | 0.0304 | +1.26 pp | `[+0.60 pp, +1.44 pp]` | 0.00212 | 0 |
| **Neutral player share** | 54.39% | 49.06% | **-5.33 pp** | 0.0376 | -5.51 pp | `[-5.85 pp, -4.82 pp]` | 0.00261 | 0 |
| **Weak-shooter 3PA share (eligible $N=199$)** | 36.25% | 31.08% | **-5.17 pp** | 0.0828 | -5.23 pp | `[-6.31 pp, -4.02 pp]` | 0.00584 | 0 |
| Weak-shooter 3PA share (all $N=200$) | 36.32% | 31.17% | -5.15 pp | 0.0827 | -5.20 pp | `[-6.27 pp, -3.98 pp]` | 0.00589 | 0 |
| Stretch-big 3PA share (all defined $N=176$) | 38.01% | 39.32% | +1.31 pp | 0.2077 | 0.00 pp | `[-1.76 pp, +4.34 pp]` | 0.01555 | 24 |
| Stretch-big 3PA share (eligible $N=40$) | 35.95% | 36.67% | +0.72 pp | 0.1491 | 0.00 pp | `[-3.82 pp, +5.39 pp]` | 0.02356 | 0 |
| **Points per game (PTS)** | 223.89 | 224.01 | **+0.12** | 15.94 | 0.00 | `[-2.04, +2.32]` | 1.123 | 0 |
| **Possessions per game** | 209.68 | 209.27 | **-0.41** | 7.46 | 0.00 | `[-1.45, +0.62]` | 0.524 | 0 |
| **eFG%** | 54.16% | 54.33% | **+0.17 pp** | 0.0338 | +0.03 pp | `[-0.29 pp, +0.64 pp]` | 0.00239 | 0 |
| **Team FGA per game** | 186.20 | 185.71 | **-0.49** | 8.79 | 0.00 | `[-1.71, +0.73]` | 0.621 | 0 |
| **Team 3PA per game** | 76.70 | 75.52 | **-1.18** | 6.24 | -1.00 | `[-2.04, -0.33]` | 0.436 | 0 |
| **Team 3PA/FGA share** | 41.20% | 40.65% | **-0.55 pp** | 0.0285 | -0.52 pp | `[-0.94 pp, -0.15 pp]` | 0.00200 | 0 |
| **Turnovers per 100 poss** | 16.80 | 16.91 | **+0.11** | 2.10 | 0.00 | `[-0.18, +0.40]` | 0.149 | 0 |
| **Free throw attempts (FTA)** | 35.85 | 35.15 | **-0.70** | 9.25 | 0.00 | `[-1.93, +0.58]` | 0.642 | 0 |

---

## 3. Pooled Attempt-Weighted Proportions Across All 200 Games

Across the entire 200-game cohort, total volume and attempt-weighted rates:

| Category | v6 Total | v7 Total | v6 Pooled Rate | v7 Pooled Rate | Net Shift |
|---|---:|---:|---:|---:|---:|
| Total Field Goal Attempts | 37,240 | 37,142 | 100.0% | 100.0% | -98 FGA |
| Total 3-Point Attempts | 15,339 | 15,103 | 41.19% | 40.66% | -0.53 pp |
| Primary Creator Attempts | 8,586 | 10,165 | 23.06% | 27.37% | **+4.31 pp** |
| Secondary Creator Attempts | 8,405 | 8,759 | 22.57% | 23.58% | **+1.01 pp** |
| Neutral Player Attempts | 20,249 | 18,218 | 54.37% | 49.05% | **-5.32 pp** |
| Weak-Shooter Attempts (`3pt < 40`) | 6,726 | 6,664 | 18.06% | 17.94% | -62 FGA |
| Weak-Shooter 3-Point Attempts | 2,445 | 2,077 | **36.35%** | **31.17%** | **-5.18 pp** |
| Stretch-Big Attempts (PF/C slot, `3pt ≥ 70`) | 1,917 | 1,706 | 5.15% | 4.59% | -211 FGA |
| Stretch-Big 3-Point Attempts | 722 | 664 | **37.66%** | **38.92%** | **+1.26 pp** |

---

## 4. Team-by-Team Consistency

Both teams were tested across the exact same 200 games. Team 1 was home in all games; Team 2 was away.

| Metric | Team 1 (v6 → v7) | Team 2 (v6 → v7) | Consistency Evaluation |
|---|---|---|---|
| Points per game | 110.81 → 110.50 (-0.31) | 113.08 → 113.51 (+0.43) | Stable on both sides (< 0.5 pts) |
| eFG% | 54.15% → 53.92% (-0.23 pp) | 54.25% → 54.83% (+0.58 pp) | Stable on both sides (< 0.6 pp) |
| TOV/100 possessions | 17.42 → 17.65 (+0.23) | 16.18 → 16.17 (-0.01) | Stable on both sides (< 0.3) |
| Team FGA per game | 91.90 → 91.83 (-0.07) | 94.30 → 93.88 (-0.42) | Negligible shift (< 0.5 FGA) |
| Team 3PA per game | 37.71 → 37.91 (+0.20) | 38.98 → 37.60 (-1.38) | Slight drop on Team 2 due to weak-shooter perimeter drop |
| Primary creator share | 23.70% → 28.53% (**+4.84 pp**) | 22.44% → 26.21% (**+3.77 pp**) | **Consistent upward shift** on both teams |
| Secondary creator share | 22.26% → 23.02% (**+0.76 pp**) | 22.83% → 24.14% (**+1.31 pp**) | **Consistent upward shift** on both teams |
| Neutral player share | 54.04% → 48.44% (**-5.60 pp**) | 54.73% → 49.65% (**-5.08 pp**) | **Consistent downward shift** on both teams |
| Weak-shooter 3PA share | 30.55% → 27.44% (**-3.11 pp**) | 38.34% → 32.29% (**-6.04 pp**) | **Consistent downward shift** on both teams |

The policy shift is structural and systematic: neither team exhibited divergent behavior.

---

## 5. Player-Level Archetype Analysis

All 24 players on both rosters evaluated across all 200 games:

| Player | Team | Pos | 3pt | Creation | FGA (v6 → v7) | 3PA (v6 → v7) | 3PA Share (v6 → v7) | FGA/36 (v6 → v7) | v7 Roles (Prim/Sec/Neut) |
|---|---|---|---|---|---|---|---|---|---|
| **Elias Vasquez** | team-1 | PG | 68 | 331 | 3054 → 3713 (+659) | 1443 → 1781 (+338) | 47.2% → 48.0% | 17.76 → 21.40 | 3713 / 0 / 0 |
| **Kasimir Valdez** | team-2 | PG | 39 | 321 | 2697 → 3015 (+318) | 1138 → 1133 (-5) | 42.2% → **37.6%** | 15.59 → 17.50 | 1993 / 528 / 494 |
| **Malik Sinclair** | team-2 | SG | 68 | 276 | 2788 → 2759 (-29) | 1299 → 1306 (+7) | 46.6% → 47.3% | 16.12 → 15.81 | 52 / 1866 / 841 |
| **Jalen Bellamy** | team-1 | SF | 63 | 255 | 2582 → 2462 (-120) | 1052 → 1000 (-52) | 40.7% → 40.6% | 14.93 → 14.19 | 0 / 1197 / 1265 |
| **Rafael Calloway** | team-2 | SF | 70 | 273 | 2376 → 2171 (-205) | 947 → 876 (-71) | 39.9% → 40.4% | 13.54 → 12.38 | 0 / 20 / 2151 |
| **Emil Lindqvist** | team-2 | C | 24 | 213 | 2299 → 2089 (-210) | 775 → 511 (-264) | 33.7% → **24.5%** | 12.93 → 11.76 | 0 / 0 / 2089 |
| **Jonas Cortez** | team-1 | SG | 69 | 252 | 2254 → 2019 (-235) | 835 → 775 (-60) | 37.0% → 38.4% | 12.89 → 11.68 | 0 / 10 / 2009 |
| **Bastian Delacroix** | team-2 | PG | 79 | 310 | 2093 → 2109 (+16) | 945 → 992 (+47) | 45.2% → 47.0% | 17.92 → 18.07 | 444 / 693 / 972 |
| **Ravi Ibarra** | team-1 | PF | 61 | 201 | 1959 → 1801 (-158) | 809 → 744 (-65) | 41.3% → 41.3% | 11.07 → 10.10 | 0 / 0 / 1801 |
| **Silas Barlow** | team-1 | PF | 45 | 280 | 1918 → 1851 (-67) | 714 → 686 (-28) | 37.2% → 37.1% | 16.35 → 15.73 | 101 / 805 / 945 |
| **Ilya Sandoval** | team-2 | SG | 67 | 322 | 1907 → 2084 (+177) | 916 → 978 (+62) | 48.0% → 46.9% | 16.73 → 18.30 | 712 / 1372 / 0 |
| **Tavi Abernathy** | team-1 | SG | 51 | 292 | 1849 → 1935 (+86) | 779 → 804 (+25) | 42.1% → 41.6% | 16.48 → 17.43 | 436 / 1466 / 33 |
| **Elias Kovacs** | team-1 | C | 37 | 197 | 1707 → 1540 (-167) | 520 → 423 (-97) | 30.5% → **27.5%** | 9.38 → 8.48 | 0 / 0 / 1540 |
| **Teodor Halloran** | team-1 | PG | 64 | 275 | 1690 → 1516 (-174) | 813 → 735 (-78) | 48.1% → 48.5% | 14.48 → 13.14 | 22 / 208 / 1286 |
| **Felix Ravensworth** | team-2 | PF | 44 | 246 | 1682 → 1491 (-191) | 556 → 498 (-58) | 33.1% → 33.4% | 9.22 → 8.22 | 0 / 0 / 1491 |
| **Isandro Sinclair** | team-2 | SF | 51 | 273 | 1507 → 1321 (-186) | 628 → 558 (-70) | 41.7% → 42.2% | 13.09 → 11.67 | 0 / 53 / 1268 |
| **Oren Dunmore** | team-2 | PG | 60 | 324 | 1489 → 1721 (+232) | 581 → 659 (+78) | 39.0% → 38.3% | 13.26 → 15.45 | 1721 / 0 / 0 |
| **Kellan Valdez** | team-1 | PG | 60 | 306 | 1337 → 1509 (+172) | 561 → 624 (+63) | 42.0% → 41.4% | 12.29 → 13.90 | 968 / 541 / 0 |
| Reserves (< 50 FGA) | — | — | — | — | 52 → 36 (-16) | 28 → 20 (-8) | — | — | — |

---

## 6. Answers to the 7 Basketball Behavior Review Questions

### 1. Did low-three-point players reduce perimeter attempts?
**YES.** Weak shooters (`threePoint < 40`) reduced their perimeter attempt share by **-5.17 percentage points** on eligible games (95% CI `[-6.31 pp, -4.02 pp]`). Across 200 games, weak shooters took 368 fewer three-pointers.
- Emil Lindqvist (Center, `3pt = 24`): 3PA dropped from 775 to 511 (-264 threes, -34.1%), dropping his 3PA share from 33.7% to 24.5% (-9.2 pp).
- Elias Kovacs (Center, `3pt = 37`): 3PA dropped from 520 to 423 (-97 threes, -18.7%), dropping his 3PA share from 30.5% to 27.5% (-3.0 pp).
- Kasimir Valdez (Point Guard, `3pt = 39`): 3PA share dropped from 42.2% to 37.6% (-4.6 pp).

### 2. Did stretch bigs retain three-point opportunities?
**YES in directional tendency, but INSUFFICIENT in sample size.**
- Across all 176 games with qualifying attempts, stretch-big 3PA share shifted by +1.31 pp (38.01% → 39.32%, pooled +1.26 pp).
- However, neither generated team contains a nominal Power Forward or Center with `3pt >= 70`. All stretch-big attempts came from nominal wings/guards (Rafael Calloway, Bastian Delacroix) shifted into PF slots during rotations.
- As a result, only 40 paired games met the $\ge 10$ attempt eligibility threshold in both arms.
- Controlled synthetic tests confirm that an actual stretch-five Center (`3pt = 80`) increases normalized half-court 3PA share from 37.33% to 38.47% (+1.14 pp).

### 3. Did creation roles meaningfully affect shot distribution?
**YES.**
- Primary creator share rose from 23.06% to 27.36% (+4.30 pp, 95% CI `[+3.85 pp, +4.77 pp]`).
- Secondary creator share rose from 22.56% to 23.58% (+1.02 pp, 95% CI `[+0.60 pp, +1.44 pp]`).
- Neutral player share fell from 54.39% to 49.06% (-5.33 pp, 95% CI `[-5.85 pp, -4.82 pp]`).
- Individual primary creators saw substantial volume increases: Elias Vasquez (`Cr = 331`) went from 17.76 to 21.40 FGA/36 (+3.64 FGA/36, +659 FGA across 200 games). Oren Dunmore (`Cr = 324`) went from 13.26 to 15.45 FGA/36 (+2.19 FGA/36).

### 4. Were elite scorers unintentionally suppressed?
**NO.**
- High-shooting scorer Bastian Delacroix (`3pt = 79`, `Cr = 310`) took 2,093 FGA in v6 and 2,109 FGA in v7 (+16 FGA; 17.92 → 18.07 FGA/36). He was never suppressed below his baseline.
- Malik Sinclair (`3pt = 68`, `Cr = 276`) took 2,788 FGA in v6 and 2,759 in v7 (-29 FGA, -1.0%; 16.12 → 15.81 FGA/36).
- High scorers who ranked neutral on court experienced slight proportional dilution (typically -0.5 to -1.2 FGA/36) because on-court primary creators were lifted, but no player's raw weight was reduced.

### 5. Did team scoring, eFG, turnovers or FTA shift materially?
**NO.** All macroeconomic guardrails remained stable:
- Points per game shifted by +0.12 pts (95% CI `[-2.04, +2.32]`).
- eFG% shifted by +0.17 pp (95% CI `[-0.29 pp, +0.64 pp]`).
- Turnovers per 100 shifted by +0.11 (95% CI `[-0.18, +0.40]`).
- Free throw attempts shifted by -0.70 FTA (95% CI `[-1.93, +0.58]`).
- Possessions per game shifted by -0.41 poss (95% CI `[-1.45, +0.62]`).

### 6. Are changes consistent across teams or isolated to particular rosters?
**CONSISTENT.** Both teams exhibited the same directional patterns:
- Primary creator share rose (+4.84 pp on Team 1, +3.77 pp on Team 2).
- Neutral share declined (-5.60 pp on Team 1, -5.08 pp on Team 2).
- Weak shooter 3PA share declined (-3.11 pp on Team 1, -6.04 pp on Team 2).
- Scoring, pace, and efficiency shifts were negligible on both sides.

### 7. Which player or lineup archetypes show suspicious behavior?
1. **The Weak-Shooting High Creator (Kasimir Valdez, `3pt = 39`, `Cr = 321`):**
   Because creation score (`3*handling + passing + iq`) does not penalize poor shooting, Valdez received primary creator status whenever on court without an even higher creator. His total FGA rose from 2,697 to 3,015 (+318 FGA; 15.59 → 17.50 FGA/36). His 3PA share dropped from 42.2% to 37.6% (-4.6 pp), but because his overall usage expanded, his absolute three-point attempts remained flat (1,138 in v6 vs 1,133 in v7). This is a known, expected consequence of separating creator opportunity from shooting preference, but owner should note that a poor shooter with high creation will shoot more overall shots.
2. **Weak-everywhere guards still taking ~38% threes:**
   Kasimir Valdez still took 37.6% threes in v7. This reproduces the accepted design residual in DD-M006-03: when inside scoring and midrange are equally weak, normalisation leaves the three-point share near ~38%.
3. **Stretch-big vacancy in generated rosters:**
   The default M001 league does not generate Centers with `3pt >= 70`. PF/C occupants who took qualifying stretch attempts were purely non-big starters shifted to forward during substitutions.

---

## 7. Sample Size Estimates for Stage B Confirmatory Margins

Using the observed paired difference standard deviation ($s_d$) across the 200 development games, required sample size $N$ for candidate confirmatory half-margins $E$ at $\alpha = 0.05$ ($z = 1.96$):

$$N \approx \left(\frac{1.96 \cdot s_d}{E}\right)^2$$

| Metric | Observed SD ($s_d$) | Candidate Half-Margin ($E$) | Required Sample Size ($N$) |
|---|---:|---:|---:|
| **Weak-shooter 3PA share (eligible)** | **0.0828** | $\pm 1.0$ pp (0.010) | 264 games |
| | | $\pm 1.5$ pp (0.015) | 118 games |
| | | $\pm 2.0$ pp (0.020) | 66 games |
| **Primary creator shot share** | **0.0336** | $\pm 0.5$ pp (0.005) | 174 games |
| | | $\pm 1.0$ pp (0.010) | 44 games |
| **Secondary creator shot share** | **0.0304** | $\pm 0.5$ pp (0.005) | 143 games |
| | | $\pm 1.0$ pp (0.010) | 36 games |
| **Neutral player shot share** | **0.0376** | $\pm 0.5$ pp (0.005) | 217 games |
| | | $\pm 1.0$ pp (0.010) | 55 games |
| **eFG% (Guardrail)** | **0.0338** | $\pm 0.5$ pp (0.005) | 176 games |
| | | $\pm 0.75$ pp (0.0075) | 79 games |
| | | $\pm 1.0$ pp (0.010) | 44 games |
| **Total Points per game (Guardrail)** | **15.94** | $\pm 1.5$ pts | 434 games |
| | | $\pm 2.0$ pts | 245 games |
| | | $\pm 3.0$ pts | 109 games |

### Takeaway for Stage B
A confirmatory sample of **500 paired games** (as proposed in `verification-plan.md` §5) provides overwhelming statistical power for all primary creator and neutral metrics (capable of resolving margins within $\pm 0.3$ pp), weak-shooter 3PA share (resolving within $\pm 0.73$ pp), and total points (resolving within $\pm 1.4$ pts).

---

## 8. Unresolved Owner Decisions

1. **Stretch-Big Confirmatory Evaluation Strategy:**
   Because default generated rosters lack nominal Centers with `3pt >= 70`, only 40/200 paired games were eligible. The owner must choose one of:
   - *Option A:* Retain the unit and synthetic archetype audit as the authoritative proof for stretch bigs, omitting stretch-big 3PA share from the held-out generated league primary cohort.
   - *Option B:* Construct a synthetic paired league containing genuine stretch-five centers and run a dedicated synthetic cohort.
   - *Option C:* Relax the stretch-big eligibility threshold from $\ge 10$ FGA to $\ge 5$ FGA.
2. **Weak-Shooting Creator Behavior:**
   Evaluate whether Kasimir Valdez taking 3,015 FGA (+318 FGA) with 37.6% threes is acceptable as designed, or whether future milestones should couple creator opportunity multipliers with shooting efficiency.
3. **Stage B Confirmatory Protocol Authorization:**
   Review and authorize the formal Stage B confirmatory protocol before any run on held-out seeds (10001–10500).

---

## 9. Regression and Verification

Environment: Windows x64; Dart 3.12.2 stable; Flutter 3.44.2 stable.

| Check | Command | Result |
|---|---|---|
| Core static analysis | `dart analyze` from `packages/simulation_core` | PASS; no issues |
| Core formatting | `dart format --set-exit-if-changed lib test` from `packages/simulation_core` | PASS; 91 files, 0 changed |
| Full core VM tests | `dart test` from `packages/simulation_core` | PASS; 617 tests |
| Core Chrome tests | `dart test -p chrome test/deterministic_random_test.dart test/generator_test.dart test/validation_test.dart test/simulation` | PASS; 616 tests |
| Flutter analysis | `flutter analyze` at repository root | PASS; no issues |
| Flutter widget/flow tests | `flutter test` at repository root | PASS; 111 tests |

Note: The Chrome command excludes `domain_isolation_test.dart`, which uses `dart:io`.

- **Deterministic reproduction:** Repeated executions of paired simulations with seeds 2001–2200 produce identical metrics, event ledgers, and fingerprints.
- **Fixtures intact:** Historical v1–v6 fixture files and the canonical v7 fixture file were not modified.
- **Held-out seeds untouched:** No seeds in the 10001–10500 held-out range were inspected or executed.
- **No production version changes:** Simulation version remains 7, rules version 3, event schema version 3, fingerprint version 5, duration model version 2.
- **No new PRNG stages or gameplay changes:** All random draw order and probability coefficients remain identical to the accepted T04/T05 baseline.
