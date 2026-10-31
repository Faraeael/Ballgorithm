# T019 Evidence — Reproduction Metadata

> **Purpose:** record exactly how the six review games were re-executed from committed evidence.
> **Commit of source evidence:** `93808eaa6582dfd8c7ab562830cba893d8f6c661`
> **Reconstruction commit:** this commit

## Environment

- OS: Windows-11-10.0.26100-SP0 (Windows 11 Pro 10.0.26100 x64)
- CPU / RAM: Intel Core i7-2600 @ 3.40 GHz (4C/8T) / 16,265 MiB
- Dart SDK: Dart SDK version: 3.12.2 (stable) (Tue Jun 9 01:11:39 2026 -0700) on "windows_x64"
- Runtime: Dart VM via `dart run` (evidence extraction; not a performance measurement)
- Python (table generation / verification): 3.13.1

## Tool

`packages/simulation_core/tool/t019_game_extract.dart` — read-only extractor. It accepts **no** seed, team or matchup arguments; it reads the committed held-out artifact, replays the recorded `gameId`, `seed`, `matchupIndex` and `orientation`, executes the pinned v4 model **once per game**, and fails with a non-zero exit on any aggregate or fingerprint mismatch.

## Commands (exact)

```bash
cd E:/ballgorithm-dev/packages/simulation_core
dart analyze tool/t019_game_extract.dart
dart run tool/t019_game_extract.dart \
  --raw=../../specs/002-possession-simulation/amendment-004-heldout/v4-heldout-raw.json \
  --slots=68,771,455,55,117,153 \
  --out=../../specs/002-possession-simulation/t019-evidence/t019-games.json
```

## Inputs

- League fixture: `LeagueGenerator(GenerationConfig(seed: 20261028))`, 8 teams sorted by id, `ActiveLineup.defaultFor` on both sides.
- Rules: `GameRules.standard` (rules 2, 4x720 s, 300 s OT, maxOvertimes 10, 24 s clock, maxEvents 50000).
- Versions exercised: {"simulation": 4, "rules": 2, "eventSchema": 2, "actionDurationModel": 2, "fingerprint": 2}.
- Matchup enumeration: directed matchup `m = 2*pairIndex + orientation` over the 28 lexicographic unordered pairs.

## Games reproduced

| Slot | Matchup | Orientation | Seed | gameId | `inputFingerprint` | Fingerprint matches record | Aggregate mismatches |
|---|---|---|---|---|---|---|---|
| 68 | 3 | 1 | 10340 | `am4h-68-3-10340` | `d85c35ca724b042fbbf8df36993daaff92776ff01f324a051394b9bcb7dc80b0` | True | 0 |
| 771 | 38 | 0 | 10051 | `am4h-771-38-10051` | `f8dff9b6d4e24bdec4e324da3d7a3b1e5d39ca6921b8c667db4eec864f522d36` | True | 0 |
| 455 | 22 | 0 | 10559 | `am4h-455-22-10559` | `5a08a874ed6ec95c91cfbec87191f590d6e8f6ee58215e239ee7b9ddad219eb9` | True | 0 |
| 55 | 2 | 0 | 10359 | `am4h-55-2-10359` | `3bf38083c66f6cecea46c759f568e1662c5409cda0bb6b6e313b1fded4d0fa74` | True | 0 |
| 117 | 5 | 1 | 10453 | `am4h-117-5-10453` | `4154530f3a35b57757dd1f732723baf7e12bf4867557b6c60619e90a4ff14e12` | True | 0 |
| 153 | 7 | 1 | 10585 | `am4h-153-7-10585` | `729edffe2d01c818a7dc2a76b4a1fbfa0165bf2d99341a5cf9139f5508440bad` | True | 0 |

**Total aggregate mismatches across six games: 0.** Compared fields per game: 60 recorded integers (scores, periods, overtimes, event count, possession counts, shooting/rebounding/turnover/foul totals, shot-clock and offensive-foul categories, and all phase-trace denominators) plus 4 recorded strings (`gameId`, `homeTeamId`, `awayTeamId`, `inputFingerprint`).

## Additional integrity checks performed

- `GameEventReducer.validate` on every replayed ledger — all six passed.
- `EventAccounting.aggregate` reconciled to `result.homeScore` / `awayScore` — all six passed (the tool aborts otherwise).
- Player box scores sum to team box scores for all 15 metrics on both teams in all six games: **0 discrepancies**.
- Selected slots are exactly those produced by the documented T018 selection rule; no game was added, replaced or excluded.

## Artifact hashes (LF-normalised bytes)

- `t019-games.json`: `4bdd982dd2a080ad9630d1eacf9fba56df7e49b6a14b3cf77edfd8af5a69c4cd`

## What this file does NOT claim

- It is **not** a new cohort, a new calibration sample, or additional statistical evidence. It re-executes six games that were already part of the frozen held-out cohort.
- Per-player **minutes are NOT MODELED** (fixed five-player lineups, no substitutions); the `minutes` field is emitted as the literal string `NOT_MODELED`.
- No possession-level play-by-play is stored, so sequence-level plausibility cannot be assessed from these records.
