# M006-T03 — Implementation Evidence: Dormant Derived Shot Preferences

> **Status:** T03 evidence only. M006 is **not** accepted; T04–T06 are not authorized.
> **Baseline:** T02 evidence commit `5c4558318fe1602019d56d19b300ead5c7cdc09d`
> (`impl/m006-t02-opportunity`); frozen M006 `d5f9f7d16372cb523f149d3536d972ed5f83e36b`.
> **Implementation commit:** `b00ca3183a38ea02657670bdf152da780b1212ef`
> (`impl/m006-t03-shot-preferences`).
> **Protected branches unchanged:** `develop/m002` `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`;
> `main` `a431aeb5a652b134ce40cf442c7d9ffee874fe79`.

## 1. Scope implemented

Only DD-M006-03 (piecewise three-point willingness) and the T03 halves of DD-M006-08 and
DD-M006-09: a pure, deterministic, dormant shot-preference policy. No activation, no call-site
change, no version bump, no fixture, no UI, no cohort, and no change to shooting accuracy.

## 2. Changed files

| File | Change |
|---|---|
| `packages/simulation_core/lib/src/simulation/shot_preference.dart` | New policy: `DerivedShotPreference` |
| `packages/simulation_core/lib/src/simulation/probability_model.dart` | Behaviour-preserving extraction of `rawShotZoneWeights`; new `rawThreePointWeight`; `_threePointBaseWeight` / `_minimumZoneWeight` constants |
| `packages/simulation_core/lib/simulation_core.dart` | One export line |
| `packages/simulation_core/test/simulation/m006_t03_shot_preference_test.dart` | 33 focused tests |
| `packages/simulation_core/test/domain_isolation_test.dart` | One dormancy source-scan test (Chrome-excluded IO test) |

No frozen specification, fixture, version constant, `GameInput`, `Player` schema, rotation policy,
`GameSimulator` or UI file changed.

## 3. Exact formula

```text
ability(p) = 70 × (p − 50)   when p < 50
           = 30 × (p − 50)   when p ≥ 50          # continuous at p = 50 (both 0)

threeRaw = max(200, 3600 + ability(threePoint) + slotThree[occupiedSlot] + phaseThree[phase])

insideRaw   = v6 formula, unchanged
midrangeRaw = v6 formula, unchanged
weights     = [insideRaw, midrangeRaw, threeRaw] normalised once to 10000
```

- `slotThree` (PG→C): `250, 350, 200, -400, -900`; `phaseThree` (transition, early, half-court):
  `-400, 0, 200`. Unchanged from v6.
- Integer arithmetic only; `ability` is `70/30` scaling of a `p − 50` delta, never a float.
- The ability curve is applied to the three-point rating only. `shotMakeBasisPoints` still uses its
  own `(threePoint − 50) × 40` conversion term and is untouched.
- Normalisation is `BasketballProbabilityModel.normalizeBasisPointWeights`, i.e. the model's existing
  proportional convention (floor share, remainder to the last positive slot). No second convention.
- `threeRaw` is computed from ratings, never from already-normalised v6 weights.

## 4. Raw and normalized vectors (no draws)

Half-court, `[inside, midrange, three]`:

| Archetype (slot) | Attributes I/M/T/ath | raw v6 | raw v7 | normalized v6 | normalized v7 |
|---|---|---|---|---|---|
| Weak PG | 40/45/30, 55 | 1530/2570/3570 | 1530/2570/2650 | 1994/3350/4656 | 2266/3807/3927 |
| Weak SG | 45/50/35, 60 | 1840/2800/3790 | 1840/2800/3100 | 2182/3321/4497 | 2377/3617/4006 |
| Non-shooting C | 80/35/20, 65 | 3810/1910/2180 | 3810/1910/800 | 4822/2417/2761 | 5843/2929/1228 |
| High-three C | 75/55/80, 60 | 3650/2430/3620 | 3650/2430/3800 | 3762/2505/3733 | 3694/2459/3847 |
| High-three F (PF) | 70/65/78, 65 | 3290/2990/4072 | 3290/2990/4240 | 3178/2888/3934 | 3127/2842/4031 |
| Median SF | 50/50/50, 50 | 2100/2750/4000 | 2100/2750/4000 | 2372/3107/4521 | 2372/3107/4521 |

Normalized three shares (basis points, then rounded display): 39.27 %, 40.06 %, 12.28 %, 38.47 %,
40.31 %, 45.21 %. All six reproduce the frozen audit table to its displayed precision
(39.3 / 40.1 / 12.3 / 38.5 / 40.3 / 45.2).

Transition phase:

| Archetype | raw v6 | raw v7 | normalized v6 | normalized v7 |
|---|---|---|---|---|
| Weak PG | 2530/2170/2970 | 2530/2170/2050 | 3298/2829/3873 | 3748/3214/3038 |
| Weak SG | 2840/2400/3190 | 2840/2400/2500 | 3368/2846/3786 | 3669/3100/3231 |
| Non-shooting C | 4810/1510/1580 | 4810/1510/200 | 6088/1911/2001 | 7377/2315/308 |
| High-three C | 4650/2030/3020 | 4650/2030/3200 | 4793/2092/3115 | 4706/2054/3240 |
| High-three F | 4290/2590/3472 | 4290/2590/3640 | 4144/2501/3355 | 4077/2461/3462 |
| Median SF | 3100/2350/3400 | 3100/2350/3400 | 3502/2655/3843 | 3502/2655/3843 |

Early phase:

| Archetype | raw v6 | raw v7 | normalized v6 | normalized v7 |
|---|---|---|---|---|
| Weak PG | 1830/2470/3370 | 1830/2470/2450 | 2385/3220/4395 | 2711/3659/3630 |
| Weak SG | 2140/2700/3590 | 2140/2700/2900 | 2538/3202/4260 | 2764/3488/3748 |
| Non-shooting C | 4110/1810/1980 | 4110/1810/600 | 5202/2291/2507 | 6303/2776/921 |
| High-three C | 3950/2330/3420 | 3950/2330/3600 | 4072/2402/3526 | 3997/2358/3645 |
| High-three F | 3590/2890/3872 | 3590/2890/4040 | 3467/2791/3742 | 3412/2747/3841 |
| Median SF | 2400/2650/3800 | 2400/2650/3800 | 2711/2994/4295 | 2711/2994/4295 |

Boundary and floor vectors:

| Case | Result |
|---|---|
| `ability(0/1/25/49/50/51/75/100)` | `−3500/−3430/−1750/−70/0/30/750/1500` |
| C, `threePoint = 0`, half-court | `threeRaw = 200` (unfloored value would be −600) |
| C, `threePoint = 0`, half-court normalized | `5454/4181/365` — floor is not a ban |
| C, `threePoint = 100`, half-court | `threeRaw = 4400` |
| PG, `threePoint = 100`, half-court | `threeRaw = 5550` |
| Same SF, `threePoint = 70`: slot 0 vs slot 3 | `4650` vs `4000` (bonus Δ 650) |

**Specification cross-check note (no goalpost moving).** The frozen half-court audit and phase check
for both stretch-big rows reproduce exactly. The frozen phase-check line's two below-50 v7 values do
not: it states weak PG early `39.9 %` and non-shooting C early `16.9 %`, while the frozen formula with
the approved 70 slope yields `36.30 %` and `9.21 %`. Those two figures are reproducible with a
50-slope curve instead, i.e. they are a stale earlier-draft residual that was not updated when the
owner approved the 70/30 split. The six half-court values — the numbers the acceptance criteria use —
reproduce exactly with 70/30. No frozen file was edited; the discrepancy is recorded here as a
documentation defect for the owner.

## 5. Tests, counts and results

| Gate | T02 baseline | T03 | Delta |
|---|---|---|---|
| `dart analyze` (core) | clean | clean | 0 |
| `dart format --set-exit-if-changed lib test` | 82 files, 0 changed | 84 files, 0 changed | +2 files |
| `dart test` (core VM) | 571 passed / 0 failed | **605 passed / 0 failed** | +34 (33 policy + 1 scan) |
| Chrome-compatible core suite (`-p chrome`, documented file list, IO test excluded) | 570 passed / 0 failed | **603 passed / 0 failed** | +33 |
| `flutter analyze` | clean | clean | 0 |
| `flutter test` | 111 passed / 0 failed | **111 passed / 0 failed** | 0 |

Environment: Dart SDK 3.12.2, Flutter tooling from the same SDK, Windows x64. Excluded from the
Chrome run: `test/domain_isolation_test.dart` (uses `dart:io`), exactly as documented in
`verification-plan.md` §6. No source was modified during testing.

## 6. Ability / preference separation proof

Fixed lineup and defender; zone-specific conversion and the non-shot coefficients are pinned by
literal and re-asserted after calling the whole preference API:

| Coefficient (fixed fixture) | Pinned value | After preference calls |
|---|---|---|
| `shotMakeBasisPoints` three / midrange / inside | 3844 / 4304 / 6280 | identical |
| `freeThrowMakeBasisPoints` | 8080 | identical |
| `assistBasisPoints` | 5664 | identical |
| `blockBasisPoints` (three) | 180 | identical |
| `andOneBasisPoints` | 256 | identical |
| `shootingFoulBasisPoints` | 878 | identical |

- Moving the same shooter from the PG slot to the PF slot changes the normalized three weight
  (5139 → 4302) and leaves `shotMakeBasisPoints` byte-identical: slot is a preference input only.
- A higher three-point rating raises the three weight (rating 25 < rating 95) — that is willingness.
  It also raises the make probability through the pre-existing `(rating − 50) × 40` conversion term;
  the policy neither reads nor writes that term.
- Free throw, foul, assist and block formulas were not touched; the only production edit is the
  extracted raw zone vector and two constants that carry the identical values (`3600`, `200`).
- No `Player` field, no snapshot, no new randomized decision stage, no draw-order change.

## 7. Dormancy proof

- `grep -rn "DerivedShotPreference" lib | grep -v shot_preference.dart` → **no matches**.
- `rawThreePointWeight` is referenced only by `shot_preference.dart`; production
  `_shotZoneWeightsForSlot` calls only `rawShotZoneWeights`, the extracted **v6** formula.
- `selectAction`, `selectFinalTickAction`, `_selectShot`, `shotUsageWeights` and
  `_shotZoneWeightsForSlot` are unchanged in behaviour; `shotZoneWeights` still returns the pinned v6
  reference vectors for all six archetypes and all three phases.
- New source-scan test (`domain_isolation_test.dart`) fails if any of `OffensiveRoleRanking`,
  `OffensiveOpportunity` or `DerivedShotPreference` appears in `lib/src` outside its own file. T01 and
  T02 therefore remain dormant as well. The test is removed at T04, as `tasks.md` requires.
- The policy consumes no randomness: `rng.drawCount` is unchanged across repeated policy calls, and
  repeated calls return identical vectors.

## 8. Version and fixture preservation

- `gameSimulationVersion` 6, `gameFingerprintVersion` 4; rules 3, event schema 3, duration model 2,
  PRNG `xorshift32-v1` — all unchanged (no version file touched).
- No fixture file and no canonical-ledger file changed (`git status` shows none); the pinned v6
  canonical fixture, the historical digest tests and the no-plan equivalence tests pass inside the
  full suite.
- No expectation was rebaselined to hide a regression.

## 9. Acceptance-criteria support (none marked PASS)

| AC | Support |
|---|---|
| AC-M006-04 | Supported for T03: production weights equal the pinned v6 vectors and the source scan finds no production call site |
| AC-M006-10 | Supported: piecewise 70/30 three weight; inside/midrange raw terms asserted equal to the v6 terms for every archetype and phase |
| AC-M006-11 | Supported: 39.27 % ≤ 40.0 %, 40.06 % ≤ 41.0 %, 12.28 % ≤ 15.0 %, median SF identical to v6 (Δ 0 bp) |
| AC-M006-12 | Supported: high-three C 38.47 % ≥ 36.0 %, high-three F 40.31 % ≥ 39.0 %; `threePoint = 0` still yields raw 200 and a positive normalized share — no ban, no role gate |
| AC-M006-13 | Supported: no new draws; every per-branch draw count unchanged (existing draw-order and canonical-ledger tests green) |
| AC-M006-34 | Supported: preference changes zone weights only; make, free-throw, foul, assist and block coefficients pinned and identical |
| AC-M006-37 | Partially supported: no new draw stage, no schema or snapshot change |

All matrix rows remain **NOT RUN** until activation evidence exists.

### T02 acceptance-criterion mapping correction (T02 report not rewritten)

The historical `t02-implementation-evidence.md` §8 cites the wrong matrix rows. Corrected mapping,
recorded here without editing the frozen matrix or the historical report:

- T02 principally supports **AC-M006-07**, **AC-M006-08**, **AC-M006-09** and **AC-M006-33**.
- **AC-M006-06** concerns v5/v6 ledger rejection by the v7 reader at T04 and must not be claimed as a
  T02 result.

## 10. Remaining risks

- The policy is dormant: no simulated ledger exercises it, so no gameplay or calibration claim exists.
- Two below-50 early-phase reference figures in the frozen spec disagree with the frozen formula
  (§4). The owner should correct the spec text at the next approved amendment; no criterion depends
  on them.
- A weak-everywhere shooter still takes ~36–39 % of shots from three (frozen residual, DD-M006-03);
  the three-point floor of 200 keeps a non-shooter at ~3–12 % depending on slot and phase.
- The extracted `rawShotZoneWeights` is a production-file refactor of a hot path; it is proven
  byte-equivalent by the pinned v6 vectors, the normalisation-identity test and the full suite.
- T04 must switch three call sites, bump simulation 7 / fingerprint 5 and pin v7 fixtures in one
  commit; the source-scan test must be removed in that same commit.

## 11. Readiness for T04

T03 is complete and verified: dormant, deterministic, draw-free, version-neutral, with all six frozen
audit vectors reproduced exactly and no production behaviour change. T04 activation is ready **for
owner authorization**; it is not authorized by this report. One documentation defect (§4 phase-check
line) should be acknowledged by the owner before activation, since activation fixes the observable
behaviour that the stale figures describe.
