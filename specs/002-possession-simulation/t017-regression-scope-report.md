# T017 — Full Regression, Compatibility and Scope Audit

> **Date:** 2026-10-31
> **Task:** T017 — full Dart/Flutter regressions, format/analyze, independence and scope audit (Amendment 004 / M002).
> **Authorization:** owner *Ballgorithm M002 — T017 Full Regression and Scope Audit*
> **Source commit audited:** `04d7d8f23c27925bb44ac22ad32abcba4ff27894` (`develop/m002`; unpushed, 1 ahead of `origin/develop/m002` @ `dc6f85a8`)
> **Scope of this task:** verification and documentation only. No `lib/`, test assertion, frozen specification or simulation behaviour was modified.

---

## 1. Final verdict

**T017 FAIL — CORRECTIVE ACTION REQUIRED**

Every T017 regression, compatibility, formatting, analysis, independence and scope check **passed**. One blocker remains, and it is in **T016's evidence provenance**, not in the simulation:

> **BLOCKER B1** — the committed T016 benchmark report and JSON artifacts state the measured cohort as seeds `50001..51000` (measured game `i` uses seed `50001 + i`), but the committed harness actually simulated seeds **`50061..51060`**, starting at matchup index **4**. The AC12 measurements themselves are unaffected; the provenance statement in committed evidence is false, and `--warmup` mutates the measured cohort, so the recorded cohort is not reproducible from the "documented" description.

T016 is therefore **not marked complete**, and T018 is not eligible until B1 is corrected under separate authorization.

---

## 2. Environment and tooling

| Item | Value |
|---|---|
| Workspace | `E:/ballgorithm-dev` |
| Branch | `develop/m002` (clean tree at audit start and end) |
| HEAD | `04d7d8f23c27925bb44ac22ad32abcba4ff27894` |
| `origin/develop/m002` | `dc6f85a822ee448f032c49a331b313bf9abc032c` (local is 1 ahead; no divergence) |
| OS | Microsoft Windows 11 Pro `10.0.26100`, build `26100`, x64 |
| CPU / RAM | Intel Core i7-2600 @ 3.40 GHz (4C/8T) / 16,265 MiB |
| Dart SDK | 3.12.2 (stable), `windows_x64` |
| Flutter | 3.44.2 stable, framework `c9a6c48423`, engine `04efd7c093d4` |
| Python (evidence verifiers) | 3.13.1 |

## 3. Commands and results

### 3.1 Simulation core (`packages/simulation_core`)

| # | Command | Exit | Result |
|---|---|---|---|
| 1 | `dart analyze lib test tool` | **0** | `No issues found!` — 0 errors, 0 warnings, 0 lints |
| 2 | `dart format --output=none --set-exit-if-changed lib test tool` | **0** | `Formatted 68 files (0 changed)` |
| 3 | `dart test` | **0** | **351 passed, 0 failed** (12 s) |
| 4 | `dart test -p chrome test/deterministic_random_test.dart test/generator_test.dart test/validation_test.dart test/simulation` | **0** | **350 passed, 0 failed** (115 s) |

**Chrome exclusion (explicit):** `test/domain_isolation_test.dart` is IO-dependent (imports `dart:io` to scan `lib/` sources) and cannot run under `-p chrome`. It is the single difference between the 351 VM tests and the 350 Chrome tests. No other test was excluded, tagged or skipped; there is no `dart_test.yaml` tag configuration in the package.

### 3.2 Flutter application (repository root)

| # | Command | Exit | Result |
|---|---|---|---|
| 5 | `flutter analyze` | **0** | `No issues found!` (40.3 s) |
| 6 | `flutter test` | **0** | **8 passed, 0 failed** (26 s) |

Warnings: none reported by any of the six commands. `flutter test` regenerated `windows/flutter/generated_plugin_registrant.*` and `generated_plugins.cmake` as a build side effect; these were reverted (`git checkout windows/`) so the audited tree stayed clean. No source file was changed by any verification command.

### 3.3 Checks deliberately not repeated

| Check | Why not run |
|---|---|
| T015 1,120-game calibration cohort | Already verified evidence; T017 is a regression/scope audit, not a re-calibration |
| T014 E1–E6 sensitivity re-execution | Already verified evidence |
| T016 1,000-game benchmark | Already committed evidence, and reproducing it is explicitly out of scope for T017 (its *provenance* was audited instead — see B1) |
| Amendment 003/004 held-out cohorts | Already verified evidence; integrity re-verified from committed artifacts (§8) |

## 4. VM / Chrome compatibility

- VM: 351/351 pass. Chrome: 350/350 pass (IO test excluded).
- Identical assertions execute on both platforms, including the `t012` canonical-ledger suite, which recomputes identical ledger bytes and SHA-256 digests on VM and Chrome, and `deterministic_random_test.dart`, which pins `xorshift32-v1` vectors.
- No platform-conditional test was added, removed or skipped to obtain this result.

## 5. M001 preservation (AC11)

| Check | Evidence | Status |
|---|---|---|
| M001 source untouched since baseline `a431aeb` | `git diff --name-only a431aeb..HEAD -- lib/src/generation lib/src/models lib/src/validation lib/src/domain_versions.dart` → **empty** | **PASS** |
| No behavioural line removed anywhere in `lib/` since M001 | `git diff --numstat a431aeb..HEAD -- lib` → **0 deletions** (43 files, 17,322 insertions, 0 deletions) | **PASS** |
| M001 versions / default snapshot / PRNG vectors pinned | `test/simulation/m001_regression_test.dart` — `M001 versions and default snapshot remain pinned` | **PASS** |
| No `dart:math Random` in gameplay | `grep "Random("` in `lib/` matches only `DeterministicRandom`; `dart:math` is imported solely as `show max` in `probability_model.dart` | **PASS** |

`simulation_core.dart` gained 16 additive export lines for M002 symbols; no existing M001 export was removed or renamed.

## 6. Canonical fixtures, versions and fingerprints

| Requirement | Evidence | Status |
|---|---|---|
| v1 canonical ledger fixture | `test/simulation/t012_canonical_ledger_fixture.dart` (seed-42, 800 events, 94–77) | **PASS** |
| v2 canonical ledger fixture | `t012_canonical_ledger_fixture_v2.dart` | **PASS** |
| v3 canonical ledger fixture | `t012_canonical_ledger_fixture_v3.dart` | **PASS** |
| v4 canonical ledger fixture | `t012_canonical_ledger_fixture_v4.dart` | **PASS** |
| Fingerprint compatibility | `gameFingerprintVersion = 2` retained; `t012`/`turnover_nonsteal` fingerprint fixtures pass on VM and Chrome | **PASS** |
| Version contract | `gameSimulationVersion = 4`, `gameRulesVersion = 2`, `gameEventSchemaVersion = 2`, `gameActionDurationModelVersion = 2`, `gameFingerprintVersion = 2`; suite asserts version-consistency rejections | **PASS** |
| Seed identity / alias | `s and s + 2^32 share events but not the fingerprint`; `normalizedSeed` 0 → `0x9E3779B9` | **PASS** |
| Replay determinism | 20-repetition identity, pinned digests, reducer round trip (T012/T013 suites) | **PASS** |

## 7. Acceptance-matrix audit (AC01–AC13)

| AC | Requirement | Evidence | Status |
|---|---|---|---|
| AC01 | Headless pure-Dart simulation | `dart test` runs the full game headlessly; `domain_isolation_test.dart` scans `lib/` imports | **PASS** |
| AC02 | Input/version validation | `game_input_test.dart`, `validation_test.dart`, typed `GameValidationException` paths | **PASS** |
| AC03 | Determinism | `t012_canonical_ledger_test.dart` + `m001_regression_test.dart`; VM/Chrome parity | **PASS** |
| AC04 | Clock handling | `game_reducer_test.dart`: shot-clock bounds, horn precedence, simultaneous expiry, OT bounds (`enforces the ten-overtime bound`) | **PASS** |
| AC05 | Event causality | `t010_event_hardening_test.dart`, `t013_ledger_mutation_test.dart` (24 one-defect mutations rejected) | **PASS** |
| AC06 | Box-score accounting | `game_accounting_test.dart`, `event_accounting.dart` reconciliation in every simulation harness | **PASS** |
| AC07 | Event vocabulary | `game_event_test.dart`, `turnover_nonsteal_test.dart`, attribution tests | **PASS** |
| AC08 | Boundedness / typed errors | `t013_adversarial_game_test.dart`: `maxEvents` 50,001st event, zero-clock guard, 11th OT, invalid probability inputs | **PASS** |
| AC09 | Directional skills | E1–E6: historical v1 E4 INCONCLUSIVE (preserved); v2 and v4 reruns PASSED (dev seeds `1..200`; fresh `10001..10200` for the held-out G9) — **AC09 remains NOT signed off** | **PASS (verification only — gate open by design)** |
| AC10 | Calibration | T015 executed; owner review pending — **not passed** | **PASS (verification only — gate open by design)** |
| AC11 | M001 preservation | §5 above | **PASS** |
| AC12 | Desktop performance | T016 measured and passes thresholds on the named environment; **provenance statement defective — see B1** | **BLOCKER (evidence, not threshold)** |
| AC13 | Scope restrictions | §9 below | **PASS** |

## 8. Historical evidence and D1 status

All committed evidence verifiers were re-run against `04d7d8f`:

| Verifier | Command | Result |
|---|---|---|
| Amendment 004 recovery | `python specs/002-possession-simulation/amendment-004-recovery/verify_evidence.py` | **PASSED** — 5 artifacts, 280 slots, seeds 1–200, gates G1–G8 + G9 recomputed |
| Amendment 004 held-out (§4 D1) | `python .../amendment-004-heldout/verify_heldout.py --git-ref 04d7d8f…` | **PASSED** — 12 artifacts, 2,240 primary games, 600 seeds, G1–G9 |
| D1 CGM/DOF audit | `python .../amendment-004-heldout/audit_d1_dof.py` | **PASSED** — 66 estimators, max diff `5.551e-17`, 0 negative variances, 0 conclusion flips |

| Integrity claim | Evidence | Status |
|---|---|---|
| Amendment 003 guardrail failures preserved | `amendment-003-waiver-addendum.md` unchanged since `9f8458a`; pace `+2.21%` dev / `+2.05%` held-out vs `+2.5%` min; OF share `26.02%` / `25.67%` vs `≤24.0%` | **PASS (failures retained)** |
| Amendment 004 qualified D1 disposition preserved | `OWNER-D1-DISPOSITION.md` intact; disposition `QUALIFIED HELD-OUT EVIDENCE ACCEPTED FOR FURTHER M002 REVIEW — D1 PROCEDURAL EXCEPTION RECORDED` | **PASS** |
| Frozen thresholds not rewritten | `git diff a7910cf..HEAD -- amendment-004-turnover-calibration-spec.md acceptance-matrix.md` → **empty** | **PASS** |
| Coefficients/timing unchanged since authorized v4 implementation | `git diff 83edd52..HEAD -- lib` → **empty**; offensive-foul base still `170`, clamp still `clampBasisPoints(..., min: 0, max: 10000)` with `[100, 1000]` call sites | **PASS** |
| Raw held-out evidence intact | checksum-verified against committed blobs by `verify_heldout.py` | **PASS** |
| AC09/AC10 not prematurely signed off | `tasks.md` records AC09 NOT passed (v1) and AC10 READY FOR OWNER REVIEW (not passed) | **PASS** |

## 9. Independence and dependency / scope audit (AC13)

**Package dependencies** (`packages/simulation_core/pubspec.yaml`): runtime `crypto: ^3.0.7` only (the approved SHA-256 fingerprinting exception); dev `lints`, `test`. No Flutter, Flame, HTTP, database, storage or platform package.

**Imports inside `lib/`:** relative library imports plus `dart:convert`, `dart:math show max`, and `package:crypto/crypto.dart`. A scan for `dart:io`, `dart:ui`, `package:flutter`, `package:flame`, `package:http`, `dart:html`, `dart:js`, `package:sqflite`, `package:path_provider` in `lib/` returns **no matches**.

**Simulation behaviour untouched since `83edd52`:** `git diff 83edd52..HEAD -- packages/simulation_core/lib` is empty, so every later commit is documentation/evidence/tooling only.

**Source changes since M001 baseline `a431aeb`:** 43 files, all additions (`0 deletions`), confined to `lib/simulation_core.dart` (additive exports) and `lib/src/simulation/*` plus their tests. No season, trade, contract, coaching, rotation, injury, salary, draft or free-agent system exists in `lib/` (grep matches are prose uses of the word "contract" in protocol documentation).

**T016 tooling is not a simulation dependency.** `tool/t016_performance.dart` is a `tool/` harness only; it is never imported by `lib/`, is not exported from `simulation_core.dart`, and is not listed as a dependency. `dart:io` appears only in `tool/` harnesses and in the one IO-scoped test.

**Flutter presentation layer:** no simulation rule lives in `lib/` (app); the app imports the core package and formats values. `flutter analyze` clean.

## 10. BLOCKER B1 — T016 evidence provenance (detail)

**Claim in committed evidence** (`t016-benchmark-1000-games-run{1,2,3}.json`, `seedPolicy` field):
> `seed = 50001 + i for i in [0, games); outside every statistical seed corpus`

and in `t016-performance-report.md` §2:
> `seed = 50001 + i` for `i ∈ [0, 1000)`

and §10.4:
> `50001..51000` were chosen to be outside every statistical corpus

**What the committed harness actually does** (`git show 04d7d8f:packages/simulation_core/tool/t016_performance.dart`):

```dart
106:    final matchupIndex = index % directedMatchups;
116:        seed: runtimeSeedBase + index,
183:  for (var i = 0; i < warmup; i++) {          // warmup consumes indices 0..59
184:    runOne(i);
196:  for (var i = warmup; i < warmup + games; i++) {   // measured indices 60..1059
197:    final outcome = runOne(i);
```

With `--warmup=60 --games=1000`, the measured games ran indices `60..1059`, i.e. **seeds `50061..51060`** and **matchup indices starting at `60 % 56 = 4`** — not `50001..51000` starting at matchup 0.

**Impact assessment**

| Aspect | Impact |
|---|---|
| AC12 thresholds (60 s / 100 ms p95 / 128 MiB) | **Unaffected.** 1,000 distinct complete games were measured, 0 typed / 0 accounting / 0 bound failures |
| Calibration isolation | **Still holds.** `50061..51060` overlaps no statistical corpus (`1..1300`, `2001..2600`, `10001..10600`), so no T013–T015/Amendment 003/004 sample was contaminated |
| Provenance truthfulness | **Defective.** The recorded cohort description is false |
| Reproducibility | **Weakened.** `--warmup` shifts the measured cohort, so the recorded cohort cannot be re-derived from the documented description alone |

**Reproduction of the finding (no simulation needed):**

```bash
cd E:/ballgorithm-dev
git show 04d7d8f:packages/simulation_core/tool/t016_performance.dart | sed -n '106,120p;180,200p'
python -c "
import json;d=json.load(open('specs/002-possession-simulation/t016-benchmark-1000-games-run1.json'))
print(d['seedPolicy'], d['warmupGames'], d['gamesRequested'])"
```

**Prepared correction (NOT committed — requires separate authorization):** the working repair is preserved in `git stash@{0}` ("T016 harness seed-space fix"). It (a) moves warmup to a disjoint seed range `60001 + i`, (b) makes measured games run `i ∈ [0, games)` → seeds `50001..51000` at matchups `0..`, (c) rejects `--games` values whose range would collide with the warmup range, (d) emits observed-cohort provenance (`firstObservedSeed`, `lastObservedSeed`, `distinctObservedSeeds`, first/last matchup index) read back from the constructed inputs so future claims are self-verifying. It does **not** touch simulation behaviour. Applying it requires re-running the AOT benchmark and refreshing the report figures and §11 SHA-256 values, i.e. an amended T016 commit.

Per the T017 instruction ("Do not automatically fix blockers"), it was **not** applied.

## 11. Known mobile limitations (from T016, unchanged)

Android performance remains **NOT MEASURED** — no device, emulator or profile build was executed. Architectural observations only:

1. **CPU:** ~4–6 ms desktop per game (`simulate` ~3.9 ms) will cost more on mid-range ARM cores; the extrapolation is unmeasured.
2. **Memory:** ~19 MiB RSS growth over 1,000 games mixes the Dart heap with VM footprint; it is a weak proxy for a mobile heap budget.
3. **UI isolate:** `GameSimulator.simulate` is synchronous and CPU-bound; on the Flutter UI isolate it would block frames for the full game duration. The pure-Dart core is isolate-friendly in principle, but **no isolate offload has been implemented or measured**.
4. No ARM parity, battery or thermal data exists.

## 12. Open items

| ID | Class | Item |
|---|---|---|
| **B1** | **BLOCKER** | T016 seed-provenance claim false (`50001..51000` vs actual `50061..51060`); `--warmup` mutates the measured cohort. Fix prepared in `git stash@{0}`; needs authorization to commit, re-run, refresh hashes. |
| W1 | WARNING | `simulate` is synchronous and would block the Flutter UI isolate; no offload implemented or measured. |
| W2 | WARNING | Android performance NOT MEASURED (no device). |
| W3 | WARNING | T016 memory evidence is RSS-based (allocator + VM overhead), not heap-isolated; AOT GC cannot be forced. |
| W4 | WARNING | Amendment 003 pace-share failures and the procedural waiver remain formally FAILED; AC09 and AC10 remain unsigned. |
| W5 | WARNING | Amendment 004 D1 procedural exception remains recorded; qualified evidence only, single league fixture, `[100, 1000]` bp clamp-floor binding rate and inside-vs-midrange zone split unmeasured. |
| D1 | DEFERRED | `tasks.md` T016/T017 ledger rows remain unchecked pending B1 (see §13). |
| D2 | DEFERRED | Chrome exclusion of `domain_isolation_test.dart` is structural (`dart:io` source scan), not a defect. |

## 13. Recommendation for T018

**T018 is NOT eligible.** T018 prepares the exact AC01–AC13 acceptance report, which would inherit B1 into the permanent record. Recommended sequence:

1. Authorize the prepared T016 harness fix (`git stash@{0}`), re-run the AOT benchmark, refresh `t016-performance-report.md` figures and §11 hashes, and amend the unpushed T016 commit.
2. Re-issue T017 closeout: only the T016 artifact hashes change; no T017 regression check needs repeating (no `lib/`, `test/` or dependency change is involved).
3. Then authorize T018.

`tasks.md` remains with T016 and T017 **unchecked**, because T016's evidence is not verified as stated and T017's authorization bundled T016 closeout. T018 and T019 remain unchecked and unauthorized.
