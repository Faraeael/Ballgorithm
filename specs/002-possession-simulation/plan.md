# Implementation Plan 002 — Draft (No execution authorization)

Status: **FROZEN — READY FOR IMPLEMENTATION AUTHORIZATION**
Frozen: 2026-10-28. Implementation remains **NOT AUTHORIZED**.

## Baseline constraints

- Pure Dart package `packages/simulation_core`; public exports in
  `lib/simulation_core.dart`; no Flutter/Flame/IO/network.
- Existing models: `League`, `Team`, `Roster`, `Player`, `PlayerAttributes`
  (12 integer ratings 0–100), typed IDs, `Position` (PG, SG, SF, PF, C),
  `GenerationConfig`.
- `DeterministicRandom` (`xorshift32-v1`): 32-bit state, seed masked with
  `0xFFFFFFFF`, zero mapped to `0x9E3779B9`, `nextInt` supports 1..2^32.
- `coreEngineVersion = 1.0.0`, `snapshotSchemaVersion = 1` remain unchanged.
- M001 ratings are uncalibrated (TD-01) and fixed lineups omit fatigue,
  foul-outs and substitutions.

## Proposed package structure

```text
packages/simulation_core/lib/src/
  simulation/
    game_config.dart          # GameRules, GameInput, version constants
    active_lineup.dart        # canonical PG..C lineup and validation
    game_event.dart           # sealed event hierarchy + canonical event JSON
    game_state.dart           # minimal replay state
    game_reducer.dart         # pure transition guard + canonical replay
    possession_engine.dart    # action selection and outcome generation
    game_simulator.dart       # orchestration, clocks, bounds
    game_result.dart          # result + ledger + fingerprint
    box_score.dart            # derived-only player/team/period totals
    probability_model.dart    # basis-point probabilities + duration model
    event_accounting.dart     # single accounting implementation
    game_fingerprint.dart     # canonical input serialization + SHA-256
  validation/
    game_validation.dart      # GameValidationCode + typed failures
packages/simulation_core/test/simulation/
    game_input_test.dart
    game_reducer_test.dart
    game_simulator_test.dart
    game_accounting_test.dart
    game_determinism_test.dart
    game_probability_test.dart
    game_calibration_test.dart
```

Keep the structure flat; no interface per event and no second state machine.
`box_score.dart` may hold value types only; totals are produced by
`event_accounting.dart`.

## Public API (illustrative)

```dart
final game = GameSimulator().simulate(
  GameInput(
    league: league,                 // one authoritative M001 source
    homeTeamId: home.id,
    awayTeamId: away.id,
    homeLineup: homeFive,           // ordered PG, SG, SF, PF, C
    awayLineup: awayFive,
    seed: 42,
    rules: GameRules.standard,
  ),
);

game.inputFingerprint;              // lowercase SHA-256 hex
game.events;                        // immutable, ordered, typed
game.boxScore;                      // derived only from events
GameEventReducer.replay(game.input, game.events); // validates ledger
```

`GameInput` retains the `League` reference; `GameResult` stores the fingerprint,
versions and ledger, not a duplicate roster model. Duplicating player data is
forbidden.

## Event ledger schema (RG-01)

Ledger header (canonical, ordered):

```text
eventSchemaVersion, gameSimulationVersion, gameRulesVersion,
prngImplementationId, inputFingerprint, gameId, events[]
```

Every event carries:

```text
sequence        int, 1-based, strictly increasing
type            event type name
period          int, 1-based
gameClock       int seconds remaining in period
shotClock       int seconds remaining, or null when no live possession
```

| Event | Payload |
|-------|---------|
| `GameStarted` | `homeTeamId`, `awayTeamId`, `startingTeamId` |
| `PeriodStarted` | `startingTeamId` |
| `PossessionStarted` | `possessionId`, `offenseTeamId`, `shotClock` |
| `PossessionEnded` | `possessionId`, `offenseTeamId`, `reason` (`madeFieldGoal`, `turnover`, `defensiveRebound`, `madeFinalFreeThrow`, `periodEnd`) |
| `FieldGoalAttempt` | `teamId`, `shooterId`, `shotValue` (2 or 3), `made`, `assistedById?`, `blockedById?`, `andOne` |
| `PersonalFoul` | `committingTeamId`, `committingPlayerId`, `drawnByPlayerId?`, `kind` (`shooting`, `nonShooting`, `offensive`), `freeThrowsAwarded` (0–3), `bonus` |
| `FreeThrowAttempt` | `teamId`, `shooterId`, `groupId`, `attemptIndex` (1-based), `attemptsInGroup`, `made`, `lastOfGroup` |
| `Rebound` | `teamId`, `playerId`, `offensive`, `missedEventSequence` |
| `DeadBallMiss` | `teamId`, `missedEventSequence`, `reason` (`periodEnd`) |
| `Turnover` | `teamId`, `playerId`, `reason` (`steal`, `shotClock`, `offensiveFoul`), `stolenById?` |
| `PeriodEnded` | `period` |
| `GameEnded` | `finalPeriod` |

No scores or totals in events: they are derived. IDs are strings; clocks, shot
values and indices are integers; no floats.

### Canonical ordering

- Made FG without and-one: `FieldGoalAttempt` → `PossessionEnded` →
  `PeriodEnded` if the period ends.
- Made and-one: `FieldGoalAttempt(made, andOne)` → linked `PersonalFoul` →
  `FreeThrowAttempt` → `Rebound` or `DeadBallMiss` if the final FT misses. A
  made final FT, a defensive rebound, or a zero-clock `DeadBallMiss` emits
  `PossessionEnded`; an offensive rebound continues the same possession and
  starts a new phase with new A1 draws. `PeriodEnded` only when the period ends.
- Missed FG: `FieldGoalAttempt` → (`Rebound` | `DeadBallMiss` at zero). OREB
  continues the possession; DREB emits `PossessionEnded`; zero-clock miss emits
  `DeadBallMiss` then `PossessionEnded`.
- Turnover: `Turnover` → `PossessionEnded` → next possession/period end.
- Shooting foul on a miss: `PersonalFoul` → FT sequence (no FGA) → rebound or
  dead-ball. A made final FT, defensive rebound, or zero-clock `DeadBallMiss`
  ends possession; an offensive rebound of a live missed final FT continues the
  possession and starts a new phase. No counted FGA in either case.
- Non-bonus defensive non-shooting foul: `PersonalFoul`, possession continues,
  shot clock reset; no `PossessionEnded`.
- Bonus non-shooting foul: `PersonalFoul` → FTs → rebound/change of possession,
  with the same made/defensive/offensive-rebound possession rule.
- Offensive foul: `PersonalFoul(offensive)` + `Turnover` → `PossessionEnded`.
- `GameEnded` follows the final `PeriodEnded`; no event may follow it.

## Replay reducer invariants

Reject with typed `GameValidationCode` on:

- duplicate/non-increasing sequence IDs, wrong event schema version, events
  after `GameEnded`, events before `GameStarted`;
- period numbers outside `1..(4 + overtimes)`, a game clock that increases
  within a period, negative clocks, a shot clock above the configured maximum,
  or a shot-clock increase not produced by an enumerated OD-12 reset;
- `PossessionStarted` while a possession is open or with a zero shot clock;
  attempts/FGs/Fouls with no live possession; multiple open FTs or an FT group
  with mismatched size/index;
- a foul linked to a made FG whose `andOne` flag is false; assist on a miss;
  block on a make; steal not linked to an opponent turnover; foreign/bench
  player attribution; duplicate player on a lineup;
- two rebounds for one miss, a rebound before a miss, a rebound from the wrong
  team (offensive rebound must be the shooting team, defensive the opponent);
- `DeadBallMiss` not at zero clock/period end or with a rebound;
- possession ending without a legal reason; new live possession after the horn;
- `PeriodEnded` with open FTs/possession, nonzero clock, or missing buzzer
  resolution; `GameEnded` with a tied score or before the final period;
- exceeding 50,000 events; 64 consecutive zero-clock events at an unchanged
  timestamp within a period; 10 overtimes.

The reducer and `EventAccounting` share one accounting implementation. No
module may maintain a parallel score counter.

## Clock and possession mechanics

- Period lengths: 720 s regulation, 300 s OT; shot clock 24 s.
- Dead-ball processing and FTs consume 0 game seconds; both clocks freeze.
- The game clock is non-increasing within a period. The shot clock increases
  only through an enumerated OD-12 reset and never exceeds its maximum.

### A1 offensive-phase duration (owner-approved)

A duration belongs to a live offensive phase, not to every emitted event. A
possession may contain multiple phases after offensive rebounds (and after a
retained possession following a non-bonus defensive foul). `gameActionDurationModelVersion = 1`
is provisional and uncalibrated; changing weights or brackets requires a
rules-version bump.

| Phase type | Basis points | Share | Duration bracket |
|------------|--------------|-------|------------------|
| Transition | 1500 | 15% | 2–7 s |
| Early offense | 3000 | 30% | 5–11 s |
| Half-court | 5500 | 55% | 10–22 s |

Exact PRNG draw order per phase:

1. `typeDraw = rng.nextInt(10000)`: `0..1499` transition, `1500..4499` early,
   `4500..9999` half-court.
2. `offsetDraw = rng.nextInt(count)` with count 6, 7 or 13:
   `duration = lower + offsetDraw` (2, 5, 10 respectively).
3. Terminal action and outcome draws in the probability model's documented
   order: action category, actor, zone, make/miss, foul/and-one, assist, block,
   rebound team, rebound player, free throws. Conditional branches document the
   draws they consume.

A final-tick attempt consumes no type/duration draws and uses outcome draws
directly. Each new phase after an offensive rebound or retained possession draws
type and duration again.

### Clock-expiry classification (no clamping)

Let `Rg` be game-clock seconds remaining and `Rs` the shot clock at phase start.

| Condition | Resolution |
|-----------|------------|
| `Rg == 0` | Illegal state; period must end. |
| `Rg == 1 && Rs >= 1` | Final-tick attempt: no phase draws; a deliberate shot consumes 1 s and releases at 0. Miss → `DeadBallMiss`; shooting foul completes FTs; `PeriodEnded` after resolution. |
| `D <= Rg && D <= Rs` | Phase completes at `D`; if `D == Rg` a shot releases at 0 and is legal, resolved before `PeriodEnded`. |
| `D > Rs && Rs < Rg` | Shot clock expires at `Rg - Rs`; shot-clock turnover (OD-05). The planned action is abandoned, never converted into a shot. |
| `D > Rg && Rg < Rs` | Game clock expires; period ends at 0 with no terminal action, turnover or rebound. |
| `D > Rg && Rg == Rs` | Horn precedence at 0; no shot because no legal release was planned before expiry. |

A shot released exactly at shot-clock zero (`D == Rs`, with game time remaining)
is legal; the violation applies only when no valid attempt was released. Any
shooting or bonus-awarding foul that is the terminal action of a phase initiated
before expiry is resolved at its timestamp, including zero, and its free throws
complete before `PeriodEnded`. A duration beyond the limiting clock is never
clamped and never becomes a legal shot. Only the explicit final-tick path, `D == Rg`, or a shot at `D == Rs`
produces a zero release. Existing precedence rules apply when a verified shot or qualifying
shooting foul was initiated before expiry. Awarded FTs after the horn complete
before `PeriodEnded`; a missed final FT at zero is `DeadBallMiss`, not a rebound.
No new live possession begins after the horn.

## Fingerprint (OD-06)

Canonical ordered UTF-8 JSON, then SHA-256 lowercase hex:

```text
fingerprintVersion: 1
league: <League.toJson field order>
homeTeamId, awayTeamId
homeLineup: [pgId, sgId, sfId, pfId, cId]
awayLineup: [...]
gameSeed, normalizedSeed
rules: {
  periods, periodSeconds, overtimeSeconds, maxOvertimes,
  shotClockSeconds, offensiveReboundResetSeconds,
  nonBonusFoulResetFloorSeconds, bonusRegulationFouls,
  bonusOvertimeFouls, maxEvents, maxZeroTimeEvents,
  gameActionDurationModelVersion,
  phaseWeights: [1500, 3000, 5500],
  phaseDurations: [[2,7], [5,11], [10,22]]
}
versions: { simulation, rules, eventSchema, prng, coreEngine, leagueSchema }
```

Only integers, booleans and strings. Field order is the schema above, not map
iteration. The full league snapshot means unrelated roster edits change the
fingerprint; document this. Raw seeds that alias modulo 2^32 produce identical
gameplay but distinct fingerprints; record as intended identity semantics.
`package:crypto` is the **owner-approved (A2, 2026-10-28)** SHA-256
implementation: pure Dart, browser-compatible, no network, no native
cryptography, identical VM/Chrome results, lockfile-pinned during
implementation. It is the first runtime dependency of `simulation_core`; the
implementation PR must record the dependency audit and keep the domain import
audit clean.

## Determinism and serialization

- Use a new game-local `DeterministicRandom` instance; no `Random()`, wall clock
  or unordered iteration.
- Canonical event JSON uses the header/event field order above.
- Pin one ledger and one fingerprint fixture; any behavior change requires a
  simulator/rules version bump and fixture review.
- Test VM and Chrome/JS; same-run equality alone is insufficient.
- No disk persistence or migration in M002. TD-02/TD-03 must be addressed before
  career saves of game results.

## Probability model

- Integer basis points (`0..10000`); bounded integer draws from
  `DeterministicRandom.nextInt`; convert to decisions without floating-point
  serialization.
- Document coefficients and clamps for usage, zone choice, success, turnovers,
  steals, blocks, fouls, rebounds, assists and free throws.
- `midrange` is explicit for midrange selection/conversion; `stamina` is unused
  until M003.
- Pre-register AC09 experiments and metrics before calibration.

## Accounting

Player and team totals are computed once from the ledger:

```text
FGM = 2PM + 3PM; FGA = 2PA + 3PA
PTS = 2*2PM + 3*3PM + FTM
REB = OREB + DREB
team.METRIC = sum(player.METRIC) for player-credited metrics
team.TOV = sum(player.TOV)
team.PF = sum(player.PF)
team.PTS = sum(player.PTS) = sum(periodPoints)
```

Add derived checks: each made FG has one shooter; assists only on made FGs by a
teammate on court; steals pair with opponent turnovers; blocks only on missed
FGAs; each live miss has exactly one rebound or one `DeadBallMiss`.

## Implementation phases (after authorization)

1. Validate inputs/lineups/rules/seeds and define versioned constants.
2. Implement typed events, canonical serialization and the pure reducer with
   hand-authored legal/illegal fixtures.
3. Implement one accounting path with every equation and invariant.
4. Implement basis-point probability model and the action-duration model.
5. Implement orchestration: periods, clocks, bonus, FTs, overtime, bounds.
6. Pin ledger/fingerprint fixtures; verify VM and Chrome.
7. Run AC09 pre-registered experiments, then ≥1,000-game calibration report.
8. Measure performance against OD-08; audit scope and M001 regressions.
9. Produce the acceptance report for AC01–AC13.

## Performance

Reference targets (provisional, OD-08): 1,000 games ≤ 60 s desktop optimized
Dart; p95 ≤ 100 ms/game; ≤ 128 MiB incremental memory; no unbounded loops.
Record CPU, OS, Dart version, compilation mode, warmup and sample size. No
Android claim without a device measurement; if the reference environment is
unavailable, report evidence and leave sign-off pending.

## Deliverable handoff

Updated public API docs, version constants, executable tests and fixtures,
calibration report, limitations and the full acceptance report. New code stays
inside `packages/simulation_core`; no Flutter UI changes are required.
