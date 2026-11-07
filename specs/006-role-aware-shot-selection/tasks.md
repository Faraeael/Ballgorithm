# Tasks 006 — Role-Aware Shot Selection v1 (DRAFT, rev 2)

> **Status: DRAFT — NOT AUTHORIZED.** No task may start without a separate owner authorization.

## T01 — Contract, role ranking and version boundary

- [ ] Add a pure helper ranking the five players on court by
  `creation = 3·ballHandling + passing + basketballIQ` (tie-break canonical court-slot order);
  no `Player` field, no snapshot change.
- [ ] Recompute the ranking from the current `TeamOnCourt` at every shot; document that it is a
  classification, not a ballhandler, and that turnover/foul actors keep their own draw.
- [ ] Bump `gameSimulationVersion` to 7 and `gameFingerprintVersion` to 5 atomically.
- [ ] Tests: ranking determinism and tie-break; position-free behaviour on the audit lineups;
  substitution changes the ranking; v5/v6 ledgers rejected with `unsupportedSimulationVersion`;
  no M001 snapshot change.

## T02 — Usage policy

- [ ] Apply role multipliers after raw usage and before normalisation; single actor draw unchanged.
- [ ] Tests: multipliers, floor, normalisation sum, shuffled roster equality; controlled share table
  (baseline 28.2/22.4; creator-big line 31.9; bench-PG line 28.7) reproduced.

## T03 — Zone-willingness policy

- [ ] Replace the linear three term with `70·(p−50)` below 50 / `30·(p−50)` above 50; keep slot,
  phase and the 200 floor.
- [ ] Unit vectors must reproduce the normalized audit table exactly (weak PG 39.3%, weak SG 40.1%,
  non-shooting C 12.3%, high-three C 38.5%, high-three F 40.3%, median 45.2%).
- [ ] Tests: no new draws; per-branch draw order unchanged; inside/midrange formulae untouched.

## T04 — Simulator integration, v7 fixtures and historical migration

- [ ] Wire the policy through `BasketballProbabilityModel`; no simulator event changes.
- [ ] Pin new v7 canonical fixture(s) with seed, lineups, plans, digest and event count.
- [ ] Do not modify any v1–v6 fixture file; add the v6 fixture to the archive-parse/digest tests.
- [ ] Convert current-suite historical generation assertions per `verification-plan.md` §2; run the
  historical v6 generation once in a detached worktree at `68018db` and record the result.
- [ ] Tests: v7 repeat-run identity, VM/Chrome parity, typed rejection v5/v6 ↔ v7, v7 mutation
  matrix, no-plan determinism, explicit v6→v7 intentional-difference record.

## T05 — Instrumentation and metrics

- [ ] Optional debug shot-decision observer (non-persistent; DD-M006-05).
- [ ] Ledger-derived metrics with the verification-plan denominators: FGA/36, weak-shooter 3PA
  share, stretch-big 3PA share, shot-time primary/secondary role share, team 3PA distribution,
  guardrails.
- [ ] Controlled archetype fixtures: construct synthetic rosters with fixed attributes so a genuine
  stretch-five exists; document construction and validation; never modify M001 generation.

## T06 — Pre-registered evaluation and owner review

- [ ] Freeze protocol: metrics, development seeds 1–200, held-out seeds 10001–10500, thresholds,
  CIs and Holm correction, before any cohort.
- [ ] Establish the v6 baseline and paired-difference variance; finalize the OPEN thresholds from
  development data only.
- [ ] Run held-out once; report effect sizes and CIs against the frozen decisions.
- [ ] Owner box-score review (weak shooter, primary creator, stretch-big) stated as directional.
- [ ] Acceptance report; no acceptance claim before the owner decision.

## Evidence and stop rules

- Any draw-order change, new random draw, schema change or coefficient outside the approved policy
  stops the task.
- Failure to reproduce the controlled normalized table, or stretch-big collapse, returns to design.
- No cohort before the protocol freeze.
