# T014 — Pre-registered paired-seed sensitivity protocol

Status: **FROZEN BEFORE EXECUTION — T014 only.** T015–T019 remain unauthorized.
Baseline commit: `fb9636814dc9c187ac5007352b1a3a159c41e201` (`develop/m002`, T013).
This protocol was written and frozen before any T014 experiment was run. It
implements AC09 as defined in `calibration-plan.md`.

Prior exploratory evidence: the T008 development probes in
`probability_sensitivity_test.dart` are acknowledged as prior, exploratory
diagnostics. They are not re-used, re-analysed or cited as AC09 evidence, and
their conclusions are not carried into this protocol.

## 1. Interventions (six, exactly)

| ID | Intervention | Target | Expected direction |
|---|---|---|---|
| E1 | `threePoint` +20 (clamp 100) on one shooter | his 3PT% | increase |
| E2 | `freeThrow` +20 (clamp 100) on one shooter | his FT% | increase |
| E3 | `rebounding` +20 (clamp 100) on the starting center | his share of live rebound opportunities | increase |
| E4 | `ballHandling` +20 (clamp 100) on the starting point guard | his turnovers per 100 offensive possessions | decrease |
| E5 | `perimeterDefense` +20 (clamp 100) on one defender | opponent eFG% on his positional matchup | decrease |
| E6 | +20 (clamp 100) on seven offensive skills of all five players of one lineup | team points per 100 completed possessions | increase |

E6 operational definition of "each offensive skill" (the frozen plan does not
enumerate fields): `insideScoring`, `midrange`, `threePoint`, `freeThrow`,
`passing`, `ballHandling`, `basketballIQ`. `perimeterDefense`, `interiorDefense`,
`rebounding`, `stamina` and `athleticism` are unchanged in the E6 primary
intervention.

## 2. Subject selection rules (deterministic, rating-based only)

Fixture: `const LeagueGenerator().generate(const GenerationConfig(seed: 20261028))`.
Home/treated team = `league.teams[0]` (`team-1`); opponent = `league.teams[1]`
(`team-2`). Baseline lineups = `ActiveLineup.defaultFor` for both teams.

Subjects are selected from the **home starting lineup** by pre-intervention
ratings only, with ties broken by lower lineup index (PG, SG, SF, PF, C):

| ID | Rule |
|---|---|
| E1 | highest `threePoint` in the home lineup |
| E2 | highest `freeThrow` in the home lineup |
| E3 | home lineup index 4 (starting center) |
| E4 | home lineup index 0 (starting point guard) |
| E5 | highest `perimeterDefense` in the home lineup |
| E6 | all five home lineup players |

No subject is changed after any result is seen. Actual selected players and
ratings are recorded in the results and report.

## 3. Pairing and corpus

- Seeds **1 through 200** inclusive, identical in both arms.
- Baseline arm: unmodified fixture, `GameRules.standard`, `gameId: game-1`,
  default probability model (`BasketballProbabilityModel()` via `GameSimulator`).
- Intervention arm: same fixture, seed, gameId, rules, lineups, opponent and
  player IDs/names/positions; only the target rating(s) differ.
- Baseline games are identical across E1–E6 and are computed once (200 games),
  then reused. Intervention games: 200 per experiment (1,200 games).
- Total executions: 1,400 games (200 baseline + 1,200 intervention).
- Both arms use the default `GameSimulator` probability model; no injected model.
- Per-seed divergence of event streams is expected and allowed; comparison is
  paired at the aggregate level, never per-event or per-game monotonicity.

## 4. Attribute-application integrity

`League.toJson()` is copied, the target player's attribute map is incremented by
20 capped at 100, and the copy is rebuilt with `League.fromJson` (full domain
validation). The home lineup is rebuilt with `ActiveLineup.defaultFor` from the
rebuilt roster, so the lineup references the changed `PlayerAttributes`
instances. Integrity is asserted per run:

- only the target attribute value(s) differ anywhere in the league snapshot;
- player ID, team, name, position, roster order and lineup order are unchanged;
- both arms produce valid `GameInput` values with different fingerprints;
- applied delta equals `min(20, 100 - baselineRating)`.

## 5. Primary metrics and denominators

Notation: `P` = selected player; `T` = treated home team; `O` = opponent.

| ID | Numerator | Denominator | Per-seed metric |
|---|---|---|---|
| E1 | P's made 3-point FGs | P's 3-point attempts | 3PM / 3PA |
| E2 | P's made FTs | P's FT attempts | FTM / FTA |
| E3 | P's total rebounds | live rebound opportunities in the game | REB / opportunities |
| E4 | P's turnovers | T's started possessions | 100 × TOV / startedPossessions |
| E5 | O's positional-matchup FGM + 0.5 × 3PM | O's positional-matchup FGA | eFG% |
| E6 | T's points | T's completed possessions | 100 × points / completedPossessions |

Definitions used throughout (from `calibration-plan.md`):

- `live rebound opportunity` = one `Rebound` event. `DeadBallMiss` events are
  not live rebound opportunities and are excluded. The denominator is the number
  of live rebound events in the game (every live miss resolves to exactly one
  rebound per T010/T013).
- `startedPossessions` (per team) = number of `PossessionStarted` events with
  that team as offense.
- `completedPossessions` (per team) = number of `PossessionEnded` events with
  that team as offense and reason `turnover`, `madeFieldGoal`,
  `madeFinalFreeThrow` or `defensiveRebound`. `periodEnd` closures are excluded;
  offensive-rebound continuations create no `PossessionEnded`.
- E5 positional matchup = opponent `FieldGoalAttempt` events whose shooter
  occupies the same `Position` as `P`. Fixed positional assignments only; no
  switches or help defense are inferred.

Secondary descriptive metrics (reported, not part of the confirmatory family):
3PA and FGA usage for E1; FTA counts for E2; OREB/DREB split and team rebound
shares for E3; team/steal/non-steal/shot-clock turnover splits for E4; opponent
turnovers per 100 opponent started possessions for E5; points per game, FG%,
3PA/FGA, FT%, turnover rate, shot-clock violations and OREB share for E6.

## 6. Zero-opportunity policy

A seed pair contributes to the primary analysis only when **both** arms have a
defined metric (denominator > 0). Zero-opportunity seeds:

- are never assigned a rate of 0, 1 or a favourable outcome;
- are counted and reported per arm and for "zero in both arms";
- are excluded from the paired difference, never replaced by other seeds.

Opportunity-weighted pooled rates are reported separately as descriptive
evidence only. The per-seed mean paired difference is the sole primary estimator;
pooled and per-seed metrics are never swapped after inspection.

## 7. Statistics

- Paired difference: `delta_i = intervention_i - baseline_i` for valid pairs.
- Estimate: arithmetic mean of valid deltas; also median, sample SD (n−1).
- Standardized effect: paired Cohen's `dz = mean / SD`. If `SD == 0`, `dz` is
  reported as undefined; a degenerate zero-variance sample cannot pass.
- **Bootstrap**: 10,000 paired resamples of whole seed-pair observations with
  replacement, percentile 95% interval, type-7 linear-interpolation quantiles.
  Bootstrap RNG: `xorshift32-v1` reimplemented in the analysis tool
  (`tool/t014_stats.dart`), seed **20261029**, independent of the game PRNG and
  of the permutation stream.
- **Hypothesis test**: two-sided paired sign-flip permutation test, 10,000
  deterministic permutations, seed **424242**, same independent RNG
  implementation. Monte Carlo p-value `p = (1 + #{|mean_perm| >= |mean_obs|}) /
  (M + 1)`, so `p` is never reported as 0.
- **Multiplicity**: Holm–Bonferroni across the six confirmatory p-values;
  adjusted `p_(i) = max_{j<=i} min(1, (m-j+1) * p_(j))`, `m = 6`.
- E5's opponent-turnover diagnostic is exploratory and outside the six-test
  family; it is reported with its own unadjusted p-value only.

## 8. Success criteria (fixed)

An experiment **PASSES** only if all hold:

1. mean paired difference has the expected sign;
2. the 95% percentile bootstrap interval excludes zero in that direction;
3. Holm-adjusted p < 0.05;
4. at least **100** valid paired seeds contribute;
5. no protocol deviation invalidates inference.

Otherwise: **FAIL** when evidence is sufficient and points opposite the expected
direction (Holm-adjusted p < 0.05 with opposite sign), and **INCONCLUSIVE** when
the interval includes zero, the p-value is not significant, or fewer than 100
valid pairs contribute.

AC09 overall passes only if all six experiments pass. T014 execution is complete
when all six are run and reported honestly, regardless of AC09 outcome.

## 9. Treatment of the frozen E5 wording

`calibration-plan.md` writes "opponent eFG% against him / opponent TOV rate" with
both directions. This protocol resolves the ambiguity before execution: eFG% is
the **confirmatory** metric (expected decrease); opponent turnovers per 100
possessions is a **directional diagnostic** (expected increase) reported with
unadjusted uncertainty. The multiplicity family remains exactly six (E1–E6), so
the diagnostic cannot be promoted or dropped after seeing data.

## 10. Deviations and known limitations

- No new defensive attribution fields, switches or help-defense inference exist;
  E5 measures only the fixed same-position matchup.
- E4 and E3 use single-player changes while the model applies several
  team-average and position-weighted terms, so weak or null effects are
  expected model findings, not harness failures.
- E1/E2 rates are per-game ratios with discrete and sometimes few opportunities;
  zero-opportunity seeds are excluded per §6.
- The fixture is one league and one matchup; results are aggregate evidence for
  this fixture, not a general realism claim.
- Any methodological flaw discovered after execution is reported as a deviation
  and requires a full rerun with the correction documented; thresholds are never
  adjusted after seeing results.
