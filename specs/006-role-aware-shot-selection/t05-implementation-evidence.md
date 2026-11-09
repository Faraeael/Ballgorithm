# M006-T05 Implementation Evidence

**Status:** implementation evidence only; owner acceptance not recorded.

- **Task:** M006-T05 — shot decision instrumentation and basketball behavior metrics.
- **Branch:** `impl/m006-t05-shot-metrics`.
- **Base:** T04 `8618885c72b96024c4f8df0857f477790ab06e46`.
- **Frozen specification:** `d5f9f7d16372cb523f149d3536d972ed5f83e36b`.
- **Starting protected refs:** `develop/m002` `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`; `main` `a431aeb5a652b134ce40cf442c7d9ffee874fe79`.
- **Implementation commit:** `b2664f36016c93ff9b508925bd9cbdd9c9c77343`.

## Scope and files

T05 adds passive observation and ledger-derived analysis. It changes no gameplay probability, version, event, player, snapshot, fixture, or M001 generator contract.

Implementation files:

- `packages/simulation_core/lib/simulation_core.dart` — public exports.
- `packages/simulation_core/lib/src/simulation/game_simulator.dart` — optional observer wiring.
- `packages/simulation_core/lib/src/simulation/probability_model.dart` — emits decision observation from existing calculations.
- `packages/simulation_core/lib/src/simulation/shot_decision_trace.dart` — immutable observation value.
- `packages/simulation_core/lib/src/simulation/game_metrics.dart` — deterministic ledger analyzer and metric values.
- `packages/simulation_core/test/simulation/m006_t04_activation_test.dart` — observer identity and policy-weight comparisons, plus controlled archetype tests.
- `packages/simulation_core/test/simulation/game_metrics_test.dart` — ledger totals, role replay, substitution, foul-out, and occupied-slot tests.

Evidence and documentation correction:

- `specs/006-role-aware-shot-selection/t05-implementation-evidence.md` — this record.
- `specs/006-role-aware-shot-selection/t04-evidence-correction-20261109.md` — separately identified correction; historical T04 report remains unchanged.

No historical fixture or canonical v7 fixture file changed. No new dependency. No `Player` field or event schema change. Simulation version remains 7; fingerprint version remains 5.

## Observer contract

`GameSimulator` accepts optional `onShotDecision`. With no callback, execution preserves existing behavior. Each actual field-goal decision reports `ShotDecisionTrace` containing team and shooter IDs; current five-player lineup; primary and secondary creator IDs; shooter role and creation score; raw and role-adjusted usage weights; phase; occupied slot; raw and normalized zone weights; chosen zone; and shot-success basis points.

The trace is immutable. Collection fields are defensive unmodifiable copies. It contains no engine state and is not serialized, persisted, added to events, or hashed into fingerprints. The callback adds no random draw and makes no decision. Observation occurs after the existing success draw. Tests compare observer-off and observer-on event bytes, fingerprint, and final scores for identical input and seed; all match.

## Metrics and denominators

`GameMetricsAnalyzer.analyze` accepts validated `GameResult`. It replays `GameStarted`, `PeriodStarted`, `PeriodEnded`, `Substitution`, `FieldGoalAttempt`, and free-throw events in canonical ledger order. Minutes derive from actual on-court intervals. It does not mutate the result.

- Player points, FGM/FGA, 3PM/3PA, FG%, 3P%, seconds, minutes, and FGA/36. FGA/36 is `FGA × 2160 / secondsPlayed`, defined only at `secondsPlayed >= 240`.
- Rating buckets: `<40`, `40–69`, and `>=70` three-point rating; each reports FGA, 3PA, and pooled `Σ3PA / ΣFGA`. The bucket's share of team threes is `bucket.3PA / team.3PA`.
- Role attempts use the five players actually on court at each `FieldGoalAttempt`, position-free creation ranking, and canonical tie order. Team and player primary/secondary/neutral FGA shares use team/player FGA denominators.
- Stretch big means three-point rating `>=70` while occupying PF or C court slot at shot time. Player and team metrics report FGA and 3PA from qualifying attempts; nominal position does not substitute for occupied slot.
- Team metrics include points, eFG (`(FGM + 0.5 × 3PM) / FGA`), TOV/100 possessions, FTA, 3PA/FGA, possessions, and accounting consistency.
- Zero denominators and insufficient player exposure yield `null` rates, not zero. Rates are ratios, not percentages; reports format them as percentages.

Definitions follow frozen `verification-plan.md` §3. The analyzer cross-checks ledger totals against validated box scores and game result, including points, possessions, player/team shooting, turnovers, and role/bucket conservation.

## Sample canonical v7 game

Generated from the pinned `v7FixtureInput()` with seed 42. The temporary report runner was removed after capturing output. One game is descriptive evidence, not a realism claim or causal estimate.

**Final:** Team 1 108, Team 2 89; four periods; 823 events; 199 total possessions. Accounting consistency: `true`.

| Team | PTS | FG | 2P | 3P | FT | ORB | DRB | REB | AST | TOV | STL | BLK | PF | eFG | TOV/100 | 3PA/FGA | Poss. |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Team 1 | 108 | 44/86 | 33/50 | 11/36 | 9/15 | 11 | 40 | 51 | 25 | 18 | 9 | 2 | 22 | 57.6% | 18.00 | 41.9% | 100 |
| Team 2 | 89 | 32/85 | 23/54 | 9/31 | 16/24 | 17 | 33 | 50 | 20 | 20 | 8 | 1 | 18 | 42.9% | 20.20 | 36.5% | 99 |

### Top five by FGA

| Team | Player | FGA | 3PA/FGA | PTS | Minutes | FGA/36 |
|---|---|---:|---:|---:|---:|---:|
| 1 | Jalen Bellamy | 16 | 8/16 | 18 | 29.1 | 19.81 |
| 1 | Elias Vasquez | 13 | 5/13 | 20 | 33.0 | 14.20 |
| 1 | Jonas Cortez | 12 | 5/12 | 13 | 32.4 | 13.35 |
| 1 | Kellan Valdez | 9 | 2/9 | 10 | 20.8 | 15.60 |
| 1 | Ravi Ibarra | 8 | 4/8 | 10 | 32.0 | 9.00 |
| 2 | Emil Lindqvist | 16 | 3/16 | 17 | 32.0 | 18.00 |
| 2 | Bastian Delacroix | 14 | 4/14 | 14 | 20.5 | 24.57 |
| 2 | Malik Sinclair | 13 | 6/13 | 15 | 33.0 | 14.20 |
| 2 | Kasimir Valdez | 12 | 2/12 | 9 | 29.1 | 14.85 |
| 2 | Oren Dunmore | 8 | 6/8 | 10 | 18.0 | 15.99 |

### Top five scorers

| Team | Player | Points | FGA |
|---|---|---:|---:|
| 1 | Elias Vasquez | 20 | 13 |
| 1 | Jalen Bellamy | 18 | 16 |
| 1 | Tavi Abernathy | 18 | 8 |
| 1 | Jonas Cortez | 13 | 12 |
| 1 | Ravi Ibarra | 10 | 8 |
| 2 | Emil Lindqvist | 17 | 16 |
| 2 | Malik Sinclair | 15 | 13 |
| 2 | Bastian Delacroix | 14 | 14 |
| 2 | Oren Dunmore | 10 | 8 |
| 2 | Kasimir Valdez | 9 | 12 |

### Player shot volume and roles

`P/S/N` means primary/secondary/neutral FGA reconstructed at each shot. All listed minutes and FGA/36 derive from the ledger. `FGA/36` stays eligible because all listed players exceeded 240 seconds.

| Team | Player | PTS | FGM/FGA | 3PM/3PA | 3PA/FGA | Minutes | FGA/36 | P/S/N FGA |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | Jonas Cortez | 13 | 6/12 | 1/5 | 41.7% | 32.4 | 13.35 | 0/0/12 |
| 1 | Jalen Bellamy | 18 | 8/16 | 2/8 | 50.0% | 29.1 | 19.81 | 0/6/10 |
| 1 | Elias Vasquez | 20 | 8/13 | 2/5 | 38.5% | 33.0 | 14.20 | 13/0/0 |
| 1 | Ravi Ibarra | 10 | 4/8 | 2/4 | 50.0% | 32.0 | 9.00 | 0/0/8 |
| 1 | Silas Barlow | 8 | 3/8 | 1/4 | 50.0% | 21.5 | 13.38 | 0/1/7 |
| 1 | Teodor Halloran | 6 | 2/7 | 0/2 | 28.6% | 19.1 | 13.23 | 0/0/7 |
| 1 | Tavi Abernathy | 18 | 6/8 | 2/4 | 50.0% | 24.0 | 12.01 | 2/6/0 |
| 1 | Elias Kovacs | 5 | 2/5 | 1/2 | 40.0% | 28.3 | 6.36 | 0/0/5 |
| 1 | Kellan Valdez | 10 | 5/9 | 0/2 | 22.2% | 20.8 | 15.60 | 5/4/0 |
| 2 | Rafael Calloway | 5 | 2/5 | 1/2 | 40.0% | 32.4 | 5.56 | 0/0/5 |
| 2 | Kasimir Valdez | 9 | 3/12 | 0/2 | 16.7% | 29.1 | 14.85 | 8/0/4 |
| 2 | Bastian Delacroix | 14 | 6/14 | 2/4 | 28.6% | 20.5 | 24.57 | 5/3/6 |
| 2 | Malik Sinclair | 15 | 6/13 | 1/6 | 46.2% | 33.0 | 14.20 | 2/7/4 |
| 2 | Emil Lindqvist | 17 | 6/16 | 1/3 | 18.8% | 32.0 | 18.00 | 0/0/16 |
| 2 | Oren Dunmore | 10 | 3/8 | 2/6 | 75.0% | 18.0 | 15.99 | 8/0/0 |
| 2 | Isandro Sinclair | 7 | 1/4 | 0/2 | 50.0% | 23.4 | 6.15 | 0/0/4 |
| 2 | Ilya Sandoval | 5 | 2/8 | 1/5 | 62.5% | 19.1 | 15.12 | 2/6/0 |
| 2 | Felix Ravensworth | 7 | 3/5 | 1/1 | 20.0% | 32.6 | 5.52 | 0/0/5 |

Team 1 attempt shares: primary 23.3%, secondary 19.8%, neutral 57.0%. Team 2: primary 29.4%, secondary 18.8%, neutral 51.8%. These are pooled shot-time classifications, not starter-only labels.

### Archetype observations and substitutions

- Team 1 weak shooters: 2/5 from three; pooled weak-shooter 3PA/FGA 40.0%. Their 2 3PA are 5.6% of team 36 3PA. Elias Kovacs: 2/5 FGA from three.
- Team 2 weak shooters: 5/28; pooled 17.9%. Their 5 3PA are 16.1% of team 31 3PA. Kasimir Valdez: 2/12; Emil Lindqvist: 3/16.
- Team 1 stretch bigs: no qualifying PF/C occupant; 0 FGA and 0 3PA, ratio undefined.
- Team 2 stretch big occupants: 7 FGA, 3 3PA; pooled 42.9%. Occupied-slot rule applies; nominal player position alone does not qualify.
- The ledger includes 25 substitutions. Observed shot-time role changes include: player-1-2 secondary→neutral (event 113); player-2-3 primary→secondary (170); player-1-5 neutral→secondary (173); player-1-7 secondary→primary (189); player-2-8 primary→secondary (229); player-1-7 primary→secondary (247); player-1-5 secondary→neutral (258); player-2-3 secondary→neutral (271).

Notable caution: Team 2 recorded 42.9% eFG; Bastian Delacroix reached 24.57 FGA/36. The 19-point margin and single-game attempt profiles are suspicious signals to inspect, not realism conclusions. Samples are one game and tiny player archetype buckets.

## Controlled archetypes and policy comparisons

Deterministic fixtures cover weak point guard, elite creator wing, elite scorer with neutral creation rank, non-shooting center, stretch-five center, high-three power forward, and substitution-driven role changes. Position-free creator ranking is tested independently from shooting rating. The metrics tests verify that role assignment changes with current teammates and substitutions, and that stretch-big classification follows occupied PF/C slot rather than nominal position.

Fixed-input policy comparisons are formula-level only:

Half-court fixed-input zone comparisons. Vectors list `[inside, midrange, three]` basis points; no game outcomes:

| Archetype | Raw v6 | Raw v7 | Normalized v6 | Normalized v7 |
|---|---|---|---|---|
| Weak PG | 1530/2570/3570 | 1530/2570/2650 | 1994/3350/4656 | 2266/3807/3927 |
| Non-shooting C | 3810/1910/2180 | 3810/1910/800 | 4822/2417/2761 | 5843/2929/1228 |
| High-three C | 3650/2430/3620 | 3650/2430/3800 | 3762/2505/3733 | 3694/2459/3847 |
| High-three PF | 3290/2990/4072 | 3290/2990/4240 | 3178/2888/3934 | 3127/2842/4031 |
| Median SF | 2100/2750/4000 | 2100/2750/4000 | 2372/3107/4521 | 2372/3107/4521 |

For equal v6 raw usage weights `[100,100,100,100,100]`, v6 normalizes to `[2000,2000,2000,2000,2000]`. With role order primary, secondary, neutral, neutral, neutral, v7 proportional adjusted raw weights are `[135,115,100,100,100]`, normalizing to `[2454,2090,1818,1818,1820]`. This isolates opportunity policy. Zone vectors isolate preference policy. Existing shot-success vectors remain unchanged; comparisons are not simulated-game causal effects. No second simulator, v6 re-enable flag, or archived v6/v7 box-score comparison was added.

## Tests and verification

Environment: Windows x64; Dart 3.12.2 stable; Flutter 3.44.2 stable.

| Check | Command | Result |
|---|---|---|
| Core analysis | `dart analyze` from `packages/simulation_core` | PASS; no issues |
| Core format | `dart format --set-exit-if-changed lib test` from `packages/simulation_core` | PASS; 91 files, 0 changed |
| Full core VM | `dart test` from `packages/simulation_core` | PASS; 617 tests |
| Core Chrome | `dart test -p chrome test/deterministic_random_test.dart test/generator_test.dart test/validation_test.dart test/simulation` | PASS; 616 tests |
| Flutter analysis | `flutter analyze` at repository root | PASS; no issues |
| Flutter tests | `flutter test` at repository root | PASS; 111 tests |

The Chrome command excludes `domain_isolation_test.dart`, which uses `dart:io`.

T04 reported 612 VM, 611 Chrome, and 111 Flutter tests. T05 adds five core tests; Flutter count is unchanged. New coverage checks observer-off/on event-byte, fingerprint, and score identity; immutable trace collections; policy weight separation; ledger totals; undefined denominators; shot-time role changes; substitution/foul-out replay; and occupied-slot stretch-big classification. The pinned v7 fixture still validates and reproduces.

The required full core suites ran existing T013 structural cases on seeds 1–200 and pre-existing probability-sensitivity probes using up to 400 seeds. The requested canonical report uses seed 42, inside the proposed T06 pilot range. These runs did not evaluate paired v6/v7 policies; no T06 pilot or held-out evaluation ran. Owner must assess the seed overlap before T06 evidence collection.

## Compatibility and acceptance evidence

Observed compatibility checks: simulation 7 and fingerprint 5 remain unchanged; no event schema or `Player` field changes; historical v1–v6 fixture files remain untouched; canonical v7 fixture remains untouched; M001 league generator unchanged. Observer identity and full VM/Chrome test suites pass.

This evidence supports T05 implementation criteria for observer passivity, ledger metrics, shot-time roles, archetype coverage, and reproducibility. It does not mark any frozen acceptance-matrix row accepted; owner review remains required. No realism, production-readiness, Android-performance, or statistical acceptance claim is made.

## Risks and limits

- A single canonical game cannot establish realism or stable player archetype behavior.
- Generated roster archetypes and per-player attempt counts remain small; pooled values need the authorized evaluation protocol.
- The analyzer requires a validated `GameResult`; it is not a second event validator.
- The observer is in-process callback instrumentation; it is not persisted or rendered by the app.

## T06 readiness recommendation

T05 instrumentation and metrics are available for review. Recommend T06 only after owner acceptance of T05, a frozen pilot/evaluation protocol, explicit T06 authorization, and owner resolution of the seed-ID overlap above. Do not infer readiness for held-out evaluation from deterministic tests or this one-game report.