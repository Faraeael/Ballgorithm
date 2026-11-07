# Verification Plan 006 — Role-Aware Shot Selection v1 (DRAFT, rev 2)

> **Status: DRAFT — nothing here has been executed.** Revision 2 adds the historical fixture
> migration strategy and quantitative evaluation design. Baseline `develop/m002`
> `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`.

## 1. Test layers

| Layer | Purpose | Examples |
|---|---|---|
| Contract | Role ranking, version boundary | Position-free ranking, tie-break, atomic 7/5 bump, v5/v6 rejection |
| Weight unit | Usage and zone policy | Multipliers, normalisation, piecewise curve, floors, shuffled input equality |
| Determinism | Repeatability and parity | Repeat-run identity, Dart VM/Chrome equality, per-branch draw-order audit |
| Simulator | Ledger integrity | Reducer acceptance, accounting conservation, no new event types |
| Fixtures | Versioned evidence | New v7 digest; v1–v6 archived bytes preserved |
| Metrics | Decision evidence | FGA, per-36 attempts, 3PA share by bucket, role shares at shot time |
| Comparison | Policy attribution | Usage-only, zone-only and both-policy paired runs |
| Owner review | Directional judgment | Weak shooter, creator, stretch-big box scores |

## 2. Historical fixture compatibility (design, not executed)

The v7 weighting change intentionally produces different events. Historical **fixture files** and
their digests are never modified. Historical **generation** assertions are not re-run against the
current engine; they are executed once in a detached read-only worktree at the accepted M005
implementation `68018db98cd033b3008513ff7e6d174eaa81f09f` and recorded, exactly as the M004 v5 replay
was verified at `36bc3597` during T04. The current suite keeps archive-integrity and typed-rejection
coverage and gains a v7 fixture. No second engine is maintained in the product.

| Test (file) | Current behaviour | Proposed revision-3 treatment |
|---|---|---|
| `t04` “pinned bytes, digest and header” | Asserts v6 fixture digest and v6 header | Keep archive digest/header assertions as history; move “current constants” assertions to the v7 fixture test |
| `t04` “the pinned plan reproduces the fixture and repeats exactly” | Re-runs the simulator and compares v6 bytes | Cannot hold under v7. Archive integrity stays; v6 reproduction is verified once at the M005 checkpoint; v7 generation/repeat moves to a new fixture test |
| `t04` “replay validates, completes and reconciles minutes” | Decodes/replays v6 ledger | v7 reader rejects v6, so replay coverage moves to the v7 fixture; v6 replay verified at the checkpoint |
| `t04` “decoded v6 ledger preserves … links” | Link integrity on v6 | Same migration: v7 fixture for current coverage; v6 verified at checkpoint |
| `t04` mutation matrix (8 tests) | Mutates decoded v6 events | Apply the matrix to the v7 ledger; v6 mutation is impossible because decode is rejected |
| `t04` “null-plan event array equals the pinned v5 array” | Current v6 output equals v5 events | Historical only: verify at the M005 checkpoint; current suite asserts v7 no-plan determinism and records the intentional v6→v7 difference |
| `t04` “null plans consume no rotation decisions” | No tactical subs without a plan | Still valid; update version references |
| `t04` “v6 build rejects the v5 fixture …” | Typed rejection | Extend to v5 **and** v6 fixtures rejected with `unsupportedSimulationVersion`; never a schema error |
| `t04` “version identifiers follow the frozen M005 boundary” | 6/4/3/3/2 | Update to the M006 boundary 7/5/3/3/2 |
| `t04` “historical v1–v5 fixture bytes remain parseable and pinned” | Archive parse/digest | Unchanged; add the v6 fixture to the archive list |
| `t012` “seed 42 reproduces the committed golden bytes and digest” | Compares current prefix to v5 fixture; pins v6 fingerprint | Archive digest stays; current-generation prefix comparison is retired to the checkpoint; v7 fixture covers current output; fingerprint re-pinned at implementation time |
| `t012` “the archived v5 golden ledger is rejected by the v6 reader” | Typed rejection | Rename to current reader; expectation unchanged (`unsupportedSimulationVersion`, not schema) |
| `t012` “published seed digests reproduce on this platform” | v6 ledger/event digests for seeds 1, 99, 20261029 | v6 digests retired to the checkpoint record; v7 repeat-run and new v7 digests after implementation |
| `t012` fingerprint identity tests | Pins `05e56d…` (v6) and payload version | Re-pin the v7 fingerprint and version 5; structural assertions unchanged |
| `t012` v1–v3 archive parse test | JSON parse only | Unchanged |
| `t012` raw seed alias | Events equal, fingerprints differ within the current version | Unchanged (no historical bytes) |
| `t03` “version identifiers are the frozen M005 values” | 6/4/3/3/2 | Update to 7/5/3/3/2 |
| `t03` “a v4 ledger header is rejected by the v5 reader” | Schema mutation on a current ledger | Rename to current reader; same typed `unsupportedEventSchemaVersion` expectation |
| `t03` “a no-disqualification game equals the pre-participation baseline” | Pins v6 seed-15 fingerprint and event hash | Historical values verified at the checkpoint; v7 pins in the current suite |
| `t03` “v5 event array matches the pinned v4 baseline exactly” | Fixture-to-fixture only | Unchanged |
| `t07` current-version constants | 6/4 | Update to 7/5; archive markers, digest and v4 prefix digest untouched |
| `m001_regression_test` version cross-check | Expects simulation 6 | Update the cross-check to 7; M001 identifiers stay pinned |
| `game_input_test` / `turnover_nonsteal_test` pinned fingerprint | `05e56d…` (v6) | Re-pin the v7 fingerprint at implementation; structure unchanged |
| `t01_rotation_plan_test` version test | 6/4 | Update to 7/5; null-plan behaviour test unchanged |
| App widget tests | No historical fingerprints pinned | Unchanged; informational T024 prints only |

Rules for the migration: no historical fixture file changes; no silent rebaseline labelled as a fix;
archive tests remain in-tree; checkpoint results are recorded in the M006 evidence; current-version
tests use only v7 artifacts.

## 3. Metrics and denominators

| Metric | Definition | Denominator |
|---|---|---|
| FGA per 36 | `FGA × 2160 / secondsPlayed` per player; rate metrics require `secondsPlayed ≥ 240` | Actual ledger minutes |
| Weak-shooter 3PA share | `Σ 3PA / Σ FGA` for players with `threePoint < 40`, pooled across games and lineups | Field-goal attempts |
| Stretch-big 3PA share | Same formula for `threePoint ≥ 70` at PF/C slots | Field-goal attempts |
| Primary/secondary role share | Pooled FGA by role classification computed at the moment of each shot (lineups replayed from substitutions) | Team FGA |
| Team 3PA distribution | `Σ team 3PA / Σ team FGA`; share of team 3PA taken by `threePoint < 40` players | Team FGA |
| Guardrails | Points/game, eFG, TOV/100, FTA/game, possessions/game, exact accounting conservation | Per-game and per-100-possession |

## 4. Controlled, formula-level acceptance (deterministic, no cohort)

Exact normalized expectations from the audit (half-court):

- Weak PG three share ≤ 40.0% (design 39.3%).
- Weak SG three share ≤ 41.0% (design 40.1%).
- Non-shooting C three share ≤ 15.0% (design 12.3%).
- High-three C ≥ 36.0% (design 38.5%); high-three F ≥ 39.0% (design 40.3%).
- Median shooter within ±1.0 pp of v6 (design 0.0 pp).
- Rank ordering: primary ≥ secondary ≥ neutral usage shares in constructed lineups; creator big
  becomes primary when the nominal guard's creation score is lower.
- Substitution: replacing the creator guard recomputes the ranking and moves the primary share to
  the highest-creation player on court.

These are verified by unit vectors, not by simulation cohorts.

## 5. Empirical evaluation (thresholds OPEN)

Protocol, to be frozen before any cohort:

1. **Seeds.** Development 1–200 for establishing the v6 baseline variance; held-out 10001–10500 for
   the single evaluation run. Weights are frozen before the held-out run.
2. **Design.** Paired by seed between v6 (checkpoint worktree) and v7 on identical inputs. Report
   paired differences per game, means, 95% CIs and effect sizes.
3. **Primary metrics (4, Holm-adjusted).** Weak-shooter pooled 3PA share; stretch-big pooled 3PA
   share (non-inferiority); primary-vs-secondary role share ordering; team 3PA/FGA.
4. **Guardrail metrics.** eFG, points/game, TOV/100, FTA/game; exact accounting and reducer
   validity.
5. **Sample size.** With `n` paired games and per-game difference SD `s`, the 95% CI half-width is
   `1.96·s/√n`. A pilot on the development seeds estimates `s`; the held-out size is chosen so the
   weak-shooter difference CI half-width is ≤ 1.0 pp. If `s ≈ 6 pp`, `n ≈ 140` pairs suffice; the
   proposal is 500 pairs for margin.
6. **Thresholds.** Require ≥ 3 pp absolute reduction for weak-shooter pooled 3PA share and no more
   than 2 pp reduction for stretch-bigs, both with CIs excluding the adverse margin. These numbers
   are **OPEN**: they may only be finalized from the development baseline, never after held-out
   results are seen.

Minimum baseline evidence needed before thresholds can be fixed: v6 development-seed 3PA distribution
by ability bucket, per-game variance of the pooled metric, and the paired-difference SD.

## 6. Commands (when authorized)

```powershell
cd packages/simulation_core
dart pub get
dart analyze
dart format --set-exit-if-changed lib test
dart test
dart test -p chrome test/deterministic_random_test.dart test/generator_test.dart `
  test/validation_test.dart test/simulation

cd ..\..
flutter analyze
flutter test
```

## 7. Failure conditions

- Any new random draw, altered per-branch draw order, or schema change outside the design.
- Any v1–v6 fixture file modified, or a historical assertion silently rebaselined.
- Stretch-big perimeter volume collapsing; weak-shooter reduction failing the controlled bounds.
- Repeat-run or VM/Chrome divergence.
- A cohort executed before the protocol freeze.
