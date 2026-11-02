# Plan 004 — Foundational Player Participation

> **Status:** **DRAFT — NOT FROZEN.** Planning input for owner review; no implementation authorized.
> **Baseline:** `develop/m002` at `125e1e652baa41db17f3684242bbd73683f9602b`.
> **Companions:** `spec.md`, `tasks.md`, `design-decisions.md`, `acceptance-matrix.md`, `verification-plan.md`.

## 1. Architecture summary

Participation becomes ledger-derived state. The input supplies the starting five; the reducer and the
simulator maintain the current five; every change is an event; minutes are computed from timestamps.

```text
GameInput (CourtLineup x2, seed, rules)
      │
      ▼
GameSimulator ── emits ──► Substitution (window-anchored, no draws)
      │                        │
      ▼                        ▼
GameEventLedger ──► GameEventReducer.validate ──► ValidatedGameLedger
                            │
                            ├─ current five per team (replayed)
                            └─ disqualification / continuation invariants
                                   │
                                   ▼
                     EventAccounting.aggregate ──► GameBoxScore (+ secondsPlayed)
```

## 2. Component impact

| Component | Change |
|---|---|
| `models/*` | unchanged (M001 generation, roster, positions, attributes) |
| `CourtLineup` / `CourtSlot` | new; replaces `ActiveLineup` in `GameInput`, `GameResult` and the app runner; **input lineups are starting lineups only** |
| `game_input.dart` | immutable starting lineups; `isActive` removed or renamed to starting-lineup semantics in the atomic v5 transition |
| `game_event.dart` | new `Substitution`, new `SubstitutionReason`; schema dispatcher accepts it |
| `game_versions.dart` | proposed bumps (sim 5, rules 3, schema 3, fingerprint 3) |
| `game_rules.dart` | `foulOutLimit`, `substitutionPolicyVersion`, validation, `toJson` |
| `game_fingerprint.dart` | payload: slot-player pairs + new rules fields |
| `game_reducer.dart` | current-five state, window flag, substitution validation, ceiling exemption, continuation checks, pending horn-replacement obligation |
| `game_simulator.dart` | mutable on-court five, foul-out detection, window emission, deterministic replacement |
| `event_accounting.dart` | initialize every roster player with zero values; credit substitute events to the substituting player; `secondsPlayed` derivation and conservation check |
| `box_score.dart` | additive `secondsPlayed` |
| `game_state.dart` | unchanged (active five stays reducer-internal) unless owner asks for exposure |
| `probability_model.dart` | positional-bonus lookups switch from `player.position` to slot index (nine sites); no coefficient change |
| `action_intent.dart` | `TeamOnCourt` carries `CourtLineup` |
| App: `game_runner.dart` | builds `CourtLineup.defaultFor` |
| App: `game_result_view.dart` | participants by **entry** (starters then entrants, tagged), minutes column, disqualification/continuation indicators, non-participant disclosure |
| App tests | migrate lineup construction; new UI assertions |

## 3. Reducer design

State additions (private to `_Replay`):

- `Map<String, CourtLineup> _lineups` seeded from `input`.
- `_SubstitutionWindow? _window` with kind and the event that opened it, plus a per-window
  `Set<String> _windowPlayers`.
- `Map<String, bool> _pendingHornReplacement` per team, surviving `PeriodEnded`, cleared by a lawful
  W5 substitution or voided by `GameEnded`.
- Foul counts already derived from events; no new persisted state.

Validation order for `Substitution`:

1. game started, not ended, period matches current period.
2. window open and legal for this team and reason.
3. clocks: `gameClock == state.gameClock`, `shotClock == state.shotClock`, `gameClock > 0`.
4. roster ownership: both players on the team roster; out-player active; in-player inactive; not
   disqualified.
5. reason consistency: `foulOut` ⇒ out-player at/over limit; `tactical` ⇒ below limit (and legal while
   an eligible bench exists).
6. window-local player bound (§4.1 of the spec).
7. replace in `_lineups[team]`; five slots remain filled and unique.
8. do **not** touch possession, offense team, clocks, free-throw group or pending flags.

Window opening/closing:

- Open W0/W1 inside foul handling, W2/W4 after possession end, W5 in `_periodStarted`.
- Close on any event that is not a `Substitution`.
- At close, assert: for each team, an over-limit active player implies either an empty eligible bench
  or a recorded pending replacement obligation from a clock-0 disqualification. The obligation is
  cleared only by a lawful W5 substitution (or by `GameEnded`), never by an arbitrary event.
- While an obligation is pending, an explicit allowlist governs which events may follow (free throws of
  the awarded group, `DeadBallMiss`, `PeriodEnded`, `PeriodStarted`, W5 `Substitution`, `GameEnded`);
  any live event is rejected until the replacement is recorded.

Ceiling rule: the generic pending-shot-clock consumption block gains one exemption — `Substitution`
neither validates against nor clears `_pendingShotClockCeiling`; it must still match the current
`shotClock`, which equals the ceiling after a retained foul. All other events keep the existing rule.

## 4. Simulator design

- Replace `late final TeamOnCourt` with mutable on-court state holding `CourtLineup`.
- After emitting a `PersonalFoul`, evaluate disqualification for the committing player:
  - if the foul awards free throws → try W0 replacement for the offending team immediately before the
    first FT (unless `gameClock == 0`);
  - if retained non-bonus → try W1;
  - if offensive → the subsequent turnover/possession-end opens W4.
- If the game clock is 0, defer to the next period's W5; if `GameEnded` follows, do nothing.
- Replacement selection is a pure function: roster order, same-seat preference, no RNG.
- The five used for the remainder of the possession is the updated one (W1 splits a possession).
- Foul accumulation per player is derived from events for decisions; the simulator keeps a local count
  for efficiency and must agree with the reducer.

## 5. Accounting design

- Walk the ledger once, tracking each team's active five and its timestamps.
- On each clock-carrying event, close the current interval at that event's clock for all five active
  players, then continue.
- On substitution, close the outgoing interval and open the incoming one at the same clock.
- On `PeriodStarted`, open intervals at `periodLength(period)`; on `PeriodEnded`, close at 0.
- Fail with a typed accounting error if any interval is negative or if the conservation sum fails.

## 6. Determinism and replay

- Substitution consumes no PRNG draw; A1/action draw structure is untouched.
- Realized draw consumption diverges from v4 only through outcome-dependent branches after a lineup
  change; within v5 it is fully reproducible per input.
- For default lineups, slot == primary position, so v5 and v4 produce identical event lists for games
  with no disqualification (used as a mechanism check).
- Replay never re-derives a replacement choice; the event is authoritative.
- Worker/caller parity must be re-verified because `GameInput` now carries a different type.

## 7. Migration plan

1. T02: introduce a non-exported `CourtLineup`/`CourtSlot` built internally from `ActiveLineup`; public
   API, barrel, serialization and version identifiers untouched; no reachable mismatched slots.
2. T02: switch positional-bonus lookups to slot index; assert digest and event-list equivalence against
   pinned v4 values.
3. T03: in one atomic commit, adopt publicly (export, migrate `GameInput`/`GameResult`, remove
   `ActiveLineup`, rename or remove `GameInput.isActive` to starting-lineup semantics, permit
   mismatched slots), change the payload to slot-player pairs, bump all four versions, and add the
   event and rules. T03 stops at a compiling contract: no-substitution games still run and are
   deterministic, the new event round-trips, but reducer acceptance and emission are T04/T05.
4. Add reducer support, then simulator emission.
5. Add accounting (all-roster initialization) and UI.
6. Pin the v5 canonical fixture; keep v1–v4 fixtures untouched and verified by their pinned builds.

## 8. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | The ceiling exemption becomes a broad "administrative event" bypass | Exemption is limited to `Substitution`; negative tests prove ceilings survive and later illegal increases still fail |
| R2 | Slot indirection changes outcomes unexpectedly | Default lineups map slot == position; assert event-list equality with v4 for no-disqualification games before enabling substitutions |
| R3 | Horn/horn-adjacent disqualifications produce contradictory state | Absolute "no substitution at clock 0" rule plus W5 deferral; both made and missed final FT paths tested |
| R4 | Deferred replacement leaves a disqualified player nominally active during buzzer FTs | Documented exception; UI must not present them as active participants; test asserts no live action |
| R5 | Substitution windows interact with free-throw group state | W0 is the only in-group window, restricted to the disqualified defender's team; group fields asserted unchanged |
| R6 | Minutes accounting double counts or drops intervals | Single-pass derivation from events; conservation check fails the box on mismatch |
| R7 | App migration churn breaks M003 behaviour | M003 UI tests must stay green with only lineup-type changes |
| R8 | Depleted five-player rosters surprise users | Explicit disclosure; UI marks continuation |
| R9 | Accounting keeps initializing only the starting five, so substitute events are rejected or silently dropped | Accounting must initialize the whole roster; fixture with a scoring/rebounding/fouling substitute |
| R10 | A version bump ships in a separate commit from the payload change, so an intermediate build mislabels its contract | T03 is one atomic public-contract commit; intermediate T02 keeps old payload bytes |
| R11 | Historical ledgers are assumed to parse under v5 | Explicit typed rejection; comparisons use two pinned builds; no transparent-parse promise |
| R12 | Callers treat `GameInput.isActive` as current eligibility after substitutions | Rename/remove it in T03; reducer uses its reconstructed five; tests assert a substituted player is eligible and a starter who left is not |
| R13 | Horn deferral silently becomes a general over-limit exemption | Pending-replacement obligation is per team and must be satisfied at W5 before the next possession; negative fixtures reject over-limit continuation with an eligible bench and no obligation |

## 9. Out of scope

Rotations, fatigue, coaching AI, user lineups, technical fouls, injuries, timeouts, persistence,
seasons, trades, contracts, tactics, shot-selection tuning, statistical re-certification.
