# Amendment 001 — Non-steal turnover reason

Status: **IMPLEMENTED — owner-authorized contract amendment.**
Base: published T008 checkpoint `06abdf2` on
`feat/m002-phase2a-probability-model`.
Frozen M002 specification (`dd4234d`) is unchanged.

## Owner decision

The owner authorized one additive event-contract change: a turnover reason for
live offensive giveaways with no credited defensive steal. JEV Playground
supported the naming (`nonSteal` 83%, `other` 16%, `liveBall` 1%; readiness
1.53/2, limited confidence). Implementation correctness rests on the review and
tests in this amendment, not on the JEV score.

Selected value: **`TurnoverReason.nonSteal`** (wire `nonSteal`).

Rationale over `liveBall`: `nonSteal` states the one thing the event must
prove — no defender was credited with a steal — and it mirrors
`TurnoverKind.nonSteal` already emitted by the T008 probability model.
`liveBall` describes timing rather than attribution and would invite readers to
infer that other turnovers are dead-ball events, which they are not.

## Semantics

`nonSteal` is a turnover committed by an active offensive player without a
credited defensive steal. It covers simplified bad passes, traveling, lost
balls and out-of-bounds giveaways. The reason is attributive, not mechanical:
M002 does not model the specific giveaway type.

Rules:

- `stolenById` must be `null`.
- The turnover team must own the current possession.
- The credited player must be active for that team.
- No pending shot, miss, rebound, free-throw group, dead-ball miss or other
  unresolved outcome may precede it.
- It cannot follow a pending offensive foul; offensive-foul turnovers keep
  `TurnoverReason.offensiveFoul`.
- The game clock must be greater than zero; the period horn takes precedence.
- The shot clock must be greater than zero; shot-clock expiry keeps
  `TurnoverReason.shotClock`.
- The possession ends with `PossessionEnded(reason: turnover)`; the opponent
  must receive the next possession.

No personal foul, steal, field-goal attempt or points are generated.

## Versioning

| Constant | Value |
|---|---|
| `gameEventSchemaVersion` | **2** (was 1) |
| `gameSimulationVersion` | 1 (unchanged) |
| `gameRulesVersion` | 1 (unchanged) |
| `gameFingerprintVersion` | 1 (unchanged) |
| `gameActionDurationModelVersion` | 1 (unchanged) |
| `coreEngineVersion` / `snapshotSchemaVersion` | 1.0.0 / 1 (unchanged) |

## Fingerprint effect

`gameEventSchemaVersion` contributes to the canonical input fingerprint
(`game_fingerprint.dart`). Recomputing with the actual canonical serializer for
the pinned fixture (`buildInput()`: league seed 20261028, seed 42, standard
rules):

- schema v1: `82618eb22dc59379c64736cc802262eb0643a2b1ede68f1bb2db8606bed2f850`
- schema v2: `bcb1a58f09500c0d4132b48709962bd44409a25b6e23ee91d27d3c9f30cb97a8`

The pinned fixture in `test/simulation/game_input_test.dart` is updated to the
v2 value.

## Compatibility policy

- Ledger headers with `eventSchemaVersion != 2` are rejected with
  `GameValidationCode.unsupportedEventSchemaVersion`.
- Schema-v1 ledgers are **not** reinterpreted as v2.
- No persistence, migration or dual-version reader is introduced.
- Existing schema-v2 payloads keep their field shapes; only the allowed reason
  domain grows by one value.

## Reducer and accounting implications

Reducer (`game_reducer.dart`, `_turnoverEvent`):

- New `TurnoverReason.nonSteal` case enforcing the rules above.
- Rejection codes: `periodHornPrecedence` for a zero game clock,
  `turnoverInvalid` for a zero shot clock, a non-null `stolenById`, or a pending
  offensive foul.
- Generic possession, team, active-player, live-clock, unresolved-outcome and
  possession-end handling is unchanged.
- `steal`, `shotClock` and `offensiveFoul` behavior is untouched.

Accounting (`event_accounting.dart`) is unchanged and remains the single path:
the turnover credits `player.turnovers++`, team TOV aggregates from players, and
steals are credited only from `stolenById`. A `nonSteal` turnover therefore
credits one player TOV, one team TOV, zero steals, and no PF/FGA/points.

Probability model: `TurnoverKind.nonSteal` is unchanged and now maps to
`TurnoverReason.nonSteal`. Coefficients, draw order and PRNG behavior are
unchanged.

## Tests added

`test/simulation/turnover_nonsteal_test.dart`:

1. valid `nonSteal` turnover closes the possession;
2. `stolenById` rejected;
3. no open possession rejected;
4. wrong team rejected;
5. inactive player rejected;
6. pending miss and pending free-throw group rejected;
7. offensive-foul replacement rejected;
8. `PossessionEnded(turnover)` accepted;
9. same-team restart rejected;
10. opponent restart accepted;
11. one player TOV, one team TOV, zero steals, no PF/FGA/points;
12. canonical JSON round-trip with `nonSteal`;
13. header emits schema v2;
14. legacy v1 header rejected;
15. v2 fingerprint fixture matches actual canonical input;
16. existing steal, shot-clock and offensive-foul fixtures still pass;
17. zero game clock rejected with period-horn precedence, zero shot clock
    rejected in favour of `shotClock`.

Also updated: the M002 schema-version pin in
`test/simulation/m001_regression_test.dart` (M001 pins unchanged) and the
fingerprint fixture in `test/simulation/game_input_test.dart`.

## Deferred

T009–T019 remain unauthorized. This amendment adds no orchestrator, no
complete-game generation, no calibration, no Flutter changes and no event-schema
change beyond the single additive reason plus version bump.
