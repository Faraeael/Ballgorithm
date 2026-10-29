# M002 Phase 2A — Probability model (T008)

Status: **IMPLEMENTED — Phase 2A, T008 only. Uncalibrated.**
Base: `feat/m002-phase2a-probability-model` at Phase 1 commit `46d5dce`.
Specification: frozen M002 (`dd4234d`). Formal calibration and AC09/AC10 are
T014/T015 and remain unauthorized.

This document records the provisional coefficients of
`BasketballProbabilityModel` (`lib/src/simulation/probability_model.dart`) and
the typed decisions in `lib/src/simulation/action_intent.dart`. Coefficients are
design choices, not empirically validated basketball constants. No realism claim
is made.

## Scope boundary

The model returns typed decisions only:

- `PhaseDuration` — A1 phase type and planned integer seconds;
- `ShotAttemptAction` — shooter, zone, make/miss, and-one, shooting foul,
  assist and block attribution;
- `TurnoverAction` — ballhandler, steal versus non-steal classification;
- `OffensiveFoulAction`, `NonShootingFoulAction`;
- `ReboundIntent` — team plus one active rebounder;
- `FreeThrowGroupIntent` — per-attempt made flags.

It does not emit events, move clocks, own possessions, implement bonus
thresholds, free-throw sequencing, period logic or a second scoreboard. T009/T010
translate decisions into the existing `GameEvent` hierarchy and resolve OD-02
clock precedence.

## Determinism and draw order

Integer basis points (`0..10000`) only; the caller's game-local
`DeterministicRandom` is the only randomness source. No floats, wall clock,
`Random()`, network or Flutter imports.

| Entry point | Draws (in order) |
|-------------|------------------|
| `drawPhaseDuration` | 1) `nextInt(10000)` phase type; 2) `nextInt(upper-lower+1)` duration offset |
| `selectAction` | 1) `nextInt(10000)` category (turnover / offensive foul / non-shooting foul / field goal); 2) actor over normalized basis-point weights; 3) turnover: steal share then (steal only) defender; field goal: zone then make; 4) field goal: foul check, then assist (made) or block (miss without foul); conditional actor draws for passer/blocker |
| `selectFinalTickAction` | No A1 and no category draws: actor, zone, make, foul, assist/block |
| `resolveRebound` | 1) rebound team; 2) rebounder on the winning side |
| `resolveFreeThrows` | one draw per awarded attempt |

Actor draws consume exactly one `nextInt(10000)` over weights normalized to
10000. Weight normalization assigns the rounding remainder to the last positive
slot, so an excluded player (assist passer cannot be the shooter) is never
selected.

## Coefficient summary

Sharp modifiers use `rating - 50`; `clamp` is inclusive.

### Usage and actors

| Decision | Formula | Clamp | Expected direction |
|----------|---------|-------|--------------------|
| Shot usage | position base PG 260, SG 240, SF 220, PF 190, C 170 + `max(0, bestShot-50)*3` + `(ballHandling-50)*2` + `(basketballIQ-50)`, floor 60, normalized | 10000 total | Better scorers/handlers receive more attempts per aggregate sample; no player can own every action |
| Ballhandler | position base PG 420, SG 320, SF 280, PF 220, C 180 + `ballHandling*3` + `passing` + `IQ` | 10000 total | Primary handler dominates live turnovers and foul-drawing |
| Steal weighting | `perimeterDefense*3 + athleticism*2` + position bonus 200/160/120/80/40 | — | Perimeter defenders steal more |
| Assist weighting | `passing*3 + IQ*2` + position bonus 300/150/100/60/40, shooter excluded | — | Pass-first players create assists |
| Block weighting | `interiorDefense*3 + athleticism*2` + position bonus 20/40/120/260/380 | — | Interior defenders block more |
| Rebound weighting | `rebounding*3 + athleticism` + position bonus 0/40/100/220/300 | — | Bigs and strong rebounders dominate |

### Shot selection

| Zone | Weight | Position bonus (PG→C) | Phase bonus (transition/early/half) |
|------|--------|-----------------------|-------------------------------------|
| Inside | `2400 + (insideScoring-50)*22 + (athleticism-50)*10` | −400/−250/0/600/900 | +700/0/−300 |
| Midrange | `2500 + (midrange-50)*26` | 100/200/150/0/−300 | −300/0/100 |
| Three | `3600 + (threePoint-50)*24` | 250/350/200/−400/−900 | −400/0/200 |

Each weight has a floor of 200 and the three are normalized to 10000.
`midrange` changes both this selection and midrange conversion.

### Conversion, fouls and free throws

| Decision | Base | Modifiers | Clamp |
|----------|------|-----------|-------|
| Make | 5300 inside, 4000 midrange, 3300 three | +`(zoneRating-50)*40` +`(IQ-50)*8` +`(teamAvgPassing-50)*4` +`(athleticism-50)*6` inside only −`(defender interior/perimeter-50)*30` | 700..9000 |
| Shooting foul on a miss | 800 | +`(athleticism-50)*4` +`(IQ-50)*2` +`(insideScoring-50)*2` +`(50-defenderIQ)*3` | 200..2400 |
| And-one on a make | 160 | +`(athleticism-50)*3` +`(insideScoring-50)*3` −`(defenderInterior-50)*2` | 30..800 |
| Free throw | 6000 | +`(freeThrow-50)*65` | 1500..9800 |
| Assist on a make | 5400 | +`(teamAvgPassing-50)*12` +`(teamAvgIQ-50)*8` | 1500..9000 |
| Block on a miss | 520 two-point, 220 three | +`(defenderInterior-50)*8` +`(defenderAthleticism-50)*5` −`(shooterInsideScoring-50)*4` −`(shooterIQ-50)*2` | 50..2200 |
| Turnover per action | 1050 | −`(teamAvgBallHandling-50)*7` −`(teamAvgPassing-50)*3` −`(teamAvgIQ-50)*3` +`(oppAvgPerimeterDefense-50)*5` +`(oppAvgAthleticism-50)*2` + phase 250/100/0 | 150..2500 |
| Steal share of turnovers | 4800 | +`(oppAvgPerimeterDefense-50)*14` +`(oppAvgAthleticism-50)*6` −`(handlerBallHandling-50)*6` −`(handlerPassing-50)*3` | 1500..8500 |
| Offensive foul | 420 | −`(teamAvgIQ-50)*3` +`(oppAvgIQ-50)*2` +`(teamAvgAthleticism-50)*2` | 100..1000 |
| Non-shooting defensive foul | 1000 | +`(50-oppAvgIQ)*5` +`(teamAvgAthleticism-50)*4` +`(teamAvgIQ-50)*2` | 300..2200 |
| Offensive-rebound share | 2700 | +`(offReboundStrength - defReboundStrength)*12`, strength = `avgRebounding*2 + avgAthleticism`; + zone 100/0/150 | 800..4500 |

No path returns 0 or 10000 for a shot: misses and makes are always possible.
Defender assignment is positional (PG defends PG … C defends C), which is a
documented M002 simplification.

## Attribute effects

| Attribute | Effect |
|-----------|--------|
| `insideScoring` | inside zone weight, inside conversion, and-one pressure, block resistance |
| `midrange` | midrange zone weight and conversion |
| `threePoint` | three zone weight and conversion |
| `freeThrow` | free-throw make probability |
| `passing` | turnover probability, steal share, assist probability, assisted-shot quality |
| `ballHandling` | usage weight, ballhandler weight, turnover probability, steal share |
| `perimeterDefense` | perimeter conversion resistance, turnover pressure, steal weighting |
| `interiorDefense` | inside conversion resistance, block probability and weighting, and-one resistance |
| `rebounding` | team offensive-rebound share and rebounder weighting |
| `athleticism` | inside conversion/selection, turnover pressure, blocks, steals, rebounds |
| `basketballIQ` | turnover probability, offensive fouls, conversion, assists, block resistance |
| `stamina` | **unused** until M003 (verified by test) |

## Aggregate sensitivity probes (development diagnostics)

400 paired seeds × 50 draws per arm, same matchup, only the listed rating changes.
Not AC09: no bootstrap CI, no Holm correction, no realism claim.

| Probe | Mean paired difference |
|-------|------------------------|
| `threePoint` +20 → PG 3PT% | +0.0771 |
| `insideScoring` +20 → PG rim FG% | +0.0776 |
| `midrange` +20 → PG midrange share | +0.0414 |
| `freeThrow` +20 → C FT% | +0.1310 |
| `rebounding` +20 → C rebound share | +0.0095 (weak) |
| `perimeterDefense` +20 (team) → opponent 3PT% | −0.0649 |
| `interiorDefense` +20 (team) → block rate | +0.0083 (weak) |
| `ballHandling` +20 (team) → TOV per action | −0.0163 |
| `passing` +20 (team) → assisted FGM share | +0.0194 |
| `athleticism` +20 (team) → offensive-rebound share | +0.0234 |
| `basketballIQ` +20 (team) → TOV per action | −0.0076 |

## Limitations and risks

- Coefficients are provisional and uncalibrated; T014/T015 own statistical
  acceptance and owner review.
- Turnover probability uses team averages while attribution is per player;
  single-player security changes are diluted. A +20 `ballHandling` on the
  primary handler alone is not expected to be statistically detectable in a
  small game sample.
- `TurnoverAction.kind == TurnoverKind.nonSteal` maps to
  `TurnoverReason.nonSteal` (event schema v2) under
  `amendment-001-nonsteal-turnover.md`.
- Defender assignment is strictly positional; no switching, help defence or
  double teams.
- Rebound weighting and block weighting produce deliberately modest per-player
  shifts (see weak probes); the aggregate paths are the contract.
- No home-court advantage, no fatigue, no substitutions, no foul-outs (M002
  scope).
- One-second clock granularity and A1 overshoot classification remain owned by
  the later orchestrator; this model never clamps a planned duration.
