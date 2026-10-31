# Amendment 004 — Fresh Held-Out Validation Protocol (FROZEN BEFORE EXECUTION)

> **Date:** 2026-10-31
> **Status:** PROTOCOL FROZEN. No held-out game had been simulated when this file was committed.
> **Authorization:** owner "Amendment 004 Final Gate and Fresh Held-Out Evaluation"
> **Scope:** protocol finalization, fresh held-out execution, evidence preservation, statistical reporting. It does **not** authorize tuning, threshold changes, production acceptance, M002 closure, or T016–T019.

## 1. Models under test

| Arm | Commit | Offensive-foul base | `gameSimulationVersion` |
|---|---|---|---|
| Baseline v3 | `9f8458ab345ea7c075f3b910b60d7ee964f1c5fe` (isolated `git archive` checkout) | 420 bp | 3 |
| Candidate v4 | `28a1e0b5e5d90a794225e2f382ef7d3a44603573` + protocol commit (library code identical to `c359c3577f14d7e903c9e8836912f7045dba0b52`) | 170 bp | 4 |

`git diff 9f8458a..28a1e0b -- packages/simulation_core/lib` is exactly two lines: `gameSimulationVersion 3→4` and offensive-foul base `420→170`. Clamp `[100, 1000]` bp, timing brackets, `gameRulesVersion` 2, `gameActionDurationModelVersion` 2, `gameEventSchemaVersion` 2 and `gameFingerprintVersion` 2 are unchanged. v3 is never run with v4 defaults: its library code comes only from the pinned v3 checkout.

## 2. Fresh seed schedule

```
i = 20*m + s            m = 0..55 (directed matchup), s = 0..19, i = 0..1119
seed(i) = 10001 + ((137*i + 23) mod 600)
```

`m = 2*pairIndex + orientation`; pairs are the 28 lexicographic unordered pairs of the eight league teams sorted by id; orientation 0 = lower index at home. League fixture seed `20261028` (the only league used by every prior M002 artifact).

Enumerated and verified (`seed-manifest.csv`, SHA-256 `bb90f10db2a28ac7cf65ecf375001fa56aefbd82bb3e6dee50c328a09ddaace7`):

| Property | Result |
|---|---|
| Matchup-seed slots | 1,120 |
| Unique seeds | 600 |
| Seed range | `[10001, 10600]` |
| Seeds used twice / once | 520 / 80 |
| Duplicate `(matchup, seed)` pairs | 0 |

### 2.1 Exposure audit

All seed ranges documented in repository specs, tools and tests were searched.

| Corpus | Seeds |
|---|---|
| T009/T014/T015/Amendment 002–004 development | 1–200 |
| T015 / Amendment 003 diagnostic and calibration pools | 1–1300 |
| Amendment 003 held-out cohort | 2001–2600 |
| T011/T013 pinned and matrix seeds | 1–36, 42, 99, 100, 20261028, 20261029 |
| Statistical-method seeds (bootstrap/permutation, not game seeds) | 20261029, 424242 |
| Unit tests in `test/` | 1–400 |

No documented or coded game seed lies in `[10001, 10600]`. One helper, `seedWithTypeDraw` in `t013_adversarial_game_test.dart`, scans seeds upward to 2,000,000 for a PRNG first-draw value; it inspects a single `DeterministicRandom` draw and never simulates a game, so it creates no outcome-level exposure to this cohort. **No conflict; execution is not blocked.**

Honest limit: fresh seeds do not create a fresh league or roster distribution (§7).

## 3. Execution procedure (frozen)

Runner: `packages/simulation_core/tool/amendment_004_pilot_runner.dart --cohort=heldout` (default mode, the recovered 280-game development pilot, is unchanged and was regression-checked against `pilot-v4-raw.json`: 280/280 rows identical on all pre-existing fields). New additive row fields: `freshViolations`, `retFoulViolations`.

```bash
# v4 (candidate), from packages/simulation_core
dart run tool/amendment_004_pilot_runner.dart <dir>/v4-heldout-raw.json --cohort=heldout
dart run tool/amendment_004_t014_runner.dart <dir>/t014-v4-fresh-raw.json --seed-offset=10000

# v3 (baseline), isolated checkout of the pinned commit
git archive 9f8458ab345ea7c075f3b910b60d7ee964f1c5fe packages/simulation_core \
  | tar -x -C <v3dir> --strip-components=2
cp packages/simulation_core/tool/amendment_004_pilot_runner.dart <v3dir>/tool/
(cd <v3dir> && dart pub get && \
  dart run tool/amendment_004_pilot_runner.dart <dir>/v3-heldout-raw.json --cohort=heldout)
```

Every game is validated through `GameEventReducer.validate` and its score reconciled with `EventAccounting` before a row is recorded. Any failure aborts the run. Each row records matchup, orientation, seed, `inputFingerprint`, all version identifiers, FGA/FGM/3PA/3PM/FTA/FTM, points, turnover categories, foul categories, completed possessions, phase denominators, and shot-clock violations by continuation context (fresh / oreb / retained-foul).

Rules: no intermediate inspection to select or change parameters; no extra seeds; no re-runs except to repair a crash, in which case the failure is reported and no result is inspected before the identical command is rerun.

## 4. Frozen gates (original thresholds, unchanged)

Evaluated on the **v4 held-out arm** against the Amendment 004 specification §3.2 envelopes:

| Gate | Metric | Envelope | Definition |
|---|---|---|---|
| G1 | Offensive fouls / team-game | `[1.80, 2.60]` | `Σ offensiveFoulTov / (2N)` |
| G2 | Offensive-foul share of turnovers | `[0.100, 0.160]` | `Σ offensiveFoulTov / Σ tov` |
| G3 | Turnovers / 100 completed possessions | `[15.0, 19.5]` | `100·Σ tov / Σ completed` |
| G4 | Shot-clock violations / game | `[3.0, 5.5]` | `Σ shotClockTov / N` |
| G5 | Completed possessions / team-game | `[100.0, 106.0]` | `Σ completed / (2N)` |
| G6 | Team median FGA | `[88.0, 95.0]` | median of `homeFga ∪ awayFga` over 2N team-games |
| G7 | 3PA / FGA | `[0.380, 0.450]` | `Σ threePa / Σ fga` |
| G8 | eFG% | `[0.510, 0.540]` | `(Σ fgm + 0.5 Σ threePm) / Σ fga` |
| G9 | T014 E1–E6 | all six PASSED (expected sign, Holm p < 0.05) | see §4.1 |

`N = 1,120` games. A gate passes only when the point estimate lies inside its envelope; confidence intervals are reported, not substituted for the rule.

Rollback triggers (§3.3 of the specification), also evaluated: offensive fouls per team-game not below 3.0; offensive-foul share above 18.0%; 3PA-rate shift (v4 − v3, percentage points) above 2.0; eFG% shift above 1.5 percentage points.

### 4.1 G9 evidence classes (kept separate)

- **G9-development** — already recovered (`amendment-004-recovery/t014-v4-raw.json`, seeds 1–200). This is **not** held-out evidence and is not counted toward the held-out verdict.
- **G9-fresh** — one new run of the same frozen T014 E1–E6 protocol (same league fixture, subjects, +20 rating delta, bootstrap seed 20261029 and permutation seed 424242, Holm correction) with the 200 game seeds shifted to **10001–10200** (`--seed-offset=10000`), simulation v4. Only this run is used for held-out G9. It is pre-registered here and run once.

## 5. Statistics (frozen)

- Unit of analysis: game (matchup × seed slot). Seeds repeat across matchups (520 twice) and matchups repeat across seeds, so observations are not independent.
- Ratio metrics: linearized ratio estimator. Variance: two-way cluster-robust (Cameron–Gelbach–Miller) over `seed` (600) and `matchup` (56) clusters, `V = V_seed + V_matchup − V_game`; intersection clusters are single games because `(matchup, seed)` is unique. If the estimate is non-positive, the larger one-way variance is used. 95% normal intervals.
- Paired deltas (v4 − v3): linearized difference of per-game scores, same variance estimator, using exact seed/matchup/orientation pairing.
- Median FGA: pigeonhole bootstrap (independent seed and matchup cluster resampling, 2,000 replicates, NumPy `default_rng(20261031)`).
- Implementation: `analyze_heldout.py`, committed with this protocol. A dry run on the recovered pilot data reproduced the previously recorded pilot gate values and the recorded OF/team-game cluster interval `[-3.44, -3.02]`.

## 6. Verdict rule (frozen)

- **PASSED — READY FOR M002 OWNER REVIEW**: 2,240 games executed with 0 validation/accounting errors; G1–G8 pass on held-out v4; G9-fresh passes; no rollback trigger fires.
- **FAILED — REVISION REQUIRED**: otherwise, with every failing gate preserved and reported.
- **INCONCLUSIVE**: execution or evidence-integrity defect.

Amendment 003 guardrail failures and the procedural waiver (`amendment-003-waiver-addendum.md`) are historical records and are not modified or retroactively passed. AC09 and AC10 are not marked accepted by this experiment.

## 7. Known limitations (declared before execution)

1. One generated league fixture (seed `20261028`), eight rosters; fresh seeds are not fresh rosters or leagues.
2. Frequency with which the `[100, 1000]` bp offensive-foul clamp floor binds is not measured.
3. Amendment 003 pace and offensive-foul-share failures remain formal historical failures.
4. Internal gate passes do not establish NBA-level basketball realism; NBA comparisons are descriptive only.
5. Cluster-robust intervals with 600 seed clusters are approximate; 56 matchup clusters is a small count for the matchup dimension.

## 8. Evidence to be preserved

Raw `v3-heldout-raw.json`, `v4-heldout-raw.json`, `t014-v4-fresh-raw.json`; `heldout-paired.csv`; `heldout-summary.json`; `seed-manifest.csv`; `execution-metadata.json` (commands, commits, tool versions); `CHECKSUMS.sha256` over LF bytes; `verify_heldout.py`. Raw files are never deleted. Checksums are verified against committed Git blobs (`git show <commit>:<path> | sha256sum`), not only working-tree files. `.gitattributes` (`* -text`) disables newline conversion.
