# M002 Acceptance Evidence Report

> **Date:** 2026-10-31
> **Milestone:** M002 possession simulation (Amendments 001–004)
> **Source commit reported:** `6097ea491f201e2a4ff5eb563e5e0343c5f223c1` (`develop/m002`, branch 4 commits ahead of `origin/develop/m002` @ `dc6f85a8`)
> **Current model versions:** `gameSimulationVersion` **4**, `gameRulesVersion` **2**, `gameEventSchemaVersion` **2**, `gameActionDurationModelVersion` **2**, `gameFingerprintVersion` **2**, PRNG `xorshift32-v1`, M001 `coreEngineVersion` 1.0.0 / `snapshotSchemaVersion` unchanged
> **Task:** T018 — evidence synthesis and documentation only. No simulation behaviour, cohort, threshold or parameter was changed.

**Zero acceptance criteria are signed off by this report.** It records verified evidence and states, per criterion, whether it is PASS, FAIL, PENDING OWNER REVIEW or NOT MEASURED. AC09 and AC10 require explicit owner sign-off and are **not** granted here. M002 is **not** declared complete.

---

## 1. Matrix summary

| AC | Requirement | Result | Basis |
|---|---|---|---|
| AC01 | Headless pure-Dart full game | **PASS** | `dart test` 351/351; `domain_isolation_test.dart` import scan |
| AC02 | Input and version validation | **PASS** | `game_input_test.dart`, `validation_test.dart`, typed `GameValidationException` |
| AC02b | Seed identity and normalization | **PASS** | `normalizedSeed 0 → 0x9E3779B9`; `s` vs `s+2^32` alias; even/odd opening possession |
| AC03 | Determinism and replay | **PASS** | T012 canonical ledgers v1–v4; 20-repetition identity; VM/Chrome digest parity |
| AC04 | Clocks and timing | **PASS** | `game_reducer_test.dart` clock/horn/reset/OT suites |
| AC04b | A1 duration brackets and boundaries | **PASS** | `t013_adversarial_game_test.dart` draw boundaries and bracket min/max |
| AC05 | Event causality | **PASS** | `t010_event_hardening_test.dart`; 24 one-defect ledger mutations rejected |
| AC06 | Box-score accounting | **PASS** | `game_accounting_test.dart`; every harness reconciles `EventAccounting` |
| AC07 | Event vocabulary | **PASS** | `game_event_test.dart`, `turnover_nonsteal_test.dart` |
| AC07b | Ledger boundary and ordering | **PASS** | `game_reducer_test.dart` lifecycle/ordering rejection |
| AC07c | Attribution rules | **PASS** | `team.TOV == Σ player.TOV`; PG shot-clock attribution; link validity |
| AC08 | Boundedness and typed errors | **PASS** | 50,001st event, zero-clock guard, 11th OT, invalid probability inputs |
| AC09 | Attribute sensitivity (E1–E6) | **PENDING OWNER REVIEW** | v1 E4 inconclusive (preserved); v2 and v4 reruns 6/6 PASSED |
| AC10 | Statistical calibration + owner sign-off | **PENDING OWNER REVIEW** | T015 8/9 provisional bands; TOV/100 above band; no realism sign-off |
| AC11 | M001 preservation | **PASS** | M001 paths untouched since `a431aeb`; 0 deleted lines in `lib/` |
| AC11b | Fingerprint compatibility | **PASS** | `gameFingerprintVersion` 2 retained; fingerprint fixtures VM/Chrome identical |
| AC12 | Desktop performance | **PASS** | Corrected AOT: 5.83–6.16 s / p95 8.21–9.40 ms / 22–23 MiB |
| AC13 | Scope compliance | **PASS** | Only `lib/src/simulation/*` + additive exports; no out-of-scope systems |

Android runtime performance: **NOT MEASURED** (no device, emulator or profile run). This is a limitation, not an AC12 failure — the frozen criterion itself permits no Android claim without device measurement.

---

## 2. Detailed criteria

### AC01 — Headless pure-Dart simulation
- **Requirement:** a complete game runs headlessly in `dart test` with no Flutter imports and no file/network writes.
- **Evidence:** `packages/simulation_core/test/simulation/*` (all suites run headless); `test/domain_isolation_test.dart` scans `lib/` for forbidden imports; `dart test` → **351 passed, 0 failed**; `dart test -p chrome …` → **350 passed, 0 failed** (IO test excluded).
- **Versions:** v4 / rules 2 / schema 2 / duration model 2.
- **Limitations:** Chrome cannot run the `dart:io` source-scan test; the scan is VM-only by design.

### AC02 — Input and version validation
- **Requirement:** typed rejections for invalid lineups, duplicate/foreign players, unknown rules/version, invalid seeds, empty IDs.
- **Evidence:** `test/simulation/game_input_test.dart`, `test/validation_test.dart`, `test/simulation/game_reducer_test.dart`; `GameValidationException` + `GameValidationCode` machine-readable codes.
- **Result:** PASS — tests assert codes, not message wording.

### AC02b — Seed identity
- **Requirement:** seed 0 normalizes to `0x9E3779B9` with away starting; even seed home starts, odd away; `s` and `s+2^32` share events but differ in fingerprint; no PRNG draw for the opening possession.
- **Evidence:** `game_input_test.dart` (`expect(input.normalizedSeed, 0x9E3779B9)`), `turnover_nonsteal_test.dart` (`s and s + 2^32 share events but not the fingerprint`).
- **Result:** PASS.

### AC03 — Determinism and replay
- **Requirement:** identical output for identical input/seed, pinned ledgers and fingerprints, VM/Chrome parity, A1 draw order.
- **Evidence:** `t012_canonical_ledger_fixture.dart` (v1, seed 42, 800 events, 94–77), `_v2`, `_v3`, `_v4`; `t012_canonical_ledger_test.dart` (digest and byte equality on VM and Chrome); `m001_regression_test.dart`.
- **Result:** PASS — four immutable fixture generations coexist; v4 fixture pinned under `gameSimulationVersion` 4.

### AC04 / AC04b — Clocks, timing, duration brackets
- **Requirement:** 720→0 periods, 300 s OT, 24 s violation, 14 s resets, horn precedence, last-tick behaviour, 11th-OT typed failure; A1 brackets 2–7 / 5–11 / 10–22 with type-draw boundaries 0/1499/1500/4499/4500/9999 and no silent clamping.
- **Evidence:** `game_reducer_test.dart` (`enforces the ten-overtime bound`, `rejects simultaneous shot-clock turnover at the horn`, `allows shot-clock expiry before the period horn`, clock-bound/reset tests); `t013_adversarial_game_test.dart` (draw boundaries, bracket endpoints, `D == Rg`, `D == Rs`, `Rg == 1`).
- **Result:** PASS. Amendment 003 continuation timing is present in v3/v4 and covered by AC04b-style tests; its own *experimental* guardrails are separately recorded (§4).

### AC05 — Event causality
- **Evidence:** `t010_event_hardening_test.dart` (lifecycle, possession, rebound, and-one ordering), `t013_ledger_mutation_test.dart` (24 single-defect mutations each rejected with a typed code).
- **Result:** PASS.

### AC06 — Accounting
- **Requirement:** all equations reconcile, `team.TOV == Σ player.TOV`, FGM = 2PM+3PM, FGA = 2PA+3PA, PTS consistency.
- **Evidence:** `game_accounting_test.dart`; `event_accounting.dart` reconciliation runs inside every committed harness, per run: 1,120 games (T015), 280 v3 + 280 v4 (Amendment 004 pilot), 280 v3 + 280 v4 (recovery re-execution), 2,240 primary (held-out), 1,400 T014 interventions (held-out), 3,000 (T016 benchmark). Zero accounting mismatches were reported by any of these runs.
- **Result:** PASS.

### AC07 / AC07b / AC07c — Vocabulary, ledger boundary, attribution
- **Evidence:** `game_event_test.dart`; `turnover_nonsteal_test.dart`; reducer ordering/unknown-shape rejections; attribution tests for PG shot-clock turnovers, offensive-foul offender attribution, assist/steal/block link validity, rejection of foreign/bench attribution.
- **Result:** PASS.

### AC08 — Boundedness
- **Evidence:** `t013_adversarial_game_test.dart` — `default caps are the frozen OD-14 values`, reducer rejects a ledger longer than `maxEvents`, 50,001st event fails, 65th consecutive zero-clock event fails, 11th OT fails, invalid probability inputs fail, no NaN/Infinity.
- **Note:** the T016 benchmark independently asserts per-game bounds (`events.last is GameEnded`, `overtimes ≤ 10`, `periodsPlayed ≤ 14`, `events.length ≤ 50000`) for 3,000 games; 0 violations.
- **Result:** PASS.

### AC09 — Attribute sensitivity (owner gate)
- **Requirement:** E1–E6 with 200 paired seeds each, 95% CI excluding zero in the expected direction, Holm correction; aggregate only.
- **Evidence (three independent generations, kept separate):**

| Generation | Seeds | Result |
|---|---|---|
| v1 historical (`t014-sensitivity-report.md`, `t014-statistical-summary.json`) | 1–200 | E1/E2/E3/E5/E6 PASSED; **E4 (`ballHandling`) INCONCLUSIVE** — mean +0.24594, CI `[−0.09193, +0.58251]`, Holm p = 0.1503, wrong sign |
| v2 rerun (`t014-statistical-summary-v2.json`, simulation v2) | 1–200 | **6/6 PASSED** (E4 −0.43500, CI `[−0.76569, −0.08823]`, Holm p = 0.012399) |
| v4 reruns (`amendment-004-recovery/t014-v4-raw.json`; `amendment-004-heldout/t014-v4-fresh-raw.json`) | 1–200 (dev) and 10001–10200 (fresh) | **6/6 PASSED** in both; fresh-run Holm p = 0.000600 |

- **Status: PENDING OWNER REVIEW.** AC09 is not signed off: v1 E4 was inconclusive and remains recorded as such. The later passes are separate evidence generations, not a retroactive correction of v1.
- **Limitations:** aggregate-only; 200 paired seeds; single league fixture; E4's mechanism changed between v1 and v2 (exposure/security contract), which is why the two are not comparable.

### AC10 — Statistical calibration (owner gate)
- **Requirement:** ≥1,000 games, full mandatory table, seed list, outlier diagnostics, example games, owner sign-off; no automatic realism verdict.
- **Evidence:** `t015-calibration-protocol.md`, `t015-calibration-report.md`, `t015-diagnostic-cases.md`, `t015-game-sample.csv` (1,120 rows), `t015-statistical-summary.json` — 1,120/1,120 completed, 0 typed failures, 0 structural/foul-audit issues, 200 distinct seeds, determinism 10/10.
- **Frozen provisional bands (simulation v2):** 8 of 9 within band; **`tovPer100Completed` 24.7594 vs band `[7, 24]` → above**.
- **Status: PENDING OWNER REVIEW.** This report does not convert that band breach into a pass, and does not claim NBA realism.
- **Limitations:** v2-era model; the band set was provisional; no human gameplay review has been performed (T019).

### AC11 — M001 preservation
- **Evidence:** `git diff --name-only a431aeb..HEAD -- packages/simulation_core/lib/src/generation lib/src/models lib/src/validation lib/src/domain_versions.dart` → **empty**; `git diff --numstat a431aeb..HEAD -- lib` → **0 deleted lines** across 43 files (17,322 insertions, 0 deletions); `m001_regression_test.dart` pins M001 versions, default snapshot and PRNG vectors.
- **Result:** PASS — `simulation_core.dart` gained 16 additive export lines for M002 symbols; no existing export removed or renamed.

### AC11b — Fingerprint compatibility
- **Evidence:** `gameFingerprintVersion = 2` retained; `t012` fingerprint fixtures; `turnover_nonsteal_test.dart` (`pinned fingerprint matches the actual v2 canonical input`); fingerprint payload embeds `gameSimulationVersion`, so v3 and v4 inputs are distinguishable; VM and Chrome produce identical hex.
- **Result:** PASS.

### AC12 — Desktop performance
- **Requirement:** 1,000 games ≤ 60 s (optimized desktop Dart), p95 ≤ 100 ms/game, ≤ 128 MiB incremental, environment and warmup recorded, no Android claim without device measurement.
- **Evidence (corrected cohort, commit `29d71d3`):** `t016-benchmark-corrected-1000-games-run{1,2,3}.json`, `t016-provenance-correction-addendum.md`.

| Run | Seeds / matchups | Complete | Total | p95 | Incremental RSS |
|---|---|---|---|---|---|
| 1 | 50001–51000 / 0–47 | 1,000 | 5.826 s | 8.207 ms | 23 MiB |
| 2 | 50001–51000 / 0–47 | 1,000 | 6.161 s | 9.397 ms | 23 MiB |
| 3 | 50001–51000 / 0–47 | 1,000 | 5.978 s | 9.339 ms | 22 MiB |

- Windows 11 10.0.26100 x64, Intel i7-2600 (4C/8T), 16,265 MiB, Dart SDK 3.12.2, AOT (`dart compile exe`), 60 warmup games, warmup seeds 60001–60060, `observedScheduleValid = true`.
- **Result:** PASS — every criterion met with ≥5.5× headroom; 3,000/3,000 games completed with 0 typed, 0 accounting and 0 bound failures.
- **Historical note:** the original measurement (commit `04d7d8f`) also passed but carried a false cohort label (`50001..51000` stated, `50061..51060` executed); it is preserved unchanged and the correction is recorded in `t016-provenance-correction-addendum.md`.
- **Limitations:** RSS-based memory (heap + VM overhead), integer-MiB granularity, AOT GC not forceable; single machine and SDK.

### AC13 — Scope compliance
- **Evidence:** changes since M001 baseline confined to `lib/src/simulation/*` + additive barrel exports + tests; **no** season, trade, contract, coaching, rotation, injury, salary or draft system in `lib/`; runtime dependency set is `crypto ^3.0.7` only (approved fingerprinting exception); `lib/` imports limited to relative paths, `dart:convert`, `dart:math show max`, `package:crypto`; no `dart:io`/`dart:ui`/Flutter/Flame/http in `lib/`; no app-layer simulation rules.
- **Result:** PASS. Tooling under `packages/simulation_core/tool/` is not imported by `lib/` and is not a simulation dependency.

---

## 3. Statistical history — kept as history

### 3.1 Historical v1 / v2 evidence
- **T014 v1:** E4 (`ballHandling`) INCONCLUSIVE (wrong sign, Holm p = 0.1503). Preserved in `t014-sensitivity-report.md` and `t014-statistical-summary.json`.
- **T015 calibration (simulation v2):** 1,120 games; `tovPer100Completed` = 24.7594 against the frozen band `[7, 24]` — **above band**; documented structural finding that 14.65 shot-clock violations/game follow from the 14 s reset × 10–22 s A1 bracket.

### 3.2 Amendment 003 — continuation timing
- **Purpose:** separate continuation timing policy from offensive action selection.
- **Development result (1,120 games, v2 vs v3):** two pre-registered guardrails **FAILED**:
  - Pace increase delta **+2.21%** (+2.22 poss/team-game), 95% CI `[+1.85, +2.59]`, against a `+2.5%` minimum.
  - Offensive-foul turnover share **26.02%** (10.88 OF / 41.82 TOV) against a `≤ 24.0%` ceiling.
- **Held-out result:** recorded in downstream addenda as **+2.05%** pace and **25.67%** offensive-foul share — both still failing their frozen thresholds.
- **Procedural waiver:** `amendment-003-waiver-addendum.md` permits held-out collection only; it explicitly does **not** convert either failure into a PASS and preserves both as formal FAILURES.
- **Evidence gap (disclosed):** the Amendment 003 **held-out** per-game artifacts are **not present in this repository** — only the three Amendment 003 design/waiver documents exist. The `+2.05%` / `25.67%` figures are cited in downstream documents (`amendment-004-recovery/amendment-004-evidence-recovery-addendum.md`, `amendment-004-heldout/OWNER-D1-DISPOSITION.md`) but cannot be re-derived from committed raw evidence here. Treat them as **reported, not independently verifiable in-repo**.

### 3.3 Amendment 004 — offensive-foul calibration (420 → 170 bp)
| Stage | Artifact | Result |
|---|---|---|
| Frozen specification | `amendment-004-turnover-calibration-spec.md` (`a7910cf`) | 9 pre-registered gates, thresholds frozen |
| Development pilot (280 games) | `amendment-004-pilot-sample.csv`, `amendment-004-statistical-summary.json` | gates met, checksum record defective |
| Evidence recovery | `amendment-004-recovery/` (`verify_evidence.py`) | 9 gates recomputed from raw rows; **PASS** |
| Fresh held-out (2,240 games) | `amendment-004-heldout/` (`verify_heldout.py`) | G1–G8 + G9-fresh all **PASS**; 0 rollback triggers |
| D1 protocol deviation | `PROTOCOL-DEVIATION.md`; `OWNER-D1-DISPOSITION.md` | original verdict **INCONCLUSIVE** preserved; owner recorded **QUALIFIED HELD-OUT EVIDENCE ACCEPTED — D1 PROCEDURAL EXCEPTION** |

Held-out v4 results (1,120 games, fresh seeds 10001–10600) with DOF-corrected intervals: OF 2.2143/team-game `[2.1430, 2.2855]`; OF share 0.1242 `[0.1205, 0.1279]`; TOV/100 17.4285 `[17.2218, 17.6353]`; SC/game 4.1714 `[4.0387, 4.3042]`; possessions/team-game 102.2929 `[101.9880, 102.5977]`; median FGA 92 `[91, 92]`; 3PA/FGA 0.4134 `[0.4106, 0.4161]`; eFG 0.5230 `[0.5187, 0.5274]`.

### 3.4 Why later improvements do not repair earlier failures
Each experimental generation has its own **pre-registered** thresholds and cohort. A failure recorded under v2/v3 thresholds remains a failure of *that* generation: the later fix does not retroactively validate the configuration that was actually specified and measured. Silently re-scoring a frozen experiment would destroy the very property — pre-registration — that makes the pass meaningful. Amendment 003's two failures therefore stay formal FAILURES even though Amendment 004's v4 evidence clears the corresponding bands; the failures describe v3, the clearance describes v4.

### 3.5 Empirical validation versus owner acceptance
- **Empirical validation** = reproducible measurement against frozen thresholds (what AC03–AC08, AC11, AC11b, AC12, AC13 and the gate tables above establish).
- **Owner acceptance** = an accountable human judgement that the result is acceptable for the milestone (AC09, AC10, and any realism claim).
- No amount of in-repo evidence converts the second into the first. This report claims only the first.

---

## 4. Human gameplay evidence for T019

**Packet location:** `specs/002-possession-simulation/t019-review-packet.md` (prepared alongside this report; no new cohort was run).

### 4.1 Selection rule (documented, reproducible)
Within the **v4 fresh held-out arm** (`amendment-004-heldout/v4-heldout-raw.json`, 1,120 games), games are sorted by `slot` ascending and the following are selected — no discretion, no exclusion:

1. **Median game** — first game whose `combinedPoints` equals the arm median (214).
2. **Lowest-scoring game** — minimum `combinedPoints`, ties by lowest `slot`.
3. **Highest-scoring game** — maximum `combinedPoints`, ties by lowest `slot`.
4. **Most shot-clock violations** — max `shotClockTov`, ties by lowest `slot`.
5. **Most offensive fouls** — max `offensiveFoulTov`, ties by lowest `slot`.
6. **Most overtimes** — max `overtimes`, ties by lowest `slot`.

Favourable-outcome selection is impossible under this rule: the extremes are included, not filtered.

### 4.2 What is available and what is not

| Requested evidence | Status | Reason |
|---|---|---|
| Completed game scores | **AVAILABLE** | `v4-heldout-raw.json` per game |
| Team box scores (FGM/FGA/3P/FT/REB/TOV/STL/BLK/PF) | **AVAILABLE (v4 team totals, home/away split)** | raw rows carry `home*`/`away*` fields |
| Turnover category breakdown | **AVAILABLE** | steal / nonSteal / offensiveFoul / shotClock per game |
| Offensive fouls, shot-clock violations | **AVAILABLE** | per game |
| Overtime behaviour | **AVAILABLE** | 18 of 1,120 games went to OT; max 2 OT; `periods` 4–6 |
| Player-level stat lines | **UNAVAILABLE** | no committed artifact stores per-player game lines; producing them needs a new run (not authorized) |
| Full team box scores on the **v2-era** model | **AVAILABLE** | `t015-game-sample.csv` (simulation v2) — historical only |

Two evidence-freshness caveats: `t015-game-sample.csv` is simulation **v2** (rules 1, duration model 1), not v4; and no artifact records possession-level play-by-play, so "does this look like basketball" must be judged from aggregates and box scores.

---

## 5. Limitations classified

| # | Limitation | Classification |
|---|---|---|
| L1 | Single generated league fixture (seed 20261028) and eight rosters; fresh seeds are not fresh leagues | **Owner decision** — outside frozen M002 acceptance requirements; bounds generalization claims |
| L2 | Android runtime performance NOT MEASURED (no device/emulator/profile run) | **Deferred future milestone** — AC12 explicitly permits no Android claim without measurement |
| L3 | No mobile isolate offloading; synchronous `simulate` would block the Flutter UI isolate | **Deferred future milestone** — UI-layer concern, not an M002 core criterion |
| L4 | Memory evidence is RSS-based (heap + VM overhead), integer-MiB granularity, AOT GC not forceable | **Owner decision** — measurement-method limitation; AC12 margin is ≥5.5× |
| L5 | Offensive-foul `[100, 1000]` bp clamp-floor binding frequency not measured | **Owner decision** — would need a separate approved measurement |
| L6 | Inside-vs-midrange shot-zone distribution not measured (rows record FGA/FGM and 3PA/3PM only) | **Owner decision** — data gap, not a failed criterion |
| L7 | Remaining NBA realism differences (e.g. TOV/100 completed 17.43 held-out vs NBA-normalised ~13.8; 4.17 shot-clock violations/game) | **Owner decision** — realism is a measured claim requiring AC10/T019 sign-off |
| L8 | Historical Amendment 003 failures (+2.21% dev / +2.05% held-out pace; 26.02% / 25.67% OF share) | **Owner decision** — formal failures preserved; never converted to PASS |
| L9 | Amendment 003 held-out raw per-game evidence absent from the repository | **Owner decision** — reported-only evidence, disclosed in §3.2 |
| L10 | Amendment 004 D1 procedural exception (variance estimator corrected post-hoc) | **Owner decision** — conditional acceptance recorded; verdict preserved as INCONCLUSIVE |
| L11 | No human gameplay/plausibility review performed; AC09/AC10 unsigned | **M002 acceptance blocker** until T019 completes and the owner signs off |
| L12 | Player-level stat lines absent from committed evidence | **Owner decision** — needed for T019 judgement; would require an authorized extraction run |
| L13 | Chrome cannot run the `dart:io` source-isolation test | **Deferred future milestone** — structural property of the test, documented gate |

Only **L11** blocks M002 closure; it is the gate T019 exists to satisfy.

---

## 6. Evidence integrity checks performed for this report

| Check | Command | Result |
|---|---|---|
| Recovery verifier | `python specs/.../amendment-004-recovery/verify_evidence.py` | **PASSED** (5 artifacts, seeds 1–200, 280 slots) |
| Held-out verifier | `python specs/.../amendment-004-heldout/verify_heldout.py --git-ref 6097ea4` | **PASSED** (12 artifacts, 2,240 games, 600 seeds, G1–G9) |
| D1 CGM/DOF audit | `python specs/.../amendment-004-heldout/audit_d1_dof.py` | **PASSED** (66 estimators, max diff `5.551e-17`, 0 flips) |
| T016 corrected evidence hashes | `git show 29d71d3:…corrected-1000-games-run{1,2,3}.json \| sha256sum` | matches `2de8540a…`, `16b9d732…`, `6eb7415f…` |
| T016 original evidence preserved | same command on `t016-benchmark-1000-games-run{1,2,3}.json` | matches `06e7b4d0…`, `3e97db67…`, `9af401d1…` |
| Frozen thresholds untouched | `git diff --stat a7910cf..HEAD -- acceptance-matrix.md amendment-004-turnover-calibration-spec.md amendment-003-seed-provenance-manifest.md` | **empty** |
| No simulation change since v4 implementation | `git diff --stat 83edd52..HEAD -- packages/simulation_core/lib` | **empty** |
| Static analysis / format | `dart analyze` (clean), `dart format --set-exit-if-changed lib test tool` (68 files, 0 changed) | **PASS** |

No large experiment was re-run for this report; all figures are read from committed artifacts or from committed verifier output.

### 6.1 Self-review of this report
- **Denominators:** per-team-game figures divide by `2N`; per-100-possession figures divide by `Σ completed`; both are stated in §2/§3 rather than left implicit.
- **No cross-generation comparison is presented as improvement on the same threshold.** §3.4 states explicitly that v3 failures stand while v4 clears a different frozen set.
- **PASS labels are attached only where a frozen threshold and a committed artifact agree.** AC09/AC10 are `PENDING OWNER REVIEW`, not PASS; Android is `NOT MEASURED`.
- **Superseded evidence is labelled** (`t015-game-sample.csv` = simulation v2; original T016 cohort mislabelled and corrected).
- **No figure in this report was produced by a new simulation run.**

---

## 7. Required owner decisions

| # | Decision | Blocking? |
|---|---|---|
| AC09 | Accept or reject attribute-sensitivity evidence, given v1 E4 was inconclusive and later generations passed | **Yes** |
| AC10 | Accept or reject calibration realism, given 8/9 provisional bands and `tovPer100Completed` above band (v2) | **Yes** |
| D1 | Confirm the conditional Amendment 004 D1 acceptance continues to apply for M002 review | No (recorded) |
| L1/L5/L6/L12 | Accept scope of evidence as-is, or authorize additional measurement | No (deferred) |

M002 closure requires T019 human review plus the two AC09/AC10 owner decisions. **M002 is not declared complete by this report.**
