# Calibration and Basketball Plausibility Plan 002

Status: **FROZEN — READY FOR IMPLEMENTATION AUTHORIZATION**
Frozen: 2026-10-28. Implementation remains **NOT AUTHORIZED**.

Three separate gates:

1. **Structural correctness (hard):** event/clock/possession constraints and
   complete stat reconciliation.
2. **Statistical directionality (hard):** pre-registered paired-seed experiments
   show aggregate effects in the expected direction.
3. **Basketball plausibility (human review):** distributions and sample games are
   reviewed against an explicitly chosen fictional style; parameters and limits
   are disclosed.

Accounting correctness is not evidence of realism.

## Sample design

- **1,000 completed games** for the base distribution run: pinned league
  fixture(s), diverse home/away pairings and seeds; never one team pair only.
- **100 distinct seeds** for every core invariant/property test (AC06 minimum);
  **200 recommended**. Use 100 as the gate.
- **AC09 paired-seed experiments:** 200 seeds per experiment, same matchup,
  rules, lineups and seed; only the target ratings change. Branch divergence
  means outcomes are compared as paired aggregates, never as per-game
  monotonicity.
- Record every seed, team/lineup IDs, versions, environment and configuration.
  Publish summaries and a machine-readable sample; do not store huge ledgers in
  Git.
- The A1 action-duration distribution below is fixed but uncalibrated; pace,
  points and possession bands are interpreted against it and it is versioned.

## A1 duration model (uncalibrated, versioned)

Live offensive phases, not individual events, consume the approved durations:
transition 15% (2–7 s), early offense 30% (5–11 s), half-court 55% (10–22 s),
using basis points 1500/3000/5500 and two bounded PRNG draws per phase. The
distribution is provisional and uncalibrated; calibration evaluates pace under
this fixed model and never retunes brackets after seeing the sample without a
rules-version bump. Watch the interaction between the 14-second offensive-rebound
reset and the 10–22 s half-court bracket: overshoot is classified as a shot-clock
turnover, so a high ORB violation rate is a design finding, not a reason to clamp
durations.

## AC09 pre-registered experiments and decision rule

Register before looking at calibration data; changing it afterwards invalidates
the evidence.

| # | Intervention | Primary metric | Expected direction |
|---|--------------|----------------|--------------------|
| E1 | +20 `threePoint` for one high-usage shooter (clamped 100) | his 3PT% | increase |
| E2 | +20 `freeThrow` for one FT shooter | his FT% | increase |
| E3 | +20 `rebounding` for one big | his share of rebound opportunities | increase |
| E4 | +20 `ballHandling` for the primary ballhandler | his turnovers per 100 offensive possessions | decrease |
| E5 | +20 `perimeterDefense` for the primary defender | opponent eFG% against him / opponent TOV rate | decrease / increase |
| E6 | +20 to each offensive skill of all five offensive players | team points per 100 possessions | increase |

Decision rule per experiment:

- Mean paired difference across 200 seeds in the expected direction.
- 95% percentile bootstrap confidence interval (10,000 resamples) excludes zero.
- Report the standardized effect size and the number of seeds contributing data.
- Holm–Bonferroni correction across the six experiments for the overall claim.
- Zero opportunities are reported, never counted as success.
- A failed experiment is a design finding, not a reason to change the rule after
  seeing the data.

These are aggregate claims only. No individual game, player or seed is promised
to move in the expected direction.

## Provisional bands (not source-validated NBA benchmarks)

Initial warning thresholds for the fictional NBA-inspired league; owner review
required. Violations trigger diagnosis, not silent band edits.

| Metric (per team per game unless noted) | Initial review band | Interpretation |
|-----------------------------------------|---------------------|----------------|
| Median points | 85–130 | Scoring pace sanity |
| Median FGA | 70–105 | Shot volume |
| 3PA / FGA, aggregate | 0.20–0.55 | Shot mix |
| FG%, aggregate | 0.36–0.57 | Broad conversion guardrail |
| FT%, aggregate | 0.55–0.90 | FT rating mapping |
| FTA / FGA, aggregate | 0.10–0.50 | Foul/bonus path |
| OREB share of live missed FG/final FT | 0.12–0.40 | Rebound contests |
| Turnovers per 100 completed possessions | 7–24 | Turnover plausibility |
| Assisted FGM share | 0.25–0.85 | Assist modeling |
| Combined game points outside 90–340 | Report occurrence | Sanity diagnostic |
| BLK / FGA, STL / TOV, pace (possessions per 48 min) | No pass/fail band yet | Report only; owner sets bands after the first sample |

No home-court advantage exists in M002, so home/away differences are sampling
noise and must be labelled as such.

## Mandatory reporting

For points, pace, FGA, FGM%, 3PA share, FTA/FGA, FT%, OREB%, TOV rate, AST share,
BLK per FGA and steals per turnover:

- mean, median, standard deviation, 5th/95th percentiles and zero/denominator
  cases;
- home vs away, high-rated vs low-rated teams, and position distribution;
- one low, one median and one high scoring game with event-linked box scores.

Define the possession count once and use it throughout:

- `startedPossessions` = number of `PossessionStarted` events;
- `completedPossessions` = possessions ending by turnover, made FG without
  attached FTs, made final FT, or defensive rebound; period-ending possessions
  and offensive-rebound continuations are reported separately;
- label engine counts separately from estimated box-score possessions
  (`FGA - OREB + TOV + 0.44*FTA`), which are not the same metric.

OREB% uses `OREB / (OREB + opponent DREB)` over live missed FG/final FT attempts;
`DeadBallMiss` is excluded.

Report overtime games, maximum overtime count, bound failures, min/max
events/game and any invalid states.

## Failure-pattern checklist

- Home team always/never wins.
- Overtime impossible or far too common.
- Near-zero turnovers, rebounds, FTs, 3PA or blocks across large samples.
- Perfect/zero shooting for implausible proportions of games.
- One player scores nearly every point regardless of ratings.
- Points change without ledger/box-score changes.
- Offensive rebounds end possessions or defensive rebounds retain them.
- Last-FT misses create orphan/dead-ball rebounds.
- Possessions exceed the shot clock or periods exceed the game clock.
- Any completion timeout, repeated dead-ball action or invisible random bailout.
- A game exceeding any OD-14 bound ends silently with a winner.

## Performance evidence

AC12 targets (provisional): 1,000 games ≤ 60 s on a documented desktop, p95
≤ 100 ms/game, ≤ 128 MiB incremental memory, no unbounded loops. Record CPU, OS,
Dart version, compilation mode, warmup and measurement method. If the reference
environment is unavailable, report what was measured and leave sign-off pending.
No Android device claim without a real measurement.

## Review decision

AC10 is approved only after the owner sees aggregate evidence with definitions
and sampling method, plus inspectable example games. Approval records the
dataset/engine versions and remaining limitations. The engine never self-certifies
realism.

Definitions reference: https://www.nba.com/stats/help/glossary and
https://official.nba.com/rule-no-5-scoring-and-timing .
