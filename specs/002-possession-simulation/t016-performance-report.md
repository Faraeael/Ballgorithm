# T016 — Performance Verification Report (AC12)

> **Date:** 2026-10-31
> **Task:** T016 — measure bounded runtime/memory under a named environment and document Android suitability constraints without fabricated measurements.
> **Authorization:** owner *Ballgorithm M002 — Guarded Remote Backup + T016 Performance*
> **Source commit measured:** `dc6f85a822ee448f032c49a331b313bf9abc032c` (`develop/m002`, simulation `gameSimulationVersion = 4`)
> **Scope:** measurement only. No probability coefficient, duration bracket, rule, acceptance criterion or historical evidence was changed. Runtime seeds are **not** basketball-calibration evidence.

---

## 1. Environment (named)

| Item | Value |
|---|---|
| Operating system | Microsoft Windows 11 Pro, version `10.0.26100`, build `26100` |
| Architecture | x86-64 (`AMD64`) |
| CPU | Intel Core i7-2600 @ 3.40 GHz — 4 cores / 8 logical processors |
| Installed RAM | 16,265 MiB |
| Dart SDK | 3.12.2 (stable), `windows_x64`, Tue 2026-06-09 |
| Runtime / compilation mode | **AOT compiled native executable** (`dart compile exe`) — optimized desktop Dart, not `dart run` JIT and not debug mode |
| Benchmark binary | `packages/simulation_core/build/t016_bench.exe`, 6,702,080 bytes (deleted after measurement; rebuild from the committed harness) |
| League fixture | M001 `LeagueGenerator(GenerationConfig(seed: 20261028))`, 8 teams, `ActiveLineup.defaultFor` both sides |
| Rules | `GameRules.standard` — `rulesVersion` 2, 4 × 720 s periods, 300 s OT, `maxOvertimes` 10, 24 s shot clock, `maxEvents` 50000 |
| Versions exercised | `gameSimulationVersion` 4, `gameRulesVersion` 2, `gameEventSchemaVersion` 2, `gameActionDurationModelVersion` 2, `gameFingerprintVersion` 2 |

Background workload was limited to this shell session; no other user workloads were started deliberately.

## 2. Inputs and seed policy

- **Games:** 1,000 measured per run; 1,000 complete games is the AC12 sample size.
- **Matchup policy:** directed matchup `i % 56`, i.e. the 28 lexicographic unordered pairs of the eight id-sorted teams in both orientations — the same enumeration used by every M002 calibration harness.
- **Runtime seed policy:** `seed = 50001 + i` for `i ∈ [0, 1000)`.
  These seeds vary the game inputs for timing only. They lie outside every statistical seed corpus (`1..1300` development, `2001..2600` Amendment 003 held-out, `10001..10600` Amendment 004 held-out, unit-test ranges `1..400`) and must not be analysed as calibration evidence.
- **Warmup:** 60 discarded games (`--warmup=60`) before the measured loop, so page-in, allocator and code-path warmup costs fall outside the measurement. No GC can be forced in AOT, so warmup garbage may still be present at the baseline read; this biases the memory reading upward, not downward.

## 3. Method

**Timing.** Each game is timed with two independent `Stopwatch` scopes:

1. **`simulate`** — `GameSimulator().simulate(input)` only (engine cost).
2. **per-game total** — the whole measured iteration: `GameInput.create` + `simulate` + `GameEventReducer.validate` + `EventAccounting.aggregate` + bounds checks. This is a **conservative upper bound** on engine cost and is the value used for the AC12 total-time verdict.

`loopWallMs` is the wall clock of the entire 1,000-game loop, including the validation work.

**Memory.** `ProcessInfo.currentRss` is read immediately after warmup (baseline) and after the measured loop (end); `ProcessInfo.maxRss` gives the process peak. Incremental memory is reported both as `end − baseline` and as `peak − baseline`; the AC12 verdict uses the larger (`peak − baseline`).

**Correctness inside the benchmark.** Every one of the 1,000 games is validated per run:

- `GameEventReducer.validate` on the produced ledger (ordering, schema, causality).
- `EventAccounting.aggregate` reconciled against `result.homeScore` / `result.awayScore`.
- Bounds: non-empty event list, last event is `GameEnded`, `overtimes <= maxOvertimes`, `periodsPlayed <= periods + maxOvertimes`, `events.length <= maxEvents`.

Any typed `GameValidationException`, accounting mismatch or bound violation is counted and reported rather than silently dropped.

## 4. Reproducible commands

```powershell
# from the repository root
cd packages/simulation_core
dart analyze                        # No issues found
dart compile exe tool/t016_performance.dart -o build/t016_bench.exe

# one authoritative measurement (repeated three times)
#   games=1000, warmup=60, AOT binary
& '.\build\t016_bench.exe' --games=1000 --warmup=60 --out='build\t016_run1.json'
```

Harness arguments: `--games=<n>` (default 1000), `--warmup=<n>` (default 60), `--out=<path>` (omitted → JSON is printed to stdout only). The harness writes nothing outside `--out`.

## 5. Runtime results

Three independent 1,000-game AOT runs. Run 1 is the reported measurement; runs 2–3 are a stability check, not a search for a favourable result.

| Run | Completed | Typed failures | Accounting failures | Bound violations | Loop wall (ms) | Per-game total (ms) | p50 (ms) | **p95 (ms)** | p99 (ms) | max (ms) | `simulate` total (ms) | `simulate` p95 (ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1,000 | 0 | 0 | 0 | 6,327 | 6,325.8 | 5.511 | **9.527** | 13.508 | 29.796 | 4,382.0 | 6.655 |
| 2 | 1,000 | 0 | 0 | 0 | 5,582 | 5,580.9 | 5.268 | **7.508** | 9.482 | 39.366 | 3,873.8 | 5.289 |
| 3 | 1,000 | 0 | 0 | 0 | 5,651 | 5,650.4 | 5.339 | **7.252** | 10.441 | 17.640 | 3,918.6 | 5.401 |

Engine-only cost (`simulate`) is roughly 0.69 of the measured per-game total; the remainder is input construction, reducer validation and accounting reconciliation performed by the harness.

`externalCpuSeconds` from the OS was 6.641 / 5.844 / 5.969 s for runs 1–3, consistent with the single-threaded wall clock above.

Run 1's full JSON, including `perGameP50Ms` and `simulateP50Ms`, is committed as `t016-benchmark-1000-games-run1.json`.

## 6. Memory results

| Run | Baseline RSS (MiB) | End RSS (MiB) | Process peak `maxRss` (MiB) | Incremental `end − baseline` (MiB) | Incremental `peak − baseline` (MiB) |
|---|---|---|---|---|---|
| 1 | 20 | 39 | 39 | 19 | **19** |
| 2 | 20 | 39 | 39 | 19 | **19** |
| 3 | 20 | 38 | 38 | 18 | **18** |

Peak RSS grows by ~19 MiB across 1,000 complete games and does not keep growing after the warmup allocation, i.e. no evidence of unbounded per-game retention in this sample.

**Measurement limitation.** An external `Process.PeakWorkingSet64` cross-check returned `0` for the already-exited process on this platform, so it is **not** used; all memory figures come from Dart's `ProcessInfo` inside the measured process. RSS is a coarse allocator-level measure that includes the Dart heap and the VM's own footprint; it does not isolate simulation objects, and it does not prove the absence of leaks beyond 1,000 games.

## 7. AC12 verdicts

| AC12 criterion (frozen) | Threshold | Measured | Verdict |
|---|---|---|---|
| 1,000 complete games | ≤ 60 s on desktop optimized Dart | **6.327 s** (runs 2–3: 5.582 / 5.651 s) | **PASS** |
| p95 latency per game | ≤ 100 ms | **9.527 ms** (runs 2–3: 7.508 / 7.252 ms) | **PASS** |
| Incremental memory | ≤ 128 MiB | **19 MiB** peak − baseline (runs 2–3: 19 / 18 MiB) | **PASS** |
| Environment and warmup recorded | required | §1 and §2 above | **PASS** |
| No Android claim without device measurement | required | §8 — no device measurement performed | **PASS (compliant: Android NOT MEASURED)** |
| Correct execution (all games completed, no failures) | required by this task | 3,000/3,000 completed; 0 typed, 0 accounting, 0 bound violations | **PASS** |

Headroom is large: the total-time measurement has ~9.5× margin, the p95 measurement ~10× margin, and the memory measurement ~6.7× margin.

## 8. Android / mobile suitability

**Android performance is NOT MEASURED.** No Android device, emulator or profile-mode build was run for this task. The following are architectural observations only.

1. **CPU time.** A 1,000-game run costs ~5.6–6.3 s of desktop x86 wall clock for the full validate-and-reconcile loop, and ~3.9–4.4 s for pure simulation. Mid-range ARM mobile CPUs are commonly several times slower per core than a 2011-era desktop i7 at the same clock, so a single game should be expected to cost more than the ~4–6 ms measured here. That remains plausibly interactive for a single game, but this extrapolation is unmeasured and must not be presented as an Android result.
2. **Memory.** ~19 MiB of RSS growth for 1,000 complete games is modest by desktop standards. Because RSS includes the Dart heap and VM footprint, the incremental figure is a weak proxy for a Dart heap-only budget; a mobile heap limit check requires device measurement with the platform memory profiler.
3. **UI isolate blocking.** `GameSimulator.simulate` is a synchronous, pure-Dart, CPU-bound loop with no I/O and no yielding. Called on the Flutter UI isolate it would block frame production for the whole game duration (~4–6 ms measured here, more on mobile). The pure-Dart core is isolate-friendly in principle (no Flutter, Flame, database, network or production `dart:io` dependencies, deterministic integer PRNG state), but **no isolate offload has been implemented or measured**. Whether offloading is required is a UI-layer decision outside T016 scope.
4. **Determinism vs. platform.** Cross-runtime parity (`Dart VM` / `Chrome`) is covered by the existing AC11 suites, not by T016; T016 says nothing about ARM parity.
5. **Battery/thermal.** Not measured; sustained-load behaviour on a phone cannot be inferred from a 6-second desktop burst.

## 9. Verification performed

| Check | Command | Result |
|---|---|---|
| Static analysis (whole package) | `cd packages/simulation_core && dart analyze` | No issues found |
| Static analysis (harness) | `dart analyze tool/t016_performance.dart` | No issues found |
| Formatting | `dart format --set-exit-if-changed tool/t016_performance.dart` | Clean (0 changed) |
| Package test suite | `cd packages/simulation_core && dart test` | **351 passed**, 0 failed |
| No gameplay change | `git diff` shows no `lib/` or `test/` modification in this task | Confirmed |
| `dart:io` isolation | `lib/` untouched; `dart:io` is used only by `tool/` harnesses, as existing tooling already does | Unchanged |

Chrome-compatible tests, Flutter widget tests and M001 vector suites were **not** re-run for this task: no `lib/`, `test/` or M001 source file changed, so there is no new parity or vector surface introduced by T016. That omission is recorded rather than hidden.

## 10. Risks and limitations

1. **Single environment.** One desktop machine, one OS build, one SDK version. The AC12 thresholds are met here with wide margins, so a modestly slower machine would still pass; no claim is made about other hardware.
2. **Coarse memory measure.** `ProcessInfo` RSS mixes the simulation heap with VM overhead, and AOT GC cannot be forced, so the incremental figure is an upper-bound estimate rather than a precise heap measurement.
3. **Three runs only.** Stability across three runs is reported; no statistical claim about latency distribution tails beyond p99 is made, and `max` shows visible OS/GC jitter (17.6–39.4 ms), which is why p95 — not min or best — is the reported statistic.
4. **Runtime seeds are not calibration evidence.** `50001..51000` were chosen to be outside every statistical corpus; results here must never be pooled with T013/T014/T015/Amendment 003/004 samples.
5. **No leak proof.** 1,000 games show no growing RSS trend, but longer sessions (thousands of games, editor/live-sim use) are untested.
6. **Android and isolate offload unmeasured.** §8 is architectural reasoning, not a device profile.

## 11. Evidence artifacts

| Artifact | SHA-256 (LF bytes) |
|---|---|
| `t016-benchmark-1000-games-run1.json` | `06e7b4d056cd21a2486324b5639e5523247966f2a88e76c3acc1878068cdb4a9` |
| `t016-benchmark-1000-games-run2.json` | `3e97db679aa5f3dfd09e02d06b8e60e2c9605ab9e99b0f33d522937ad1372532` |
| `t016-benchmark-1000-games-run3.json` | `9af401d1603808c2cadfdc63d4aafc9da7146d4c6efb08aa7e48c0a946c35a66` |

Compiled binaries and the smoke run were deleted after measurement; the harness regenerates them.

## 12. T016 verdict

**T016 PASS** — every frozen AC12 criterion is met on the named environment with all 3,000 measured games completing without typed, accounting or bound violations, and Android suitability remains explicitly NOT MEASURED.

No optimization was performed and no requirement was changed. T017–T019 remain unauthorized.
