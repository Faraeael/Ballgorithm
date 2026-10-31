# T017 — Closeout Addendum: BLOCKER B1 Resolution

> **Date:** 2026-10-31
> **Status:** T017 CONDITIONALLY CLOSED. The historical `t017-regression-scope-report.md` is preserved unchanged, including its `T017 FAIL — CORRECTIVE ACTION REQUIRED` verdict.
> **Historical report:** `t017-regression-scope-report.md`, commit `f2225ce1b401fe546e9ed799ca384060c447988a`
> **B1 correction:** commit `29d71d32792701d0dcb84d91692d28958b9738f2` (`perf(t016): correct benchmark seed/matchup provenance and re-measure AC12`)
> **This addendum:** separate documentation commit

---

## 1. Why a separate addendum

The T017 report recorded `T017 FAIL — CORRECTIVE ACTION REQUIRED` with exactly one blocker, B1. Rewriting that report would destroy the audit trail that caught the defect. This addendum records the resolution instead: the failure report stands, and the blocker it raised is now closed with verifiable evidence.

## 2. B1 was the sole blocker

The T017 report §12 lists one `BLOCKER` row (B1) and warnings W1–W5 plus deferred items D1–D2. Every one of T017's own regression, compatibility, formatting, analysis, independence and scope checks passed at the time (`dart analyze` clean, `dart format` 68 files 0 changed, 351 VM / 350 Chrome / 8 Flutter tests, evidence verifiers PASS). No second blocker was raised, and none has since appeared.

## 3. Blocker resolution

| B1 requirement | Resolution | Evidence |
|---|---|---|
| Warmup and measured seed spaces disjoint | Warmup uses `60001 + i`; measured uses `50001 + i` | `t016_performance.dart`: `warmupSeedBase`, disjoint guard, `measuredCohort.seedRangesDisjoint = true` |
| Exactly 1,000 measured games use seeds `50001..51000` | Confirmed by execution, read back from built inputs | `firstObservedSeed = 50001`, `lastObservedSeed = 51000`, `distinctObservedSeeds = 1000` in all three corrected runs |
| Measured matchup sequence begins at index `0` | Measured loop runs `i ∈ [0, games)` | `firstObservedMatchupIndex = 0`, `lastObservedMatchupIndex = 47` |
| Changing `--warmup` does not change measured inputs | Verified by differential execution at `--warmup=0/3/25` | `measuredCohort` identical except `warmupSeedRange` |
| Observed first/last seed and matchup recorded from actual execution | `RunOutcome` carries `seed`/`matchupIndex` from the constructed `GameInput` | `measuredCohort` block |
| Harness validates schedules before benchmarking | Pre-run: range, disjointness, corpus non-overlap, matchup bounds (`exit 64/65`); post-run: observed-vs-scheduled equality (`exit 66`) | `games=10001` run rejected with `exit 64`; `observedScheduleValid = true` |
| No measured seeds overlap calibration corpora | Explicit corpus check against `1..1300`, `2001..2600`, `10001..10600`, `1..400` | `statisticalSeedCorpora` guard, passes |
| AC12 thresholds re-met on the corrected cohort | Total 5.83–6.16 s ≤ 60 s; p95 8.21–9.40 ms ≤ 100 ms; incremental 22–23 MiB ≤ 128 MiB | `t016-benchmark-corrected-1000-games-run{1,2,3}.json` |
| Historical evidence preserved | Original JSONs, original report, historical T017 FAIL report all unchanged | `git diff` empty for those paths |

Full detail: `t016-provenance-correction-addendum.md`.

## 4. Correction scope verification

| Claim | Verification | Result |
|---|---|---|
| Only benchmark tooling changed | `git diff --stat f2225ce..29d71d3` → `tool/t016_performance.dart` + T016 evidence/docs | **CONFIRMED** |
| No simulation library change | `git diff --stat f2225ce..HEAD -- packages/simulation_core/lib` → empty | **CONFIRMED** |
| No test assertion change | `git diff --stat f2225ce..HEAD -- packages/simulation_core/test lib/ test/` → empty | **CONFIRMED** |
| No dependency declaration change | `git diff --stat f2225ce..HEAD -- packages/simulation_core/pubspec.yaml pubspec.yaml` → empty | **CONFIRMED** |
| No frozen acceptance rule change | `git diff --stat f2225ce..HEAD -- acceptance-matrix.md amendment-004-turnover-calibration-spec.md amendment-003-seed-provenance-manifest.md` → empty | **CONFIRMED** |
| No coefficient/clamp/timing/version change | `git diff 83edd52..HEAD -- packages/simulation_core/lib` → empty; offensive-foul base still `170`, clamp still `[100, 1000]` | **CONFIRMED** |
| Committed evidence bytes match recorded hashes | `git show 29d71d3:…corrected-1000-games-run{1,2,3}.json \| sha256sum` equals the addendum table | **CONFIRMED** |

## 5. Reuse of the previous regression results

The T017 regression matrix is reused, not re-run, because the tested source is byte-identical:

| Command | Previous result | Reused? | Justification |
|---|---|---|---|
| `dart analyze lib test tool` | clean | Yes | `lib/`, `test/` unchanged since `f2225ce`; `tool/` re-analyzed below |
| `dart format --output=none --set-exit-if-changed lib test tool` | 68 files, 0 changed | Partially re-run | Corrected harness re-checked: 0 changed |
| `dart test` (VM) | 351 passed | Yes | No `lib/` or `test/` change |
| `dart test -p chrome …` | 350 passed | Yes | No `lib/` or `test/` change |
| `flutter analyze` / `flutter test` | clean / 8 passed | Yes | No app or core source change |

Targeted verification of the corrected tooling (re-run after the correction):

| Command | Result |
|---|---|
| `dart analyze tool` | `No issues found!` |
| `dart analyze` (whole package) | `No issues found!` |
| `dart format --output=none --set-exit-if-changed tool/t016_performance.dart` | 1 file, 0 changed (exit 0) |

## 6. Final task state

| Task | State |
|---|---|
| T016 | **COMPLETE** — AC12 PASS on the corrected, self-verifying cohort; Android NOT MEASURED |
| T017 | **COMPLETE** — regression/scope audit passed; sole blocker B1 resolved and verified |
| T018 | Unchecked, unauthorized |
| T019 | Unchecked, unauthorized |

No milestone acceptance, AC09/AC10 sign-off, or M002 completion is implied by this closeout.
