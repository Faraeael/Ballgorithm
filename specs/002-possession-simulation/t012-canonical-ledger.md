# T012 — Canonical ledger fixture and cross-platform determinism

Status: **IMPLEMENTED — T012 only.** T013–T019 remain unauthorized.
Base: `c895fce` (`develop/m002`, T011 checkpoint).
Task scope: pin one complete canonical ledger, prove VM/Chrome byte equality and
preserve the M001 baseline. No simulator, rules, probability, schema or PRNG
change was required.

This task supplies evidence for AC03 only. It does not claim AC01–AC13 closure.

## 1. Input fixture

Built with the existing `buildInput` test helper (`test/simulation/support.dart`):

| Field | Value |
|---|---|
| League | `const LeagueGenerator().generate(const GenerationConfig(seed: 20261028))` |
| Home | `league.teams.first` (`team-1`, first generated team) |
| Away | `league.teams[1]` (`team-2`) |
| Lineups | `ActiveLineup.defaultFor` for both teams |
| gameId | `game-1` |
| Raw game seed | `42` (`normalizedSeed = 42`) |
| Rules | `GameRules.standard` |

League snapshot: 8 teams × 12 players, `jsonEncode(league.toJson())` length
29,263 (pinned by `m001_regression_test.dart`).

## 2. Versions

```
gameSimulationVersion          1
gameRulesVersion               1
gameEventSchemaVersion         2
gameFingerprintVersion         1
gameActionDurationModelVersion 1
prngImplementationId           xorshift32-v1
coreEngineVersion              1.0.0
snapshotSchemaVersion          1
```

None of these changed in T012.

## 3. Canonical encoding

`jsonEncode(result.ledger.toJson())` — no pretty printing, no key sorting, no
normalization.

Ledger header order:

```
eventSchemaVersion, gameSimulationVersion, gameRulesVersion,
prngImplementationId, inputFingerprint, gameId, events
```

Event order: `sequence` 1…N; event field order per `_baseJson()`
(`sequence`, `type`, `period`, `gameClock`, `shotClock`) followed by the typed
payload fields in `game_event.dart` declaration order.

## 4. Pinned input fingerprint

```
bcb1a58f09500c0d4132b48709962bd44409a25b6e23ee91d27d3c9f30cb97a8
```

`GameFingerprint.of(input)`; SHA-256 over `GameFingerprint.canonicalJson(input)`
(UTF-8).

## 5. Pinned complete-ledger SHA-256

```
f8cfc12e01d8ba187c602021eaaabbac13b8438cf7e34ec5af3ff03b3d97387f
```

SHA-256 over the canonical UTF-8 bytes above; recomputed independently from the
current implementation before the fixture was created, and again from the
committed fixture itself.

## 6. Golden fixture location and format

```
packages/simulation_core/test/simulation/t012_canonical_ledger_fixture.dart
```

`const String t012CanonicalLedgerJson` — the exact canonical stream (133,901
characters, printable ASCII, no escaping needed), split into adjacent
single-quoted literals of 1,000 characters for reviewability. Feeding the
constant to `utf8.encode` reproduces the canonical bytes; no file IO, no
`dart:io`, no browser-incompatible loading. The fixture is immutable at run
time: no test writes or regenerates it.

## 7. Event count and final score

| Field | Value |
|---|---|
| Events | 800 (`GameStarted` … `GameEnded`) |
| Final score | 94–77 (home–away) |
| Periods | 4 regulation, no overtime |
| Event mix | 204 `PossessionStarted`, 204 `PossessionEnded`, 159 `FieldGoalAttempt`, 97 `Rebound`, 48 `Turnover`, 48 `PersonalFoul`, 30 `FreeThrowAttempt`, 4 `PeriodStarted`, 4 `PeriodEnded`, 1 `GameStarted`, 1 `GameEnded` |

The ledger also carries 9 `nonSteal` turnovers, 18 steals, 11 offensive fouls,
9 shooting fouls, 1 and-one, 39 assisted makes, 1 block and 20 offensive
rebounds, so the golden exercises Amendment 001 and the T010 edge paths.

## 8. Additional pinned seed digests

Same fixture configuration, different raw game seed; digest as above.

| Seed | Ledger SHA-256 | Events | Score |
|---|---|---|---|
| 1 | `610dea0941d463da7960b912ea2004f91562a0567bbecba9e7aabba23c6a1e61` | 800 | 119–80 |
| 42 | `f8cfc12e01d8ba187c602021eaaabbac13b8438cf7e34ec5af3ff03b3d97387f` | 800 | 94–77 |
| 99 | `b325c79d846d4401443878616682437120ee9db1fc8f59ae995a4f9bb184dc17` | 780 | 105–108 |
| 20261029 | `c996cd4a4d0dc03a647bef578ee2cf1cfe9efd4dc84392778f9bfec312b96493` | 799 | 76–96 |

Only seed 42 stores the full ledger; the other seeds are pinned by digest plus
replay/accounting checks, which avoids three further 130 KB copies without
weakening the assertion (any byte change alters the digest).

## 9. VM and Chrome execution

Environment:

- Dart SDK 3.12.2 (stable) on windows_x64
- Google Chrome 156.0.8078.49 (Dart's browser test platform)

Commands (from `packages/simulation_core`):

```
dart test test/simulation/t012_canonical_ledger_test.dart          → 12 passed
dart test -p chrome test/simulation/t012_canonical_ledger_test.dart → 12 passed
```

Full gates:

```
dart format --output=none --set-exit-if-changed lib test → 50 files, 0 changed
dart analyze                                             → No issues found
dart test                                                → 256 passed
dart test -p chrome test/simulation test/deterministic_random_test.dart \
    test/generator_test.dart test/validation_test.dart   → 255 passed
flutter analyze                                          → No issues found
flutter test                                             → 8 passed
```

`domain_isolation_test.dart` remains VM-only (it inspects source imports) and is
excluded from the Chrome run, as in every earlier milestone.

Each runtime executes `GameSimulator().simulate`, encodes the ledger, hashes the
bytes and compares against the same committed constant. Chrome does not read a
VM-produced digest; it recomputes it.

## 10. Cross-platform seed-alias behaviour

Seeds `42` and `42 + 2^32 = 4294967338`:

- `normalizedSeed` is `42` for both;
- the full gameplay event sequence is identical (event JSON equal);
- final scores and period counts are identical;
- input fingerprints differ (raw seed is part of the payload);
- ledger JSON differs only in `inputFingerprint`.

Verified on VM and Chrome. Values are exactly representable in both Dart int
arithmetic and JavaScript numbers.

## 11. Decode / re-encode round trip

```
golden JSON → jsonDecode → GameEventLedger.fromJson → toJson → jsonEncode
```

Result: character-identical and byte-identical to the golden stream; digest
unchanged. The decoded ledger then passes `GameEventReducer.validate` with
`state.ended == true`, `eventCount == 800`, no open possession, and
`EventAccounting.aggregate` reproduces the original `GameBoxScore` exactly
(players, teams, period points compared through an ordered projection).

Structural assertions on the decoded ledger:

- `GameStarted` first, `GameEnded` last, period/possession ordering intact;
- free-throw groups: contiguous `attemptIndex` 1…n, one team/shooter, only the
  last attempt flagged `lastOfGroup`;
- and-one attempts are followed by that shooter's first free throw;
- `Rebound.missedEventSequence` always points backwards at a missed FG (same
  team when offensive) or a missed final FT;
- `nonSteal` turnovers keep wire reason `nonSteal` and no `stolenById`;
  `steal` turnovers always carry `stolenById`;
- no floating-point token anywhere in the canonical stream (checked on the byte
  stream, because JS decodes every number as `double`).

## 12. Fingerprint identity evidence

Asserted in `t012_canonical_ledger_test.dart`:

| Property | Result |
|---|---|
| Payload field order | `fingerprintVersion, league, homeTeamId, awayTeamId, homeLineup, awayLineup, gameSeed, normalizedSeed, rules, versions` |
| Version identifiers present | `fingerprintVersion = 1`; `versions` = simulation/rules/eventSchema/prng/coreEngine/leagueSchema |
| Re-encode stability | repeated `GameFingerprint.of` and `canonicalJson` calls equal |
| Hex form | 64 lowercase hex characters |
| Unrelated roster change | bumping `team-3` player-1 `stamina` changes the fingerprint |
| Lineup membership | swapping in the second team-1 PG changes the fingerprint |
| Lineup order | reordering PG/SG is rejected by `ActiveLineup.create` (`invalidLineupPositions`); canonical PG,SG,SF,PF,C order is enforced, not merely hashed |
| Raw seed | `42 → 43` changes the fingerprint |
| A1 weights | `[5000,2500,2500]` changes the fingerprint |
| A1 brackets | `[[3,7],[5,11],[10,22]]` changes the fingerprint |
| Rules value | `bonusRegulationFouls: 4` and `maxOvertimes: 2` change it |
| Rule-variant simulation | variant ledger reports the variant fingerprint and replays cleanly |

## 13. M001 preservation

- No file under `packages/simulation_core/lib/` changed; `git diff` for the
  library is empty.
- `m001_regression_test.dart` still passes: `coreEngineVersion = 1.0.0`,
  `snapshotSchemaVersion = 1`, `prngImplementationId = xorshift32-v1`, league
  JSON length 29,263, first player `Jonas Cortez` with the pinned attributes,
  and the frozen `GameRules.standard` values.
- M001 PRNG vectors, F01/F02 reducer protections, Amendment 001 behaviour,
  T008 coefficients/draw order, T009 input-rules configuration and T010
  validation hardening are untouched; T011's 40-seed and bounds suite still
  passes in the same run.
- The pure-Dart core still imports no Flutter, `dart:io`, network, storage or
  platform API; the fixture is a compile-time string constant.

## 14. Intentional future updates

The golden fixture must fail on real changes. To update it after an authorized
version change (rules, simulation, event schema or PRNG):

1. Obtain separate owner authorization for the change.
2. Recompute with the pinned fixture (one-off script, not committed):

   ```dart
   final input = buildInput(seed: 42);            // test/simulation/support.dart
   final result = GameSimulator().simulate(input);
   print(jsonEncode(result.ledger.toJson()));
   ```

3. Verify the new input fingerprint, digest, event count and score by hand and
   record them in this document.
4. Replace `t012CanonicalLedgerJson` and the pinned constants in
   `t012_canonical_ledger_test.dart` in the same reviewed commit.
5. Re-run the VM and Chrome suites; both must pass before the change is merged.

There is deliberately no `--update-goldens` flag and no write path: a failing
comparison prints the first differing character offset, its location (the
containing event sequence number, or `ledger header` before the first event),
both digest values and the surrounding expected/actual windows.

## 15. Known limitations

- One full ledger is stored (seed 42). Seeds 1/99/20261029 are digest + replay
  pinned only; the full byte stream for those seeds is not committed.
- The ledger header does not carry `gameFingerprintVersion` or
  `gameActionDurationModelVersion`; both are covered by the fingerprint payload
  and the rules JSON. This is the pre-existing v2 contract and was not changed.
- The golden covers Dart VM and Dart-Compiled-to-JS in Chrome. Native Android
  runtime evidence remains T016/T017 work.
- No calibration, adversarial-property sweep (T013) or acceptance closure is
  claimed here.
- The fixture is a large source constant (133 KB); moving it to an asset would
  reintroduce platform-dependent loading, so it stays a compile-time string.

## 16. Files

Created:

- `packages/simulation_core/test/simulation/t012_canonical_ledger_test.dart`
- `packages/simulation_core/test/simulation/t012_canonical_ledger_fixture.dart`
- `specs/002-possession-simulation/t012-canonical-ledger.md`

Modified:

- `specs/002-possession-simulation/tasks.md` (T012 checked, T013–T019 unchecked,
  current workflow note)
