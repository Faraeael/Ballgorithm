# M006-T06E — Confirmatory Execution Integrity Audit

- **Date:** 2026-11-09
- **Status:** EXECUTION-INTEGRITY AUDIT COMPLETE — ISSUES IDENTIFIED & REPAIRED.
- **Repository:** `Faraeael/Ballgorithm`
- **Branch:** `impl/m006-t06e-execution-integrity`
- **Base Baseline:** Stage B Freeze `cacfd7a8583b7c4baa7f3f8d769f701d10809b2d`.
- **Primary Focus:** Repairing Context B synthetic roster construction and reconciling genuine-center metrics with exposure sufficiency rules prior to Stage C execution.

---

## 1. Discovered Deficiencies and Root Causes

A thorough pre-execution audit of `packages/simulation_core/tool/m006_pilot_runner.dart` and `m006_analyze_paired.py` identified two material discrepancies in the Context B tooling:

### Deficiency 1: Synthetic Roster Attribute Profile Mismatch
In `m006_pilot_runner.dart` (lines 120–152), the helper function `modCenter` used Team 1's attribute template for both centers:
```dart
// Pre-repair implementation:
insideScoring: 75, midrange: 55, threePoint: three, freeThrow: 75, passing: 60, ballHandling: 55, ...
```
While this matched Team 1's registered Center (`player-1-8`, $3\text{PT}=80$), it overwrote Team 2's Center (`player-2-5`, $3\text{PT}=78$), whose pre-registered attributes were:
```
insideScoring: 70, midrange: 65, threePoint: 78, freeThrow: 75, passing: 55, ballHandling: 50, perimeterDefense: 50, interiorDefense: 65, rebounding: 70, athleticism: 65, stamina: 70, basketballIQ: 60
```
- **Consequence:** Team 2's Center simulated with slightly altered secondary attributes (`insideScoring 75` instead of `70`, `midrange 55` instead of `65`, etc.).
- **Repair:** Fixed in `m006_pilot_runner.dart` to apply distinct constant attribute vectors for `player-1-8` and `player-2-5`. Verified via unit test `test/simulation/m006_t06e_synthetic_roster_test.dart` (5/5 tests passing).

### Deficiency 2: Genuine-Center vs. PF/C Occupant Measurement Ambiguity
In earlier pilot analysis, `stretchBigFga` aggregated all attempts where the shooter had $3\text{PT} \ge 70$ and occupied either `Position.pf` or `Position.c`.
- **Consequence:** In Context A (generated league), this captured wing starters (Rafael Calloway, Bastian Delacroix) rotated into PF.
- **Investigation of Tactical Rotations:** Under `RotationPreset.balanced`, starting centers play ~31–33 minutes per game, but split time across Slot 4 (Center, ~17 mpg) and Slot 3 (Power Forward, ~15 mpg) when backup Centers enter the game.
- **Exposure Reality:** An individual Center in Slot 4 alone reached $\ge 10$ FGA in only **26 of 200 games (13.0%)**. However, across both big slots (PF/C), genuine centers averaged 12–13 FGA/game and reached $\ge 10$ FGA in **138 of 200 games (69.0%)**.
- **Repair:** Introduced separate tracking for:
  1. `genuineCenterFga` / `genuineCenterThreePa`: Field-goal attempts by `player-1-8` or `player-2-5` while strictly occupying Slot 4 (Center).
  2. Total on-court genuine Center player attempts (across PF and C slots).
  3. General PF/C occupant stretch-big attempts (retained for descriptive continuity).

---

## 2. Corrected Development Rerun Results (Seeds 3001–3200)

Using the corrected roster attributes and distinct metrics, seeds 3001–3200 were re-simulated under historical v6 (`68018db9`) and active v7 (`ac187b08`):

| Estimand Definition | Defined Games ($N$) | v6 3PA Share | v7 3PA Share | Mean Diff ($d_g$) | SD ($s_d$) | Non-Inf Bound ($-\Delta$) | One-Sided $p$-value |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Population 1 (Slot 4 Center Only)** | 200 / 200 | 34.77% | 36.30% | **+1.53 pp** | 0.10656 | $-1.5$ pp | $4.02 \times 10^{-5}$ |
| **Population 2 (Genuine Center Players Across PF/C)** | 200 / 200 | 38.54% | 40.04% | **+1.44 pp** | 0.08031 | $-1.5$ pp | $6.87 \times 10^{-7}$ |
| **Population 3 (All PF/C Occupants with 3PT $\ge 70$)** | 200 / 200 | 37.95% | 39.85% | **+1.90 pp** | 0.08785 | $-1.5$ pp | $6.63 \times 10^{-8}$ |

### Feasibility Interpretation
All three populations demonstrate robust statistical non-inferiority: the perimeter attempt share increased by $+1.4$ to $+1.9$ percentage points, safely ruling out the non-inferiority boundary of $-\Delta = -1.5$ pp ($p < 10^{-4}$ in all cases).
- Under unconditional defined variance ($s_d = 0.080$ to $0.107$), statistical power for non-inferiority at $N = 250$ remains **$> 99.9\%$**.

---

## 3. Exposure Sufficiency Reconciliation

The frozen Stage B protocol specified:
> "Gate 2: At least one genuine Center records $\ge 10$ FGA while occupying Slot 4 in both simulator arms on at least $160 / 250$ paired games (64.0%)."

### The Mathematical Conflict
Because tactical substitutions slide the starter Center to Power Forward for ~15 minutes per game, an individual Center alone in Slot 4 reached $\ge 10$ FGA in both arms in only **26 / 200 games (13.0%)**.
- If Gate 2 is enforced as strictly "Slot 4 alone", Context B will fail its sufficiency gate post-simulation, despite robust Center volume across the game.
- If Gate 2 is reconciled to evaluate genuine Centers across their active on-court big slots (PF/C), the observed rate is **138 / 200 games (69.0%)**, which comfortably achieves the $\ge 64.0\%$ threshold ($160 / 250$).

This conflict cannot be resolved unilaterally by coding agents. It requires an explicit owner decision via the accompanying Corrigendum Proposal.

---

## 4. Tooling Hardening & Verification

1. **Fail-Fast Manifest & Export Validation:**
   `m006_analyze_paired.py` now enforces strict fail-fast validation of manifest SHA-256, cohort size, unique seeds, seed-set equality, game ID matching, accounting consistency, and finite non-NaN numbers.
   Pairing is performed strictly by seed identity, rendering the tool immune to array order.
2. **Confirmatory Decision Finalizer:**
   `packages/simulation_core/tool/m006_confirmatory_finalizer.py` deterministic script combines Context A and Context B summaries, applies dynamic Holm-Bonferroni step-down across the four primary $p$-values, checks TOST guardrails, verifies sufficiency gates, and produces machine-readable and Markdown reports.
3. **Adversarial Test Suite:**
   `test/simulation/test_m006_confirmatory_tooling.py` (13/13 tests passing) confirms failure on shuffled exports, duplicate seeds, missing seeds, extra seeds, incorrect hashes, broken accounting, invalid provenance, endpoint failure, guardrail failure, and insufficiency.
