# Verification Plan 005 — Rotations and Playing-Time Management

> **Status:** **FROZEN — OWNER APPROVED 2026-11-06.** Defines required evidence; **nothing here has
> been run**. Implementation is **NOT STARTED**.
> **Baseline:** `develop/m002` at `f53201314e9cfdcc8734eb523e41f313f3c644c2`.

## 1. Test layers

| Layer | Purpose | Examples |
|---|---|---|
| Contract | Types, serialization, validation | Canonical plan JSON; insertion-order equality; typed validation |
| Allocation | Preset mathematics | Standard vectors; short-period vectors; starter-first remainder |
| Policy unit | Deterministic selection | Deficits, thresholds, tie-breaks, cooldown, zero draws |
| Simulator | Real games emit lawful participation | Tactical windows; mandatory-first collision; OT allocations |
| Reducer acceptance | Emitted ledgers validate | Every tactical substitution accepted |
| Accounting | Minutes and conservation | Tactical splits; OT; depletion |
| Determinism | Replay and parity | v6 fixture digest; repeats; worker/caller; Chrome |
| Compatibility | No-plan behavior | v5 event-array equality, header excluded |
| UI | Setup, transport and display | 360/393/430 widget tests; disclosure |

## 2. Fixtures

1. **Canonical v6 ledger** — a planned game with at least one tactical substitution, pinned by digest
   and full events.
2. **No-plan equivalence fixture** — same input and seed as the pinned v5 fixture with
   `rotationPlan == null`; event array equality excluding header/version metadata.
3. **Preset vectors** — Balanced and Starter-heavy for `n = 5, 6, 7, 8, 9, 12` under standard rules,
   plus the short-period `n = 6` case.
4. **Starter-first remainder fixture** — a roster and lineup where the remainder is smaller than five,
   proving starters receive the extra seconds in canonical court-slot order before reserves.
5. **Custom-plan fixture** — a valid non-preset target vector that sums to `T` and respects `C`.
6. **Invalid-plan matrix** — unknown id, duplicate id, missing id, negative target, target above `C`,
   wrong total, zero starter target, unknown preset, preset/target mismatch, `n < 5`, one-sided plan.
7. **Mandatory-first collision fixture** — a sixth foul and a due rotation at the same window; the
   foul-out replacement must be emitted and no tactical swap for that team.
8. **Window fixtures** — tactical substitution at W1, W2, W4 and W5; no tactical event at W0 or after
   made field goals, defensive rebounds, live turnovers, `PeriodEnded` or `GameEnded`.
9. **Overtime fixture** — regulation tie, one and multiple overtime periods, an overtime foul-out, and
   the `spec.md` §8.4 allocation vectors asserted exactly.
10. **Depletion fixture** — no eligible bench; tactical swaps stop; conservation holds.
11. **Persistence-of-lineups fixture** — a non-default starting five is the actual first five, and the
    opponent uses `defaultFor`.
12. **Rematch fixture** — lineup, both plans and matchup preserved; only the seed advances.

## 3. Rejection list (each needs a typed code where applicable)

1. Plan missing `home` or `away` team plan.
2. Plan target id not on the associated team roster.
3. Plan omits a roster player or repeats one.
4. Negative target or target above `C`.
5. Target sum not equal to `T`.
6. A selected starter with `target == 0`.
7. Unknown preset.
8. Preset and explicit targets disagree.
9. `n < 5` roster.
10. Lineup slot order, size, uniqueness or ownership violation.
11. A tactical substitution emitted before a mandatory foul-out replacement (simulator negative test).
12. A tactical substitution at clock 0 or on a non-window event (simulator negative test).
13. Two tactical substitutions for one team in one window (simulator negative test).
14. A disqualified player selected as a tactical outgoing or incoming player.
15. An overtime allocation whose sum differs from `O` or exceeds `L` for any player.
16. A v5 ledger read by a v6 build (typed schema-version rejection).

## 4. Allocation and conservation checks

- Every preset vector sums exactly to `T`; every player is in `[0, C]`; all five starters are `> 0`.
- Remainder recipients are exactly the first `rem` participants in starters-then-reserves order.
- Custom plans sum exactly and pass the same checks.
- Short-period rules yield exact integers with no minute rounding.
- Per team, `Σ secondsPlayed == 5 × Σ periodLength(played)` for regulation, overtime, tactical
  substitution games and depletion.
- A tactical substitution closes the outgoing interval and opens the incoming interval at the same
  clock; two substitutions at one clock are both handled.
- Minutes and participation come from the ledger; no simulator minutes state exists.
- Overtime allocation is recomputed per period, uses the then-eligible set, and never carries actuals
  across periods.
- Depleted continuation conserves seconds and emits no tactical swap.

## 5. Determinism checks

- **Rotation draw isolation:** zero PRNG draws on the rotation path; a controlled-phase draw-count
  assertion compares a no-plan run and a plan run up to the first tactical substitution.
- **Repeat identity:** the canonical v6 fixture reproduces byte-identical events and ledger digest on
  repeated runs.
- **Worker/caller parity:** `compute` and direct simulation produce equal `GameResult` values.
- **Cross-runtime:** Chrome-compatible core tests pass, excluding the IO-dependent
  `domain_isolation_test.dart` with the exclusion recorded.
- **No-plan compatibility:** canonical event array equality with the pinned v5 array, header/version
  excluded.

## 6. Commands (expected, from the repository root and package)

```text
flutter pub get
flutter analyze
flutter test
dart format --set-exit-if-changed lib test

cd packages/simulation_core
dart pub get
dart analyze
dart format --set-exit-if-changed lib test
dart test
```

Chrome-compatible core tests are required when replay, fingerprints or serialization change — M005
changes fingerprints and serialization — excluding the IO-dependent isolation test with the exclusion
recorded. Historical checks: v1–v5 fixtures remain untouched and are exercised by their pinned tests;
the v6 reader's typed rejection of a v5 ledger is asserted.

No statistical cohort is required or authorized for M005. No M002 AC09/AC10 claim is made.

## 7. Evidence artefacts

- `specs/005-rotations-playing-time/` acceptance report (created at T06).
- Canonical v6 fixture file with digest.
- No-plan v5 event-array equality record.
- Preset vector table test names.
- Mutation test names mapped to §3 numbering.
- Widget-test names per width.
- Walkthrough record with milestone evidence.

## 8. Stop rules

Stop and report if: a preset vector does not conserve `T`; any target exceeds `C`; a remainder is
assigned outside the approved order; a tactical substitution precedes a mandatory replacement; the
reducer rejects an emitted ledger; no-plan events differ from v5 outside header/version metadata; a
repeat or parity run differs; or the implementation needs a new window, timeout, rule field or PRNG
draw.
