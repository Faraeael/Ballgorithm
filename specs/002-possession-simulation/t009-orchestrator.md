# T009 — Game orchestrator implementation note

Status: **IMPLEMENTED — T009 only.** T010–T019 remain unauthorized.
Base: `aed81da` (`feat/m002-nonsteal-turnover-contract`, schema v2).
Branch: `feat/m002-phase2b-game-orchestrator`.

This note records the orchestrator built on top of the T008 probability model.
The frozen specification (`spec.md`, `plan.md`, `design-decisions.md`) and
Amendment 001 are unchanged.

## Public API

```dart
final result = GameSimulator().simulate(input); // GameInput -> GameResult
```

`GameSimulator()`
- pure Dart, no Flutter/IO/network;
- owns one `DeterministicRandom(input.normalizedSeed)`;
- produces a complete ledger, then validates it with `GameEventReducer.validate`
  and derives all statistics with `EventAccounting.aggregate`;
- throws `GameValidationException` on any illegal transition or bound, and never
  returns a partial result.

`GameResult`
- `input` (canonical source reference, not a duplicated league),
- `inputFingerprint`, `ledger`, validated `state`, `boxScore`,
- `homeTeamId`, `awayTeamId`, `winnerTeamId`, `loserTeamId`,
- `homeScore`, `awayScore`, `homePeriodScores`, `awayPeriodScores`,
- `periodsPlayed`, `overtimes`, `possessions`,
- `simulationVersion`, `rulesVersion`, `eventSchemaVersion`,
  `prngImplementationId`.

Scores and period totals are read from the validated box score; the
orchestrator keeps no authoritative scoreboard. A transient points sum over
already-emitted events is used only to decide whether regulation/OT must
continue, and the reducer independently recomputes the tie check.

## Event ordering per possession

1. `PossessionStarted` at the current game clock with the configured shot clock.
2. One or more offensive phases. A phase draws the A1 type and duration, then
   resolves the terminal action at `gameClock - D`, `shotClock - D`.
3. Terminal outcomes:
   - made FG without and-one → `FieldGoalAttempt` → `PossessionEnded(madeFieldGoal)`;
   - made and-one → `FieldGoalAttempt(made, andOne)` → `PersonalFoul(shooting, 1)`
     → `FreeThrowAttempt` → rebound/dead-ball or `PossessionEnded(madeFinalFreeThrow)`;
   - missed FG → `FieldGoalAttempt` → (`Rebound` or `DeadBallMiss` at zero);
   - missed shooting foul → `PersonalFoul(shooting, 2|3)` with **no FGA** → FTs;
   - defensive non-shooting foul → `PersonalFoul(nonShooting)`; bonus awards two
     FTs, otherwise possession is retained and the shot clock resets to
     `max(remaining, 14)` capped at 24;
   - offensive foul → `PersonalFoul(offensive)` → `Turnover(offensiveFoul)`;
   - steal → `Turnover(steal, stolenById)`;
   - non-steal → `Turnover(nonSteal)` with no stealer;
   - shot-clock expiry → `Turnover(shotClock)` at `gameClock - shotClock`,
     charged to the lineup PG.
4. `PossessionEnded` with the matching reason; the next possession starts with
   the opponent unless the period ends.

Period boundaries: `PeriodStarted(periodLength)` / `PeriodEnded(0)`; overtime
alternates the opening team and starts only after a tied period. `GameEnded`
follows a non-tied final period. A tie at the overtime limit raises
`overtimeLimitExceeded`.

## Clock precedence

The A1 plan is never clamped:

| Condition | Behaviour |
|---|---|
| `D <= Rg && D <= Rs` | Phase completes at `Rg-D`; release at zero game or shot clock is legal |
| `D > Rs && Rs < Rg` | Shot-clock violation at `Rg-Rs`; planned action never selected |
| `D > Rg && Rg <= Rs` | Period expires at 0; no terminal action, turnover or rebound |
| `Rg == 1` | Final-tick attempt; no A1 or category draws; consumes 1 s; release at 0 |
| `D == Rg`, shooting or bonus-awarding foul | Foul resolves at 0; free throws complete before `PeriodEnded` |
| `D == Rg`, non-bonus non-shooting foul | Foul recorded at 0; period ends (no retained possession after the horn) |
| `D == Rg`, live turnover or offensive foul | Action discarded; period expires (no legal live turnover at the horn) |
| `D == Rs < Rg`, non-shot action | Shot-clock violation; only a shot or a bonus-awarding foul resolves |

At zero game clock, a made FG ends with `PossessionEnded(madeFieldGoal)`; a miss
is `DeadBallMiss`; awarded FTs complete before `PeriodEnded`; a missed final FT
at zero is `DeadBallMiss`, never a rebound.

## RNG ownership and determinism

Opening possession consumes no draw. Draws are consumed only by the T008
entry points: A1 type/duration, action selection, rebound resolution and
free-throw groups. Expiry before the planned action consumes no outcome draws.
The one documented exception is a phase that reaches the horn exactly
(`D == Rg`) with a non-shot action: the action is selected, then discarded
because the event contract has no legal live turnover at the horn. This branch
is deterministic and rare.

Same canonical input and versions reproduce the exact ledger and result;
verified over 20 repeated runs.

## Versions

`gameSimulationVersion = 1`, `gameRulesVersion = 1`,
`gameEventSchemaVersion = 2`, `gameFingerprintVersion = 1`,
`gameActionDurationModelVersion = 1`; M001 `coreEngineVersion` and
`snapshotSchemaVersion` unchanged. No new dependency.

## Completed T009 scope

- four regulation periods, 720 s; overtime 300 s; configured via `GameRules`;
- 24 s shot clock with OD-12 resets (24 after make/DREB/turnover, 14 after OREB,
  `max(remaining,14)` capped after a non-bonus foul);
- simple bonus (5th regulation / 4th overtime defensive team foul), team fouls
  reset per period, shooting/and-one fouls count, offensive fouls do not;
- free throws consume zero game time, one group ID per award, only the final FT
  is reboundable;
- deterministic possession IDs and alternating opening teams;
- max 10 overtimes, 50,000 events, 64 zero-time events at one timestamp, each a
  typed failure;
- all ledgers replay through `GameEventReducer`; box scores derive only from
  `EventAccounting`.

## Deferred to T010

- exhaustive buzzer/foul/rebound edge-case hardening and adversarial fixtures;
- richer dead-ball sequencing (no timeouts or substitutions exist in M002);
- any tuning of the A1/14-second interaction (see known issue below).

## Known gameplay issues (not tuned)

200 standard games, seeds 1–200, pinned league:

| Metric | Observed | Provisional band |
|---|---|---|
| Combined points/game | 199.7 (team min 63, max 144) | 90–340 combined sanity |
| FGA/game (both teams) | 165.4 | — |
| FG% | 0.459 | 0.36–0.57 |
| 3PA/FGA | 0.419 | 0.20–0.55 |
| FT% | 0.654 | 0.55–0.90 |
| FTA/FGA | 0.193 | 0.10–0.50 |
| OREB share | 0.279 | 0.12–0.40 |
| Turnovers/game | 49.9 | 7–24 per 100 possessions |
| Offensive fouls/game | 10.4 | report only |
| Shot-clock violations/game | 14.295 | report only |
| Assists/FGM | 0.552 | 0.25–0.85 |
| Blocks/game | 4.0 | report only |
| Steals/game | 12.1 | report only |
| Personal fouls/game | 43.5 | report only |
| Overtime rate | 3/200 | report only |

Turnovers sit slightly above the provisional band because the approved A1
half-court bracket (10–22 s) occasionally exceeds the 14 s offensive-rebound
and non-bonus-foul resets. The specification forbids clamping durations, so
this is reported as a calibration finding for T014/T015, not silently tuned.
These are observed development diagnostics, not statistically approved
calibration results.

## Shot-clock violation diagnosis (200 standard games)

| Measure | Value |
|---|---|
| Total violations | 2,859 (14.295/game) |
| After a normal 24 s possession start | 0 |
| After an offensive rebound (14 s) | 1,800 |
| After a retained non-bonus possession | 1,059 |
| Other preceding event type | 0 |
| Clock-arithmetic mismatches | 0 |
| Share of possessions ending in a violation | 6.9% |

A1 explains the frequency. For 5,246 offensive-rebound phases the expected
count is `0.55 × 8/13 = 33.8%` (1,775.6); observed 1,800. For 3,709 retained
possessions the expected count from `P(D > reset)` is 1,053.8; observed 1,059.
No shot-clock violation follows a normal 24-second start, because no A1 bracket
exceeds 22 s. This is valid rule behaviour with an unrealistic frequency, not a
clock or possession defect.

## Boundary diagnostics (200 standard games)

Observed development diagnostics from an instrumented copy that produced
identical ledgers for the reviewed seeds:

| Measure | Count |
|---|---|
| Field-goal releases at game clock 0 | 99 |
| — explicit final-tick (`Rg == 1`) executions | 58 |
| — final-tick executions that emitted an FGA | 56 |
| — zero-clock FGAs from normal phases with `D == gameClock` | 43 |
| Actions discarded at the exact period horn (live turnover/offensive foul) | 8 |
| Aggregate substitutions at exact shot-clock zero | 79 |
| — non-bonus non-shooting fouls | 21 |
| — steal/non-steal turnovers combined | 44 |
| — offensive fouls | 14 |
| Preserved horn non-shooting fouls | 7 |
| Preserved shot-clock-zero bonus fouls | 11 |

The 79 figure is the aggregate of substituted action types, not a count of
discarded non-bonus fouls. All are development diagnostics, not approved
calibration results.

## Limitations

- `OffensiveFoulAction.victimId` has no serialized field; the event payload
  records the offender and foul details only.
- One-second clock granularity; no subsecond events.
- At exact shot-clock zero, 21 non-bonus non-shooting fouls, 44 turnovers and
  14 offensive fouls were replaced by the violation across 200 games; 8 live
  turnovers/offensive fouls were discarded at the exact horn. Each consumes the
  selected action's draws without an event because the frozen contract cannot
  represent them together with expiry precedence. Qualifying shooting and
  bonus-awarding fouls are preserved and resolve (7 horn fouls and 11
  shot-clock-zero bonus fouls observed).
- Positional defender assignment and fixed lineups are inherited from T008.
- Formal calibration and AC09/AC10 remain unauthorized.

## Verification

- Dart VM: 182 tests; Chrome-compatible: 181; Flutter: 8.
- 200/200 standard seeded games and 300/300 one-second-rule stress games
  completed with zero reducer or bound failures during development probes.
- All generated ledgers replayed; box scores and period totals derive from
  `EventAccounting`.
- 1000-game runtime is not formally measured (T016); development probe measured
  about 6 ms/game on the authoring machine for standard games including final
  validation.
