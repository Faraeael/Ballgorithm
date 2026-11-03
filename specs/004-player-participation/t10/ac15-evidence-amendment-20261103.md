# AC-M004-15 Evidence Amendment — 2026-11-03

## 1. Amendment identity

- Milestone: M004 Foundational Player Participation
- Criterion: AC-M004-15 (minutes conservation)
- Owner authorization date: 2026-11-03
- Amendment type: evidence requirement only
- Original frozen document: `specs/004-player-participation/acceptance-matrix.md` (frozen 2026-11-02, retained unchanged)
- Original evidence requirement: "Accounting tests; typed failure on mutated totals."
- Approved replacement evidence requirement: see §3.

The frozen matrix is **not** edited. This addendum records a dated, traceable owner-authorized
change to the evidence requirement only.

## 2. Preserved functional requirement

Exact minutes conservation remains mandatory across:

- regulation;
- overtime;
- W1 interval splits;
- substitution boundaries;
- depleted-roster continuation;
- five-player rosters.

No simulation behavior, coefficient, clock, event ordering, version or fixture changes.

## 3. Replacement evidence requirement (approved wording)

> Accounting tests demonstrate exact minutes conservation across regulation, overtime, W1
> splits, continuation and five-player rosters. Negative reducer tests demonstrate typed
> rejection of event mutations that violate the validated clock, period and active-lineup
> invariants. A source-backed invariant proof establishes that inconsistent completed-game
> minute totals are unreachable through the public ValidatedGameLedger pathway; the
> downstream accounting reconciliation guard is retained as defence-in-depth.

## 4. Formal invariant proof

`GameEventReducer.validate` is the only producer of `ValidatedGameLedger`; its constructor is
private. For a validated completed game:

1. `GameStarted` must open period 1 at `rules.periodSeconds` (`game_reducer.dart`, `_gameStarted`, `invalidGameClock`).
2. `PeriodStarted` must use the full `rules.periodLength(period)`, with no open possession or free throws (`_periodStarted`, `invalidGameClock` / `periodAlreadyStarted`).
3. Clocks are bounded by the period length and nonincreasing within a period (`_apply`, `invalidGameClock` / `gameClockIncreased`).
4. `PeriodEnded` requires game clock 0 and no open possession (`_periodEndedEvent`, `periodEndInvalid`).
5. The active five is validated as five roster players; every `Substitution` swaps exactly one active player and must not change the game clock (`_substitution`, `deadBallClockAdvanced` / `invalidShotClock` / `periodNotStarted`).
6. `GameEnded` requires a closed final period at or after the regulation period count (`_gameEnded`, `gameEndInvalid`).
7. `EventAccounting.aggregate` accrues each interval delta from the last clock to the current clock to all five active players; substitutions also accrue the (zero) substitution interval. For each period, the deltas from the full period length down to zero telescope to exactly `periodLength(period)`.
8. Therefore:

   `sum(playerSeconds for one team) = 5 × Σ(completedPeriodLengths)`

   for every validated completed game. A mismatch is unreachable through the public API.
9. The `secondsPlayed` reconciliation guard in `event_accounting.dart` (`periodEndInvalid`) runs only when `ledger.state.ended`; it is retained as defence-in-depth, not as reachable acceptance evidence.

Positive conservation evidence: `t06_minutes_test.dart` (regulation, W1 split, same-clock, overtime, horn boundary, depleted five-player roster), `t07_canonical_participation_test.dart` (replay seconds and team totals).

## 5. Negative evidence (typed reducer rejections)

Existing tests and expected `GameValidationCode` values:

| Test | Code |
|---|---|
| `t013_ledger_mutation_test.dart` "an increasing game clock is rejected" | `gameClockIncreased` |
| `t013_ledger_mutation_test.dart` "a shot clock above the configured maximum is rejected" | `invalidShotClock` |
| `t013_ledger_mutation_test.dart` "a rebound resolved at a different clock is rejected" | `deadBallClockAdvanced` |
| `t013_ledger_mutation_test.dart` "a period end with an open possession is rejected" | `periodEndInvalid` |
| `t013_ledger_mutation_test.dart` "a second GameStarted is rejected" | `duplicateGameStarted` |
| `game_reducer_test.dart` clock/period bounds | `invalidGameClock`, `gameClockIncreased`, `periodNotStarted` |
| `t04_participation_test.dart` "rejects a substitution that moves the clock" | `deadBallClockAdvanced` |
| `t04_participation_test.dart` "rejects a substitution that changes the shot clock" | `invalidShotClock` |
| `t04_participation_test.dart` "rejects a substitution whose period does not match" | `periodNotStarted` |

No mutated-totals accounting failure is fabricated, no `ValidatedGameLedger` is forged, and
`EventAccounting` is unchanged.

## 6. Scope and effect

- Conservation behavior unchanged.
- Evidence requirement amended by explicit owner authorization dated 2026-11-03.
- Original frozen wording retained for historical traceability; the matrix is not edited.
- No gameplay contract, version, fixture or acceptance-threshold change.
- No NBA-realism or performance certification.
- No release authorization.
- AC-M004-15 may be marked PASS only under this amendment, not under the superseded
  negative-test wording.
