# Plan 005 — Rotations and Playing-Time Management

> **Status:** **FROZEN — OWNER APPROVED 2026-11-06.** No implementation authorized; T01–T06 each need a
> separate owner authorization and implementation is **NOT STARTED**.
> **Baseline:** `develop/m002` at `f53201314e9cfdcc8734eb523e41f313f3c644c2`.
> **Companions:** `spec.md`, `tasks.md`, `design-decisions.md`, `acceptance-matrix.md`,
> `verification-plan.md`.

## 1. Architecture summary

The rotation plan is immutable input. The simulator turns it into a deterministic substitution policy
that only emits existing `Substitution(reason: tactical)` events at existing legal windows. The ledger
remains the single source of truth; minutes are still derived by accounting.

```text
Setup UI (managed team, starting five, preset/custom targets)
      │
      ▼
GameRequest { league, teams, seed, homeLineup?, awayLineup?, rotationPlan? }
      │  (isolate / compute)
      ▼
Worker: lineups = supplied ?? CourtLineup.defaultFor(team)
      │
      ▼
GameInput { ..., homeLineup, awayLineup, rotationPlan? }  ──► fingerprint v4
      │
      ▼
GameSimulator
      ├─ preset expansion → validated integer-second targets
      ├─ on W1/W2/W4/W5: mandatory foul-out first, then ≤1 tactical swap/team
      └─ overtime: fresh per-period allocation, no extra PRNG draws
      │
      ▼
GameEventLedger ──► GameEventReducer.validate ──► ValidatedGameLedger
      │
      ▼
EventAccounting.aggregate ──► GameBoxScore (+ secondsPlayed, participation)
```

## 2. Component impact

| Component | Change |
|---|---|
| `models/*` | unchanged (M001 generation, roster, positions, attributes) |
| `CourtLineup` / `CourtSlot` | unchanged; supplied as starting lineups |
| `rotation_plan.dart` | **new**: `RotationPlan`, `TeamRotationPlan`, `RotationPreset`, canonical JSON, preset expansion, typed validation |
| `game_input.dart` | add nullable `rotationPlan`; validate roster ownership and target set |
| `game_versions.dart` | simulation 6, fingerprint 4 in one atomic commit; other identifiers unchanged |
| `game_fingerprint.dart` | include the canonical plan in the payload when present |
| `game_rules.dart` | unchanged (policy constants are engine behavior, not rule fields) |
| `game_event.dart` | unchanged (`Substitution(reason: tactical)` already legal) |
| `game_reducer.dart` | unchanged semantics; must accept every emitted tactical substitution under existing window bounds |
| `game_simulator.dart` | plan-driven tactical hook after W1/W2/W4/W5 mandatory sequences; deficit selection; overtime allocation |
| `rotation_policy.dart` | **new**: pure deficit/tie-break/threshold logic, no PRNG |
| `event_accounting.dart` | unchanged; tactical substitutions already credit the entrant |
| `box_score.dart` | unchanged (`secondsPlayed` exists) |
| App: `game_runner.dart` (`GameRequest`) | carry optional lineups and plan; worker fallback to `defaultFor` |
| App: `game_setup_screen.dart` | managed team, starting five, preset/custom targets, validation |
| App: `game_screen.dart` | rematch re-sends the same lineups and plan with the advanced seed |
| App: `game_result_view.dart` | minutes/statistics for starters and entrants (M004 behavior retained) |
| Tests | contract, policy, simulator, fixture, parity, widget, walkthrough per `verification-plan.md` |

## 3. Contract design

- `RotationPlan` is a value object over two `TeamRotationPlan` values. Both are required when the plan
  is present.
- `TeamRotationPlan.targetSeconds` is canonicalized to roster order at construction; serialization
  always emits roster order, never map insertion order.
- Preset expansion is a pure function `expand(preset, roster, starters, rules) → Map<PlayerId,int>`.
  Custom targets skip expansion but use the same validation.
- Validation order: plan presence/pairing → roster ownership → target set equality → range → exact sum
  → starter positivity → preset/target agreement. All failures are typed issues.
- `GameInput.create` validates the plan against the resolved lineups and rules, so an invalid plan can
  never reach the simulator.
- Fingerprint: the plan serializes canonically and is included only when non-null. A `null` plan keeps
  the v4 (post-bump) no-plan payload shape, which must be stable.

## 4. Policy design

- State per team: validated targets, actual seconds derived from emitted events, active five, last
  tactical swap timestamp, last swap pair.
- Hooks are called from the existing window-opening code paths, strictly after the mandatory
  replacement sequence. Hook placement is specified in `spec.md` §7; W0 gets no tactical hook.
- Thresholds are computed from the active period length: regulation `periodSeconds`, overtime
  `overtimeSeconds`.
- Selection is a pure function of `(active five, bench, targets, actuals, expected, tie-break data)`.
  It returns at most one swap; the simulator emits it or nothing.
- Cooldown and reverse-swap suppression use game seconds and the last swap for that team.
- No PRNG call exists on any rotation path. The draw-count test asserts equality with the no-plan path
  up to the first tactical substitution and unchanged total draws for a plan that never triggers.

## 5. Overtime design

- The regulation plan is never mutated. At each `PeriodStarted` for an overtime period, the simulator
  computes `otTarget` from the regulation target, `L = rules.overtimeSeconds`, `C`, and the eligible
  set ordered active-slots-then-roster.
- The allocation is cached for that period only and discarded at `PeriodEnded`.
- Deficit accounting inside overtime is period-local; regulation actual seconds are not mixed in.
- Foul-out replacement still runs first; the period's `otTarget` is not retroactively rewritten.
- Depleted continuation disables tactical swaps; ledger conservation still holds.

## 6. Determinism and replay

- Rotation consumes zero PRNG draws; A1/action draw structure is untouched.
- The only new events are `Substitution(reason: tactical)`, which already exist in schema 3.
- Replay never re-derives a tactical decision; the event is authoritative.
- Same `GameInput`, seed and versions ⇒ identical ledger on Dart VM and Chrome.
- Worker/caller parity must be re-verified because `GameRequest` and `GameInput` both grow.
- No-plan mode must reproduce the pinned v5 event array for the same input and seed, header excluded.

## 7. Migration plan

1. **T01:** add `RotationPlan`/`TeamRotationPlan`/preset expansion/serialization; add nullable
   `rotationPlan` to `GameInput`; change the fingerprint payload; bump simulation 6 and fingerprint 4
   in the same commit. Stop at a compiling, validated contract: no tactical emission yet.
2. **T02:** add the pure policy component and unit tests, including zero-draw assertions. Not wired.
3. **T03:** wire hooks at W5 first, then W1/W2/W4; enforce mandatory-first ordering; add legality and
   precedence tests.
4. **T04:** pin v6 canonical fixtures, add replay/worker parity, and assert no-plan v5 event-array
   equivalence.
5. **T05:** Flutter setup editor, lineup/plan transport, worker fallback, validation feedback.
6. **T06:** physical-device walkthrough and owner acceptance evidence.

Each task is separately authorized; the sequence is a dependency order, not a single authorization.

## 8. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Preset remainder rule drifts back to global roster-order rounding | §5.4 wording is normative; contract test asserts the exact vector and the starters-first order |
| R2 | Floors plus remainder accidentally exceed `C` | Assert `target ≤ C`; the `n = 5` branch is exact; no clamping loop masks an error |
| R3 | Tactical hook emitted before a mandatory foul-out replacement | Mandatory-first ordering is a spec invariant; negative tests construct the collision |
| R4 | Windows are event-driven; targets can be structurally unattainable | Mandatory disclosure; tests assert legality, not target achievement |
| R5 | Overtime uses regulation thresholds and delays swaps | Overtime-scaled `h_ot`/`cooldown_ot`; tests assert the constants for 300 s |
| R6 | Overtime allocation reuses regulation actuals and inherits a deficit | Period-local actuals; regulation targets/minutes immutable; tests assert no carry-over |
| R7 | Recomputing overtime allocation from a mutated plan | Allocation derives from the original regulation target only; cached per period and discarded |
| R8 | Plan map insertion order changes the fingerprint | Canonical roster-order serialization; equality test with shuffled insertion |
| R9 | Version bump split from the payload change mislabels a build | T01 is one atomic public-contract commit |
| R10 | No-plan mode silently drifts from v5 | Event-array equality fixture with header/version excluded |
| R11 | Rematch drops the plan or lineup | `GameRequest` carries both; rematch test asserts preservation and seed advance |
| R12 | Simulator minutes diverge from accounting | Deficit state derives from emitted events; tests cross-check `EventAccounting` |
| R13 | Rotation is mistaken for fatigue/tactics | Non-goals and disclosure; no attribute, coefficient or probability change |
| R14 | Small-roster presets surprise users | Vectors documented; Balanced vs Starter-heavy are visibly distinct; disclosure that presets are heuristics |
| R15 | Rotation reduces foul concentration but is presented as fixing disqualifications | Explicit non-claim; foul-rate investigation is out of scope |

## 9. Out of scope

Fatigue/stamina, injuries/ejections, coaching AI, in-game manual substitutions, technical fouls,
timeouts, post-basket substitutions, persistence, seasons, trades, contracts, tactics, shot-selection
tuning, probability/coefficient changes, statistical re-certification, Android performance
measurement.
