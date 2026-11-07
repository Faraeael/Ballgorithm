# M006-T02 — Implementation Evidence: Dormant Opportunity Weights

> **Status:** T02 evidence only. M006 is **not** accepted; T03–T06 are not authorized.
> **Baseline:** T01 evidence commit `8ca330e5277302ff001c55a9f8eb7f52e5356be1`
> (`impl/m006-t01-role-ranking`); frozen M006 `d5f9f7d16372cb523f149d3536d972ed5f83e36b`.
> **Implementation commit:** `283f4c57cd3b15a17c315bacb2b7b74d749a716e`
> (`impl/m006-t02-opportunity`).
> **Protected branches unchanged:** `develop/m002` `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`;
> `main` `a431aeb5a652b134ce40cf442c7d9ffee874fe79`.

## 1. Scope implemented

Only DD-M006-02 and the T02 half of DD-M006-08: a pure, deterministic, dormant opportunity-weight
policy. No activation, no zone policy, no version bump, no fixtures, no UI, no cohort.

## 2. Changed files

| File | Change |
|---|---|
| `packages/simulation_core/lib/src/simulation/offensive_opportunity.dart` | New policy: `OffensiveOpportunity` |
| `packages/simulation_core/lib/src/simulation/probability_model.dart` | Behaviour-preserving extraction of `rawShotUsageWeights`; `shotUsageWeights` now normalises it; new `normalizeBasisPointWeights` |
| `packages/simulation_core/lib/src/simulation/game_validation.dart` | New typed code `roleAssignmentMismatch` |
| `packages/simulation_core/lib/simulation_core.dart` | One export line |
| `packages/simulation_core/test/simulation/m006_t02_opportunity_test.dart` | 13 focused tests |

No frozen specification, fixture, version constant, `GameInput`, `Player` schema or UI file changed.

## 3. Function contract

```text
multipliers: primary 13500 bp, secondary 11500 bp, neutral 10000 bp
adjustedUsageWeights(activeLineup, roles):
  raw  = model.rawShotUsageWeights(activeLineup)        # v6 formula, canonical slot order
  weighted[i] = raw[i] × multiplierFor(roles.roleOf(player_i))
  return model.normalizeBasisPointWeights(weighted)     # proportional, sum exactly 10000
```

- `applyRoleMultipliers(rawUsageWeights, activeLineup, roles)` exposes the multiplier step for
  independent tests; it still validates alignment and requires exactly five raw weights.
- Exact integer arithmetic; multipliers are applied to the **raw** vector, not to an
  already-normalised one; normalisation runs exactly once, through the model's own convention.
- Output is in canonical court-slot order, not creation-rank order.
- Pure: consumes no randomness, mutates no input, holds no state.
- Dormant: no production path imports or calls it.

## 4. Input-alignment guarantees

`adjustedUsageWeights` rejects a role assignment that does not describe exactly the active five:
wrong length, duplicate ids, unknown ids or a different player set throw `GameValidationException`
with `GameValidationCode.roleAssignmentMismatch` at `roles.ranking`. A raw vector whose length differs
from five throws the same code at `rawUsageWeights`. T01's `roleOf` neutral fallback therefore cannot
silently mask mismatched inputs inside T02. No T01 correction was required.

## 5. Multiplier vector and normalisation proof

Equal raw weights `[100,100,100,100,100]` with primary/secondary/neutral ranking produce:

```text
weighted = [13500, 11500, 10000, 10000, 10000] × 100
normalised = [2454, 2090, 1818, 1818, 1820]   sum = 10000
```

The test asserts that exact vector. The earlier layers were already proportional; applying the
multipliers to raw values (not to normalised shares) keeps the ratio exact before the single
normalisation.

## 6. Baseline comparisons

| Gate | T01 baseline | T02 | Delta |
|---|---|---|---|
| `dart analyze` (core) | clean | clean | 0 |
| `dart format --set-exit-if-changed lib test` | 80 files, 0 changed | 82 files, 0 changed | +2 files |
| `dart test` (core VM) | 558 passed / 0 failed | **571 passed / 0 failed** | +13 |
| Chrome-compatible core suite (IO test excluded) | 557 passed / 0 failed | **570 passed / 0 failed** | +13 |
| `flutter analyze` | clean | clean | 0 |
| `flutter test` | 111 passed / 0 failed | 111 passed / 0 failed | 0 |

Version constants remain `gameSimulationVersion` 6 and `gameFingerprintVersion` 4; rules 3, event
schema 3, duration model 2, PRNG `xorshift32-v1`. No fixture file changed; every historical digest
and canonical byte test remains green.

## 7. Dormancy proof

- `grep -rn "offensive_opportunity\|OffensiveOpportunity" lib/src --include=*.dart` outside the
  policy file returns **no matches**.
- `selectAction`, `selectFinalTickAction`, `_selectShot`, `shotUsageWeights`,
  `_shotZoneWeightsForSlot` and `shotMakeBasisPoints` keep their v6 behaviour; the only model change
  is the extracted raw formula, and `shotUsageWeights` still returns exactly the same vector (tested
  and pinned by the full suite).
- Tests assert zero PRNG draws, unchanged inputs, and unchanged zone make probability after calling
  the policy.
- Full v6 suite, including the pinned canonical fixture and no-plan equivalence, passes unchanged.

## 8. Acceptance-criteria support (none marked PASS)

| AC | Support |
|---|---|
| AC-M006-06 | Supported: multipliers applied before normalisation, sum exactly 10000, slot order preserved |
| AC-M006-07 | Supported: roster-insertion independence and exact incremental weighting |
| AC-M006-09 | Supported: neutral multiplier is exactly 1.0; no multiplier below 1.0 |
| AC-M006-33 | Supported for the policy: opportunity change leaves zone make probability unchanged |
| AC-M006-36 | Not yet applicable; actor paths untouched and proven by the unchanged suite |
| AC-M006-37 | Partially supported: no draws added; no schema change |

All matrix rows remain **NOT RUN** until activation evidence exists.

## 9. Remaining risks

- The policy is dormant; no simulated ledger yet exercises role-adjusted usage.
- The extracted raw usage function is a production file change: mitigated by the identical formula,
  full-suite fixture pins and the explicit normalisation-identity test.
- `roleAssignmentMismatch` is a new public validation code; no existing code path emits it.
- T03 zone preferences, activation, versioning and cohorts remain unauthorized.
