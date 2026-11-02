# Plan 003 — Mobile Game Day

> **Status:** **FROZEN — OWNER-APPROVED 2026-11-02**. Implementation is not authorized by this freeze.
> **Frozen at:** `develop/m002`, baseline `6ca43b632e9229216a49966b35bb660c6651c2e8`.
> **Companion documents:** `spec.md`, `tasks.md`, `design-decisions.md`, `documentation-debt.md`.

## 1. Architecture

No simulation logic moves. The core stays the single source of basketball truth; the app adds a
thin orchestration and presentation layer.

| Layer | Location | Responsibility |
|---|---|---|
| Domain | `packages/simulation_core/**` | Unchanged. `GameInput.create`, `ActiveLineup.defaultFor`, `GameSimulator.simulate`, `GameResult`. |
| Seed derivation | `lib/features/game/game_seed.dart` | Pure integer function, no simulation dependency. |
| Runner | `lib/features/game/game_runner.dart` | Accepts a `GameRequest`, builds `GameInput` **inside the worker**, invokes the simulator, maps failures to a typed UI error. |
| Setup screen | `lib/features/game/game_setup_screen.dart` | Home/away selection, seed preview, confirm. |
| Game screen | `lib/features/game/game_screen.dart` | Run state (loading / error / result), result rendering, rematch, return. |
| Presentation widgets | `lib/features/game/*_widgets.dart` | Score header, period table, team stats table, player box score, disclosure. |

```text
LeagueScreen --Play Game--> GameSetupScreen --Run--> GameScreen --Return--> LeagueScreen
                                    ^                    |
                                    +------ Rematch -----+ (same teams, next seed, in place)
```

### 1.1 Screen responsibilities

- `GameSetupScreen` owns nothing but the chosen teams and rematch index. It derives the seed for
  display, and pushes `GameScreen` with the selected `Team`s, the league, and the rematch index.
- `GameScreen` owns the run lifecycle. It issues one `GameRequest` per run, calls the runner once, and
  renders exactly one of: loading, error, result. Rematch increments the rematch index and re-runs in
  place, so the back stack never grows with games.
- Widgets receive immutable view data extracted from the single `GameResult`; they do not compute
  basketball quantities.

### 1.2 Run lifecycle (no permanently stuck state)

```text
idle -> running -> success
                \-> failure -> retry -> running
```

- `running` is entered synchronously before awaiting the runner.
- Completion always leaves `running` — success, `GameValidationException`, or any other error.
- Re-entry while `running` is ignored (no double run from repeated taps).
- Failure renders typed codes plus a retry action; navigation back is always allowed.

### 1.3 Presentation rules

- Final score and winner from `GameResult.homeScore` / `awayScore` / `winnerTeamId`.
- Period rows from `GameResult.homePeriodScores` / `awayPeriodScores`; overtime shown when
  `periodsPlayed > input.rules.periods`.
- Team totals from `GameResult.boxScore.teams[teamId.value]`.
- Player rows from `GameResult.boxScore.players`, ordered by team, then canonical PG→C lineup order
  for the five active players.
- Rounding, percentage and formatting helpers stay in `lib/`.
- Narrow layout: fixed-width numeric columns, horizontally scrollable only for the player table if
  unavoidable at 360 dp; scores and period table never scroll horizontally.

## 2. Input construction

The runner takes a small value and does all core validation inside the worker:

```text
GameRequest = (League league, TeamId homeTeamId, TeamId awayTeamId, int seed)

worker(GameRequest request):
  homeLineup = ActiveLineup.defaultFor(homeTeam)
  awayLineup = ActiveLineup.defaultFor(awayTeam)
  input      = GameInput.create(
                 gameId: '<homeId>-<awayId>-<seed>',
                 league: request.league,
                 homeTeamId, awayTeamId, homeLineup, awayLineup,
                 seed: request.seed,
                 rules: GameRules.standard)
  return GameSimulator().simulate(input)
```

Placing `GameInput.create` inside the worker is deliberate: it makes typed input-validation failures
travel the same boundary as successful results, so worker error transport is testable without a
contrived simulator. It also keeps one validation path — the app never pre-validates what the core
rejects. The UI additionally prevents selecting the same team twice, purely to avoid an obvious dead
end; `GameValidationCode.teamsNotDistinct` remains authoritative for any request that reaches the
core.

## 3. Isolate feasibility assessment

### 3.1 Object graph inspected

`GameInput` and `GameResult` were read and traversed statically (2026-11-02, baseline `6ca43b6`):

| Type | Fields | Sendable |
|---|---|---|
| `LeagueId`, `TeamId`, `PlayerId` | Extension types over `String` (erased at runtime) | Yes — plain `String` |
| `GenerationConfig` | 3 × `int`, `String` | Yes |
| `League` | id, `String`, `GenerationConfig`, `List<Team>` (unmodifiable) | Yes |
| `Team` | id, `String`, `String`, `Roster` | Yes |
| `Roster` | `List<Player>` (unmodifiable) | Yes |
| `Player` | id, 2 × `String`, `Position` enum, `PlayerAttributes` | Yes — enums are const objects |
| `PlayerAttributes` | 12 × `int` | Yes |
| `ActiveLineup` | `List<Player>` (unmodifiable) | Yes |
| `GameRules` | ints, `List<int>`, `List<List<int>>` (unmodifiable) | Yes |
| `GameInput` | strings, ids, league, lineups, `int`, rules | Yes |
| `GameEventLedger` | 2 × `String`, `List<GameEvent>` (unmodifiable) | Yes |
| `GameEvent` hierarchy | ints, bools, strings, enums, nullable id extension types | Yes |
| `GameState` | bools, ints, nullable `String` | Yes |
| `GameBoxScore` | maps of value classes, `Map<String, Map<int,int>>` | Yes |
| `PlayerBoxScore` / `TeamBoxScore` | ints and `String` team id | Yes |
| `GameResult` | input, fingerprint, ledger, state, box score, ints, `String` | Yes |
| `GameValidationException` / `GameValidationIssue` | enum + strings, unmodifiable list | Yes |

No closures, function-typed fields, `RegExp` instances, native handles, streams, sockets or
`dart:io` objects are stored anywhere on these graphs. `RegExp` literals appear only inside
constructors and validators, never as fields.

Structural notes:

- Message passing **copies** objects; identities differ across the boundary. Comparisons must use the
  fingerprint and canonical ledger bytes, never `identical`.
- League payload is small: 8 teams × 12 players plus attributes — tens of kilobytes at most,
  copied once per run.
- Unmodifiable collections are ordinary Dart objects and are copied like any list/map.

### 3.2 Options

| Option | Description | Assessment |
|---|---|---|
| **A** | `Isolate.run`/`compute` returns `GameResult` directly | Smallest change: no mapping layer, no duplicate data model, no drift risk. Succeeds only if the graph above is accepted by the VM message protocol — plausible statically, unproven until T021. |
| **B** | Return a UI-specific DTO | Adds a parallel result model, mapping code and an equivalence test against the canonical ledger. Buys decoupling the UI does not need, since `lib/` already passes core models (`League`, `Team`, `Player`) straight into widgets. Rejected as the default; keep as fallback if A fails empirically. |
| **C** | Synchronous run on the UI isolate | No device or emulator measurement of mobile cost exists (`M002-OWNER-ACCEPTANCE.md` §6: Android NOT MEASURED). Blocking the frame loop for an unknown duration is a poor default and is explicitly gated behind separate owner authorization plus measurement. Rejected for this milestone. |

**Recommendation: A.** Single representation, no second source of truth, least code. B stays a
documented fallback only if T021's parity test shows the graph cannot cross the boundary.

### 3.3 Execution mechanism

`compute()` from `package:flutter/foundation.dart` with a top-level or static callback:

- On mobile/desktop it runs the callback in a separate isolate, which is the frame-blocking fix.
- On web it executes inline in the current event loop. That keeps the existing
  `flutter run -d chrome` development path working instead of throwing `UnsupportedError`, which raw
  `Isolate.run` would require a `kIsWeb` branch for.
- `flutter test` runs on the Dart VM, so the parity test exercises a genuine isolate and proves
  sendability.

The runner exposes `Future<GameResult> run(GameRequest request)` with the default implementation doing
`compute(_simulateRequest, request)`, where the worker builds `GameInput` and returns `GameResult`.
Nothing else in the pipeline differs between the direct and offloaded paths — which is exactly what the
parity test asserts.

### 3.4 Parity and lifecycle verification (by owning task)

| Check | Task | Method |
|---|---|---|
| Identical result | T021 | direct `simulate(input)` vs runner path: equal `inputFingerprint`, equal `homeScore`/`awayScore`, equal `periodsPlayed`, equal `possessions`, equal event count |
| Canonical ledger parity | T021 | SHA-256 of `ledger.toJson()` JSON encoding must match |
| Accounting reconciliation | T021 | both results' `boxScore` equal field by field; team totals equal sums of player rows |
| Typed failure transport | T021 | a request with identical home/away ids returns `GameValidationException` with `teamsNotDistinct` **from inside the worker**, because `GameInput.create` runs there; not an opaque `RemoteError` |
| No stuck loading | T023 | widget test with a failing runner: `CircularProgressIndicator` absent after the error frame |
| Single source of truth | T024 | result rendering uses only returned `GameResult` values; verified by inspecting the widget inputs and by the widget assertion in AC-MGD-05 |

T021 is the isolate gate and depends on nothing beyond the runner and seed function. The lifecycle and
rendering checks belong to the tasks that create those screens, so T021 cannot be blocked by unwritten
widgets.

## 4. Verification plan

| Group | Command / test | Expectation |
|---|---|---|
| Static | `flutter analyze` | clean |
| App tests | `flutter test` | green; existing 8 widget tests preserved, new game tests added |
| Core regression | `cd packages/simulation_core && dart test` | unchanged from the T017/T019 baseline; record the observed count |
| Core analysis | `cd packages/simulation_core && dart analyze` | clean |
| Format | `dart format --set-exit-if-changed lib test` | no changes |
| Web dev path | `flutter test --platform chrome` optional for touched widget tests | parity test may be excluded on web by documented reason |

No calibration cohort, no new statistical protocol, no held-out seeds: simulation behavior is
untouched. T025 records `Android NOT MEASURED` and makes no device performance claim.

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| RG-1 | Some graph member is rejected by the isolate message protocol | T021 is the first implementation gate; Option B is the documented fallback. |
| RG-2 | League copy cost per run is larger than expected on mobile | Measure in T021 on the VM (copy time) and record; payload is tens of KiB. |
| RG-3 | Mobile frame cost remains unmeasured | Never claim device performance; offload keeps the main isolate free regardless. |
| RG-4 | Web dev path runs synchronously | Documented; `compute` keeps it functional for development only. |
| RG-5 | Box-score tables overflow at 360 dp | Dedicated narrow-layout test; numbers right-aligned, player table allowed to scroll horizontally if needed. |
| RG-6 | Users read fixed-five totals as minutes | Mandatory disclosure on the result screen (spec §6). |
| RG-7 | UI slowly diverges into a second scoreboard | All rendered values come from one `GameResult`; no widget recomputation. |
| RG-8 | Rematch seed cycle repeats after 256 games per matchup; a derived seed of 0 plays as `0x9E3779B9` | Derivation masked to a 31-bit domain, rematch masked to 8 bits, and no derived value can equal `0x9E3779B9`, so normalized seeds never alias; the repeat bound and the `0` mapping are disclosed in the UI (`design-decisions.md` DD-MGD-04). |

## 6. Preservation statement

- `packages/simulation_core/lib/**` — no behavior, coefficient, clock, rule or version change.
- Frozen M002 fixtures, historical evidence and acceptance records — untouched.
- M001 generation, snapshots and PRNG vectors — untouched.
- Existing widget `ValueKey` contracts and mobile layout behaviour — preserved.
