# M004 T08 — Fresh Matched-Seed Cohort (executed)

Status: **executed, awaiting independent results review.** No acceptance or realism claim.

## Frozen design

| Item | Value |
|---|---|
| Pairs | 200 |
| Simulations | 400 (200 v4 + 200 v5) |
| League seed | 20261028, 8 teams x 12 players, `GameRules.standard` |
| Seeds | 20001..20200 |
| Allocation | `seed = 20001 + s`, `matchup = (s ~/ 2) % 4`, s = 0..199 |
| Matchups | m0 team-1 v team-2; m1 team-3 v team-4; m2 team-5 v team-6; m3 team-7 v team-8; first listed is home |
| Parity | 50 seeds per matchup; 25 even / 25 odd per matchup |
| v5 engine | `24cc6085853d74822786a88a329d1f1c9fad739a` |
| v4 engine | `c7f1d7a978a890cfe9ef3b8fe962e666bc042292` |
| Manifest | `t08-seeds.csv`, SHA-256 `65f40465917e3293c00e9c2fd2e862a46294d881b13ea4c426faf9d7fd4c075c` |

## Raw artifact retention

Raw per-game rows are **not** committed. Stable retention path:

`E:\ballgorithm-t08-artifacts\`

| File | Bytes | SHA-256 |
|---|---|---|
| `t08-raw-v4.jsonl` | 28,768,349 | `6a1a1c574bc2e373883aca6e5c0e9c69985f9e4ef8d30b3440678c0aac87d033` |
| `t08-raw-v5.jsonl` | 29,767,654 | `58ea4969894e436fa5f75ed53e0fae39f6993662ea3009c9e4ce1a056921c9b8` |

Each row preserves registered identity, engine SHA, version identifiers, complete canonical event
array, event digest, P1–P8 metrics, per-team box, per-player foul counts, period points; v5 rows add
per-player seconds, roster rank, substitution identities and disqualified players.

## Reproduction commands (already executed once)

```bat
git worktree add E:\bg-v4-t08 c7f1d7a978a890cfe9ef3b8fe962e666bc042292
copy E:\ballgorithm-dev\specs\004-player-participation\t08\runner-v4.dart.txt E:\bg-v4-t08\packages\simulation_core\tool\t08_runner_v4.dart
copy E:\ballgorithm-dev\packages\simulation_core\tool\t08_common.dart E:\bg-v4-t08\packages\simulation_core\tool\t08_common.dart
cd /d E:\bg-v4-t08\packages\simulation_core
dart pub get
dart run tool\t08_runner_v4.dart --manifest=E:\ballgorithm-dev\specs\004-player-participation\t08\t08-seeds.csv --out=E:\ballgorithm-t08-artifacts\t08-raw-v4.jsonl --engine=c7f1d7a978a890cfe9ef3b8fe962e666bc042292 --expectManifestSha=65f40465917e3293c00e9c2fd2e862a46294d881b13ea4c426faf9d7fd4c075c

cd /d E:\ballgorithm-dev\packages\simulation_core
dart run tool\t08_manifest.dart --out=E:\ballgorithm-dev\specs\004-player-participation\t08\t08-seeds.csv
dart run tool\t08_runner_v5.dart --manifest=E:\ballgorithm-dev\specs\004-player-participation\t08\t08-seeds.csv --out=E:\ballgorithm-t08-artifacts\t08-raw-v5.jsonl --engine=24cc6085853d74822786a88a329d1f1c9fad739a --expectManifestSha=65f40465917e3293c00e9c2fd2e862a46294d881b13ea4c426faf9d7fd4c075c
dart run tool\t08_analyze.dart --v4=E:\ballgorithm-t08-artifacts\t08-raw-v4.jsonl --v5=E:\ballgorithm-t08-artifacts\t08-raw-v5.jsonl --out=E:\ballgorithm-dev\specs\004-player-participation\t08 --manifestSha=65f40465917e3293c00e9c2fd2e862a46294d881b13ea4c426faf9d7fd4c075c
```

The v4 runner is stored as text because the v5 tree cannot compile the v4 `ActiveLineup` API; it is
copied into the pinned v4 worktree before running. The historical v4 engine is unmodified.

## Primary paired results (v5 − v4, n = 200, t interval df = 199)

| Series | Mean | SD | 95% CI | min | q05 | q25 | median | q75 | q95 | max | −/0/+ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| P1 home points | −0.9700 | 5.8041 | [−1.7793, −0.1607] | −30 | −11.00 | −3.00 | 0.00 | 1.00 | 9.00 | 17 | 77/64/59 |
| P2 away points | 0.2250 | 6.4624 | [−0.6761, 1.1261] | −29 | −10.00 | −2.00 | 0.00 | 2.00 | 12.00 | 27 | 69/70/61 |
| P3 possessions | −0.3150 | 3.7598 | [−0.8393, 0.2093] | −14 | −6.00 | −2.00 | 0.00 | 1.00 | 4.00 | 21 | 69/79/52 |
| P4 turnovers | 0.0200 | 2.2416 | [−0.2926, 0.3326] | −10 | −4.00 | −0.25 | 0.00 | 1.00 | 4.00 | 6 | 50/90/60 |
| P5 FGA | −0.1750 | 4.3241 | [−0.7779, 0.4279] | −13 | −7.05 | −2.00 | 0.00 | 1.00 | 6.05 | 23 | 70/79/51 |
| P6 3PA | −0.2400 | 3.0213 | [−0.6613, 0.1813] | −9 | −5.05 | −2.00 | 0.00 | 1.00 | 5.00 | 11 | 79/66/55 |
| P7 FTA | 0.0750 | 4.0561 | [−0.4906, 0.6406] | −13 | −6.05 | −2.00 | 0.00 | 1.25 | 7.05 | 15 | 61/80/59 |
| P8 personal fouls | 0.0100 | 2.5103 | [−0.3400, 0.3600] | −8 | −4.00 | −1.00 | 0.00 | 1.00 | 5.00 | 8 | 66/78/56 |

Descriptive only. A CI containing zero is not evidence of equivalence; a CI excluding zero is not a
realism or calibration finding.

## Mechanism

| Category | Games | Result |
|---|---|---|
| A — no disqualification | 11 | 11/11 complete canonical event-array equality |
| B — disqualification with substitution | 189 | 189/189 prefix equality up to the first v5 `Substitution`; first divergence equals that sequence in all 189 |
| C — disqualification without substitution | 0 | no observations |

Mechanism verdict: **PASS**. No unexpected pre-substitution divergence.

First-divergence index (1-based): 11 equal games; diverged games min 100, median 545, max 853.

Continuation: one horn-at-game-end case, slot 97 (`m004-t08-m0-20098`, seed 20098, overtime period 5,
`player-2-1` sixth foul at game clock 0, followed by `PossessionEnded(periodEnd)` → `PeriodEnded` →
`GameEnded`). No substitution window opens; legitimate, not a depleted-roster continuation.
True depleted-roster continuation: **0**.

## Participation descriptives

- Disqualifications: 464 total, 189 games with at least one, mean 2.32/game, max 6.
- Substitutions: 463 total, 189 games with at least one, mean 2.315/game, max 6.
- Mean `secondsPlayed` by canonical roster rank (400 player-games per rank):
  rank 1 2738.0, rank 2 2695.3, rank 3 1405.3, rank 4 1750.1, rank 5 1803.8, rank 6 1074.3,
  rank 7 1139.7, rank 8 844.4, rank 9 749.7, rank 10 100.2, rank 11 68.9, rank 12 52.9.
- Matchup breakdown: `t08-summary.json` → `matchupBreakdown` (n = 50 each, descriptive).

## Integrity

- 200 v4 rows, 200 v5 rows, 200 paired rows, 400 simulations; unique seeds 20001..20200.
- Registered identity (seed, matchup, gameId, teams, starting side) identical across arms for every slot.
- No failed, missing, replaced or extra simulations.
- No production simulation source, frozen specification or historical fixture changed.
