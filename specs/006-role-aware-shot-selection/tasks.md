# Tasks 006 — Role-Aware Shot Selection v1 (DRAFT)

> **Status: DRAFT — NOT AUTHORIZED.** Every item is planning text. No task may start without a
> separate owner authorization naming its files, tests and gates.

## T01 — Contract, role derivation and version boundary

- [ ] Add a pure helper that ranks an active five by creation score
  (`slotBase + 3·ballHandling + passing + basketballIQ`, tie-break canonical slot order) and returns
  an immutable role ranking; no `Player` field, no snapshot change.
- [ ] Bump `gameSimulationVersion` to 7 and `gameFingerprintVersion` to 5 in one commit; no other
  constant changes.
- [ ] Tests: ranking determinism, tie-break, immutability, no M001 snapshot/schema change,
  fingerprint payload version, typed `unsupportedSimulationVersion` rejection of a v6 ledger.

## T02 — Usage policy

- [ ] Apply role multipliers to raw usage weights before normalisation; keep the single actor draw.
- [ ] Tests: multiplier application, floor preservation, normalisation sum, ordering stability,
  identical results for identical attributes regardless of insertion order.
- [ ] Record the exact draw order unchanged.

## T03 — Zone-willingness policy

- [ ] Replace the linear three-point term with the approved piecewise ability curve; keep position
  and phase bonuses and the 200 floor.
- [ ] Unit vectors: weak guard, weak centre, stretch centre, strong guard, median forward; assert
  directional three shares against v6 values computed in-test from the same attributes.
- [ ] Tests: no new draws; zone weights bounded; inside/midrange formulae unchanged; make/hazard
  coefficients untouched.

## T04 — Simulator integration and fixtures

- [ ] Wire the policy through `BasketballProbabilityModel` only; the simulator keeps its existing
  draw sequence and event translation.
- [ ] Pin new v7 canonical fixture(s) with fixed lineups and plans; record the seed, digest and
  event count.
- [ ] Prove repeat-run identity, VM/Chrome parity, and document intentional v6 differences.
- [ ] Preserve every v1–v6 fixture byte-for-byte; add a rejection test for cross-version ledgers.

## T05 — Instrumentation and metrics

- [ ] Optional debug shot-decision observer (non-persistent; not in the ledger or fingerprint), if
  DD-M006-05 is approved.
- [ ] Ledger-derived metrics: FGA per player, attempts per 36 minutes of actual play, 3PA share by
  `threePoint` bucket, low-ability perimeter volume, high-ability bigs' perimeter volume, primary
  versus secondary role shot share, team 2PA/3PA distribution.
- [ ] Controlled archetype fixtures: construct synthetic teams with fixed attributes so a genuine
  stretch-five exists even if the generated league lacks one; document construction and validation.

## T06 — Pre-registered evaluation and owner review

- [ ] Freeze the protocol: development seeds, held-out seeds, metrics, thresholds and failure
  conditions before running any cohort.
- [ ] Run the cohort once; report effect sizes, uncertainty and the pre-registered decisions.
- [ ] Owner gameplay review comparing weak shooter, primary creator and stretch-big box scores.
- [ ] Acceptance report; no acceptance claim before the owner decision.

## Evidence and stop rules

- Any draw-order change, new random draw, schema change or coefficient change outside the approved
  policy stops the task.
- If a directional threshold cannot be met without erasing stretch-bigs, stop and return to design.
- No cohort runs before the protocol is frozen.
