# Acceptance Matrix 005 — Rotations and Playing-Time Management

> **Status:** **FROZEN — OWNER APPROVED 2026-11-06.** All rows are **NOT RUN**; this matrix defines the
> evidence required, not evidence achieved. Implementation is **NOT STARTED**.
> **Baseline:** `develop/m002` at `f53201314e9cfdcc8734eb523e41f313f3c644c2`.
> Task mapping: `T01` contract, `T02` policy, `T03` simulator, `T04` fixtures/parity, `T05` UI
> transport, `T06` walkthrough/acceptance.

| ID | Task | Requirement | Evidence required | Status |
|---|---|---|---|---|
| AC-M005-01 | T01 | `RotationPlan` / `TeamRotationPlan` are exported, immutable and canonically serialized home-then-away; targets emit in canonical roster order, never map insertion order | Contract tests; JSON golden; shuffled-insertion equality | NOT RUN |
| AC-M005-02 | T01 | Plan validation rejects unknown/duplicate/missing player ids, out-of-range targets, wrong totals, zero starter targets, unknown presets and preset/target disagreement with typed codes | Negative contract tests asserting codes and paths, not message wording | NOT RUN |
| AC-M005-03 | T01 | `null` plan means legacy no-rotation; a non-null plan requires both home and away team plans | Constructor and `GameInput.create` tests | NOT RUN |
| AC-M005-04 | T01 | Preset expansion sums exactly to `T` for rosters 5…12 under standard and non-standard `periodSeconds`; `n < 5` is rejected; `n == 5` assigns `C` to all five | Property/table tests; typed rejection | NOT RUN |
| AC-M005-05 | T01 | The standard-rules vectors in `spec.md` §5.5 are asserted exactly, including Balanced vs Starter-heavy distinction and no reserve exceeding any starter target | Table test | NOT RUN |
| AC-M005-06 | T01 | The short-period vectors in `spec.md` §5.6 are asserted exactly | Table test | NOT RUN |
| AC-M005-07 | T01 | Remainder seconds go to starters in canonical court-slot order first, then selected reserves in canonical roster order; the withdrawn "canonical roster-order rounding" phrase is not an operative rule | Unit test on the remainder order; source/doc scan finds no conflicting statement | NOT RUN |
| AC-M005-08 | T01 | The canonical plan is included in the fingerprint when present and absent when `null`; semantically equal plans produce one fingerprint | Fingerprint tests; insertion-order equality | NOT RUN |
| AC-M005-09 | T01 | The selected starting lineup is part of the canonical input and fingerprint; a supplied lineup is the actual on-court five; the opponent uses `defaultFor` unless configured | `GameInput.create` tests; fingerprint payload; simulator first-five assertion | NOT RUN |
| AC-M005-10 | T01 | Versions: simulation 6 and fingerprint 4 land together; rules 3, schema 3, duration 2, PRNG `xorshift32-v1` and M001 identifiers unchanged | Constant assertions; fixture version checks | NOT RUN |
| AC-M005-11 | T01 | Public field, fingerprint payload and both version bumps are one atomic commit; no build exposes the new payload under an old version; no tactical substitution is claimed operational | Commit inspection; build + targeted tests | NOT RUN |
| AC-M005-12 | T02 | Policy is pure and deterministic; rotation consumes zero PRNG draws | Unit tests; draw-count assertion | NOT RUN |
| AC-M005-13 | T02 | Regulation expected/deficit use integer seconds and the regulation horizon; nothing is recomputed after the regulation horn | Unit tests at controlled elapsed values | NOT RUN |
| AC-M005-14 | T02 | Thresholds are `max(1, periodSeconds ~/ 8)` and `max(1, periodSeconds ~/ 6)` in regulation, and use `overtimeSeconds` in overtime, including the floor at 1 | Constant tests at 720, 300 and very short periods | NOT RUN |
| AC-M005-15 | T02 | Outgoing is minimum deficit with roster-index/id tie-breaks; incoming is maximum deficit with same-position, roster-index and id tie-breaks | Unit tests for both chains and ties | NOT RUN |
| AC-M005-16 | T02 | At most one tactical swap per team per window; cooldown and exact-reverse suppression are enforced | Unit tests; repeated-window fixtures | NOT RUN |
| AC-M005-17 | T02 | Eligible bench excludes active, disqualified and zero-target players; disqualified players are never selected | Unit tests | NOT RUN |
| AC-M005-18 | T03 | Tactical hooks fire only at W1/W2/W4/W5, after the full mandatory sequence; W0 and non-window possession ends get no tactical hook; no new windows or timeouts | Simulator integration tests; ledger scan | NOT RUN |
| AC-M005-19 | T03 | A mandatory foul-out replacement always precedes a tactical swap; the team emits no tactical swap in that window | Constructed collision test (foul-out and rotation due at one window) | NOT RUN |
| AC-M005-20 | T03 | Every emitted tactical substitution is reducer-valid at the same game clock and shot clock, changes no possession state, and respects the per-window bound | Reducer acceptance over emitted ledgers; negative fixtures | NOT RUN |
| AC-M005-21 | T03 | Team seconds remain `5 × Σ regulation period lengths`; minutes and participation stay ledger-derived with no simulator minutes scoreboard | Accounting cross-check; conservation tests | NOT RUN |
| AC-M005-22 | T03 | Two different plans produce different per-player minutes on the same input and seed | Paired simulator test | NOT RUN |
| AC-M005-23 | T03 | Overtime allocation: `base = floor(regTarget × L ÷ C)`, cap `L`, active-slots-then-roster round-robin, exact sum `O`, equal-split fallback and no carry-over | Unit tests against `spec.md` §8.4 | NOT RUN |
| AC-M005-24 | T03 | Overtime is deterministic: identical plan and seed reproduce the same allocations, substitutions and ledger; thresholds use overtime length; an overtime foul-out keeps mandatory priority | Repeat runs; OT foul-out fixture | NOT RUN |
| AC-M005-25 | T03 | Depleted continuation still disables tactical swaps and conserves seconds in regulation and overtime | Depletion fixtures | NOT RUN |
| AC-M005-26 | T04 | New v6 canonical fixture(s) are pinned; every v5 fixture is preserved and not rebaselined | Digest and file diff | NOT RUN |
| AC-M005-27 | T04 | No-plan mode reproduces the pinned v5 canonical event array for the same input and seed, header/version excluded | Equality fixture | NOT RUN |
| AC-M005-28 | T04 | Repeat-run identity and worker/caller parity under v6; Chrome-compatible core tests pass with the IO-dependent isolation test excluded and recorded | Repeat runs; parity test; command record | NOT RUN |
| AC-M005-29 | T04 | Rematch preserves the managed lineup, both team plans and the matchup, and advances only the seed along `deriveGameSeed` | Rematch test; seed sequence assertion | NOT RUN |
| AC-M005-30 | T05 | Setup offers managed team, five starter slots, Balanced / Starter-heavy / Custom; invalid plans block confirmation; layout holds at 360 dp with no overflow | Widget tests at 360/393/430 | NOT RUN |
| AC-M005-31 | T05 | Lineup and plan survive setup → `GameRequest` → worker → `GameInput`; absent lineup falls back to `defaultFor` | Transport tests | NOT RUN |
| AC-M005-32 | T05 | Results show actual minutes and statistics for starters and entrants with M004 tagging, disqualification indicators and the disclosure text | Widget tests; disclosure assertions | NOT RUN |
| AC-M005-33 | T06 | A physical-device (or owner-approved substitute) walkthrough shows legal tactical substitutions, bench minutes, deterministic repeat, plan-preserving rematch and a visibly different preset | Recorded walkthrough milestones | NOT RUN |
| AC-M005-34 | T06 | Scope compliance: no fatigue, injuries, coaching AI, manual in-game substitutions, technical fouls, contracts, trades, seasons, persistence, coefficient or probability changes, timeouts or new dead-ball events | File/API diff review | NOT RUN |
| AC-M005-35 | T06 | Acceptance report states PASS / FAIL / NOT RUN / NOT MEASURED with commands, versions, seeds and fixture digests; no claim depends on an unexecuted test | Report review | NOT RUN |

## Explicit non-claims

- No NBA-level realism or calibration claim.
- No claim that rotations normalize foul-out frequency; foul-rate investigation is outside M005.
- No AC09/AC10 re-certification.
- No Android performance, memory, battery or large-text accessibility measurement.
- No production or release authorization.
- Presets are documented heuristics, not validated basketball rotations.

## Historical M004 limitations retained

All M004 non-acceptances and preserved limitations remain in force: technical fouls are not modelled;
a disqualified player may continue when no eligible bench player remains; post-field-goal substitution
windows are excluded; no in-game manual substitution; no fatigue; no coaching AI. M005 does not amend
any M004 acceptance record.
