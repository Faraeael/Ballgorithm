# T011 — Complete-game reliability and termination

Status: **IMPLEMENTED — T011 only.** T012–T019 remain unauthorized.
Base: `7cfef4c` (`feat/m002-phase2c-event-hardening`).
Branch: `feat/m002-t011-game-reliability`.

T011 validates that the existing probability-driven orchestrator finishes legal
games deterministically and terminates pathological or over-limit runs with
typed failures. No simulator, reducer, probability, A1, rules or schema change
was needed.

## Tested lifecycle guarantees

Every successful generated game in the 40-seed standard sample is checked
independently of the simulator's return path:

- one `GameStarted`, one `GameEnded` (last event), four regulation
  `PeriodStarted`/`PeriodEnded` pairs, overtime pairs only where required;
- strictly increasing sequence numbers; every event belongs to the active period;
- period starts at the configured length, ends at game clock 0, opening team
  alternates by OD-01;
- no nested possession, every `PossessionEnded` matches the open
  `possessionId`/offense/period, no possession open at period end or game end;
- no `PossessionStarted` after the final `PeriodEnded`;
- non-increasing game clock per period, non-negative clocks, shot clock within
  `0..24`;
- overtime only after a tied preceding period;
- final score equals the derived box score and period totals, never tied;
- every ledger accepted by `GameEventReducer.validate`;
- `FGM=2PM+3PM`, `FGA=2PA+3PA`, `PTS=2*2PM+3*3PM+FTM`, `REB=OREB+DREB`,
  `FTM<=FTA`, `FGM<=FGA`, team totals equal player sums.

## Loop and termination audit

| Loop | Progress | Zero-time transitions | Bound / failure |
|---|---|---|---|
| `run` period loop | period increments or `GameEnded` | none | `periods + maxOvertimes` → `overtimeLimitExceeded` |
| `_playPeriod` | clock decreases by phase duration or period break | possession closure at 0 | clock reaches 0 |
| `_playPossession` | every applied phase consumes `D >= 1` second (default brackets are 2–14 s; custom rules may allow 1 s); retained possession or OREB repeats with a lower clock | FT groups terminate the possession | clock 0 or possession end |
| Free-throw helper | fixed 1–3 attempts | all attempts at one timestamp | finite loop |
| `_emit` | event appended | — | `maxEvents`, `maxZeroTimeEvents` |
| Shot-clock violation / horn branches | clock moves to violation time or 0 | — | possession/period end |

No unbounded retry exists. A valid sequence at a configured limit is accepted;
the next event or overtime fails with the typed bound. No winner is fabricated
and no partial `GameResult` is returned.

## Determinism and reentrancy

- 5 repeats of seed 7 produce identical ledger JSON, score, period scores and
  winner.
- One default `GameSimulator` reused across seeds 11/12/11 and interleaved
  reproduces each ledger exactly.
- Distinct seeds produce different ledgers.
- League, roster, lineup IDs and rules serialization are unchanged after
  simulation.
- Sequential games with standard, custom-A1 and standard rules stay isolated.
- A matching injected model reproduces the default ledger; a mismatched model is
  rejected with `GameValidationCode.invalidRules` before gameplay.

## Regulation and overtime termination

- Non-tied Q4 ends with `GameEnded`; tied Q4 enters OT; non-tied OT ends the
  game; tied OT continues.
- Tiny-rule seed 26 with `maxOvertimes = 2` plays exactly 2 OT periods and is
  accepted: the limit is inclusive.
- Seed 26 with `maxOvertimes = 1`, seed 1 with `maxOvertimes = 2`, and seed 1
  with `maxOvertimes = 0` (tied regulation) fail with
  `overtimeLimitExceeded`.
- OT periods use the configured length (1 s in the fixture, 300 s standard) and
  alternate the opening team.
- The simulator permits up to `maxOvertimes` (10 by default); a tie at that
  limit fails. The reducer independently enforces the ten-OT cap; the
  configurable-limit path is exercised at 2 because a natural 10-OT game is not
  reliably reachable.

## Execution bounds exercised

| Bound | Fixture | Result |
|---|---|---|
| Event count, exact | seed 42 has 800 events; `maxEvents = 800` | success, identical events |
| Event count, beyond | `maxEvents = 799` | `eventLimitExceeded` |
| Event count, small | `maxEvents = 5` | `eventLimitExceeded` |
| Zero-time run, exact | seed 42 maximum run 7; `maxZeroTimeEvents = 7` | success, identical events |
| Zero-time run, beyond | `maxZeroTimeEvents = 6` | `zeroTimeEventLimitExceeded` |
| Zero-time run, small | `maxZeroTimeEvents = 1` | `zeroTimeEventLimitExceeded` |
| Overtime, exact | seed 26 tiny, `maxOvertimes = 2`, 2 OT | success |
| Overtime, beyond | seeds 26/1, limits 1/2/0 | `overtimeLimitExceeded` |

## Coverage

Required standard seeds 1, 2, 3, 4, 5, 42, 99, 100, 20261029 plus seeds 6–36
(40 standard games total): all replay and reconcile; 1 overtime game; event
counts 768–900, average 814.6.

Configured matrix, seeds 1–3 each (18 games): 14 successes and 4 expected
`overtimeLimitExceeded`, 0 unexpected failures.
Configurations: 1-second periods/shot clock; 2-second; 5-second with 2-second
shot clock; 24-second with 5-second shot clock; 60-second with 24-second shot
clock and bonus threshold 1; 30-second with custom A1 weights
`[2500,2500,5000]` and brackets `[[2,3],[4,6],[7,10]]`.

Additional focused fixtures: two-OT tiny game, overtime-bound failures, exact
event/zero-time limits, small limits, custom-A1 reuse, injected-model mismatch.

## Defects

None found. No code change was required.

## Published canonical compatibility

Seeds 1, 42, 99 and 20261029 retain the published SHA-256 ledger digests:

```
1        610dea0941d463da7960b912ea2004f91562a0567bbecba9e7aabba23c6a1e61
42       f8cfc12e01d8ba187c602021eaaabbac13b8438cf7e34ec5af3ff03b3d97387f
99       b325c79d846d4401443878616682437120ee9db1fc8f59ae995a4f9bb184dc17
20261029 c996cd4a4d0dc03a647bef578ee2cf1cfe9efd4dc84392778f9bfec312b96493
```

M001 vectors, F01/F02, Amendment 001, T008 coefficients/draw order, T009
custom-A1 ownership and T010 validation are unchanged.

## Verification

```
dart format --output=none --set-exit-if-changed lib test  → 0 changed
dart analyze                                              → No issues found
dart test                                                 → 244 passed
dart test -p chrome …                                     → 243 passed
flutter analyze / flutter test                            → clean / 8 passed
```

14 new T011 tests; 40 generated standard games, 18 matrix games, focused
boundary fixtures. All successful ledgers replay; all box scores reconcile.

## Deferred to later tasks

- T012: canonical ledger fixture pinning and VM/Chrome golden comparison.
- T013: exhaustive adversarial/property matrix over ≥100 seeds and all
  acceptance-matrix cases.
- T014–T015: statistical calibration.
- T016: formal runtime and memory acceptance.
- T017–T019: acceptance report, human review and sign-off.
- No AC01–AC13 closure is claimed here.
