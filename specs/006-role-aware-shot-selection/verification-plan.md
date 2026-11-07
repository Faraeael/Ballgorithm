# Verification Plan 006 — Role-Aware Shot Selection v1 (DRAFT)

> **Status: DRAFT — nothing here has been run.** Baseline `develop/m002`
> `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`.

## 1. Test layers

| Layer | Purpose | Examples |
|---|---|---|
| Contract | Role derivation, version boundary | Ranking determinism, tie-break, atomic version bump, v6 rejection |
| Weight unit | Usage and zone policy | Multipliers, normalisation, piecewise curve, floors, shuffled input equality |
| Determinism | Repeatability and parity | Repeat-run byte identity, Dart VM/Chrome equality, draw-order audit |
| Simulator | Ledger integrity | Reducer acceptance, accounting conservation, no new event types |
| Fixtures | Versioned evidence | New v7 digest; v1–v6 preserved byte-for-byte |
| Metrics | Decision evidence | FGA, per-36 attempts, 3PA share by ability bucket, role shares |
| Comparison | Policy attribution | Paired usage-only, zone-only and both-policy runs on identical seeds |
| Owner review | Directional judgment | Weak shooter, primary creator, stretch-big box scores |

## 2. Controlled archetypes

The generated league may contain no genuine stretch-five. Verification must therefore construct
deterministic synthetic rosters with fixed attributes (for example: a 20-`threePoint` centre, a
35-`threePoint` guard, an 80-`threePoint` forward, an 85-`threePoint` centre on separate lineups),
build a valid league around them through the existing validation path, and rerun the same seed.
Construction rules, attribute values and lineups are committed with the tests so the fixture is
reproducible; M001 generation and its vectors are never modified.

## 3. Metrics (ledger-derived unless stated)

- FGA per player and per 36 minutes of ledger-derived playing time.
- 3PA share by `threePoint` bucket (low < 40, mid 40–69, high ≥ 70).
- Low-ability players' perimeter volume; high-ability forwards'/centres' perimeter volume.
- Primary versus secondary role shot share, using the derived ranking only for classification.
- Team 2PA/3PA distribution and points-per-attempt guardrails; no changes to turnover, foul or
  assist coefficients.
- Optional debug observer: inside/midrange choices, test-only, never in canonical output.

## 4. Pre-registered evaluation

Before any cohort run, a protocol file freezes:

1. Metrics and their exact definitions.
2. Development seeds and separate held-out seeds.
3. Directional thresholds and failure conditions per metric.
4. Statistical treatment (paired design, effect sizes, uncertainty, and any multiple-comparison
   adjustment).
5. The decision rule for “directional acceptance”, explicitly not NBA realism.

The protocol commits first; the cohort runs once; results are reported against it without moving
thresholds. A null or contradictory result is a design review trigger, not a license to tune
post-hoc.

## 5. Determinism commands

```powershell
# Core package
cd packages/simulation_core
dart pub get
dart analyze
dart format --set-exit-if-changed lib test
dart test
# Chrome-compatible core suite, IO-only isolation test excluded and recorded
dart test -p chrome test/deterministic_random_test.dart test/generator_test.dart `
  test/validation_test.dart test/simulation

# App
cd ..\..
flutter analyze
flutter test
```

## 6. Failure conditions

- Any new random draw, altered per-branch draw order, or schema change outside the approved design.
- Any v1–v6 fixture modified.
- Stretch-big perimeter volume collapsing toward zero.
- Weak-shooter perimeter volume not materially reduced.
- Repeat-run or VM/Chrome divergence.
- A cohort executed before the protocol commit.

## 7. Evidence artefacts

Draft design package (this directory); later, the pre-registration commit, metric reports, v7 fixture
digest, parity commands and the owner review record. No artefact may be labelled accepted before the
owner decision.
