# Tasks 006 — Role-Aware Shot Selection v1 (DRAFT, rev 3)

> **Status: DRAFT — NOT AUTHORIZED.** No task may start without a separate owner authorization.
> Sequencing: T01–T03 add dormant, unit-tested policy code; T04 activates it and bumps versions
> atomically.

## T01 — Dormant role helper (no behaviour change)

- [ ] Add a pure helper ranking the five players on court by
  `creation = 3·ballHandling + passing + basketballIQ` (tie-break canonical court-slot order) and
  returning an immutable primary/secondary/neutral assignment.
- [ ] Do **not** change `selectAction`, `_selectShot`, `shotUsageWeights` or `_shotZoneWeightsForSlot`.
- [ ] Do **not** bump any version constant in this task.
- [ ] Tests: ranking determinism and tie-break; position-free behaviour on the audit lineups;
  substitution recomputation; assignment never influences turnover/foul actor draws (separate draw
  path untouched); dormancy test proving production weights equal the v6 reference vectors.
- [ ] Document the classification-versus-ballhandler distinction where the helper is introduced.

## T02 — Dormant usage policy (no behaviour change)

- [ ] Add a pure function `roleAdjustedUsage(rawWeights, roleRanking)` applying 1.35 / 1.15 / 1.00
  before normalisation; no call site changes yet.
- [ ] Tests: multiplier application, floor preservation, normalisation sum, shuffled roster
  equality, raw ordering preserved before normalisation; dormancy test asserting `selectAction`
  still consumes the v6 weight vector.

## T03 — Dormant zone policy (no behaviour change)

- [ ] Add a pure function `threePointWeight(shooter, slotIndex, phase)` implementing the 70/30
  piecewise ability curve; production zone function unchanged.
- [ ] Unit vectors reproducing the normalized audit exactly: weak PG 39.3%, weak SG 40.1%,
  non-shooting C 12.3%, high-three C 38.5%, high-three F 40.3%, median 45.2%.
- [ ] Tests: no new draws; inside/midrange formulas untouched; dormancy test asserting production
  zone weights equal the v6 reference vectors.

## T04 — Activation, atomic version bump, fixtures and migration

- [ ] Switch the three production call sites to the new functions in one commit.
- [ ] Bump `gameSimulationVersion` to 7 and `gameFingerprintVersion` to 5 in the same commit; rules
  3, schema 3, duration 2 and PRNG unchanged.
- [ ] Pin the new v7 fixture(s) with seed, lineups, plans, digest and event count.
- [ ] Apply the historical-test migration in `verification-plan.md` §2: no v1–v6 fixture file
  changes; historical v6 generation verified once at `68018db` in a detached worktree and recorded.
- [ ] Tests: v7 repeat-run identity, VM/Chrome parity, v5/v6 → `unsupportedSimulationVersion`
  rejection, v7 mutation matrix, no-plan determinism, explicit v6→v7 intentional-difference record.
- [ ] Remove the dormancy guards, because production now intentionally uses the new functions.

## T05 — Instrumentation and metrics

- [ ] Optional debug shot-decision observer (non-persistent; DD-M006-05).
- [ ] Ledger-derived metrics with the verification-plan denominators: FGA/36 (240 s minimum),
  weak-shooter pooled 3PA share, stretch-big pooled 3PA share, shot-time primary/secondary role
  share, team 3PA distribution, guardrails.
- [ ] Controlled archetype fixtures: construct synthetic rosters with fixed attributes so a genuine
  stretch-five exists; never modify M001 generation.
- [ ] Metrics classify each shot using the ranking of the five on court at that moment, replayed
  from substitution events.

## T06 — Pilot, frozen protocol, held-out evaluation and owner review

- [ ] Stage A development pilot on development seeds only: estimate per-game variance, pooled
  metrics, eligibility counts and sample size. Never inspect held-out seeds.
- [ ] Stage B freeze the confirmatory protocol: metrics, denominators, eligibility, margins, sample
  size, bootstrap unit, multiplicity, failure conditions. Owner approves before any held-out run.
- [ ] Stage C run the held-out evaluation once on the frozen protocol.
- [ ] Owner box-score review (weak shooter, primary creator, stretch-big) stated as directional.
- [ ] Acceptance report; no acceptance claim before the owner decision.

## Evidence and stop rules

- Any production behaviour change before T04, any version bump before T04, any draw-order change,
  new random draw or schema change stops the task.
- Failure to reproduce the controlled normalized table, or stretch-big collapse, returns to design.
- No held-out seed may be inspected before Stage B freeze.
- If pilot eligibility is insufficient, do not run confirmatory statistics; report and require an
  owner decision or constructed-league evidence.
