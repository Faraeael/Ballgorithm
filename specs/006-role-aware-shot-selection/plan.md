# Plan 006 — Role-Aware Shot Selection v1 (DRAFT, rev 2)

> **Status: DRAFT — NOT FROZEN.** No task is authorized. Baseline `develop/m002`
> `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`.

## 1. Delivery shape

| Task | Purpose | Key deliverable |
|---|---|---|
| T01 | Contract and version boundary | Position-free creation ranking; `gameSimulationVersion` 7, `gameFingerprintVersion` 5 in one commit; typed v5/v6 rejection |
| T02 | Usage policy | Role multipliers inside the probability model; ordering, normalisation and shuffled-input tests |
| T03 | Zone-willingness policy | Piecewise 70/30 curve; controlled normalized vectors; no new draws |
| T04 | Simulator integration, v7 fixtures and historical migration | v7 fixture with digest; v1–v6 archive untouched; historical generation verified at the M005 checkpoint; repeat identity and VM/Chrome parity |
| T05 | Instrumentation and metrics | Optional debug shot observer; ledger-derived metrics with the denominators in the verification plan; shot-time role classification |
| T06 | Pre-registered evaluation and owner review | Frozen protocol (development/held-out seeds, thresholds, CIs, Holm), single held-out run, owner box-score review |

## 2. Gates

- **G0 design:** owner answers DD-M006-01…07; this rev-2 draft reviewed.
- **G1 contract:** version bump + ranking helper only; no behaviour change.
- **G2 policy:** T02/T03 unit evidence green; normalized controlled table reproduced.
- **G3 integration:** v7 fixture pinned; v1–v6 fixture files unchanged; historical v6 generation
  verified once at `68018db` in a detached worktree and recorded; typed rejection both directions.
- **G4 evidence:** metrics reproducible; empirical protocol frozen before the held-out run; one run.
- **G5 acceptance:** owner decision only.

## 3. Version and fixture impact

simulation 7 / fingerprint 5; rules 3, schema 3, duration 2, PRNG unchanged. New v7 fixtures are
additive. Historical v1–v6 fixtures and their digests stay byte-identical; historical generation
tests are not re-run against v7. No dual simulation engine ships.

## 4. JEV advisory (non-binding)

Piecewise structure preferred 0.71 (confidence 0.56); the “per-branch draw order without v6/v7
draw-count equality” claim returned 0.62. Recorded as risk input, not approval.

## 5. Rollback

Before G3 the change is a weight refactor; revert restores v6. After G3, historical fixtures are
untouched, so rollback is a version reversal plus test selection, never a data migration.
