# T021 — Isolate transport gate: evidence

> **Status:** **PASS — WORKER CONTRACT VERIFIED** on the native Dart VM.
> **Date:** 2026-11-02
> **Baseline:** `develop/m002` at `2abc0e290b5d10f0b5f078ff7130f7093ac8da8a` (T020 frozen and published).
> **Authorization:** `BALLGORITHM — M003 T021 ISOLATE FEASIBILITY GATE`, T021 only.
> **Scope:** app-layer worker boundary and seed derivation. No `packages/simulation_core` change.

## 1. Environment

| Item | Value |
|---|---|
| OS | Microsoft Windows 11 Pro, 10.0.26100, x86-64 |
| Flutter | 3.44.2 stable (`c9a6c48423`), channel stable |
| Dart | 3.12.2 stable, `windows_x64` |
| Engine | `04efd7c093d4e9281d5526ebcad6ecc60ba8badf` |
| Test platform | `flutter test` on the Dart VM (genuine isolate), JIT, not AOT |
| League fixture | `LeagueGenerator(GenerationConfig(seed: 20261028))`, 8 teams |
| Versions exercised | simulation 4, rules 2, event schema 2, fingerprint 2, duration model 2, `xorshift32-v1` |

Timings below are test-process measurements, not product performance and not an Android result.

## 2. Worker contract implemented

```text
GameRequest = (League league, TeamId homeTeamId, TeamId awayTeamId, int seed)

Future<GameResult> runGame(GameRequest request) => compute(_simulateGame, request)

_simulateGame(request):                      // top-level callback, no captured state
  homeTeam = league team with request.homeTeamId      (typed teamNotFound if absent)
  awayTeam = league team with request.awayTeamId
  input    = GameInput.create(
               gameId: '<homeId>-<awayId>-<seed>',
               league, homeTeamId, awayTeamId,
               homeLineup: ActiveLineup.defaultFor(homeTeam),
               awayLineup: ActiveLineup.defaultFor(awayTeam),
               seed: request.seed,
               rules: GameRules.standard)
  return GameSimulator().simulate(input)
```

- `GameInput.create` runs **inside** the worker, so input validation failures cross the same boundary
  as successful results.
- `GameSimulator.simulate` is unchanged, returns the only `GameResult`, and no widget or runner
  recomputes basketball statistics.
- Files: `lib/features/game/game_runner.dart`, `lib/features/game/game_seed.dart`.

## 3. Isolate evidence

`debugWorkerRuns` is a top-level counter incremented only inside the callback. Isolates do not share
mutable globals, so on a genuine worker isolate the calling isolate's copy stays `0`.

- Test `worker runs off the calling isolate and returns GameResult`: after `await runGame(request)`,
  `debugWorkerRuns == 0` in the test isolate. The callback therefore did **not** run on the calling
  isolate; `compute()` spawned a worker. (On web the counter would increment, because `compute` runs
  inline there — see §6.)

## 4. Criterion evidence

| # | Frozen criterion | Test | Result |
|---|---|---|---|
| D1 | `GameRequest` crosses into the worker | `worker runs off the calling isolate and returns GameResult` | PASS — result returned, calling isolate untouched |
| D2 | Worker genuinely uses a separate isolate | same | PASS — `debugWorkerRuns == 0` on caller |
| D3 | `GameResult` crosses back | same | PASS — `isA<GameResult>`, ledger and box score populated |
| D4 | Identical `inputFingerprint` | `worker and calling-isolate results are identical` | PASS — `56d6310325d0f434c25d4057e8f0d9594ca099862300a0c1860122b773ed20ce` both paths |
| D5 | Identical canonical ledger digest | same | PASS — `jsonEncode(ledger.toJson())` strings equal **and** SHA-256 equal |
| D6 | Identical team, player and period accounting | same | PASS — all 18 box-score fields per player and per team equal; per-period maps equal; each team's totals equal the sum of its player rows in both results |
| D7 | Repeated identical runs reproduce | `repeated worker runs reproduce identical results` | PASS — fingerprint, digest and scores equal across two worker runs |
| D8 | `teamsNotDistinct` from inside the worker stays typed | `teamsNotDistinct from inside the worker is a typed failure` | PASS — `GameValidationException` with `GameValidationCode.teamsNotDistinct`, issues non-empty; not a `RemoteError` |
| D9 | Worker failure completes | same test awaits the future | PASS — completes with the error; no unresolved future, default test timeout not hit |
| D10 | Seed policy, injectivity, rematch cycle | `test/game_seed_test.dart` (5 tests) + `seed normalization matches the core contract` | PASS — see §5 |

Game identity used for D4–D7: seed `20327844` (`leagueSeed 20261028`, home index 3, away index 5,
rematch 0), score away 103 – home 97, 4 periods, 805 ledger events.

Recorded overhead, same process, informational only:

| Path | Wall time |
|---|---|
| Calling-isolate simulate | 9,914–11,342 µs |
| Worker via `compute()` | 11,211–18,632 µs |

The worker path includes isolate spawn and the structural copy of `GameRequest` and `GameResult`.

## 5. Seed-domain evidence

Contract: `(leagueSeed ^ (homeIndex << 16) ^ (awayIndex << 8) ^ (rematchIndex & 0xFF)) & 0x7FFFFFFF`.

| Property | Evidence |
|---|---|
| Deterministic and repeatable | `is deterministic and repeatable` |
| Home/away not interchangeable | `home and away are not interchangeable` — all 56 ordered pairs × 6 league seeds |
| 256 distinct seeds per ordered matchup | `rematch cycle has exactly 256 distinct seeds per matchup` |
| Cycle period exactly 256 | same test — rematch 256 equals rematch 0 |
| 31-bit domain, never `0x9E3779B9` | `derived seeds stay in the 31-bit domain and never hit 0x9E3779B9` — 16,384 combinations × 6 league seeds |
| Normalized seeds injective over the bounded domain | `all 16,384 bounded inputs give distinct derived and normalized seeds` — 16,384 / 16,384 distinct, both derived and normalized, for league seeds `20261028`, `0`, `1`, `0xFFFFFFFF`, `0x9E3779B9`, `12345` |
| Core normalization unchanged | `seed normalization matches the core contract` — `GameInput.normalizedSeed` is `0x9E3779B9` for raw `0` and identity for a non-zero seed; no core source edit |

The normalization identity used by the seed tests (`0 → 0x9E3779B9`, otherwise unchanged) is asserted
against the real `GameInput.normalizedSeed` in the parity test, so the pure-math injectivity check is
not self-referential.

## 6. Platform limitations

| Platform | Evidence | Status |
|---|---|---|
| Dart VM / Flutter test (native) | full parity suite above | **PASS** |
| Flutter Web | `compute()` runs inline in the current event loop; it cannot demonstrate native worker parity. The seed, parity-comparison and box-score code paths are platform-independent, but isolate spawning is not exercised. A `flutter test --platform chrome` attempt was started for informational purposes only; it does not contribute to the verdict and no web parity claim is made. | **separate evidence; not a native parity claim** |
| Android / iOS / desktop AOT | not run | **NOT MEASURED** — no device, emulator or profile session |
| Android frame timing / memory | not run | **NOT MEASURED** — no performance claim is made |

No claim is made that the worker is required on mobile, nor that it is free. The only measured numbers
are test-process timings on this desktop machine.

## 7. Commands and results

| Command | Result |
|---|---|
| `flutter pub get` | resolved; `crypto` moved from transitive to direct dev dependency |
| `flutter analyze` | **No issues found** |
| `flutter test test/game_seed_test.dart test/game_runner_parity_test.dart` | **11/11 passed** |
| `flutter test` | **19/19 passed** (8 pre-existing widget tests preserved) |
| `cd packages/simulation_core && dart analyze` | **No issues found** |
| `cd packages/simulation_core && dart test` | **351/351 passed** — matches the recorded M002 baseline |
| `git diff -- packages/simulation_core` | empty — core untouched |

## 8. Deviations and notes

1. **Test-only dependency added:** `crypto: ^3.0.7` was added to the app's `dev_dependencies` because
   frozen criterion 2 requires a SHA-256 ledger digest. It is the same already-approved package the
   core uses for fingerprinting, it is not in the app's production dependency set, and no runtime
   dependency changed. `pubspec.lock` records `crypto` as `direct dev`.
2. **`flutter pub get` rewrote three generated Windows plugin files** with line-ending changes and no
   content difference; they were restored to the index state and are not part of this task.
3. No simulation logic, coefficient, clock, rule, event schema, PRNG draw order, version, fixture or
   historical evidence was modified.

## 9. Verdict

**ISOLATE TRANSPORT — PASS.** Direct `GameResult` transport is supported on the native Dart VM,
including typed error propagation from inside the worker, and the seed contract meets its frozen
bounds. Option B (DTO) is not required. T022 may proceed once separately authorized.
