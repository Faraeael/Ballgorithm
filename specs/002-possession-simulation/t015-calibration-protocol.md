# T015 — Calibration sampling protocol (frozen before execution)

Status: **FROZEN BEFORE THE FINAL 1,120-GAME RUN — T015 only.**
Baseline: `ab8e721dcce70e4245426a2062a0f9142244fd96` (`develop/m002`,
Amendment 002 v2). No gameplay parameter is modified by T015.

## 1. Fixture and schedule

- League: `const LeagueGenerator().generate(const GenerationConfig(seed: 20261028))`
  (8 fictional teams, 12 players each, M001 snapshot).
- Teams ordered by `TeamId` value (`team-1`…`team-8`).
- Unordered pairs in lexicographic order (28 pairs).
- Each pair played in both orientations (home first, then away first), giving 56
  directed matchups.
- 20 seeds per directed matchup → **1,120 planned games**.

## 2. Seed assignment (frozen)

For directed matchup index `m` in `0..55` (pair index `p = m ~/ 2`, orientation
`o = m % 2`) and slot `s` in `0..19`:

```
seed(m, s) = 1 + ((97 * m + 17 * s) mod 200)
```

`17` and `200` are coprime, so every directed matchup uses 20 distinct seeds; the
`97 * m` offset spreads seeds across matchups and the whole corpus covers the
`1..200` range. Seed assignment is independent of outcomes.

## 3. Inputs

- `GameInput.create(gameId: 't015-<m>-<s>', league, home, away, default lineups,
  seed, GameRules.standard)`.
- Default probability model (`GameSimulator()`), simulation v2, rules 1,
  fingerprint 1, event schema 2, A1 duration model 1, PRNG `xorshift32-v1`.
- No lineup, rules or model variation in the primary sample. A separate bounded
  configuration probe may be reported descriptively; it is not part of the
  1,120-game corpus.

## 4. Failure policy

Every planned game either completes and enters the sample, or raises a typed
`GameValidationException` recorded with matchup, seed and rule set. Failed games
are never replaced. If fewer than 1,000 games complete, the sample-size gate is
NOT MET and acceptance is NO-GO.

## 5. Possession definitions (frozen)

- `startedPossessions`: `PossessionStarted` events for that team.
- `completedPossessions`: `PossessionEnded` for that team with reason
  `turnover`, `madeFieldGoal`, `madeFinalFreeThrow` or `defensiveRebound`.
- `periodEndPossessions`: `PossessionEnded(reason: periodEnd)`.
- `orebContinuations`: offensive `Rebound` events (possession continues; no new
  `PossessionStarted`).
- `estimatedPossessions = FGA − OREB + TOV + 0.44 × FTA` (label as estimate).
- Turnover rate per 100 **completed** possessions (frozen band denominator).
- OREB% = `OREB / (OREB + opponent DREB)`; `DeadBallMiss` excluded.

## 6. Metrics (mandatory)

Team/game: points, combined points, period points, points per 100 completed
possessions, FGA/FGM/FG%, 2PA/2P%, 3PA/3P%, 3PA/FGA, FTA/FTM/FT%, FTA/FGA,
personal fouls by kind, bonus awards, fouls per period, OREB/DREB/REB, OREB%,
assists, assisted-FGM share, steals, blocks, TOV by subtype, TOV/100 completed,
started/completed/period-end/estimated possessions, events, periods, overtime,
win rates, team ratings, position splits, player concentration.

Statistics per metric: n, mean, median, sample SD, min, max, p5, p95 (type-7
percentiles), undefined/zero-denominator count, home/away split, stronger/weaker
side split. Team-level distributions use per-team-per-game observations; game
totals use per-game observations.

## 7. Frozen provisional bands (review thresholds, not NBA benchmarks)

Per-team median points 85–130; per-team median FGA 70–105; aggregate 3PA/FGA
0.20–0.55; aggregate FG% 0.36–0.57; aggregate FT% 0.55–0.90; aggregate FTA/FGA
0.10–0.50; live OREB% 0.12–0.40; TOV per 100 completed 7–24; assisted FGM share
0.25–0.85. Combined game points outside 90–340 are counted, not banded. No
invented thresholds for pace, steals/TOV or blocks/FGA.

## 8. Shot-clock diagnostics

Each shot-clock turnover is classified by the reset state that produced it:
`start24` (possession start at 24), `oreb14` (offensive rebound reset), or
`retainedFoul` (retained possession after a non-bonus defensive foul, floor
`max(remaining, 14)`), else `other`. State-entry counts provide denominators.
A1 duration classes are not recorded in the event ledger; the report states this
limitation and compares observed overshoot counts with analytic single-draw
overshoot probabilities from the frozen brackets.

## 9. Foul and free-throw checks

Bonus awards are checked against the per-period defensive foul count and the
OD-11 thresholds (5 regulation, 4 overtime); offensive fouls must not increment
the bonus counter; missed shooting fouls produce FTs with no FGA at that
timestamp; and-ones produce exactly one FT and no bonus; free throws after a
terminal horn event complete before `PeriodEnded`; missed final FT with OREB
continues the same possession; DREB transfers.

## 10. Structural verification

Every completed game is re-validated with `GameEventReducer.validate`, reconciled
with `EventAccounting`, checked for non-tied result, legal clocks/periods, and
possession ownership. Ten pinned games are simulated twice and their canonical
ledger SHA-256 compared for determinism.

## 11. Team strength

Declared measure: `rating = mean of the 11 rated attributes (all except stamina)
over the five starters`. Stronger side = higher rating in that matchup; splits
use that label. This is descriptive, with no acceptance gate.

## 12. Representative games

Lowest, median and highest combined-score games from the corpus, with period
scores, team/player boxes, turnover subtypes, foul/FT/rebound breakdown, event
count, ledger digest and event-ID references for notable sequences.

## 13. Outputs and provenance

- `t015-game-sample.csv` (one row per completed game)
- `t015-statistical-summary.json` (distributions, bands, checks, provenance)
- `t015-diagnostic-cases.md` (three games + edge-case references)
- `t015-calibration-report.md` (analysis, findings, remedies)
- Source SHA-256 for simulator, accounting, reducer, versions, harness and
  support fixture; Git HEAD, Dart version, OS.

Outputs are deterministic: same seed schedule and code give identical CSV/JSON.

## 14. Non-goals

No coefficient tuning, no A1 changes, no rule/schema/version changes, no ledger
regeneration, no T016 performance claim, no AC10 self-approval.


## 15. Supplement — passive A1 trace (separately authorized)

The original protocol recorded that A1 duration classes were not observable from
the ledger. A minimal, passive observer was subsequently authorized for T015 only:

- `GameSimulator(onPhaseTrace: ...)` receives one record per sampled A1 phase
  with kind, planned seconds, pre-draw game and shot clocks, and a resolution
  class (`legalShot`, `legalFoul`, `legalTurnover`, `shotClockOvershoot`,
  `shotClockExpiryNoAttempt`, `actionDiscardedAtHorn`, `gameClockFirst`,
  `simultaneousExpiry`).
- The observer is optional and default-off; it cannot draw randomness or mutate
  state. The one-second final-tick path never emits a phase record because it
  performs no A1 draw.
- Behaviour preservation is proven by unchanged ledger bytes and by the
  `t015-game-sample.csv` SHA-256 `1098dc8a…1314ea` before and after tracing.
- The corpus rerun is identical (1,120 completed, same turnovers, same bands);
  only additive trace sections were appended to the JSON and diagnostics.

### Clock-specific aggregation (final)

The trace is aggregated by the actual pre-draw shot clock with the denominator
restricted to shot-clock-eligible phases (`gameClockBefore > shotClockBefore`),
so observed overshoot rates are compared with `P(D > S)` on sampled phases, not
on reset-entry counts. Exact exhaustion (`D == S` with no qualifying action) is
reported separately. The retained-floor table from the event ledger is retained
as a secondary view.
