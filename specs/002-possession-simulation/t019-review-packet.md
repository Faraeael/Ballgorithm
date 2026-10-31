# T019 Human Review Packet — M002 Gameplay Evidence

> **Date:** 2026-10-31
> **Model:** `gameSimulationVersion` **4**, `gameRulesVersion` 2, `gameActionDurationModelVersion` 2
> **Source evidence:** `specs/002-possession-simulation/amendment-004-heldout/v4-heldout-raw.json` (commit `6097ea4`), 1,120 fresh held-out games, seeds 10001–10600, league fixture seed 20261028
> **Purpose:** compact material for T019 human statistical/gameplay review.
> **No new simulation was run to produce this packet.** Every number below is read from the committed artifact.

---

## 1. Selection rule (fixed before looking at any game)

Games are ordered by `slot` ascending. The packet takes:

1. **P1 — median game:** first game whose `combinedPoints` equals the arm median (**214**).
2. **P2 — lowest combined points:** minimum `combinedPoints`, ties by lowest `slot`.
3. **P3 — highest combined points:** maximum `combinedPoints`, ties by lowest `slot`.
4. **P4 — most shot-clock violations:** maximum `shotClockTov`, ties by lowest `slot`.
5. **P5 — most offensive fouls:** maximum `offensiveFoulTov`, ties by lowest `slot`.
6. **P6 — most overtimes:** maximum `overtimes`, ties by lowest `slot`.

This rule cannot favour the model: it forces the lowest- and highest-scoring games, the two worst turnover tails and the longest game into view. Reproduce with:

```bash
cd E:/ballgorithm-dev
python - <<'EOF'
import json, statistics as st
rows = sorted(json.load(open("specs/002-possession-simulation/amendment-004-heldout/v4-heldout-raw.json"))["rows"],
              key=lambda r: r["slot"])
print("median combinedPoints:", st.median([r["combinedPoints"] for r in rows]))
print(min(rows, key=lambda r: (r["combinedPoints"], r["slot"]))["slot"])      # P2
print(min(rows, key=lambda r: (-r["combinedPoints"], r["slot"]))["slot"])     # P3
print(min(rows, key=lambda r: (-r["shotClockTov"], r["slot"]))["slot"])       # P4
print(min(rows, key=lambda r: (-r["offensiveFoulTov"], r["slot"]))["slot"])   # P5
print(min(rows, key=lambda r: (-r["overtimes"], r["slot"]))["slot"])          # P6
EOF
```

## 2. Arm context (what "typical" means here)

| Metric (per game unless noted) | mean | p05 | p50 | p95 | max |
|---|---|---|---|---|---|
| Combined points | 214.96 | 184.9 | 214.0 | 248.0 | 293 |
| Total turnovers | 35.66 | 27 | 36 | 45 | 55 |
| Shot-clock violations | 4.17 | 1 | 4 | 8 | 13 |
| Offensive-foul turnovers | 4.43 | 1 | 4 | 8 | 13 |
| Personal fouls | 40.28 | 31 | 40 | 50 | 63 |
| Field-goal attempts | 184.01 | 169 | 184 | 199 | 230 |
| Steal turnovers | 13.22 | 8 | 13 | 19 | 25 |

Arm totals: 566 home wins / 554 away wins of 1,120; 0 ties; 18 games reached overtime (max 2 OT); offensive fouls **2.214 per team-game**; shot-clock violations **4.171 per game**.

## 3. Selected games

### P1 — median scoring game (214 combined)
`slot 68`, `seed 10340`, **team-3 92 – 122 team-1**, 4 periods, no OT

| | FGM–FGA | 3PM–3PA | FTM–FTA | REB (O+D) | TOV | PF | OF | SC |
|---|---|---|---|---|---|---|---|---|
| team-3 (home) | 35–93 | 13–42 | 9–11 | 49 | 20 | 20 | | |
| team-1 (away) | 49–91 | 16–35 | 8–9 | 53 | 16 | 18 | | |
| game totals | 84–184 | 29–77 | 17–20 | 102 | 36 | 38 | 9 | 5 |

Turnover mix: 10 steals, 12 non-steal, 9 offensive fouls, 5 shot-clock.

### P2 — lowest-scoring game
`slot 771`, `seed 10051`, **team-4 70 – 75 team-6**, 4 periods, no OT

| | FGM–FGA | 3PM–3PA | FTM–FTA | REB | TOV | PF |
|---|---|---|---|---|---|---|
| team-4 (home) | 30–90 | 8–35 | 2–5 | 61 | 27 | 17 |
| team-6 (away) | 27–81 | 12–37 | 9–18 | 58 | 28 | 14 |
| game totals | 57–171 | 20–72 | 11–23 | 119 | **55** | 31 |

Turnover mix: **22 steals, 22 non-steal**, 6 offensive fouls, 5 shot-clock. Both teams below 76 points with 55 total turnovers and 44 steal turnovers — this is the arm's worst turnover tail.

### P3 — highest-scoring game
`slot 455`, `seed 10559`, **team-2 141 – 152 team-7**, 4 periods, no OT

| | FGM–FGA | 3PM–3PA | FTM–FTA | REB | TOV | PF |
|---|---|---|---|---|---|---|
| team-2 (home) | 52–96 | 17–40 | 20–27 | 47 | 19 | **29** |
| team-7 (away) | 55–97 | 20–39 | 22–36 | 47 | 14 | **27** |
| game totals | 107–193 | 37–79 | 42–63 | 94 | 33 | **56** |

Turnover mix: 9 steals, 18 non-steal, 5 offensive fouls, 1 shot-clock. 293 combined points and 56 personal fouls are arm maxima; 63 free-throw attempts is well above the p95 but below the arm maximum of 89 (eFG 0.6503, 99.7th percentile) — a legitimate extreme, not a clamp artefact.

### P4 — most shot-clock violations
`slot 55`, `seed 10359`, **team-1 118 – 114 team-3**, 4 periods, no OT

| | FGM–FGA | 3PM–3PA | FTM–FTA | REB | TOV | PF |
|---|---|---|---|---|---|---|
| team-1 (home) | 48–97 | 18–46 | 4–7 | 59 | 20 | 17 |
| team-3 (away) | 42–90 | 22–44 | 8–10 | 42 | 19 | 20 |
| game totals | 90–187 | 40–90 | 12–17 | 101 | 39 | 37 |

Turnover mix: 9 steals, 9 non-steal, 8 offensive fouls, **13 shot-clock**. 13 violations is the arm maximum (p95 = 8, mean 4.17); 90 three-point attempts is also a tail.

### P5 — most offensive fouls
`slot 117`, `seed 10453`, **team-4 121 – 99 team-1**, 4 periods, no OT

| | FGM–FGA | 3PM–3PA | FTM–FTA | REB | TOV | PF |
|---|---|---|---|---|---|---|
| team-4 (home) | 46–89 | 16–40 | 13–19 | 48 | 22 | 26 |
| team-1 (away) | 35–78 | 15–33 | 14–22 | 47 | **31** | 23 |
| game totals | 81–167 | 31–73 | 27–41 | 95 | 53 | 49 |

Turnover mix: 15 steals, 17 non-steal, **13 offensive fouls**, 8 shot-clock. 13 offensive-foul turnovers is the arm maximum (mean 4.43) — the worst case the model can produce under v4.

### P6 — longest game (double overtime)
`slot 153`, `seed 10585`, **team-5 128 – 129 team-1**, **6 periods, 2 OT**

| | FGM–FGA | 3PM–3PA | FTM–FTA | REB | TOV | PF |
|---|---|---|---|---|---|---|
| team-5 (home) | 52–110 | 18–40 | 6–12 | 67 | 26 | 19 |
| team-1 (away) | 47–114 | 23–56 | 12–20 | 62 | 22 | 22 |
| game totals | 99–224 | 41–96 | 18–32 | 129 | 48 | 41 |

Turnover mix: 17 steals, 21 non-steal, 3 offensive fouls, 7 shot-clock. 224 FGA over 6 periods is consistent with extra time rather than anomalous pacing; the 1-point margin after 2 OT is a genuine double-overtime outcome.

## 4. Overtime behaviour in the arm

- 18 of 1,120 games (1.6%) reached overtime; maximum 2 OT, no game reached the 10-OT cap and none triggered the 11th-OT typed failure.
- Recorded `periods` across the arm: 4, 5 and 6 only.
- Scores are strictly unequal in all 1,120 games — no regulation or overtime game ended tied, consistent with the AC04 tie→OT transition behaving as specified.

## 5. Statistically unusual outcomes (flag for human judgement)

| Outcome | Value | Arm reference | Note |
|---|---|---|---|
| P2 combined points 145 | 55 turnovers, 44 steal turnovers | mean 35.66 TOV, p95 45 | Lowest-scoring game is also the turnover maximum: scoring suppression here is turnover-driven, not shot-quality-driven |
| P3 combined points 293, 56 PF, 42–63 FT | arm max for points and PF; 63 FTA vs arm max 89 | mean 40.28 PF | Highest-scoring game is foul- and free-throw-driven, with eFG 0.6503 |
| P4 13 shot-clock violations | arm max (p95 = 8) | mean 4.17 | Tail case of the known structural expiry interaction; **not** evidence of a clamp defect by itself |
| P5 13 offensive-foul turnovers | arm max (p95 = 8) | mean 4.43 total per game | Worst case for the Amendment 004 calibration; still bounded |
| P6 2 OT, 224 FGA | arm max | p95 199 FGA | Extra-time inflation, expected |
| eFG extremes across packet | **0.3918** (P2, 0.2nd percentile) to **0.6503** (P3, 99.7th percentile) | arm eFG 0.5230 | eFG spread within one league is very wide — worth human review |

None of these were repaired or excluded. They are the tails the selection rule was designed to surface.

## 6. What cannot be judged from this packet

1. **Player-level plausibility** — no committed artifact stores per-player game lines (points, minutes, usage, fouls per player). Judging whether individual players behave credibly requires an authorized extraction or instrumented run. **UNAVAILABLE here.**
2. **Possession-level flow** — no committed play-by-play. Whether sequences read like basketball (transition vs half-court rhythm, foul-and-bonus sequences, and-one ordering in context) cannot be assessed from aggregates.
3. **Defensive scheme realism** — the model has no tactics/rotations; defensive behaviour is positional and statistical only.
4. **Human eye test on rendering** — box scores and aggregates say nothing about how the game *looks* in the app.
5. **League-wide generalization** — one league fixture, eight rosters; no cross-league claim is supportable.
6. **NBA equivalence** — the packet contains no NBA normalisation; comparisons to real basketball statistics require an explicitly stated denominator per metric and are not inferred here.

## 7. Explicitly superseded evidence (do not use for T019 judgement)

- `t015-game-sample.csv` — simulation **v2** (rules 1, duration model 1). Rich home/away team box scores exist there, but it predates Amendments 003 and 004 and does not describe v4 behaviour.
- `t016-benchmark-*-1000-games-*.json` — runtime/memory only; no basketball content.
