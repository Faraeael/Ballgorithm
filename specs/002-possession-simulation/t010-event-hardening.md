# T010 — Event and boundary hardening

Status: **IMPLEMENTED — T010 only.** T011–T019 remain unauthorized.
Base: `bf294ff` (`feat/m002-phase2b-game-orchestrator`).
Branch: `feat/m002-phase2c-event-hardening`.

This note covers the foul, free-throw, rebound, buzzer and dead-ball audit on
top of the T009 orchestrator. Event schema stays at version 2; no probability
coefficient, A1 bracket or version constant changed.

## Scope completed

- Audited every shooting-foul, and-one, non-shooting-foul, offensive-foul,
  free-throw, rebound and buzzer path from probability intent through the
  reducer and `EventAccounting`.
- Added 40 focused legal/illegal fixtures in
  `test/simulation/t010_event_hardening_test.dart`.
- Fixed two reducer-validation gaps: duplicate miss resolution typed error and
  linked zero-time transitions that could drift clocks (see below).
- Audited 320 generated games under varied valid rule configurations plus the
  required standard seeds; no simulator legality defect was found.
- Documented expiry-substitution policy and the remaining event-contract
  limitations.

## Contract ordering (unchanged)

- Missed shooting foul: `PersonalFoul(shooting,2|3)` with **no** `FieldGoalAttempt`,
  then free throws, then rebound/dead-ball resolution.
- Made and-one: `FieldGoalAttempt(made, andOne)` → `PersonalFoul(shooting,1)`
  → one free throw → rebound/dead-ball or `madeFinalFreeThrow`.
- Non-shooting foul: below bonus, possession retained with
  `max(remaining,14)` capped at 24; at the threshold (5 regulation / 4 overtime),
  two free throws. Team fouls reset each period; shooting and and-one fouls
  count, offensive fouls do not.
- Offensive foul: `PersonalFoul(offensive)` → `Turnover(offensiveFoul)` →
  possession end; no FGA, points, steal or defensive bonus increment.
- Free-throw groups: canonical active shooter, one group ID, indices `1..n`,
  `attemptsInGroup` fixed, zero game-clock advance, only the final miss is
  reboundable; a second group has a distinct ID.
- Rebound: one resolution per live miss. OREB resets to the configured
  offensive-rebound value (14 in standard rules), keeps the same possession and
  starts a new A1 phase. DREB ends the possession and transfers control.
- At `gameClock == 0`: no rebound; a missed attempt becomes `DeadBallMiss`,
  then possession end and period end. Awarded free throws at zero complete
  before `PeriodEnded`.

## Boundary matrix exercised

| Case | Result |
|---|---|
| `D == Rg` made shot | Resolves at 0, then `PeriodEnded` |
| `D == Rg == Rs` made shot | Resolves at 0/0, then `PeriodEnded` |
| `D == Rs < Rg` shot | Release at shot-clock 0 accepted |
| `D > Rs`, Rs < Rg | Shot-clock violation; planned action abandoned |
| `D > Rg`, Rg <= Rs | Period ends without terminal action |
| `Rg == 1` | Deliberate final-tick attempt at 0 in generated games |
| Shooting foul at 0 | Free throws complete before `PeriodEnded` |
| Bonus non-shooting foul at 0 | Free throws complete before `PeriodEnded` |
| Non-bonus non-shooting foul at horn | Foul recorded, possession ends `periodEnd` |
| Missed final FT at 0 | `DeadBallMiss`, no rebound, no next possession |
| No event after `GameEnded` | Enforced by reducer |

## Confirmed defects and fixes

### 1. Duplicate miss resolution reported the wrong typed code

The reducer checked
`_pendingMiss` before `_resolvedMisses`, so a second rebound or dead-ball for the
same miss, or a dead-ball after a rebound, failed as `reboundInvalid` (or
`deadBallInvalid`). `GameValidationCode.reboundDuplicate` existed but was
unreachable. Fixed by checking `_resolvedMisses` first in `_rebound` and
`_deadBall`.

- Reproduction: miss, resolve once, then reference the same
  `missedEventSequence` again.
- Failing-before: new tests `rejects a second resolution of the same miss` and
  the duplicate case in `rejects illegal rebounds` failed with
  `reboundInvalid` instead of `reboundDuplicate`.
- Passing-after: both pass.
- Impact: error-code specificity only; legal ledgers, ordering and accounting
  are unchanged.

### 2. Linked zero-time transitions allowed clock drift

A made and-one's linked `PersonalFoul` and an offensive foul's linked
`Turnover(offensiveFoul)` are zero-time resolutions of the same play. The
reducer only ran `_checkLiveAction`, so a foul at `680/4` could follow a shot at
`690/14` with consistent clock arithmetic. Fixed by requiring the same game
clock and shot clock for both linked transitions (`_requireSameTimestamp` and
`_requireSameShotClock`).

- Reproduction: made-and-one `FieldGoalAttempt` at 690/14 with
  `PersonalFoul(shooting)` at 680/4; offensive `PersonalFoul` at 690/14 with
  `Turnover(offensiveFoul)` at 680/4.
- Failing-before: new tests `and-one foul must share the shot timestamp` and
  `offensive-foul turnover must share the foul timestamp` accepted the drifted
  ledgers.
- Passing-after: both reject with `andOneInvalid` / `turnoverInvalid`.
- Impact: validation only; the simulator already emitted same-timestamp linked
  events, so canonical ledgers, ordering and accounting are unchanged.

No simulator gameplay defect was found in the audited foul, free-throw,
rebound or buzzer flows. Standard-rules canonical ledgers for seeds 1, 42, 99
and 20261029 remain byte-identical (the T009 digest test still passes).

## Expiry substitutions — approved policy

Across 200 standard games (published T009 diagnostics, re-confirmed):

| Case | Count | Classification |
|---|---|---|
| Live turnover/offensive foul at exact horn | 8 | A — horn precedence; no legal event |
| Non-bonus non-shooting foul at exact shot-clock zero | 21 | A/C — cannot coexist with the violation |
| Steal/non-steal turnover at exact shot-clock zero | 44 | A — expired possession |
| Offensive foul at exact shot-clock zero | 14 | A — expired possession |
| Preserved horn non-shooting fouls | 7 | A — A1 qualifying foul |
| Preserved shot-clock-zero bonus fouls | 11 | A — A1 qualifying award |

Policy: when the shot clock expires with no released attempt and no
qualifying shooting/bonus award, the frozen reducer cannot represent both the
selected action and the violation (the foul resets the shot clock; a live
turnover at zero is rejected). The violation/period end is emitted and the
selected action is dropped deterministically; no action is fabricated. At the
horn, a non-bonus non-shooting foul is representable and is recorded before the
possession ends. No event-schema change is required or proposed.

## Compatibility impact

- `gameSimulationVersion = 1`, `gameRulesVersion = 1`,
  `gameEventSchemaVersion = 2`, `gameFingerprintVersion = 1`,
  `gameActionDurationModelVersion = 1`, M001 versions unchanged.
- PRNG draw order unchanged; no coefficient or A1 change.
- Custom-A1 configuration repair preserved.
- Amendment 001 `nonSteal` semantics preserved.
- Standard ledger digests unchanged.

## Remaining ambiguities / deferred

- `OffensiveFoulAction.victimId` still has no serialized field.
- Expiry-dropped selections remain unrecorded by design (above).
- Shot-clock violation frequency, turnover rate, offensive-foul rate and FT
  percentage remain calibration findings for T014/T015; not tuned here.
- T011–T019 remain unauthorized.

## Verification

```
dart format --output=none --set-exit-if-changed lib test   → 0 changed
dart analyze                                               → No issues found
dart test                                                  → 230 passed
dart test -p chrome …                                      → 229 passed
flutter analyze / flutter test                             → clean / 8 passed
```

Generated evidence: 200 standard seeded games and 300 one-second-rule stress
games complete with zero reducer/bound failures; 320 additional varied
configuration games audited with zero failures. Seeds 1, 42, 99 and 20261029
replay and reconcile; one-second games exercise overtime, zero-clock free
throws and dead-ball misses.
