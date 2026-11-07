# Plan 006 — Role-Aware Shot Selection v1 (DRAFT)

> **Status: DRAFT — NOT FROZEN.** No task is authorized. Baseline `develop/m002`
> `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`.

## 1. Delivery shape

One atomic public-contract change, then evidence. Every task requires separate owner authorization.

| Task | Purpose | Key deliverable |
|---|---|---|
| T01 | Contract and version boundary | Derived role helper + creation score; `gameSimulationVersion` 7, `gameFingerprintVersion` 5, one commit; typed v6-ledger rejection test |
| T02 | Usage policy | Role-ranked usage weights inside the probability model; unit tests for ordering, multipliers, normalisation, bounds |
| T03 | Zone-willingness policy | Piecewise ability curve; stretch-big and weak-shooter unit vectors; no new draws |
| T04 | Simulator integration and ledgers | Deterministic v7 fixtures; repeat-run identity; VM/Chrome parity; intentional-difference record |
| T05 | Evaluation instrumentation and metrics | Debug-only shot-decision observer (if approved); ledger-derived usage/3PA metrics; controlled archetype fixtures |
| T06 | Pre-registered evaluation and owner review | Frozen protocol with development/held-out seeds and thresholds; owner gameplay comparison; acceptance report |

## 2. Gates

- **G0 (design):** owner answers DD-M006-01…06; spec reviewed; JEV advisory recorded (non-binding).
- **G1 (contract):** T01 merge of version constants and role helper only; no behaviour change yet.
- **G2 (policy):** T02+T03 unit evidence green; reducer and accounting invariants unchanged.
- **G3 (integration):** T04 fixtures pinned; v1–v6 fixtures untouched; v6 reader rejects v7 and the
  v7 reader rejects v6 with `unsupportedSimulationVersion`.
- **G4 (evidence):** T05 metrics reproducible; T06 pre-registered cohort run once; owner review.
- **G5 (acceptance):** owner decision. No acceptance before G5.

## 3. Version and fixture impact

- New v7 canonical fixture(s) with explicit home/away lineups and rotation plans (M005 transport).
- Historical v1–v6 fixtures preserved; no rebaseline; historical tests keep their own versions.
- No change to M001 league generation, snapshot schema or PRNG vectors.

## 4. JEV advisory (non-binding)

A focused JEV judgment on 2026-11-07 preferred the piecewise ability slope (0.71) over a role gate
(0.16) or a multiplicative factor (0.13), with confidence 0.56, and returned 0.62 on the
"per-branch draw order is enough without v6/v7 draw-count equality" claim. Both are advisory only:
the low confidence on the evidence contract is recorded as a risk, not as approval.

## 5. Rollback

Until G3 the change is a pure policy/weight refactor; reverting the T01–T03 commits restores v6
behaviour with no fixture migration. After G3, v6 fixtures remain untouched, so rollback is a
version reversal plus test selection, not a data migration.
