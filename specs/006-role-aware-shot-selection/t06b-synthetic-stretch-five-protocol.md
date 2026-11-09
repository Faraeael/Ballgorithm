# M006-T06B — Synthetic Stretch-Five Feasibility Study Protocol

- **Date:** 2026-11-09
- **Status:** PRE-REGISTERED SUPPLEMENTAL FEASIBILITY PROTOCOL.
- **Task:** M006-T06B — Stretch-Five Development Feasibility.
- **Baseline:** `impl/m006-t06b-confirmatory-readiness` at `3525d34752d429298ef871255d706790303fdc83`.
- **Pre-Registration Requirement:** This document and its manifest must be committed before simulating seeds 3001–3200.

---

## 1. Background and Objective

The Stage A generated-league pilot revealed that the default M001 league (`seed: 20261028`) contains no nominal Center or Power Forward with `threePoint >= 70`. Consequently, only 40/200 paired games in Stage A met the stretch-big eligibility threshold ($\ge 10$ attempts), populated solely by perimeter starters shifted to PF during substitutions.

This supplemental study tests whether a deterministic synthetic roster containing genuine starting stretch-five Centers (`threePoint >= 70`) yields:
1. Sufficient attempt volume ($\ge 10$ FGA per game in $\ge 80\%$ of games).
2. Defined paired differences ($d_g = \text{v7} - \text{v6}$) in perimeter attempt shares.
3. Stable accounting and valid reducer execution in both engine checkpoints.

---

## 2. Deterministic Synthetic Roster Construction

Starting from canonical league generation `GenerationConfig(seed: 20261028)`, only the two starting Centers are deterministically modified:

### Team 1 (`team-1`, Aurora Comets)
- Replace `player-1-8` (Elias Kovacs, nominal Center) with:
  - Position: `Position.c` (Slot 4, Center).
  - Attributes: `insideScoring: 75, midrange: 55, threePoint: 80, freeThrow: 75, passing: 60, ballHandling: 55, perimeterDefense: 50, interiorDefense: 65, rebounding: 70, athleticism: 60, stamina: 70, basketballIQ: 62`.
  - Creation score: $3(55) + 60 + 62 = 287$.
  - All other 11 players on Team 1 remain identical to M001 generation.

### Team 2 (`team-2`, Ironvale Forge)
- Replace `player-2-5` (Emil Lindqvist, nominal Center) with:
  - Position: `Position.c` (Slot 4, Center).
  - Attributes: `insideScoring: 70, midrange: 65, threePoint: 78, freeThrow: 75, passing: 55, ballHandling: 50, perimeterDefense: 50, interiorDefense: 65, rebounding: 70, athleticism: 65, stamina: 70, basketballIQ: 60`.
  - Creation score: $3(50) + 55 + 60 = 265$.
  - All other 11 players on Team 2 remain identical to M001 generation.

---

## 3. Predetermined Case Manifest

- **Game Seeds:** Integer seeds `3001` through `3200` inclusive (200 paired games).
- **Manifest File:** `specs/006-role-aware-shot-selection/t06b-synthetic-stretch-five-manifest.csv`.
- **Matchup:** `team-1` (home) vs `team-2` (away).
- **Lineups:** Default starting five (`CourtLineup.defaultFor(team)`), placing modified players in starting Center slot (slot 4).
- **Rotation Plan:** `RotationPreset.balanced` expanded under `GameRules.standard` for both teams.
- **Simulation Arms:**
  - Historical v6 checkpoint: `68018db98cd033b3008513ff7e6d174eaa81f09f` in detached worktree.
  - Current v7 baseline: `ac187b08db45e5a38c6031bc5c41d6bcc8cf1d08`.

---

## 4. Evaluated Metrics and Sufficiency Threshold

1. **Genuine Stretch-Center FGA per game:** Total and per-player FGA for `player-1-8` and `player-2-5`.
2. **Genuine Stretch-Center 3PA/FGA share:** $\sum 3PA / \sum FGA$ for genuine Centers.
3. **Combined PF/C Stretch-Big 3PA/FGA share:** $\sum 3PA / \sum FGA$ across all PF/C occupants with `threePoint >= 70`.
4. **Eligibility Rate:** Percentage of games where at least one PF/C occupant with `threePoint >= 70` records $\ge 10$ FGA.
5. **Sufficiency Decision Rule:**
   - **FEASIBLE:** Eligible games $\ge 160 / 200$ (80.0%) in both arms.
   - **INSUFFICIENT:** Eligible games $< 160 / 200$.
6. **Integrity:** 100% reducer validation pass rate and accounting consistency.

---

## 5. Non-Pooling and Non-Interference Guardrails

- **Strict Separation:** Results from this synthetic feasibility cohort are purely supplemental and must NOT be combined with the generated-league pilot (seeds 2001–2200).
- **Held-Out Protection:** Seeds 10001–10500 remain strictly untouched.
- **Production Isolation:** No change to production LeagueGenerator or default M001 league vectors.
