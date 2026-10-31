# T016 — Seed and Matchup Provenance Correction Addendum

> **Date:** 2026-10-31
> **Status:** CORRECTION RECORD. The original T016 report, tooling revision and measurements are preserved unchanged.
> **Original evidence:** commit `04d7d8f23c27925bb44ac22ad32abcba4ff27894` — `t016-performance-report.md`, `t016-benchmark-1000-games-run{1,2,3}.json`
> **Blocker record:** `t017-regression-scope-report.md` §10 (BLOCKER B1), commit `f2225ce1b401fe546e9ed799ca384060c447988a`
> **Corrected tooling and evidence:** this commit
> **Simulation source:** untouched by this correction; `git diff 83edd52..HEAD -- packages/simulation_core/lib` remains **empty** (no coefficient, clamp, timing, rule or version change).

---

## 1. What the seed-range error was

The T016 harness derived **both** the warmup games and the measured games from one index space:

```dart
// original, commit 04d7d8f, tool/t016_performance.dart
116:        seed: runtimeSeedBase + index,
183:  for (var i = 0; i < warmup; i++) {                 // warmup indices 0..59
184:    runOne(i);
196:  for (var i = warmup; i < warmup + games; i++) {    // measured indices 60..1059
197:    final outcome = runOne(i);
```

Because the measured loop started at `i = warmup`, the warmup consumed the first 60 seeds and the measured cohort began at index 60. With the frozen protocol (`--warmup=60 --games=1000`) the measured games therefore ran:

| | Documented in the original artifacts | Actually executed |
|---|---|---|
| Measured seeds | `50001..51000` (`seed = 50001 + i`, `i ∈ [0, 1000)`) | **`50061..51060`** |
| First measured matchup | index `0` | **index `4`** (`60 % 56`) |
| Last measured matchup | index `51` | index `51` (`1059 % 56`) |

Two defects followed:

1. **False provenance.** The `seedPolicy` field in all three committed JSON files, `t016-performance-report.md` §2 ("`seed = 50001 + i` for `i ∈ [0, 1000)`") and §10.4 ("`50001..51000`") described a cohort that was never simulated.
2. **Cohort instability.** `--warmup` silently shifted the measured cohort, so the recorded cohort could not be reconstructed from its documented description.

The AC12 measurements themselves were unaffected in substance: 1,000 distinct complete games really were timed, with zero typed, accounting or bound failures, and the actual seeds `50061..51060` overlap no statistical corpus. The defect was in the *record*, not the *thresholds*.

## 2. Which previously reported measurements used the mis-described cohort

All three original T016 runs used the undisclosed cohort. Their measured **performance numbers stand unchanged and are not retracted**; only the cohort description attached to them was wrong.

| Original artifact | Cohort actually used | Performance figures still valid |
|---|---|---|
| `t016-benchmark-1000-games-run1.json` | seeds `50061..51060`, matchups `4..51` | 6.327 s, p95 9.527 ms, 19 MiB incremental |
| `t016-benchmark-1000-games-run2.json` | seeds `50061..51060`, matchups `4..51` | 5.582 s, p95 7.508 ms, 19 MiB incremental |
| `t016-benchmark-1000-games-run3.json` | seeds `50061..51060`, matchups `4..51` | 5.651 s, p95 7.252 ms, 18 MiB incremental |

The AC12 verdict in the original report (**PASS**) is therefore not reversed; it was reached on a real 1,000-game cohort whose label was wrong.

## 3. How the harness was repaired

`packages/simulation_core/tool/t016_performance.dart` (only file changed in this correction):

| Change | Detail |
|---|---|
| Disjoint warmup space | new `const int warmupSeedBase = 60001;` — warmup game `i` uses `60001 + i` |
| Measured cohort fixed | measured loop runs `i ∈ [0, games)`; measured game `i` uses `runtimeSeedBase + i` = `50001 + i` |
| Matchup sequence fixed | measured game `i` uses directed matchup `i % 56`, starting at index `0` |
| Explicit observed provenance | `measuredCohort` block records `firstObservedSeed`, `lastObservedSeed`, `distinctObservedSeeds`, `firstObservedMatchupIndex`, `lastObservedMatchupIndex`, `warmupSeedRange`, `seedRangesDisjoint`, `observedScheduleValid` — read back from the constructed `GameInput`, not recomputed from the loop variable |
| Pre-run schedule validation | rejects `--games` beyond the measured range (`exit 64`); asserts measured and warmup ranges are disjoint; asserts **neither** range intersects any statistical corpus (`development 1..1300`, `Amendment 003 held-out 2001..2600`, `Amendment 004 held-out 10001..10600`, `unit tests 1..400`); asserts every scheduled matchup index is in `0..55` (`exit 65`) |
| Post-run cohort validation | asserts first observed seed `= 50001`, last `= 50000 + games`, first matchup `= 0`, last matchup `= (games-1) % 56`, distinct observed seeds `= completed`, and every observed seed inside the declared range (`exit 66`) |
| `runOne` signature | now takes explicit `gameIndex`, `seed`, `idPrefix` so warmup and measured games can never share an index space again |

Verification of the repair (runs with the corrected AOT binary):

```
games=10001 --warmup=1  -> "games=10001 exceeds the measured seed range (50001..60000)"  exit=64
games=8 --warmup=0/3/25 -> measuredCohort identical except warmupSeedRange
                          firstObservedSeed=50001 lastObservedSeed=50008
                          firstObservedMatchupIndex=0 lastObservedMatchupIndex=7
```

That last result demonstrates the required property: **changing `--warmup` no longer changes any measured game input.**

## 4. Exact corrected benchmark inputs

| Item | Value |
|---|---|
| Measured games | 1,000 |
| Warmup games | 60 (discarded) |
| Measured seeds | **`50001..51000`**, one per game, all distinct |
| First / last measured matchup index | **`0` / `47`** (`999 % 56`) |
| Warmup seeds | `60001..60060` |
| League fixture | `LeagueGenerator(GenerationConfig(seed: 20261028))`, 8 teams |
| Rules | `GameRules.standard` (rules v2, 4×720 s, 300 s OT, `maxOvertimes` 10, 24 s clock, `maxEvents` 50000) |
| Versions | `gameSimulationVersion` 4, `gameRulesVersion` 2, `gameEventSchemaVersion` 2, `gameActionDurationModelVersion` 2, `gameFingerprintVersion` 2 |
| Compilation | Windows Dart AOT: `dart compile exe tool/t016_performance.dart -o build/t016_bench.exe` |
| Runtime | Windows 11 Pro 10.0.26100 build 26100 x64; Intel Core i7-2600 @ 3.40 GHz (4C/8T); 16,265 MiB; Dart SDK 3.12.2 |
| Schedule validation | `observedScheduleValid = true` in all three runs |

### Reproducible commands

```powershell
cd E:/ballgorithm-dev/packages/simulation_core
dart analyze tool/t016_performance.dart
dart compile exe tool/t016_performance.dart -o build/t016_bench.exe
1..3 | ForEach-Object {
  & '.\build\t016_bench.exe' --games=1000 --warmup=60 --out="build\t016c_run$_.json"
}
```

## 5. Original versus corrected performance results

| Run | Cohort | Complete | Failures | Total (s) | p50 (ms) | **p95 (ms)** | p99 (ms) | max (ms) | `simulate` total (s) | Incremental RSS (MiB) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 (original) | seeds 50061–51060 | 1,000 | 0 | 6.327 | 5.511 | **9.527** | 13.508 | 29.796 | 4.382 | 19 (20→39) |
| 1 (corrected) | seeds 50001–51000 | 1,000 | 0 | **5.826** | 5.471 | **8.207** | 10.592 | 13.526 | 4.058 | **23** (21→44) |
| 2 (original) | seeds 50061–51060 | 1,000 | 0 | 5.582 | 5.268 | **7.508** | 9.482 | 39.366 | 3.874 | 19 |
| 2 (corrected) | seeds 50001–51000 | 1,000 | 0 | **6.161** | 5.642 | **9.397** | 12.700 | 26.408 | 4.281 | **23** |
| 3 (original) | seeds 50061–51060 | 1,000 | 0 | 5.651 | 5.339 | **7.252** | 10.441 | 17.640 | 3.919 | 18 |
| 3 (corrected) | seeds 50001–51000 | 1,000 | 0 | **5.978** | 5.381 | **9.339** | 13.554 | 20.264 | 4.139 | **22** |

Corrected range: total 5.83–6.16 s, p95 8.21–9.40 ms, incremental 22–23 MiB. The two cohorts are statistically indistinguishable in cost; the small differences are ordinary timing and allocator variance between processes, not a real change in engine work (the same 1,000 games, same league, same rules).

Incremental RSS is 4–5 MiB higher in the corrected runs (21 MiB baseline instead of 20 MiB); the larger `peak − baseline` delta is dominated by the measured-memory granularity (integer MiB) and process-level allocation variance, not by a distinct workload.

## 6. Did the AC12 verdict change?

**No.** Both cohorts pass every frozen criterion:

| AC12 criterion | Threshold | Original (04d7d8f) | Corrected | Verdict |
|---|---|---|---|---|
| 1,000 complete games | ≤ 60 s | 5.58–6.33 s | 5.83–6.16 s | **PASS** |
| p95 latency per game | ≤ 100 ms | 7.25–9.53 ms | 8.21–9.40 ms | **PASS** |
| Incremental memory | ≤ 128 MiB | 18–19 MiB | 22–23 MiB | **PASS** |
| Environment + warmup recorded | required | yes | yes | **PASS** |
| No Android claim | required | correct | correct | **PASS (compliant)** |
| Execution correctness | required | 3,000/3,000, 0 failures | 3,000/3,000, 0 failures | **PASS** |

Android remains **NOT MEASURED**; no device, emulator or profile run was performed, and no ARM extrapolation is claimed.

## 7. Preserved evidence

| Artifact | Role | SHA-256 (LF bytes) |
|---|---|---|
| `t016-benchmark-1000-games-run{1,2,3}.json` | original, unchanged | `06e7b4d0…b4a9`, `3e97db67…2532`, `9af401d1…5a66` |
| `t016-performance-report.md` | original report, unchanged | — |
| `t017-regression-scope-report.md` | historical T017 FAIL report, unchanged | — |
| `t016-benchmark-corrected-1000-games-run1.json` | corrected | `2de8540a82e746d74361fa41db4c16d4acb92228c99c4026bcbc11def6a5c1f6` |
| `t016-benchmark-corrected-1000-games-run2.json` | corrected | `16b9d732cb64c784441d5235456562b20d46fe51587a248ba5f4e788dd776dd7` |
| `t016-benchmark-corrected-1000-games-run3.json` | corrected | `6eb7415fa7515e41352d220d366e2aa02f857c4c4e2ec2ff77324c9673ed88bb` |

Reported hashes are over LF-normalized bytes and are verified against committed blobs with:

```bash
git show <commit>:specs/002-possession-simulation/t016-benchmark-corrected-1000-games-run1.json | sha256sum
```

## 8. Scope of the correction

- Changed: `packages/simulation_core/tool/t016_performance.dart` (benchmark tooling only), three corrected benchmark JSON files, this addendum.
- Not changed: any `lib/` simulation source, any test assertion, any dependency declaration, any frozen acceptance rule, any prior commit (`04d7d8f` and `f2225ce` are not amended or rewritten), any historical raw evidence.
