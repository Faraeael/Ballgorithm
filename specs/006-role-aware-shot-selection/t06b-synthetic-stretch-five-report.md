# M006-T06B — Synthetic Stretch-Five Feasibility Report

- **Date:** 2026-11-09
- **Status:** SUPPLEMENTAL FEASIBILITY EVIDENCE — FEASIBLE.
- **Task:** M006-T06B — Synthetic Stretch-Five Feasibility Study.
- **Pre-Registration Commit:** `064cbf10473a0ca4765187015f9878fb411ec5a3`.
- **Pre-Registered Protocol:** `specs/006-role-aware-shot-selection/t06b-synthetic-stretch-five-protocol.md`.
- **Pre-Registered Manifest:** `specs/006-role-aware-shot-selection/t06b-synthetic-stretch-five-manifest.csv`.
- **Paired Seeds CSV:** `specs/006-role-aware-shot-selection/t06b-synthetic-stretch-five-paired-seeds.csv`.
- **Development Seed Range:** Integer seeds `3001` through `3200` inclusive (200 paired games).
- **Historical v6 Checkpoint:** `68018db98cd033b3008513ff7e6d174eaa81f09f` (M005 accepted).
- **Current v7 Baseline:** `ac187b08db45e5a38c6031bc5c41d6bcc8cf1d08` (T05 baseline).

---

## 1. Feasibility Verdict

**VERDICT: FEASIBLE.**
A deterministic synthetic roster replacing only the starting Centers with genuine stretch-five players (`threePoint = 80` on Team 1, `78` on Team 2) resolves the stretch-big sample insufficiency observed in Stage A.
- **Eligibility Rate:** Individual stretch-five Centers recorded $\ge 10$ FGA in **85.0%** (Team 1) and **88.0%** (Team 2) of games, easily surpassing the pre-registered 80.0% feasibility threshold.
- **Paired Cohort Size:** 138 of 200 paired games met the dual-arm eligibility threshold (at least one stretch big with $\ge 10$ FGA in both v6 and v7).
- **Directional Effect:** Genuine stretch-center 3PA share increased by **+2.36 percentage points** (v6 35.89% $\to$ v7 38.24%; 95% bootstrap CI `[+1.18 pp, +3.52 pp]`).
- **Accounting & Reducer Pass:** 200/200 games (100.0%) passed reducer validation and box score accounting reconciliation in both arms.

---

## 2. Genuine Stretch-Center Performance (200 Paired Games)

Both players started in slot 4 (Center) under balanced rotation plans (~31–33 minutes per game).

| Player | Team | Pos | 3pt Rating | v6 FGA (mpg) | v7 FGA (mpg) | Net FGA | v6 3PA | v7 3PA | v6 3PA% | v7 3PA% | Net 3PA% | Games $\ge 10$ FGA |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **player-1-8** | team-1 | C | 80 | 2,628 (32.7) | 2,641 (32.6) | +13 | 963 | 1,046 | 36.64% | 39.61% | **+2.96 pp** | 170 / 200 (85.0%) |
| **player-2-5** | team-2 | C | 78 | 2,705 (31.1) | 2,718 (31.4) | +13 | 1,145 | 1,176 | 42.33% | 43.27% | **+0.94 pp** | 176 / 200 (88.0%) |

### Attempt Distribution per Game
- **player-1-8 (`3pt = 80`):** Min 5 FGA, Median 13 FGA, Max 27 FGA.
- **player-2-5 (`3pt = 78`):** Min 5 FGA, Median 13 FGA, Max 26 FGA.

Both centers maintained robust offensive involvement while anchoring the Center slot, generating reliable per-game shot volume across diverse simulated game scripts.

---

## 3. Paired Differences and Variance

Evaluated across the 138 paired games meeting the pre-registered dual-arm eligibility threshold ($\ge 10$ FGA by a qualifying PF/C occupant in both arms):

| Metric | v6 Mean | v7 Mean | Mean Diff ($d_g$) | SD ($s_d$) | Median Diff | 95% Bootstrap CI | Bootstrap SE |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Stretch-big 3PA share (eligible $N=138$)** | 35.89% | 38.24% | **+2.36 pp** | 0.0703 | +2.73 pp | `[+1.18 pp, +3.52 pp]` | 0.00595 |
| Primary creator shot share | 21.30% | 26.25% | +4.95 pp | 0.0289 | +4.74 pp | `[+4.56 pp, +5.36 pp]` | 0.00204 |
| Secondary creator shot share | 21.89% | 22.82% | +0.92 pp | 0.0329 | +0.75 pp | `[+0.46 pp, +1.38 pp]` | 0.00234 |
| Neutral player shot share | 56.81% | 50.93% | -5.88 pp | 0.0364 | -5.80 pp | `[-6.38 pp, -5.38 pp]` | 0.00257 |
| Points per game | 233.56 | 231.84 | -1.73 | 14.63 | 0.00 | `[-3.73, +0.33]` | 1.033 |
| Possessions per game | 211.36 | 210.58 | -0.79 | 8.04 | 0.00 | `[-1.93, +0.31]` | 0.568 |
| eFG% | 56.15% | 55.68% | -0.47 pp | 0.0301 | 0.00 pp | `[-0.90 pp, -0.06 pp]` | 0.00213 |

---

## 4. Key Takeaways for Stage B Protocol Design

1. **Separated Evaluation Contexts Are Essential:**
   In this synthetic cohort, converting the starting centers to stretch bigs left weak shooters scarce (only 2/200 games had combined weak FGA $\ge 20$). Conversely, in the generated-league cohort, weak shooters were abundant (199/200 games eligible) but stretch bigs were scarce (40/200 games eligible).
   - *Design Implication:* Stage B must specify two dedicated, non-overlapping evaluation contexts:
     - **Context A (Main Generated League):** Evaluates primary creator share, secondary creator share, and weak-shooter 3PA share.
     - **Context B (Constructed Stretch-Five Matchup):** Evaluates genuine stretch-center 3PA retention.
2. **Sample Size Feasibility:**
   With an observed paired difference standard deviation of $s_d = 0.0703$ for stretch bigs, a constructed cohort of **$N = 250$ paired games** achieves a 95% confidence precision half-width of $\pm 0.87$ percentage points, providing decisive evidence on whether stretch bigs retain their perimeter shot volume.
