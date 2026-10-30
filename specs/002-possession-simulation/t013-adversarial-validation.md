# T013 — Adversarial and property-based simulation validation

Status: **IMPLEMENTED — T013 only.** T014–T019 remain unauthorized.
Baseline: `d1759a09bfa7cdb5630d5aff59bb2867bdd99c16` (`develop/m002`, T012).
Scope: correctness and robustness evidence only. No simulator, reducer,
probability, rules, schema or canonical-behaviour change was made.

## 1. Corpus and results

Deterministic corpus: every seed from **1 to 200** inclusive, M001 league seed
20261028, first two generated teams, default lineups, `GameRules.standard`,
genuine probability-driven simulation.

| Metric | Result |
|---|---|
| Seeds attempted | 200 |
| Successful complete games | 200 |
| Expected typed failures | 0 |
| Unexpected failures | 0 |
| Overtime games | 3 |
| Event count range | 734–900 (average 806.7) |
| Audits per game | lifecycle (`auditGame`), accounting, causality |

Corpus event mix over 200 games:

```
GameStarted 200, PeriodStarted 803, GameEnded 200, PeriodEnded 803,
PossessionStarted 41153, PossessionEnded 41153,
FieldGoalAttempt 33074, Rebound 18818, Turnover 9983,
PersonalFoul 8706, FreeThrowAttempt 6388, DeadBallMiss 63
turnover reasons: steal 2424, nonSteal 2623, offensiveFoul 2077, shotClock 2859
```

Observed per-game averages: 49.915 turnovers, 14.295 shot-clock violations,
43.53 fouls, 31.94 free throws. These reproduce the previously documented
calibration findings; they are **not** T013 correctness failures and not
realism evidence.

## 2. Audits applied to every successful game

Lifecycle (reused T011 audit): single `GameStarted`/`GameEnded`, contiguous
sequence numbers, period attribution, opening-team alternation, no nested
possession, no possession open at period or game end, non-increasing clock,
legal shot-clock range, overtime only after a tie, final score non-tied,
reducer acceptance, box-score equality with the ledger.

Accounting (T013): every published equation per player and team
(`FGM = 2PM + 3PM`, `FGA = 2PA + 3PA`, `PTS = 2·2PM + 3·3PM + FTM`,
`REB = OREB + DREB`, range bounds, player sums = team totals, team totals = period
totals, bench players uncredited, no negative values).

Causality (T013): every live miss resolves exactly once via rebound or
`DeadBallMiss`; offensive rebounds keep the shooting team and reset to the
offensive-rebound value; defensive rebounds reset to the configured shot clock;
every credited steal matches exactly one steal turnover; every block is a missed
FGA by the opponent; assists are different active teammates; shot-clock turnovers
go to the lineup point guard; offensive-foul turnovers follow the same-timestamp
offensive foul at the same timestamp; free-throw groups are contiguous.

## 3. Determinism

- 20 identical simulations of the pinned seed-42 input are byte-identical and
  hash to the T012 golden digest `f8cfc12e…`.
- Pinned seeds 1, 42, 99, 20261029 reproduce their published digests.
- 25 distinct just-generated seeds produce 25 distinct ledgers.
- T012 golden fixture unchanged; no expected value was regenerated.

## 4. Rules matrix

Nine legal configurations × seeds 1–3 (27 runs): 22 completed games, 5 typed
`overtimeLimitExceeded` failures, 0 unexpected failures. Every configuration/seed
outcome is pinned in the test, not merely accepted by code class:

| Configuration | Seed 1 | Seed 2 | Seed 3 |
|---|---|---|---|
| one-second clocks | `overtimeLimitExceeded` | ok | ok |
| two-second clocks | `overtimeLimitExceeded` | `overtimeLimitExceeded` | `overtimeLimitExceeded` |
| five-second periods | ok | ok | ok |
| short-shot-clock floor | ok | ok | ok |
| aggressive bonus | ok | ok | ok |
| custom A1 durations | ok | ok (2 OT) | ok |
| one-second phase brackets | ok | ok | ok |
| zero overtimes | ok | ok | `overtimeLimitExceeded` |
| ten-overtime cap | ok | ok | ok (1 OT) |

The four sub-three-second failures are legitimate: one-second period granularity
keeps the game tied through the two permitted overtimes, and the simulator
refuses to fabricate a winner. The fifth is the tied regulation game under
`maxOvertimes: 0`. Each failure is checked against its configured limit
(`maxOvertimes <= 2`) and produces no partial `GameResult`.
`eventLimitExceeded` and `zeroTimeEventLimitExceeded` did not occur in any legal
configuration; those paths are exercised only by the intentional small-cap
configurations below.

| Configuration | Result |
|---|---|
| one-second periods/OT/shot clock/resets | completes |
| two-second clocks | completes |
| five-second periods, two-second shot clock | completes |
| 24-second periods, 5-second shot clock, 3/2 resets | completes |
| 60-second periods, bonus at 1 foul | completes |
| custom A1 weights `[2500,2500,5000]`, brackets `[2,3],[4,6],[7,10]` | completes |
| one-second phase brackets `[1,1],[1,2],[1,3]` | completes |
| `maxOvertimes: 0` | typed `overtimeLimitExceeded` on ties |
| `maxOvertimes: 10` | completes |

Intentional bound configurations fail with typed errors and no partial result:
`maxEvents: 200` → `eventLimitExceeded`, `maxZeroTimeEvents: 1` →
`zeroTimeEventLimitExceeded`.

Invalid configurations are rejected at input validation with `invalidRules`
(period 0, shot clock 25, 11 overtimes, bonus threshold 0, weights not summing
to 10000, zero-length bracket) and `unsupportedRulesVersion` (rules version 2).

A1 type-draw boundaries were added: draws 0 and 1499 → transition, 1500 and
4499 → early offense, 4500 and 9999 → half court, each checked through a real
seed whose first draw equals the boundary, with the planned duration inside the
approved bracket.

## 5. Event-ledger mutation matrix

Valid scripted ledgers were copied to JSON, one defect applied, decoded and
replayed. Every mutation is rejected with the expected typed code.

| Defect | Code |
|---|---|
| duplicate sequence | `invalidEventSequence` |
| skipped sequence | `invalidEventSequence` |
| out-of-order events | `invalidEventSequence` |
| event before `GameStarted` | `eventBeforeGameStarted` |
| second `GameStarted` | `duplicateGameStarted` |
| period end with open possession | `periodEndInvalid` |
| increasing game clock | `gameClockIncreased` |
| shot clock above configured maximum | `invalidShotClock` |
| rebound resolved at a different clock | `deadBallClockAdvanced` |
| field goal by the defense | `wrongTeam` |
| live action without an open possession | `noOpenPossession` |
| duplicated free-throw index | `freeThrowSequenceInvalid` |
| free throw by the defending team | `freeThrowSequenceInvalid` |
| orphan free throw without an award | `freeThrowSequenceInvalid` |
| non-bonus foul awarding free throws | `freeThrowsInvalid` |
| second rebound of one miss | `reboundDuplicate` |
| rebound of an unknown miss | `reboundInvalid` |
| offensive-team defensive rebound | `reboundWrongTeam` |
| rebound after a made shot | `reboundInvalid` |
| rebound after a zero-clock dead ball | `reboundDuplicate` |
| non-steal turnover carrying a stealer | `turnoverInvalid` |
| steal without a stealer | `stealInvalid` |
| turnover charged to the defense | `wrongTeam` |
| offensive-foul turnover without a foul | `turnoverInvalid` |

Additional corruption covered in the game test file: unsupported simulation
version, unsupported event schema version, malformed fingerprint, non-list
event container and unknown event type are rejected while decoding.

## 6. Execution bounds

- Default OD-14 caps are pinned: 50,000 events, 64 zero-time events, 10 overtimes.
- The reducer independently rejects a ledger longer than `rules.maxEvents`
  (reducer-layer fixture).
- Simulator and reducer agree that a configured event cap is inclusive: exactly
  `maxEvents` succeeds, one fewer fails with `eventLimitExceeded`.
- The literal 50,001st event and 65th same-timestamp event are **not** produced
  by a fabricated 50k-event game. The guard reads `input.rules`, so exact/over
  behaviour proven at configured caps in `t011_game_reliability_test.dart`
  exercises the same code path; this is stated as a residual gap rather than claimed as coverage.

## 7. Seed policy

- Seed 0 → normalized `0x9E3779B9`, away starts, game simulates.
- Even seeds start home; odd seeds start away.
- Negative raw seed `-1` and wide raw seed `0x1FFFFFFFF` normalize to
  `0xFFFFFFFF`, start away, simulate correctly, and produce distinct
  fingerprints from each other.
- `s` and `s + 2^32` share normalized seed, event stream and score, and differ
  in input fingerprint only.

No 32-bit raw-seed restriction was introduced. `GameValidationCode.invalidSeed`
is declared but never emitted; no seed is rejected by the documented API, and
T013 asserts the actual contract instead of inventing a rejection rule.

## 8. Acceptance-matrix coverage

See `t013-coverage-matrix.md`. Summary: AC01–AC07, AC11 and AC13 are covered by
existing tests and/or T013; AC04b and AC11b are strengthened here; **AC08 is
PARTIALLY_COVERED** — configured-limit and reducer protections are proven, but
the literal 50,001st-event and 65th-unchanged-timestamp subcases are recorded as
`GAP_FOUND`; the AC03 opening-possession draw-count subcase is not directly
tested (no public draw counter); AC09 (T014), AC10 (T015) and AC12 (T016) are
deferred, and AC01–AC13 final closure plus owner sign-off remain T017–T019.

## 9. VM and Chrome

| Suite | VM | Chrome |
|---|---|---|
| Full `dart test` | 298 passed | 297 passed (VM-only `domain_isolation_test.dart` excluded) |
| T013 files only | 42 passed | 42 passed |

Both runtimes execute the same 200-game corpus and mutation matrix; no
platform-specific difference was observed. Flutter gates: `flutter analyze`
clean, `flutter test` 8 passed.

## 10. Defects found

No production defect was found. No failing-before/passing-after repair applies.

Test-authoring corrections made during T013 (not product defects): wrong event
indices in three mutations, an illegal zero-clock script (new possession must
start at the configured shot clock), and an expectation that a rebound mismatch
reports `reboundWrongTeam` before `playerNotActive` — the reducer checks team
membership first, which is correct.

## 11. Untested or inconclusive

- Literal 50,001-event and 65-zero-time-event boundaries (see §6).
- Direct PRNG draw-count assertion for the opening possession (no public
  counter; attested design and byte-identical repeats only).
- Declared-but-unused codes `wrongOffenseTeam` and `gameAlreadyStarted`.
- Native Android runtime behaviour (T016/T017) and any performance claim.
- Bench players are uncredited by accounting; no minutes exist, so rotation
  behaviour is out of scope.

## 12. Deferred responsibilities

T014 paired-seed skill sensitivity; T015 ≥1,000-game calibration and human
review; T016 runtime/memory acceptance; T017 full release audit; T018 acceptance
report; T019 human sign-off. T013 makes no realism, calibration or performance
claim.

## 13. Commands and results

```
dart format --output=none --set-exit-if-changed lib test → 53 files, 0 changed
dart analyze                                             → No issues found
dart test                                                → 298 passed
dart test -p chrome test/simulation test/deterministic_random_test.dart \
    test/generator_test.dart test/validation_test.dart   → 297 passed
flutter analyze                                          → No issues found
flutter test                                             → 8 passed
```

New files:

- `packages/simulation_core/test/simulation/t013_adversarial_game_test.dart` (18 tests)
- `packages/simulation_core/test/simulation/t013_ledger_mutation_test.dart` (24 tests)
- `packages/simulation_core/test/simulation/t013_support.dart` (audit helpers)
- `specs/002-possession-simulation/t013-adversarial-validation.md`
- `specs/002-possession-simulation/t013-coverage-matrix.md`

Modified: `specs/002-possession-simulation/tasks.md`.

## 14. Known risks

- The 200-game corpus is correctness evidence, not calibration; the simulation
  still produces ~50 turnovers and ~14 shot-clock violations per game.
- Corpus seeds are a fixed sample; other seeds may reach untested rule
  interactions, though the reducer validates every generated ledger.
- Chrome coverage is dart2js, not native Android.
- The mutation matrix uses small scripted ledgers; coverage of rare generated
  combinations relies on the 200-game reducer acceptance, not on exhaustive
  mutation of every event type.
