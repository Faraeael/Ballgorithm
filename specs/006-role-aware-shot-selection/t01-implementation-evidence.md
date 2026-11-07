# M006-T01 — Implementation Evidence: Dormant Offensive Role Ranking

> **Status:** T01 evidence only. M006 is **not** accepted; T02–T06 are not authorized.
> **Baseline:** frozen M006 `d5f9f7d16372cb523f149d3536d972ed5f83e36b`
> (`design/m006-role-aware-shot-selection`).
> **Implementation commit:** `47dbe58bf8765aff0a4f4e47f0d2763543fc2df5`
> (`impl/m006-t01-role-ranking`).
> **Protected branches unchanged:** `develop/m002` `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`;
> `main` `a431aeb5a652b134ce40cf442c7d9ffee874fe79`.

## 1. Scope implemented

Only DD-M006-01 and the T01 half of DD-M006-08: a pure, deterministic, dormant creation-ranking
helper. No multipliers, no zone policy, no activation, no version bump, no fixtures, no UI.

## 2. Changed files

| File | Change |
|---|---|
| `packages/simulation_core/lib/src/simulation/offensive_role.dart` | New helper: `OffensiveRole`, `OffensiveRoleAssignment`, `OffensiveRoleRanking` |
| `packages/simulation_core/lib/simulation_core.dart` | One export line for the helper |
| `packages/simulation_core/test/simulation/m006_t01_offensive_role_test.dart` | 11 focused tests |

No other file changed. No frozen specification document changed.

## 3. Contract

```text
creationScore(p) = 3·ballHandling + passing + basketballIQ
ranking: descending score, ties by canonical court-slot order (PG…C)
rank 0 → primary, rank 1 → secondary, ranks 2–4 → neutral
```

- Derived from the supplied `CourtLineup` (validated five-player contract) using existing `Player`
  attributes; no position bonus, no persisted role, no `Player` field, no snapshot change.
- Returns an immutable assignment: unmodifiable ranking list, score map and role map.
- No randomness, no mutation, no simulator or model import; not referenced by any production path.

## 4. Tests (11, all passing)

1. Creation-score formula and exact arithmetic.
2. Primary/secondary/neutral assignment from descending score.
3. Canonical court-slot tie-breaking.
4. No position bonus (creator centre ranks primary; same attributes at PG rank identically).
5. Repeated derivations return identical results and consume zero PRNG draws.
6. Ranking independent of roster insertion order.
7. Immutable ranking result.
8. Substitution reclassifies the active five.
9. The same player changes role when teammates change.
10. Production `shotUsageWeights` and `shotZoneWeights` are unchanged by deriving roles.
11. An elite scorer who is not the primary creator still receives the higher v6 usage weight.

## 5. Baseline comparisons

| Gate | Baseline | T01 | Delta |
|---|---|---|---|
| `dart analyze` (core) | clean | clean | 0 |
| `dart format --set-exit-if-changed lib test` | 78 files, 0 changed | 80 files, 0 changed | +2 files (helper, test) |
| `dart test` (core VM) | 547 passed / 0 failed | **558 passed / 0 failed** | +11 |
| Chrome-compatible core suite (IO test excluded) | 546 passed / 0 failed | **557 passed / 0 failed** | +11 |
| `flutter analyze` | clean | clean | 0 |
| `flutter test` | 111 passed / 0 failed | 111 passed / 0 failed | 0 |

Fixture digests, canonical bytes and version constants were not touched: `gameSimulationVersion` 6,
`gameFingerprintVersion` 4, rules 3, event schema 3, duration model 2, PRNG `xorshift32-v1`.
`git diff` contains no fixture file.

## 6. Dormancy proof

- `grep -rn "offensive_role\|OffensiveRoleRanking" lib/src --include=*.dart` outside the helper file
  returns **no matches**.
- No production caller exists in `probability_model.dart` (`selectAction`, `_selectShot`,
  `shotUsageWeights`, `_shotZoneWeightsForSlot`, `shotMakeBasisPoints` are untouched), nor in
  `game_simulator.dart`, `game_input.dart` or any UI file.
- Tests assert production usage/zone weights are identical before and after deriving roles, and that
  the helper consumes no random draws.
- The full v6 suite, including the pinned v6 canonical fixture and no-plan equivalence tests, passes
  unchanged, so gameplay events and fingerprints are byte-identical.

## 7. Acceptance-criteria support (none marked PASS)

| AC | Support |
|---|---|
| AC-M006-01 | Supported for the helper: position-free score, no schema change |
| AC-M006-02 | Supported: deterministic ranking, slot tie-break, recomputation on lineup change |
| AC-M006-03 | Partially supported: classification semantics tested; production separation proven by dormancy |
| AC-M006-35 | Supported for the helper: teammate-dependent reclassification |
| AC-M006-36 | Not yet applicable; actors untouched and proven unchanged by the full suite |
| AC-M006-37 | Partially supported: helper adds no draw and no schema change; the full AC spans T01–T04 |

Every matrix row remains **NOT RUN** until activation evidence exists.

## 8. Remaining limitations

- The helper is not wired; role multipliers, zone preferences and version 7 do not exist yet.
- No statistical evidence, calibration or realism claim.
- Reclassification is proven at the helper level, not yet inside a simulated ledger.
- T02–T06, activation, fixtures and cohorts remain unauthorized.
