# T014 — Paired-seed attribute sensitivity report

Status: **T014 EXECUTION COMPLETE. AC09 STATISTICAL GATE NOT PASSED.**
Baseline commit: `fb9636814dc9c187ac5007352b1a3a159c41e201` (`develop/m002`, T013).
Pre-registration: `t014-analysis-protocol.md` (frozen before execution).
This task measured the existing model. No coefficient, bracket, formula, schema,
PRNG or golden fixture was changed, and none was authorised.

## 1. Pre-registration

`t014-analysis-protocol.md` fixed, before any T014 game ran: the six
interventions, subject-selection rules, league seed and matchup, pairing method,
seed corpus 1–200, metrics and denominators, zero-opportunity policy, bootstrap
and permutation parameters, Holm procedure, effect-size definition, pass/fail
criteria, the E6 offensive skill set and the E5 confirmatory/diagnostic split.
No threshold, metric or definition was changed after execution. The T008
development probes are acknowledged as prior exploratory evidence and are not
used as AC09 evidence.

## 2. Experiments and observed outcomes

Fixture: league seed 20261028, home `team-1` (treated), away `team-2`.
Baseline games are identical for all experiments and were run once (200 games);
each experiment ran its own 200 intervention games: **1,400 games total**.

| ID | Intervention | Subject (baseline rating) | Applied delta |
|---|---|---|---|
| E1 | `threePoint` +20 | `player-1-1`, SG, highest 3PT rating (69) | 69 → 89 |
| E2 | `freeThrow` +20 | `player-1-3`, PG, highest FT rating (74) | 74 → 94 |
| E3 | `rebounding` +20 | `player-1-8`, starting C (55) | 55 → 75 |
| E4 | `ballHandling` +20 | `player-1-3`, starting PG (72) | 72 → 92 |
| E5 | `perimeterDefense` +20 | `player-1-1`, SG, highest perimeter rating (58) | 58 → 78 |
| E6 | seven offensive skills +20 | all five starters | every offensive rating raised by exactly 20 |

No rating hit the 100 cap, so every applied delta is the full +20. Integrity is
asserted per run: the copied league differs only at the pre-registered attribute
paths, and both arms differ in input fingerprint (1,200/1,200 pairs). Lineups are
rebuilt from the modified roster, so the intervention lineup uses the changed
`PlayerAttributes` instances; IDs, names, positions, roster and lineup order are
unchanged.

## 3. Corpus and opportunity counts

- Planned pairs per experiment: 200 (seeds 1–200). Baseline reused across
  experiments (identical canonical input).
- Every game: reducer-validated, accounting-reconciled, non-tied, inside bounds.
- No engine failure occurred, so no exception was reclassified as a
  zero-opportunity case.

Zero counts are **per-arm inclusive** (a seed with zero opportunities in both
arms counts in both columns); exclusive counts subtract the zero-both seeds.

| ID | Valid pairs | Zero in baseline (incl. both) | Zero in intervention (incl. both) | Zero both | Zero baseline only | Zero intervention only |
|---|---|---|---|---|---|---|
| E1 | 200 | 0 | 0 | 0 | 0 | 0 |
| E2 | 172 | 28 | 28 | 28 | 0 | 0 |
| E3 | 200 | 0 | 0 | 0 | 0 | 0 |
| E4 | 200 | 0 | 0 | 0 | 0 | 0 |
| E5 | 200 | 0 | 0 | 0 | 0 | 0 |
| E6 | 200 | 0 | 0 | 0 | 0 | 0 |

E2's 28 excluded seeds had zero free-throw attempts for the subject in **both**
arms (zero opportunity, not a miss). They are excluded from the paired estimate
and retained in the CSV with `status=zero-both`.

## 4. Primary results

Paired difference = intervention − baseline, per seed; bootstrap = 10,000 paired
percentile resamples (seed 20261029); p = two-sided paired sign-flip permutation,
10,000 permutations (seed 424242); Holm across six hypotheses.

| ID | Metric | Mean baseline | Mean intervention | Mean Δ | Median Δ | SD | dz | 95% CI | raw p | Holm p | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| E1 | player 3PT% | 0.45692 | 0.52816 | **+0.07124** | +0.04281 | 0.13856 | 0.514 | [0.05225, 0.09033] | 0.0001 | 0.0006 | **PASSED** |
| E2 | player FT% | 0.77594 | 0.90174 | **+0.12580** | 0.00000 | 0.16475 | 0.764 | [0.10206, 0.15072] | 0.0001 | 0.0006 | **PASSED** |
| E3 | rebound share | 0.15880 | 0.17236 | **+0.01356** | +0.01176 | 0.02558 | 0.530 | [0.01002, 0.01706] | 0.0001 | 0.0006 | **PASSED** |
| E4 | TOV / 100 started poss. | 11.62235 | 11.86828 | **+0.24594** | 0.00000 | 2.42836 | 0.101 | [−0.09193, 0.58251] | 0.1503 | 0.1503 | **INCONCLUSIVE** |
| E5 | opponent eFG% (matchup) | 0.56391 | 0.49083 | **−0.07308** | −0.05296 | 0.11387 | −0.642 | [−0.08940, −0.05778] | 0.0001 | 0.0006 | **PASSED** |
| E6 | points / 100 completed | 99.80761 | 125.17410 | **+25.36649** | +25.01831 | 15.32520 | 1.655 | [23.23677, 27.45698] | 0.0001 | 0.0006 | **PASSED** |

The p-value floor is `1/(10,000+1) = 0.0001`; no p-value of zero is reported.
E4's observed direction is opposite the expectation (more turnovers) but the
interval includes zero and the permutation test is not significant, so it is
INCONCLUSIVE rather than FAILED. AC09 overall is therefore **INCONCLUSIVE**.

## 5. Descriptive evidence (pooled, not the primary estimator)

- **E1**: subject 3PA 1,633 → 1,903 (+16.5%); 3PM 744 → 996; pooled 3PT% 45.6% →
  52.3%; subject FGA 3,764 → 4,167; team 3PA 7,003 → 7,105. Shot selection and
  usage shifted toward the improved shooter, as expected.
- **E2**: FTA 935 → 947; FTM 736 → 849; pooled FT% 78.7% → 89.7%.
- **E3**: rebounds 2,989 → 3,246 (OREB 813 → 889, DREB 2,176 → 2,357); live
  rebound opportunities 18,818 → 18,851; team rebounds 9,300 → 9,467; pooled
  share 15.88% → 17.22%.
- **E4**: subject turnovers 2,388 → 2,434 (steal-linked 364 → 367, non-steal
  378 → 396, shot-clock 1,367 → 1,376); team turnovers 5,016 → 4,947; started
  possessions 20,579 → 20,551; completed possessions 20,198 → 20,196; pooled
  11.60 → 11.84 per 100 started possessions.
- **E5**: opponent matchup FGA 3,856 → 3,866; FGM 1,777 → 1,563; 3PM 768 → 642;
  pooled eFG% 56.0% → 48.7%; opponent turnovers 4,967 → 5,040.
- **E6**: points 20,159 → 25,394 per 200 games; completed possessions 20,198 →
  20,287; started 20,579 → 20,632; FG% 46.7% → 57.4%; 3PA/FGA 42.6% → 40.5%;
  FT% 66.7% → 77.2%; turnovers per 100 completed 24.83 → 20.84; shot-clock
  violations 1,367 → 1,304; OREB share 26.7% → 28.3%.

## 6. E5 exploratory diagnostic (outside the six-test family)

Opponent turnovers per 100 opponent started possessions: baseline 24.14,
intervention 24.55, mean paired difference **+0.44245**, 95% CI
[0.02053, 0.87325], unadjusted p = 0.0435. Direction matches the frozen
expectation (increase) but it is exploratory only and is not counted as a sixth
or seventh confirmatory result.

## 7. AC09 verdict

**INCONCLUSIVE.** Five of six pre-registered experiments pass every criterion
(expected sign, interval excluding zero, Holm-adjusted p < 0.05, ≥100 valid
pairs). E4 (`ballHandling`) does not: the point estimate moves in the wrong
direction and is not distinguishable from zero (Holm p = 0.150). AC09 requires
all six to pass, so the gate is not met and no coefficient was changed in
response.

## 8. Model observations and explanations

- **E4 weakness (expected by design).** Turnover probability is driven largely by
  team-average attributes and the position-weighted handling terms, so raising
  one player's `ballHandling` by 20 dilutes to a near-zero effect (dz 0.10).
  The subject also commits most of his turnovers as shot-clock violations
  (1,367 of 2,388), which depend on phase duration and possessions rather than
  handling skill under the current formula. This is a formula-level finding for
  owner review in T015, not a harness failure.
- **E3 small but clear.** Rebound attribution is position-weighted with team
  rebounding strength, so a single-center change moves the share by only ~1.4
  percentage points (dz 0.53), consistent with the T008 design note.
- **E1 usage response.** Improving 3PT rating changed shot selection (+270 3PA
  and +403 FGA for the subject), so conversion and volume moved together; the
  primary metric remains a ratio, not a volume claim.
- **E2 sparse opportunity.** 28/200 seeds had no FT attempt for the subject in
  either arm; the remaining 172 still met the ≥100-pair requirement.
- **E5 positional attribution.** Only same-position opponent attempts were
  counted; no switches or help defense are modelled, and the effect remains
  large (dz −0.64) because the matchup shooter is fixed.

## 9. Evidence correction and reconciliation

An evidence review found two artifact defects that did **not** affect any
statistical estimate but did misrepresent the CSV and summary:

1. `baselineMetric` / `interventionMetric` in the CSV were written in raw rate
   units while `pairedDifference` was scaled by 100 for E4 and E6. All three
   fields are now produced by the same `scaledRate` / `pairedScaledDifference`
   helpers, so every valid row reconciles exactly
   (`difference == intervention − baseline`, tolerance 1e-9).
2. `zeroBaseline` / `zeroIntervention` excluded zero-both seeds, so E2 reported
   0/0 although 28 seeds had no opportunity in either arm. Counts are now
   per-arm inclusive, with explicit `zeroBaselineExclusive` /
   `zeroInterventionExclusive` fields retained.

The experiment was re-run after the fix. Every per-seed difference, mean,
median, SD, dz, interval, p-value, Holm-adjusted p-value and verdict is
unchanged; recomputing each experiment's mean from the corrected CSV matches the
summary exactly (E1–E6 means: 0.07124, 0.12580, 0.01356, 0.24594, −0.07308,
25.36649). The runner now asserts row reconciliation while writing, and three
statistical-method tests cover scaled rates, paired differences and
zero-denominator handling.

Example corrected rows: E4 seed 2 baseline 11/100 = 11.0 per 100, intervention
7/99 = 7.0707 per 100, difference −3.9293; E6 seed 1 baseline 119/98 = 121.4286
per 100, intervention 134.2857, difference 12.8571.

## 10. Reproducibility

```
cd packages/simulation_core
dart run tool/t014_sensitivity.dart
```

Outputs (regenerated deterministically; byte-stable for the same code and seeds):

- `specs/002-possession-simulation/t014-paired-results.csv` — 1,200 rows, one
  per experiment/seed, with both input fingerprints, numerators, denominators,
  per-seed metrics **and** paired differences in the same reporting unit
  (rate for E1/E2/E3/E5, per 100 possessions for E4/E6), opportunity status,
  applied deltas and version identifiers. Every valid row reconciles; excluded
  rows carry no metric values.
- `specs/002-possession-simulation/t014-statistical-summary.json` — subjects,
  applied attributes, counts, estimates, intervals, p-values, Holm-adjusted
  p-values, verdicts, pooled and descriptive aggregates.

The experiment runs only on the Dart VM. No Chrome statistical parity is
claimed. Wall time was ~12 s for 1,400 games and 20,000 bootstrap/permutation
resamples on this workstation; that is an observation, not an AC12/T016 result.

## 11. Verification

```
dart format --output=none --set-exit-if-changed lib test tool → 56 files, 0 changed
dart analyze                                                 → No issues found
dart test                                                    → 317 passed
dart test -p chrome test/simulation test/deterministic_random_test.dart \
    test/generator_test.dart test/validation_test.dart       → 316 passed
flutter analyze                                              → No issues found
flutter test                                                 → 8 passed
```

T012 canonical goldens are unchanged (seed 42: 800 events, 94–77, fingerprint
`bcb1a58f…`, digest `f8cfc12e…`; seeds 1/99/20261029 unchanged). No production
library file, dependency, schema or version constant changed; nothing under
`packages/simulation_core/lib/` differs.

## 12. Limits

- One league fixture and one matchup; aggregate evidence only.
- 200 paired seeds per experiment; no per-game monotonicity claim.
- E4 and E3 use single-player changes in a model that applies team-average and
  position-weighted terms; weak effects are model findings.
- E5 measures only the frozen positional matchup.
- No realism, calibration or performance acceptance is claimed. T015 (≥1,000
  games, owner review) and T016 remain deferred; AC09 failure is recorded for
  owner decision, not repaired.

## 13. T014 execution verdict

**GO for execution and documentation.** All six experiments ran as pre-registered
with reproducible paired data, correct opportunity handling, uncertainty
estimation and multiplicity correction. **AC09 statistical acceptance is NOT
met** because E4 is inconclusive; that result is preserved for T015/T019 owner
review and was not tuned away.
