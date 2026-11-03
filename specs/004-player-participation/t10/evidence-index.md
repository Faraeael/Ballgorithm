# M004 Evidence Index

Baseline: `c609c3d60cdb00dac1e2951b26729872b54ff621` (`develop/m002`, 2026-11-03).
Repository: `Faraeael/Ballgorithm`. Workspace: `E:\ballgorithm-dev`.

## Milestone commits

| Task | Commit | Subject |
|---|---|---|
| T02 | `c7f1d7a978a890cfe9ef3b8fe962e666bc042292` | feat(m004-t02): adopt internal slot semantics for positional lookups |
| T03 | `8618550` | feat(m004-t03): adopt public v5 court lineup contract |
| T03 | `fb89415` | fix(m004-t03): enforce canonical roster authority |
| T03 | `d29d1ff` | fix(m004-t03): expose immutable canonical roster view |
| T04 | `cd4303a` | feat(m004-t04): validate replayed court participation |
| T04 tests | `47ec03b`, `98eeb80`, `db77953`, `139f9cb`, `7e64539` | rejection checklist and boundary coverage |
| T05 | `071457b` | feat(m004-t05): emit lawful foul-out substitutions |
| T06 | `ef1bbb4` | feat(m004-t06): derive player minutes for the full roster |
| T06 tests | `ee50aca`, `7251b58` | baseline equivalence (post-T03), substitute attribution |
| T07 | `11ec63d` | test(m004-t07): pin canonical participation ledger and replay parity |
| T07 | `24cc608` | test(m004-t07): assert complete box-score determinism |
| T08 | `40cc669` | feat(m004-t08): execute frozen matched-seed cohort |
| T08 | `bb3543f` | fix(m004-t08): report full minutes and matchup participation distributions |
| T09 | `ebea5bc` | feat(m004-t09): show participation and minutes in game results |
| T09 | `acafb0a` | fix(m004-t09): classify final-horn foul-outs from horn phase and game end |
| T09 | `c609c3d` | fix(m004-t09): classify replacements after disqualification chronologically |

Frozen M004 package: `specs/004-player-participation/{spec,plan,tasks,design-decisions,acceptance-matrix,verification-plan}.md`, frozen 2026-11-02 (`aa34ec1`); the only later change is the documented T01 erratum `d833dd5`, after which no further edits exist.

## Canonical fixtures

| Artifact | Location | Git blob SHA-1 |
|---|---|---|
| T07 canonical participation ledger (seed 42, 837 events, 4 substitutions) | `packages/simulation_core/test/simulation/t07_canonical_participation_fixture.dart` | `776796a35b947f8d8341a902023bf2fefa31f2e7` |
| T012 v5 provisional pre-substitution ledger | `packages/simulation_core/test/simulation/t012_canonical_ledger_fixture_v5.dart` | `2fc6513225afdf502e409e9e3b786de4434b5e01` |
| T012 v1–v4 archives | `t012_canonical_ledger_fixture{,_v2,_v3,_v4}.dart` | unchanged since their gates |

Pinned T07 values: input fingerprint `e9b99720fa77ecd362e05029ebdba80ded67828f662f8b5f09e1edf8581ed3ed`; ledger SHA-256 `9b4244fbacd2f615a76724ce3e9885f04160e2fd9463ce13871bbde8685b4b8a`; 837 events; substitutions at 393/511/611/805; 103–99; 4 periods. Seed-42 v4 prefix digest (392 events, build `c7f1d7a`): `0fa93f89ea7125c5270e2e14324b122dec78deec3e512c0c6ddbf6a3a08d3b9b`.

## Test references

| Area | File | Highlighted tests |
|---|---|---|
| Lineup/contract | `packages/simulation_core/test/simulation/court_lineup_test.dart` | canonical slots, size, uniqueness, ownership, mismatched slot legality |
| T03 contract | `packages/simulation_core/test/simulation/t03_contract_test.dart` | substitution JSON contract; version constants; v4 ledger rejection; fingerprint; seed-15 baseline |
| Participation | `packages/simulation_core/test/simulation/t04_participation_test.dart` | 47 tests: W0/W1/W2/W4/W5 acceptance; 29-case rejection mapping; horn P1/P2/P3; depleted continuation |
| Emission | `packages/simulation_core/test/simulation/t05_emission_test.dart` | foul-out-only emission, positional replacement, depleted roster, no-draw determinism |
| Minutes/accounting | `packages/simulation_core/test/simulation/t06_minutes_test.dart` | 8 tests: substitution seconds, W1 split, same clock, overtime, horn boundary, depletion, substitute attribution |
| Canonical/replay | `packages/simulation_core/test/simulation/t07_canonical_participation_test.dart` | 13 tests: fixture bytes/digest, replay, recorded-clock minutes, 20 repeats, v4 prefix, 8 mutations |
| T08 tooling | `packages/simulation_core/test/simulation/t08_tooling_test.dart` | allocation/parity, manifest round-trip, paired formulas, quantiles, t criticals |
| T08 mutation names | `t013_ledger_mutation_test.dart` groups A–G | sequence, lifecycle, clock, possession, foul/free-throw, rebound, turnover corruption |
| Worker parity | `test/game_runner_parity_test.dart` | 6 tests: worker isolation, ledger/fingerprint identity, substitutions, `secondsPlayed`, conservation |
| Results UI | `test/game_results_test.dart` | 16 tests: scoreboard, periods, team stats, participation order, minutes, disclosure, rematch, navigation |
| Participation UI | `test/game_participation_test.dart` | 7 tests: zero-second entrant, replaced foul-out, depleted label, FT-made/FT-missed horn, re-entry correction, slot-97 horn |
| Mobile layout | `test/game_mobile_layout_test.dart` | 13 tests at 360×640, 393×852, 430×932 |

## Command results (2026-11-03, baseline HEAD)

| Command | Result |
|---|---|
| `flutter analyze` | PASS, no issues |
| `flutter test` | PASS, 78 passed, 0 failed, 0 skipped |
| `dart format --set-exit-if-changed lib test` (app) | PASS, 21 files formatted, 0 changed |
| `dart pub get` (core) | PASS |
| `dart analyze` (core) | PASS, no issues |
| `dart test` (core, VM) | PASS, 453 passed |
| `dart format --set-exit-if-changed lib test` (core) | PASS, 70 files, 0 changed |
| `dart test -p chrome test/deterministic_random_test.dart test/generator_test.dart test/validation_test.dart test/simulation` | PASS, 452 passed; exclusion: IO-only `domain_isolation_test.dart` |
| Historical fixture diff `git diff d29d1ff..HEAD -- '*fixture*'` | only the new T07 fixture; no historical fixture change |

VM/Chrome delta = 1, exactly the excluded IO test.

## T08 source and analysis artifacts (committed)

- `specs/004-player-participation/t08/t08-seeds.csv` — SHA-256 `65f40465917e3293c00e9c2fd2e862a46294d881b13ea4c426faf9d7fd4c075c`
- `t08-README.md`, `t08-checksums.txt`, `t08-paired.csv`, `t08-summary.json`, `t08-mechanism-report.json`, `runner-v4.dart.txt`
- Tooling: `packages/simulation_core/tool/t08_{common,manifest,runner_v5,analyze}.dart`

## T08 retained raw evidence (external, unchanged)

- Archive: `E:\ballgorithm-t08-artifacts\t08-independent-review-20261103.zip` — 4,312,412 bytes, SHA-256 `731ee49f51d60237c9ef8082054ebca30be4d5a6394e257c0566771ef10b7099`, verified present at this audit.
- `t08-raw-v4.jsonl` — 28,768,349 bytes, `6a1a1c574bc2e373883aca6e5c0e9c69985f9e4ef8d30b3440678c0aac87d033`
- `t08-raw-v5.jsonl` — 29,767,654 bytes, `58ea4969894e436fa5f75ed53e0fae39f6993662ea3009c9e4ce1a056921c9b8`

T08 independent audit (already performed, not rerun): 200/200 pairs, 400 simulations, eight paired series, Category A 11/11, Category B 189/189, zero unexplained divergences, one explained final-horn continuation (slot 97, seed 20098).

## T09 device evidence

- Screenshots: `E:\ballgorithm-t09-device-review\` (16 PNGs, 1080×2460): league, matchup, dropdowns, filled setup, game result, away/home boxes, horizontal scroll, disclosures, rematch, returned league.
- Device: Infinix X6882, Android 14 (API 34), ARM64, wireless ADB, `sw360dp`, 480 dpi.
- Debug APK built and installed via `flutter run`; app launched with Impeller/Vulkan.
- Reviewed game: Redstone Coyotes (home) vs Silverlake Kestrels (away), seed 20327844; rematch seed 20327845.
- Logs: no Flutter exceptions; Android Choreographer reported 157 and 33 skipped frames (debug session; cause unmeasured).

## Environment

Flutter 3.44.2 (stable, revision `c9a6c48423`), Dart 3.12.2, Windows 11 10.0.26100, Chrome 156.0.8078.74, Android SDK 36.0.0 (one licensing warning, did not block debug build).
