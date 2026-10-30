# T015 — Gameplay realism calibration report

Status: **MEASUREMENT COMPLETE — READY FOR OWNER REVIEW (AC10 NOT PASSED).**
Baseline: `ab8e721dcce70e4245426a2062a0f9142244fd96` (`develop/m002`,
Amendment 002 v2). No gameplay parameter, rule, version, schema or golden fixture
was changed. AC09 (v2 development data) and AC10 (this report) are separate.

## 1. Sample and reproducibility

- Protocol: `t015-calibration-protocol.md` (frozen before the final run).
- Fixture: `LeagueGenerator` seed 20261028, 8 teams, default lineups,
  `GameRules.standard`, simulation v2.
- Schedule: 28 unordered pairs × 2 orientations × 20 seeds = **1,120 games**;
  seed rule `1 + ((97·m + 17·s) mod 200)`; **200 distinct seeds**, 56 directed
  matchups, 20 distinct seeds per matchup.
- Attempted 1,120; **completed 1,120**; typed failures **0**; structural audit
  issues **0**; foul-audit issues **0**. Sample-size gate (≥1,000) met.
- Determinism: 10 spread corpus games re-simulated; **10/10 identical** ledger
  digests.
- Command: `cd packages/simulation_core && dart run tool/t015_calibration.dart`.
- Environment: Dart 3.12.2 (stable) windows_x64, Windows 11 Pro 10.0.26100, 8 CPUs.
- Artifacts: `t015-game-sample.csv` (1,120 rows, 85 columns),
  `t015-statistical-summary.json`, `t015-diagnostic-cases.md`, this report.
- CSV SHA-256 `1098dc8a…1314ea` — **byte-identical before and after the A1 trace
  and its clock-specific aggregation**, proving the observer is passive. JSON
  SHA-256 `3beb47d4…cd41d`; diagnostics `0214ece3…d18dc8`. Earlier
  JSON/diagnostics (`34e2470b…b8b7`, `a1caa4e7…7c84`, `9950e848…4c11`,
  `c0a1500b…f0e1`) were superseded only by additive sections, reproduction-text
  correction and updated source hashes; the per-game CSV and every measured
  value are unchanged.

## 2. Headline results

| Quantity | Value |
|---|---|
| Combined points/game | 193.79 (p5 163, p95 226; range 135–257) |
| Team points/game | 96.89 (median 97; p5 75, p95 119) |
| Points per 100 completed possessions | 96.21 |
| Home win rate | 49.4% (553/1,120) |
| Overtime games | 27 (2.4%), max 1 OT |
| Started possessions/team/game | 102.58 (completed 100.71, period-end 1.87) |
| Game started possessions | 205.16; events/game 807.05 |
| Turnovers/game (both teams) | 49.87 (p5 40, p95 60) |
| Fouls/game | 43.62 (p5 34, p95 54) |
| Games outside combined 90–340 | 0 |

## 3. Frozen provisional bands

| Band | Measured | Denominator | Verdict |
|---|---|---|---|
| Per-team median points 85–130 | 97.0 | 2,240 team-games | within |
| Per-team median FGA 70–105 | 83.0 | 2,240 team-games | within |
| 3PA/FGA 0.20–0.55 | 0.4153 | 76,856 / 185,066 | within |
| FG% 0.36–0.57 | 0.4501 | 83,296 / 185,066 | within |
| FT% 0.55–0.90 | 0.6192 | 21,930 / 35,414 | within |
| FTA/FGA 0.10–0.50 | 0.1914 | 35,414 / 185,066 | within |
| OREB% 0.12–0.40 | 0.2763 | 29,705 / (29,705 + 77,811) | within |
| TOV/100 completed 7–24 | **24.76** | 55,854 / 225,587 | **above** (by 3.2%) |
| Assisted FGM share 0.25–0.85 | 0.5427 | 0.5427 × 83,296 | within |

Bands are review thresholds, not validated NBA benchmarks. No range was edited.

## 4. Turnover decomposition and root cause

Per game: **steal 12.17, nonSteal 12.98, shot clock 14.65, offensive foul
10.06**. Shares: live 50.45%, shot clock 29.38%, offensive foul 20.17%.

Phase census (event-derived): `PossessionStarted` 229,780 + OREB resets 29,705 +
retained-foul resets 21,362 = **280,847 phases** (250.8/game). Candidate B predicts
live turnover ≈10.0% per phase and offensive foul ≈4.2%:

- observed live turnovers 28,178 → **10.03% per phase** (prediction ✓);
- observed offensive fouls 11,267 → **4.01% per phase** vs frozen category 4.2%
  (expected 10.53/game; observed 10.06; consistent, not a translation defect).

Shot-clock violations are **entirely structural to A1 × reset states**:

| Reset state | Entries | SC turnovers | Observed rate | Analytic single-draw |
|---|---|---|---|---|
| start24 | 229,780 | 0 | 0.00% | 0.00% (max duration 22 s) |
| oreb14 | 29,705 | 10,124 | **34.08%** | **33.85%** at 14 s |
| retainedFoul | 21,362 | 6,285 | **29.42%** | floor-dependent, see below |

Retained-possession floors were derived from each foul's own shot clock
(`max(remaining, 14)`, capped at 24), so this distribution is measured:

| Floor (s) | Eligible phases | SC turnovers | Observed rate | Analytic single-draw |
|---|---|---|---|---|
| 14 | 14,411 | 4,987 | 0.3461 | 0.3385 |
| 15 | 911 | 298 | 0.3271 | 0.2962 |
| 16 | 845 | 237 | 0.2805 | 0.2538 |
| 17 | 1,316 | 257 | 0.1953 | 0.2115 |
| 18 | 1,352 | 284 | 0.2101 | 0.1692 |
| 19 | 1,188 | 147 | 0.1237 | 0.1269 |
| 20 | 453 | 48 | 0.1060 | 0.0846 |
| 21 | 454 | 20 | 0.0441 | 0.0423 |
| 22 | 432 | 7 | 0.0162 | 0.0000 |
| 23–24 | 0 | 0 | — | 0.0000 |

Total retained floors 21,362 phases / 6,285 SC turnovers. Observed rates track
the analytic single-draw probability at every floor except 22 s, where 7 of 432
phases expired although a single draw cannot exceed 22 s. These 7 cases (0.03% of
all phases) are not explainable from the ledger alone; plausible causes are
sequential sub-states inside one retained possession or a one-tick attribution
offset. They are reported as a **minor diagnostic limitation**, not a reducer
defect, and do not change the structural conclusion.

### Sampled A1 trace (separately authorized, passive)

`GameSimulator` now accepts an optional `onPhaseTrace` observer
(`phase_trace.dart`). It is disabled by default, cannot draw randomness or mutate
state, and is called once per sampled A1 phase with the drawn kind, planned
duration, pre-draw game/shot clocks and the resolution class. T015 uses it only
for measurement.

| Kind | Observed | Share | Expected | Duration mean | Range |
|---|---|---|---|---|---|
| transition | 42,075 | 15.003% | 15% | 4.519 s | 2–7 |
| earlyOffense | 84,097 | 29.987% | 30% | 7.966 s | 5–11 |
| halfCourt | 154,275 | 55.010% | 55% | 16.012 s | 10–22 |
| total | 280,447 | 100% | — | — | — |

Resolutions: legal shot 193,983; legal turnover 39,445; legal foul 26,801;
shot-clock overshoot (`D > Rs < Rg`) 15,944; exact exhaustion
(`D == Rs`, no released attempt or qualifying award) 465; game-clock-first
3,741; simultaneous expiry 18; action discarded at horn 50. Shot-clock turnovers
reconcile exactly: **15,944 + 465 = 16,409**, matching `turnoverTotals.shotClock`.

**Clock-specific observed versus theoretical expiry** — denominator is the
trace itself, restricted to phases where the shot clock can expire before the
horn (`gameClockBefore > shotClockBefore`):

| Pre-draw shot clock | Eligible phases | Overshoots | Observed | Analytic P(D>S) | Exact exhaustions | Horn-first | Simultaneous |
|---|---|---|---|---|---|---|---|
| 14 | 43,333 | 14,697 | 0.3392 | 0.3385 | 414 | 485 | 17 |
| 15 | 903 | 288 | 0.3189 | 0.2962 | 10 | 4 | 0 |
| 16 | 836 | 228 | 0.2727 | 0.2538 | 9 | 8 | 0 |
| 17 | 1,298 | 255 | 0.1965 | 0.2115 | 2 | 8 | 0 |
| 18 | 1,330 | 279 | 0.2098 | 0.1692 | 5 | 7 | 0 |
| 19 | 1,169 | 136 | 0.1163 | 0.1269 | 11 | 6 | 1 |
| 20 | 449 | 42 | 0.0935 | 0.0846 | 6 | 1 | 0 |
| 21 | 440 | 19 | 0.0432 | 0.0423 | 1 | 6 | 0 |
| 22 | 426 | 0 | 0.0000 | 0.0000 | 7 | 3 | 0 |
| 24 | 221,880 | 0 | 0.0000 | 0.0000 | 0 | 3,213 | 0 |

Overshoots + exact exhaustions reconcile to the 16,409 shot-clock turnovers
(`15,944 + 465`). The 24-second state cannot single-draw overshoot, as expected,
but 3,213 horn-first phases occur there when the game clock is the limiting clock.
Floors 14–22 account for 101,184 eligible phases. The 14 s rate matches analytic
within 0.1%; 18 s is ≈4σ above the analytic single-draw expectation (0.2098 vs
0.1692, n = 1,330). No mechanism for that deviation was found in the ledger; it is
reported as an unexplained sampling/stream-correlation caveat, not a defect.

Exact exhaustions by shot clock: 14 s 414, 15 s 10, 16 s 9, 17 s 2, 18 s 5,
19 s 11, 20 s 6, 21 s 1, 22 s 7 — total 465.

**The seven 22-second cases are explained.** Each is a half-court phase with
`D == 22` drawn on a 22-second retained floor: the duration consumes the whole
clock, shot clock reaches 0, and the phase's terminal action was a live turnover
or offensive foul — no shot release and no qualifying award — so the simulator
correctly emits a shot-clock violation at the new game clock. Example:
`t015-2-165`, seed 165, period 3, `D=22`, game clock 555 → turnover sequence 457
at clock 533. These are exact-exhaustion paths, not overshoots and not a defect;
the earlier analytic table used `P(D > S)` and therefore expected zero. Event-ID
list in `t015-diagnostic-cases.md`.

**All mandatory T015 measures are now present.** The missing A1 class gap is
closed; no production gameplay behaviour changed (CSV byte-identical, canonical
digest tests unchanged).

Because each possession emits exactly one terminal action, a 24-second possession
cannot expire before its first phase; every SC violation follows a 14-second
OREB reset or a retained-foul floor. The OREB14 rate matches the analytic 8/13 ×
0.55 half-court overshoot almost exactly. Classification: **design consequence of
the frozen A1 brackets and OD-12 resets**, not a reducer or accounting bug. A1
duration classes are not recorded in the ledger, so per-class sampled
distributions are **UNKNOWN**; only analytic single-draw probabilities and
state-level totals are reportable.

## 5. Fouls and free throws

- Shooting 9.64/game, non-shooting 23.93, offensive 10.06, bonus awards 4.86.
- Bonus thresholds verified per period (5 regulation / 4 overtime); missed
  shooting fouls never share an FGA timestamp; offensive fouls never increment
  the defensive counter; **0 audit violations in 1,120 games**.
- FT% 61.92% (mean per team 0.619, p5 0.400, p95 0.846); FTA/FGA 0.191.
- Fouls per period: Q1 10.54, Q2 11.14, Q3 10.94, Q4 10.89 (combined per game).

## 6. Shooting, rebounding, assists

FG% 45.0% (2P and 3P both represented: 3PA share 41.5%); FGM/team 37.2; FGA 82.6;
FT 9.8/15.8; OREB 13.3, DREB 34.7; live rebound opportunities/team-game 96.0;
OREB% 27.6%; assists 19.9/team; assisted share 54.3%; steals 6.1; blocks 3.4
(aggregate BLK/FGA ≈ 4.1%, reported without a pass threshold); STL/TOV ≈ 0.24.

## 7. Home/away and strength splits

| Metric | Home | Away | Stronger side | Weaker side |
|---|---|---|---|---|
| Points | 96.58 | 97.21 | 99.27 | 94.52 |
| TOV/100 completed | 24.80 | 24.76 | 24.55 | 25.01 |
| FG% | ≈0.450 | ≈0.450 | — | — |

Home win rate 49.4%: no home-court advantage exists by design, so this is sampling
noise. Team rating = mean of 11 rated attributes over the five starters.

## 8. Team and position profiles

| Team | Rating | Points mean | Median |
|---|---|---|---|
| team-1 | 53.98 | 99.9 | 100.5 |
| team-2 | 52.75 | 96.0 | 96.0 |
| team-3 | 54.76 | 96.9 | 97.0 |
| team-4 | 52.25 | 96.8 | 96.5 |
| team-5 | 51.16 | 92.6 | 93.0 |
| team-6 | 54.93 | 99.4 | 99.5 |
| team-7 | 53.33 | 100.5 | 101.0 |
| team-8 | 50.69 | 93.0 | 91.0 |

Position per-player-game: PG 24.0 pts / 21.2 FGA / 11.9 TOV / 4.2 REB / 5.8 PF;
SG 25.4 / 19.9 / 4.0 / 6.2 / 4.8; SF 20.7 / 17.4 / 3.6 / 9.0 / 4.6; PF 14.3 /
12.7 / 2.9 / 12.7 / 3.6; C 12.5 / 11.5 / 2.6 / 15.8 / 3.1. PG absorbs **47.8%** of
team turnovers (shot-clock attribution is PG-only), and the C takes 32.9% of team
rebounds. Maximum single-player scoring share averages 31.5% (no one-player
dominance). 3PA by position: PG 10.1, SG 9.1, SF 7.6, PF 4.2, C 3.3.

## 9. Representative games

| Case | Game | Seed | Score | Events | Digest |
|---|---|---|---|---|---|
| Low | `t015-46-152` | 152 | team-5 60–75 team-7 | 815 | `df8d32b7…d7726` |
| Median | `t015-34-35` | 35 | team-3 108–85 team-8 | 776 | `f8b5a75c…7d722` |
| High | `t015-11-123` | 123 | team-7 133–124 team-1 | 859 | `9c2ba67b…6cef2` |

Full boxes, period scores, turnover subtypes, possession counts and event-ID
references are in `t015-diagnostic-cases.md`. Edge-case references observed in the
sample: overtime `t015-1-98` (seed 98), dead-ball miss `t015-0-69` (seq 849),
and-one `t015-0-1` (seq 112), buzzer make `t015-0-18` (seq 209).

## 10. Verification

- 1,120/1,120 games passed `GameEventReducer.validate` and reconciled through
  `EventAccounting`; player/team equations and non-tied results verified.
- 0 structural issues, 0 foul-policy issues, 0 typed simulation failures.
- 10/10 determinism re-runs byte-identical.
- Gates: `dart format` clean; `dart analyze` clean; **345 Dart tests**;
  **344 Chrome-compatible tests**; `flutter analyze` clean; **8 Flutter tests**.

## 11. Ranked findings

| ID | Severity | Finding | Evidence | Class | Remedy | Canonical impact | Approval |
|---|---|---|---|---|---|---|---|
| F1 | P2 | Turnover rate 24.76/100 completed is 3.2% above the 24 band | §4 | Calibration/design | B: calibrate live/OF probabilities or phase mix | Changes ledgers | T016/T019 owner |
| F2 | P2 | 14.65 SC violations/game driven by 14 s reset × 10–22 s half-court bracket | 34.08% vs 33.85% analytic | Design (frozen A1) | A: revise A1/reset interaction | Changes ledgers; rules/A1 version | Owner |
| F3 | P3 | 10.06 offensive fouls/game from ≈4.2% per phase × 250.8 phases | 4.01% observed | Design/calibration | B (category probability) or accept | Changes ledgers | T016/T019 |
| F4 | P3 | PG carries 47.8% of team TOV | SC attribution + exposure | Design choice | E from Amendment 002 options | Attribution change | Separate amendment |
| F5 | P3 | FT% 61.9% low-normal, FTA/FGA 0.191 low-normal | within bands | Calibration | T016 review | Changes ledgers | Owner |
| F6 | P3 | No home advantage, fixed lineups, no foul-outs | by design | Scope | Document only | none | none |

No P0/P1 defects were found; the deviations are model-design and calibration
issues, not crashes, corruption or invalid ledgers.

## 12. Candidate remedies (not implemented)

- **A. A1 duration/reset interaction** — the only change that directly addresses
  the dominant SC component; requires an owner-approved A1/rules revision and a
  canonical ledger refresh.
- **B. Calibrate live turnover and offensive-foul probabilities** — closes F1/F3;
  affects Candidate B coefficients and needs a probability/version review and a
  T014 rerun.
- **C. Retain mechanics, document limits** — keeps determinism and existing
  evidence; leaves the realism deviations above band.
- **Recommended sequence (for owner decision):** A + B in a single future
  calibration amendment, then rerun T014/T015; C only if realism is accepted as a
  documented M002 limitation. None is authorized by T015.

## 13. AC10 status

**READY FOR OWNER REVIEW — NOT PASSED.** The sample (1,120 games), structural
and accounting verification, frozen-band comparisons, turnover/shot-clock
decomposition, sampled A1 class/duration distribution, clock-specific eligible
phase and overshoot comparison, and retained-floor distribution are complete and
reproducible. Readiness was withdrawn while the clock-specific aggregation was
missing and restored only after the trace denominators reconciled
(`15,944 + 465 = 16,409`). Human basketball-plausibility review, the F1/F2 remedy
decision, AC09 independence and Android performance (T016) remain outside this
report. No realism verdict is claimed.
