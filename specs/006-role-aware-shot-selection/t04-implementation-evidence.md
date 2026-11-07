# M006-T04 — Implementation Evidence: Offensive Shot Selection Activation

> **Status:** T04 evidence only. M006 is **not** accepted. T05–T06 were not started, no statistical
> cohort ran, and no protected branch was merged.
> **Baseline:** T03 evidence commit `681e0a46bf4bc06e5921df2a9315be6203e280a8`
> (`impl/m006-t03-shot-preferences`); frozen M006 `d5f9f7d16372cb523f149d3536d972ed5f83e36b`.
> **Branch:** `impl/m006-t04-activation`.
> **Protected branches unchanged:** `develop/m002` `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`;
> `main` `a431aeb5a652b134ce40cf442c7d9ffee874fe79`.

## 1. Commits and changed files

| Commit | Content |
|---|---|
| `cd20d84bca59fd04d18676f30025fd47baec28ce` | `docs(m006-t04)`: specification erratum for the two stale phase-check figures |
| `4e3453d0b9c152b81d7462f7f85885165a4b3309` | `feat(m006-t04)`: activation, atomic 7/5 version bump, test migration, v7 fixture |

Changed files in the activation commit:

| File | Change |
|---|---|
| `packages/simulation_core/lib/src/simulation/game_versions.dart` | simulation 7, fingerprint 5; rules 3, schema 3, duration 2 unchanged |
| `packages/simulation_core/lib/src/simulation/basis_point_weights.dart` | **new**: the model's normalisation moved here so policies and the model share one convention without an import cycle |
| `packages/simulation_core/lib/src/simulation/shot_preference.dart` | owns the zone tables and the full zone policy: piecewise three curve, v6 inside/midrange terms, 200 floor, one normalisation |
| `packages/simulation_core/lib/src/simulation/offensive_opportunity.dart` | takes the raw usage vector explicitly; keeps the 1.35/1.15/1.00 multipliers and alignment validation; normalises once |
| `packages/simulation_core/lib/src/simulation/probability_model.dart` | `shotUsageWeights` = role-adjusted policy output; `_shotZoneWeightsForSlot` = derived-preference policy; v6 zone tables, extracted raw zone statics and the private normaliser deleted |
| `packages/simulation_core/lib/src/simulation/offensive_role.dart` | doc only: no longer "dormant" |
| `packages/simulation_core/test/simulation/t04_v7_canonical_fixture.dart` | **new**: canonical v7 ledger (823 events) |
| `packages/simulation_core/test/simulation/t04_v7_fixture_test.dart` | **new**: digest, repeat identity, replay/minutes, links, mutation matrix, no-plan determinism, typed v5/v6 rejection |
| `packages/simulation_core/test/simulation/m006_t04_activation_test.dart` | **new**: 7 controlled activation tests |
| `packages/simulation_core/test/simulation/t04_v6_fixture_test.dart` | trimmed to archive-only (bytes, digest, header, event count) |
| `packages/simulation_core/test/domain_isolation_test.dart` | T01–T03 dormancy scan removed; framework/persistence scan kept |
| `packages/simulation_core/test/simulation/{game_input_test,turnover_nonsteal_test,t012_canonical_ledger_test}.dart` | fingerprint/version re-pins, historical v5 comparisons retired |
| `packages/simulation_core/test/simulation/{t013_adversarial_game_test,t03_contract_test,t03_rotation_simulation_test}.dart` | current-engine baselines migrated to v7; overtime scenario seed migrated |
| `packages/simulation_core/test/simulation/{m001_regression_test,t01_rotation_plan_test,t07_canonical_participation_test}.dart` | version identifiers 7 / 5 |
| `packages/simulation_core/test/simulation/{m006_t01_offensive_role_test,m006_t02_opportunity_test,m006_t03_shot_preference_test}.dart` | dormant-policy tests migrated to the activated contract |
| `test/game_participation_test.dart` | final-horn scenario seed migrated (`20098` → `5290`); predicate unchanged |
| `specs/006-role-aware-shot-selection/t04-specification-erratum-phase-check.md` | erratum |

No `GameSimulator`, `GameInput`, event schema, reducer, rotation policy, Flutter UI or M001 file was
changed. No legacy simulator or feature flag exists.

## 2. Activated policy architecture

```text
_selectShot(offense, defense, phase, rng)
  shooter  = pickWeighted(rng, shotUsageWeights(lineup))          # 1 draw, unchanged
             shotUsageWeights = adjustedUsageWeights(
                 rawUsageWeights: rawShotUsageWeights(lineup),
                 roles: OffensiveRoleRanking.derive(lineup))     # 1.35/1.15/1.00, sum 10000
  slot     = lineup.slotIndexForPlayer(shooter)
  zones    = _shotZoneWeightsForSlot(shooter, slot, phase)        # derived preference
  zoneDraw = rng.nextInt(10000)                                   # 1 draw, unchanged
  make     = shotMakeBasisPoints(...)                             # unchanged coefficients
  ... existing foul / assist / block draws unchanged
```

- `selectAction` still draws category before the shot branch; `selectFinalTickAction` still skips the
  A1 and category draws and calls `_selectShot` directly. Both therefore use the activated policies.
- Roles are recomputed from the active five on every shot-selection call, so substitutions are picked
  up without any persisted state.
- `OffensiveOpportunity.adjustedUsageWeights` is the only multiplier step; multipliers apply to the
  raw vector, never to an already-normalised one.

## 3. Version boundary (atomic)

| Constant | Before | After |
|---|---|---|
| `gameSimulationVersion` | 6 | **7** |
| `gameFingerprintVersion` | 4 | **5** |
| `gameRulesVersion` | 3 | 3 |
| `gameEventSchemaVersion` | 3 | 3 |
| `gameActionDurationModelVersion` | 2 | 2 |
| PRNG | `xorshift32-v1` | `xorshift32-v1` |
| `coreEngineVersion` / `snapshotSchemaVersion` | 1.0.0 / 1 | unchanged |

The v7 canonical fixture header records `gameSimulationVersion: 7` and the ledger builder rejects
simulation 5 and 6 ledgers with `unsupportedSimulationVersion` (never a schema error).

## 4. Historical fixture preservation

- v1–v6 fixture files are byte-identical; no fixture file was edited. `t04_v6_canonical_fixture.dart`
  keeps SHA-256 `7f0c3d2962f05a66ff54ad42b3a8d53059871ceca31ac1402cbc5c14e024aa12`.
- `t04_v6_fixture_test.dart` now asserts only that archived digest, header and event count. Its
  reproduction, replay, link and mutation coverage moved to the v7 fixture, as
  `verification-plan.md` §2 requires.
- `t012` keeps the archived v5 digest `3ba26e3d…` and its typed rejection by the current reader.
- Retired to the checkpoint (not rebaselined): the v5 fixture event prefix, the v4/v5 published seed
  digests, and the pre-M006 seed-15 event array and fingerprint. Each retired value is named in the
  test comment where it used to live.

## 5. M005 checkpoint verification (`68018db98cd033b3008513ff7e6d174eaa81f09f`)

Executed once in a detached read-only worktree (`git worktree add … 68018db`), removed afterwards.
`dart pub get` + `dart test`:

| Test file | Result |
|---|---|
| `t04_v6_fixture_test.dart` | 17/17 pass — v6 digest `7f0c3d29…`, fingerprint `493b7c4f…`, 804 events, 95–93, 26 tactical substitutions, minutes oracle and mutation matrix reproduce |
| `t012_canonical_ledger_test.dart` | 12/12 pass — seed-42 v6 fingerprint `05e56d11…`, v5 digest `3ba26e3d…`, published seed digests reproduce |
| `t03_contract_test.dart`, `game_input_test.dart`, `turnover_nonsteal_test.dart` | 42/42 pass in one run — seed-15 pre-M006 fingerprint `e3713d92…`, event array `7a82d20e…`, 839 events, v6 fingerprint `05e56d11…` |

Combined: **71/71 tests pass** at the accepted M005 commit (29 fixture + 42 participation), which
proves the archived v6/v5 material was generated by that engine and not by this one.

## 6. New v7 canonical fixture

`test/simulation/t04_v7_canonical_fixture.dart`; input unchanged from the v6 fixture (league seed
20261028, team-1 vs team-2, default lineups, balanced plans, game seed 42, `GameRules.standard`):

| Field | Value |
|---|---|
| `inputFingerprint` | `d1b4b98d8b1042f2aebac4271825d20a43f53d12abb3213c4c0341f36fb66538` |
| ledger SHA-256 | `3e2eab7c01d7ece322dc5c7954fe08f71bc2baeb66be910981b09dac2e8a39ce` |
| events | 823 |
| substitutions | 25 (24 tactical, 1 foul-out) |
| score | home 108 – away 89, 4 periods |
| periods | home 34/23/27/24, away 18/24/20/27 |
| first substitution | sequence 82, period 1, clock 456, team-1, `player-1-1` → `player-1-7` |

Verified: five repeat runs byte-identical; reducer validation ends the game; accounting conserves
points and 5 × 4 × 720 team-seconds; substitution intervals reconcile against an independent minutes
oracle; free-throw groups, and-one links, rebound sources, turnover reasons, possession nesting and
the monotonic clock all hold; the eight-case mutation matrix rejects with the expected typed codes.

Null-plan input (same seed, no rotation plan): fingerprint `f60d9aa9…`, ledger digest `db38c685…`,
805 events, 104–106, two foul-out substitutions, no tactical rotation decisions, byte-identical on
repeat.

## 7. Controlled basketball behaviour evidence

`m006_t04_activation_test.dart` (7 tests) plus the migrated `m006_t03` vectors:

| Case | Result |
|---|---|
| Weak PG + elite creator wing | creator is primary; his normalised share exceeds his raw share; the neutral weak guard's share is diluted, never zero |
| Weak PG + creator centre | centre is primary and out-weighs the weak guard |
| Neutral-ranked elite scorer | rank stays neutral; raw weight unchanged; normalised share positive; no multiplier below 1.0 |
| Substitution | replacing the creator moves the primary multiplier to the bench creator (`after[0] > before[0]`, sum 10000) |
| Non-shooting C (80/35/20) | half-court three 12.28 % |
| Stretch C (75/55/80) | 38.47 % |
| High-three PFC-forward (70/65/78 at PF) | 40.31 % |
| Median SF (50/50/50) | 45.21 %, identical to v6 |
| Final-tick draw path | with seed 20261107 the actor and zone draws map exactly onto the role-adjusted usage vector and the derived zone weights |
| Shot success | conversion, free-throw, foul, assist and block coefficients identical to the T03 pins; zone preference changes never touch them |

## 8. PRNG draw-order audit

| Path | Draws before | Draws after | Change |
|---|---|---|---|
| `selectAction` | category, actor, then per-branch draws | same | none |
| `selectFinalTickAction` | actor, zone, make, foul, assist/block | same | none |
| `_selectShot` | actor, zone, make, foul, assist/block | same | none |
| `shotUsageWeights` | 0 | 0 | weight calculation only |
| `_shotZoneWeightsForSlot` | 0 | 0 | weight calculation only |
| `shotMakeBasisPoints` | 0 | 0 | unchanged formula |
| Turnover / offensive-foul / non-shooting-foul actor | separate `_ballHandlerScore` draw | same | none |

`git diff` of `lib/` adds no `rng.` call and no `nextInt`; `selectAction`, `selectFinalTickAction`,
`_selectShot`, `_pickWeighted`, `_pickWeightedIndex` and every conversion/foul/assist/block formula
are untouched. No new event type or schema field exists; no role, tendency or multiplier is persisted.

## 9. Regression results (Dart SDK 3.12.2, Windows x64, no source edits during runs)

| Gate | T03 baseline | T04 | Delta |
|---|---|---|---|
| `dart analyze` | clean | clean | 0 |
| `dart format --set-exit-if-changed lib test` | 84 files, 0 changed | 88 files, 0 changed | +4 files |
| `dart test` (VM) | 605 passed | **612 passed / 0 failed** | +7 |
| Chrome-compatible suite (`-p chrome`, documented file list, IO test excluded) | 603 passed | **611 passed / 0 failed** | +8 |
| `flutter analyze` | clean | clean | 0 |
| `flutter test` | 111 passed | **111 passed / 0 failed** | 0 |

Count reconciliation: −1 dormancy scan, v6 fixture 17 → 1 archive test (−16), +17 v7 fixture tests,
+7 activation tests → 605 − 17 + 24 = 612 VM. Chrome excludes `domain_isolation_test.dart`, so the
scan removal is not visible there: 603 − 16 + 17 + 7 = 611.

## 10. Acceptance-criteria support (none marked PASS)

| AC | Support |
|---|---|
| AC-M006-04 | Superseded by activation: the dormancy scan is removed, production weights now equal the v7 vectors, and the full suite is green |
| AC-M006-05 | Supported: simulation 7 and fingerprint 5 land in one commit with rules 3, schema 3, duration 2 and `xorshift32-v1` unchanged |
| AC-M006-06 | Supported: v5 and v6 fixtures are rejected with `unsupportedSimulationVersion` and never as schema errors |
| AC-M006-07 | Supported: multiplier ratio changes raw usage; neutral is exactly 1.0 |
| AC-M006-08 | Supported: shuffled roster produces identical weights; raw order is preserved before normalisation |
| AC-M006-09 | Supported: no multiplier below 1.0; a neutral elite scorer keeps his raw weight and only dilutes |
| AC-M006-10–12 | Supported: 70/30 curve, inside/midrange unchanged, thresholds met (39.27 / 40.06 / 12.28 / 38.47 / 40.31 / 45.21 %) |
| AC-M006-13 | Supported: no new draws; per-branch draw counts unchanged |
| AC-M006-14 | Supported: five repeat runs of the pinned input are byte-identical |
| AC-M006-15 | Supported: VM 612 and Chrome 611 pass on the same suite (IO test excluded and recorded) |
| AC-M006-16 | Supported: reducer accepts the v7 ledger; points and minutes conserve |
| AC-M006-17 | Supported: v7 fixture pinned by digest with seed, lineups, plans and header |
| AC-M006-18 | Supported: every v1–v6 fixture file is byte-identical; v6 joins the archive list |
| AC-M006-19 | Supported: v6 generation verified once at `68018db` in a detached worktree (§5) |
| AC-M006-20 | Supported: no-plan mode is deterministic and its v6→v7 difference is recorded, with no byte or draw-count equality claimed |
| AC-M006-32 | Supported: conversion, and-one, shooting-foul, free-throw, assist and block reference vectors identical |
| AC-M006-34 | Supported: preference changes zone selection only |
| AC-M006-36 | Supported: turnover and foul actor paths unchanged in kind and draw |
| AC-M006-37 | Supported: no new draw stage, no `Player` or snapshot change |

T05/T06 rows remain NOT RUN.

## 11. Remaining risks

- **Intentional gameplay change.** Who shoots and from where changed: the pinned fixture moved from
  95–93 to 108–89 and 804 → 823 events. No realism, calibration or balance claim is made; only T05
  metrics and the T06 protocol can speak to basketball realism.
- **Opponent scoring rose.** The away side scored 89 against 93 and the home side 108 against 95 in
  one seed. Single-fixture evidence is not a distribution and must not be read as an effect.
- **Two reference figures were stale.** The erratum corrects them; the freeze text still shows the old
  numbers with a dated correction beside it.
- **Policy ownership moved.** Zone tables and the piecewise curve now live in `shot_preference.dart`;
  the model consumes the policy. The v6 linear formula is deleted, so any future v6 reproduction must
  use the checkpoint (§5), never the current engine.
- **Chrome run excludes** `test/domain_isolation_test.dart` (`dart:io`), as documented.
- **`shotUsageWeights` semantics changed** to the role-adjusted vector; any external caller that
  expected v6 raw-normalised weights must read `rawShotUsageWeights` explicitly.

## 12. T05 readiness

The activated engine is deterministic, versioned, fully migrated and green on VM, Chrome and Flutter,
with a pinned v7 fixture and an audited draw order. T05 instrumentation and metric work can start
**on owner authorization**; no cohort, pilot or held-out seed was touched here.
