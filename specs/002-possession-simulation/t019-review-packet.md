# T019 — Owner Review Packet: Human Basketball Evidence for M002

> **Date:** 2026-10-31
> **Model:** `gameSimulationVersion` **4**, `gameRulesVersion` **2**, `gameActionDurationModelVersion` **2**, `gameEventSchemaVersion` **2**, `gameFingerprintVersion` **2**
> **Evidence source:** `amendment-004-heldout/v4-heldout-raw.json` (1,120 fresh held-out games, seeds 10001–10600, league fixture seed 20261028), commit `93808eaa6582dfd8c7ab562830cba893d8f6c661`
> **Reproduction:** `t019-evidence/t019-games.json` and `t019-evidence/t019-reproduction-metadata.md` (six games re-executed once each; **0 aggregate mismatches**)
> **Purpose:** give the owner real basketball content to judge. **This packet prefills no decision, signs off no criterion, and closes no milestone.**

---

## 0. How to read this packet

Six games were re-executed from the committed held-out record to produce player-level and period-level detail that the aggregate artifacts do not store. For each game the tool rebuilt the exact historical input, simulated it once, and compared 60 recorded aggregates plus 4 recorded strings (including `inputFingerprint`) — **all six matched exactly**. These are therefore the same games the frozen gates were computed on, not new or selected-favourable games.

The selection rule was fixed in advance (T018, `t019-review-packet.md` §1) and forces the extremes into view: median scoring game, lowest scoring game, highest scoring game, most shot-clock violations, most offensive fouls, longest game. **Nothing was replaced because it looked bad.**

| Tag | Rule | Slot | Seed | Matchup | Orientation | Home – Away | Result |
|---|---|---|---|---|---|---|---|
| P1 | median combined points (214) | 68 | 10340 | 3 | 1 | team-3 – team-1 | 92–122 |
| P2 | lowest combined points | 771 | 10051 | 38 | 0 | team-4 – team-6 | 70–75 |
| P3 | highest combined points | 455 | 10559 | 22 | 0 | team-2 – team-7 | 141–152 |
| P4 | most shot-clock violations | 55 | 10359 | 2 | 0 | team-1 – team-3 | 118–114 |
| P5 | most offensive fouls | 117 | 10453 | 5 | 1 | team-4 – team-1 | 121–99 |
| P6 | most overtimes | 153 | 10585 | 7 | 1 | team-5 – team-1 | 128–129 |

Arm reference for calibration of "typical": 1,120 games, mean 214.96 combined points (p05 184.9, p95 248.0, max 293), mean 35.66 turnovers (p95 45), mean 4.17 shot-clock violations (p95 8), mean 4.43 offensive-foul turnovers (p95 8), mean 40.28 personal fouls (p95 50), eFG 0.523, FT/FGA 0.196, 566 home wins, 18 overtime games (max 2 OT).

### Model limits that shape every table below

- **Minutes are NOT MODELED.** Each team fields exactly one fixed five-player lineup for the whole game. There are no substitutions, no bench, no fatigue rotation and no positional shifts, so no player "plays 34 minutes" — every listed player is on the floor for the entire game. Per-player totals are shares of team production, not per-minute rates.
- **No possession-level play-by-play is stored**, so shot quality, spacing and sequence-level plausibility cannot be judged from this packet.
- **Defense is positional and statistical only** (no tactics, no schemes, no help rotations).


---

## 1. P1 — Median scoring game (slot 68, seed 10340): team-3 92 – 122 team-1

| Team | PTS | FG | 3P | FT | REB (O/D) | AST | STL | BLK | TOV | PF |
|---|---|---|---|---|---|---|---|---|---|---|
| team-3 (home) | 92 | 35/93 | 13/42 | 9/11 | 49 (15/34) | 12 | 2 | 2 | 20 | 20 |
| team-1 (away) | 122 | 49/91 | 16/35 | 8/9 | 53 (9/44) | 34 | 8 | 3 | 16 | 18 |
| **game** | 214 | 84/184 | 29/77 | 17/20 | 102 (24/78) | 46 | 10 | 5 | 36 | 38 |

| Team | P1 | P2 | P3 | P4 | Total |
|---|---|---|---|---|---|
| team-3 | 25 | 27 | 18 | 22 | 92 |
| team-1 | 23 | 29 | 25 | 45 | 122 |

**Turnovers by cause**

| Team | Steal | Non-steal | Offensive foul | Shot clock | Total |
|---|---|---|---|---|---|
| team-3 | 8 | 5 | 5 | 2 | 20 |
| team-1 | 2 | 7 | 4 | 3 | 16 |

**Shot-clock violations by continuation context**

| Context | Phases | Violations | Violation rate |
|---|---|---|---|
| Fresh (24 s clock) | 209 | 0 | 0.00% |
| Offensive-rebound reset | 24 | 1 | 4.17% |
| Retained after foul (any clock) | 19 | 4 | 21.05% |
| Retained after foul at 14 s | 12 | 4 | 33.33% |

**Player box score**

| Player | Pos | PTS | FG | 3P | FT | ORB | DRB | REB | AST | STL | BLK | TOV | PF |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Jonas Cortez (`player-1-1`) | SG | 21 | 9/18 | 3/8 | 0/0 | 0 | 6 | 6 | 7 | 2 | 0 | 3 | 4 |
| Jalen Bellamy (`player-1-2`) | SF | 24 | 11/20 | 2/5 | 0/0 | 1 | 6 | 7 | 6 | 2 | 1 | 3 | 3 |
| Elias Vasquez (`player-1-3`) | PG | 46 | 16/28 | 10/16 | 4/5 | 4 | 2 | 6 | 8 | 3 | 0 | 4 | 4 |
| Ravi Ibarra (`player-1-4`) | PF | 8 | 4/11 | 0/4 | 0/0 | 3 | 18 | 21 | 5 | 0 | 0 | 1 | 3 |
| Elias Kovacs (`player-1-8`) | C | 23 | 9/14 | 1/2 | 4/4 | 1 | 12 | 13 | 8 | 1 | 2 | 5 | 4 |
| Pavel Marchetti (`player-3-1`) | SF | 22 | 9/19 | 4/7 | 0/0 | 2 | 5 | 7 | 2 | 0 | 0 | 4 | 2 |
| Yusuf Ravensworth (`player-3-2`) | PG | 23 | 7/19 | 5/12 | 4/5 | 3 | 6 | 9 | 2 | 0 | 1 | 6 | 9 |
| Fabricio Nakamura (`player-3-3`) | C | 8 | 3/13 | 0/5 | 2/2 | 4 | 14 | 18 | 2 | 2 | 0 | 0 | 2 |
| Alonso Ferrante (`player-3-5`) | SG | 16 | 6/23 | 2/13 | 2/2 | 3 | 4 | 7 | 4 | 0 | 1 | 5 | 4 |
| Elias Eastwick (`player-3-7`) | PF | 23 | 10/19 | 2/5 | 1/2 | 3 | 5 | 8 | 2 | 0 | 0 | 5 | 3 |

_Game events: 808; action phases: 243; overtime: 0._

---

## 2. P2 — Lowest scoring game (slot 771, seed 10051): team-4 70 – 75 team-6

| Team | PTS | FG | 3P | FT | REB (O/D) | AST | STL | BLK | TOV | PF |
|---|---|---|---|---|---|---|---|---|---|---|
| team-4 (home) | 70 | 30/90 | 8/35 | 2/5 | 61 (16/45) | 18 | 12 | 4 | 27 | 17 |
| team-6 (away) | 75 | 27/81 | 12/37 | 9/18 | 58 (13/45) | 14 | 10 | 3 | 28 | 14 |
| **game** | 145 | 57/171 | 20/72 | 11/23 | 119 (29/90) | 32 | 22 | 7 | 55 | 31 |

| Team | P1 | P2 | P3 | P4 | Total |
|---|---|---|---|---|---|
| team-4 | 20 | 21 | 10 | 19 | 70 |
| team-6 | 20 | 23 | 15 | 17 | 75 |

**Turnovers by cause**

| Team | Steal | Non-steal | Offensive foul | Shot clock | Total |
|---|---|---|---|---|---|
| team-4 | 10 | 12 | 2 | 3 | 27 |
| team-6 | 12 | 10 | 4 | 2 | 28 |

**Shot-clock violations by continuation context**

| Context | Phases | Violations | Violation rate |
|---|---|---|---|
| Fresh (24 s clock) | 211 | 0 | 0.00% |
| Offensive-rebound reset | 29 | 3 | 10.34% |
| Retained after foul (any clock) | 15 | 2 | 13.33% |
| Retained after foul at 14 s | 10 | 2 | 20.00% |

**Player box score**

| Player | Pos | PTS | FG | 3P | FT | ORB | DRB | REB | AST | STL | BLK | TOV | PF |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Milo Delacroix (`player-4-1`) | SG | 23 | 10/26 | 3/12 | 0/0 | 4 | 7 | 11 | 2 | 2 | 0 | 5 | 5 |
| Gideon Larkspur (`player-4-2`) | C | 6 | 3/9 | 0/1 | 0/0 | 5 | 18 | 23 | 2 | 4 | 2 | 2 | 2 |
| Milo Jansen (`player-4-3`) | SF | 17 | 7/19 | 3/10 | 0/0 | 3 | 4 | 7 | 0 | 3 | 0 | 4 | 2 |
| Andrei Rasmussen (`player-4-5`) | PF | 6 | 2/14 | 0/4 | 2/5 | 3 | 14 | 17 | 5 | 2 | 1 | 6 | 3 |
| Dante Fairweather (`player-4-7`) | PG | 18 | 8/22 | 2/8 | 0/0 | 1 | 2 | 3 | 9 | 1 | 1 | 10 | 5 |
| Alonso Kovacs (`player-6-1`) | PF | 9 | 3/10 | 0/3 | 3/6 | 5 | 7 | 12 | 3 | 1 | 2 | 3 | 3 |
| Caleb Fairweather (`player-6-2`) | SG | 23 | 7/21 | 4/10 | 5/10 | 1 | 6 | 7 | 2 | 3 | 0 | 2 | 2 |
| Dante Lindqvist (`player-6-4`) | PG | 11 | 4/15 | 2/10 | 1/2 | 0 | 5 | 5 | 5 | 1 | 1 | 9 | 5 |
| Jonas Rasmussen (`player-6-5`) | C | 12 | 5/19 | 2/6 | 0/0 | 5 | 21 | 26 | 3 | 1 | 0 | 9 | 0 |
| Oren Sandoval (`player-6-6`) | SF | 20 | 8/16 | 4/8 | 0/0 | 2 | 6 | 8 | 1 | 4 | 0 | 5 | 4 |

_Game events: 831; action phases: 246._

---

## 3. P3 — Highest scoring game (slot 455, seed 10559): team-2 141 – 152 team-7

| Team | PTS | FG | 3P | FT | REB (O/D) | AST | STL | BLK | TOV | PF |
|---|---|---|---|---|---|---|---|---|---|---|
| team-2 (home) | 141 | 52/96 | 17/40 | 20/27 | 47 (13/34) | 31 | 4 | 2 | 19 | 29 |
| team-7 (away) | 152 | 55/97 | 20/39 | 22/36 | 47 (13/34) | 28 | 5 | 1 | 14 | 27 |
| **game** | 293 | 107/193 | 37/79 | 42/63 | 94 (26/68) | 59 | 9 | 3 | 33 | 56 |

| Team | P1 | P2 | P3 | P4 | Total |
|---|---|---|---|---|---|
| team-2 | 32 | 42 | 35 | 32 | 141 |
| team-7 | 36 | 42 | 39 | 35 | 152 |

**Turnovers by cause**

| Team | Steal | Non-steal | Offensive foul | Shot clock | Total |
|---|---|---|---|---|---|
| team-2 | 5 | 10 | 3 | 1 | 19 |
| team-7 | 4 | 8 | 2 | 0 | 14 |

**Shot-clock violations by continuation context**

| Context | Phases | Violations | Violation rate |
|---|---|---|---|
| Fresh (24 s clock) | 232 | 0 | 0.00% |
| Offensive-rebound reset | 26 | 0 | 0.00% |
| Retained after foul (any clock) | 23 | 1 | 4.35% |
| Retained after foul at 14 s | 13 | 1 | 7.69% |

**Player box score**

| Player | Pos | PTS | FG | 3P | FT | ORB | DRB | REB | AST | STL | BLK | TOV | PF |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Rafael Calloway (`player-2-1`) | SF | 30 | 11/20 | 6/13 | 2/2 | 1 | 5 | 6 | 8 | 1 | 0 | 4 | 4 |
| Kasimir Valdez (`player-2-2`) | PG | 40 | 14/23 | 6/10 | 6/8 | 1 | 2 | 3 | 9 | 0 | 0 | 6 | 7 |
| Malik Sinclair (`player-2-4`) | SG | 24 | 9/22 | 3/10 | 3/5 | 1 | 9 | 10 | 4 | 1 | 0 | 4 | 10 |
| Emil Lindqvist (`player-2-5`) | C | 32 | 12/17 | 1/2 | 7/10 | 3 | 9 | 12 | 5 | 2 | 1 | 1 | 5 |
| Felix Ravensworth (`player-2-9`) | PF | 15 | 6/14 | 1/5 | 2/2 | 7 | 9 | 16 | 5 | 0 | 1 | 4 | 3 |
| Quentin Cortez (`player-7-1`) | SF | 36 | 14/23 | 8/12 | 0/0 | 4 | 7 | 11 | 5 | 0 | 0 | 4 | 2 |
| Emeka Halloran (`player-7-2`) | C | 28 | 10/14 | 2/4 | 6/10 | 6 | 10 | 16 | 6 | 0 | 0 | 2 | 5 |
| Rafael Ibarra (`player-7-3`) | SG | 45 | 17/29 | 3/9 | 8/14 | 0 | 2 | 2 | 7 | 4 | 1 | 2 | 7 |
| Elias Gallardo (`player-7-4`) | PG | 28 | 9/22 | 5/11 | 5/7 | 0 | 2 | 2 | 8 | 1 | 0 | 3 | 11 |
| Kasimir Dunmore (`player-7-8`) | PF | 15 | 5/9 | 2/3 | 3/5 | 3 | 13 | 16 | 2 | 0 | 0 | 3 | 2 |

_Game events: 913; action phases: 276._

---

## 4. P4 — Most shot-clock violations (slot 55, seed 10359): team-1 118 – 114 team-3

| Team | PTS | FG | 3P | FT | REB (O/D) | AST | STL | BLK | TOV | PF |
|---|---|---|---|---|---|---|---|---|---|---|
| team-1 (home) | 118 | 48/97 | 18/46 | 4/7 | 59 (19/40) | 21 | 5 | 2 | 20 | 17 |
| team-3 (away) | 114 | 42/90 | 22/44 | 8/10 | 42 (10/32) | 16 | 4 | 4 | 19 | 20 |
| **game** | 232 | 90/187 | 40/90 | 12/17 | 101 (29/72) | 37 | 9 | 6 | 39 | 37 |

| Team | P1 | P2 | P3 | P4 | Total |
|---|---|---|---|---|---|
| team-1 | 30 | 33 | 23 | 32 | 118 |
| team-3 | 25 | 27 | 33 | 29 | 114 |

**Turnovers by cause**

| Team | Steal | Non-steal | Offensive foul | Shot clock | Total |
|---|---|---|---|---|---|
| team-1 | 4 | 4 | 4 | 8 | 20 |
| team-3 | 5 | 5 | 4 | 5 | 19 |

**Shot-clock violations by continuation context**

| Context | Phases | Violations | Violation rate |
|---|---|---|---|
| Fresh (24 s clock) | 208 | 0 | 0.00% |
| Offensive-rebound reset | 29 | 7 | 24.14% |
| Retained after foul (any clock) | 21 | 6 | 28.57% |
| Retained after foul at 14 s | 13 | 6 | 46.15% |

**Player box score**

| Player | Pos | PTS | FG | 3P | FT | ORB | DRB | REB | AST | STL | BLK | TOV | PF |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Jonas Cortez (`player-1-1`) | SG | 41 | 17/29 | 6/15 | 1/1 | 3 | 3 | 6 | 2 | 1 | 0 | 2 | 2 |
| Jalen Bellamy (`player-1-2`) | SF | 30 | 13/22 | 4/7 | 0/0 | 3 | 2 | 5 | 2 | 2 | 1 | 3 | 6 |
| Elias Vasquez (`player-1-3`) | PG | 15 | 5/14 | 3/10 | 2/2 | 2 | 5 | 7 | 6 | 0 | 0 | 11 | 4 |
| Ravi Ibarra (`player-1-4`) | PF | 18 | 7/13 | 4/9 | 0/2 | 4 | 16 | 20 | 7 | 1 | 1 | 3 | 4 |
| Elias Kovacs (`player-1-8`) | C | 14 | 6/19 | 1/5 | 1/2 | 7 | 14 | 21 | 4 | 1 | 0 | 1 | 1 |
| Pavel Marchetti (`player-3-1`) | SF | 29 | 11/17 | 7/8 | 0/0 | 3 | 7 | 10 | 5 | 1 | 2 | 3 | 2 |
| Yusuf Ravensworth (`player-3-2`) | PG | 15 | 4/9 | 4/8 | 3/4 | 1 | 2 | 3 | 1 | 2 | 0 | 8 | 6 |
| Fabricio Nakamura (`player-3-3`) | C | 15 | 6/17 | 3/7 | 0/0 | 2 | 11 | 13 | 2 | 1 | 2 | 1 | 3 |
| Alonso Ferrante (`player-3-5`) | SG | 32 | 10/22 | 7/13 | 5/6 | 0 | 4 | 4 | 3 | 0 | 0 | 3 | 5 |
| Elias Eastwick (`player-3-7`) | PF | 23 | 11/25 | 1/8 | 0/0 | 4 | 8 | 12 | 5 | 0 | 0 | 4 | 4 |

_Game events: 807; action phases: 242._

---

## 5. P5 — Most offensive fouls (slot 117, seed 10453): team-4 121 – 99 team-1

| Team | PTS | FG | 3P | FT | REB (O/D) | AST | STL | BLK | TOV | PF |
|---|---|---|---|---|---|---|---|---|---|---|
| team-4 (home) | 121 | 46/89 | 16/40 | 13/19 | 48 (11/37) | 22 | 8 | 4 | 22 | 26 |
| team-1 (away) | 99 | 35/78 | 15/33 | 14/22 | 47 (11/36) | 17 | 7 | 1 | 31 | 23 |
| **game** | 220 | 81/167 | 31/73 | 27/41 | 95 (22/73) | 39 | 15 | 5 | 53 | 49 |

| Team | P1 | P2 | P3 | P4 | Total |
|---|---|---|---|---|---|
| team-4 | 30 | 29 | 27 | 35 | 121 |
| team-1 | 28 | 21 | 36 | 14 | 99 |

**Turnovers by cause**

| Team | Steal | Non-steal | Offensive foul | Shot clock | Total |
|---|---|---|---|---|---|
| team-4 | 7 | 4 | 6 | 5 | 22 |
| team-1 | 8 | 13 | 7 | 3 | 31 |

**Shot-clock violations by continuation context**

| Context | Phases | Violations | Violation rate |
|---|---|---|---|
| Fresh (24 s clock) | 220 | 0 | 0.00% |
| Offensive-rebound reset | 22 | 4 | 18.18% |
| Retained after foul (any clock) | 18 | 4 | 22.22% |
| Retained after foul at 14 s | 15 | 4 | 26.67% |

**Player box score**

| Player | Pos | PTS | FG | 3P | FT | ORB | DRB | REB | AST | STL | BLK | TOV | PF |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Jonas Cortez (`player-1-1`) | SG | 23 | 7/15 | 4/7 | 5/8 | 1 | 2 | 3 | 6 | 2 | 0 | 2 | 2 |
| Jalen Bellamy (`player-1-2`) | SF | 17 | 7/16 | 2/6 | 1/2 | 1 | 9 | 10 | 3 | 1 | 0 | 7 | 3 |
| Elias Vasquez (`player-1-3`) | PG | 33 | 12/28 | 7/16 | 2/3 | 1 | 3 | 4 | 4 | 1 | 0 | 12 | 3 |
| Ravi Ibarra (`player-1-4`) | PF | 16 | 4/9 | 2/3 | 6/9 | 3 | 9 | 12 | 3 | 2 | 0 | 8 | 6 |
| Elias Kovacs (`player-1-8`) | C | 10 | 5/10 | 0/1 | 0/0 | 5 | 13 | 18 | 1 | 1 | 1 | 2 | 9 |
| Milo Delacroix (`player-4-1`) | SG | 33 | 13/23 | 4/11 | 3/5 | 2 | 7 | 9 | 2 | 1 | 1 | 5 | 7 |
| Gideon Larkspur (`player-4-2`) | C | 10 | 3/8 | 0/3 | 4/5 | 2 | 13 | 15 | 7 | 2 | 3 | 2 | 1 |
| Milo Jansen (`player-4-3`) | SF | 24 | 9/17 | 4/10 | 2/3 | 1 | 3 | 4 | 2 | 2 | 0 | 3 | 6 |
| Andrei Rasmussen (`player-4-5`) | PF | 29 | 12/19 | 3/6 | 2/4 | 4 | 12 | 16 | 5 | 1 | 0 | 3 | 9 |
| Dante Fairweather (`player-4-7`) | PG | 25 | 9/22 | 5/10 | 2/2 | 2 | 2 | 4 | 6 | 2 | 0 | 9 | 3 |

_Game events: 855; action phases: 249._

---

## 6. P6 — Double overtime (slot 153, seed 10585): team-5 128 – 129 team-1

| Team | PTS | FG | 3P | FT | REB (O/D) | AST | STL | BLK | TOV | PF |
|---|---|---|---|---|---|---|---|---|---|---|
| team-5 (home) | 128 | 52/110 | 18/40 | 6/12 | 67 (18/49) | 28 | 7 | 3 | 26 | 19 |
| team-1 (away) | 129 | 47/114 | 23/56 | 12/20 | 62 (22/40) | 21 | 10 | 5 | 22 | 22 |
| **game** | 257 | 99/224 | 41/96 | 18/32 | 129 (40/89) | 49 | 17 | 8 | 48 | 41 |

| Team | P1 | P2 | P3 | P4 | P5 (OT) | P6 (OT) | Total |
|---|---|---|---|---|---|---|---|
| team-5 | 26 | 39 | 20 | 16 | 13 | 14 | 128 |
| team-1 | 15 | 25 | 36 | 25 | 13 | 15 | 129 |

**Turnovers by cause**

| Team | Steal | Non-steal | Offensive foul | Shot clock | Total |
|---|---|---|---|---|---|
| team-5 | 10 | 10 | 1 | 5 | 26 |
| team-1 | 7 | 11 | 2 | 2 | 22 |

**Shot-clock violations by continuation context**

| Context | Phases | Violations | Violation rate |
|---|---|---|---|
| Fresh (24 s clock) | 248 | 0 | 0.00% |
| Offensive-rebound reset | 40 | 5 | 12.50% |
| Retained after foul (any clock) | 24 | 2 | 8.33% |
| Retained after foul at 14 s | 16 | 2 | 12.50% |

**Player box score**

| Player | Pos | PTS | FG | 3P | FT | ORB | DRB | REB | AST | STL | BLK | TOV | PF |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Jonas Cortez (`player-1-1`) | SG | 32 | 12/24 | 7/13 | 1/3 | 2 | 4 | 6 | 6 | 3 | 1 | 1 | 6 |
| Jalen Bellamy (`player-1-2`) | SF | 28 | 11/24 | 5/12 | 1/2 | 5 | 5 | 10 | 7 | 3 | 1 | 4 | 4 |
| Elias Vasquez (`player-1-3`) | PG | 25 | 9/32 | 4/17 | 3/3 | 1 | 9 | 10 | 5 | 2 | 0 | 9 | 3 |
| Ravi Ibarra (`player-1-4`) | PF | 21 | 6/11 | 3/4 | 6/10 | 6 | 13 | 19 | 2 | 2 | 1 | 4 | 6 |
| Elias Kovacs (`player-1-8`) | C | 23 | 9/23 | 4/10 | 1/2 | 8 | 9 | 17 | 1 | 0 | 2 | 4 | 3 |
| Pavel Ferrante (`player-5-1`) | PF | 26 | 12/20 | 2/5 | 0/4 | 6 | 14 | 20 | 4 | 0 | 1 | 0 | 7 |
| Ravi Kovacs (`player-5-2`) | PG | 34 | 13/29 | 8/13 | 0/0 | 1 | 1 | 2 | 3 | 3 | 0 | 11 | 4 |
| Jalen Grimsby (`player-5-6`) | SG | 28 | 10/25 | 5/8 | 3/4 | 0 | 7 | 7 | 13 | 1 | 2 | 7 | 3 |
| Teodor Bellamy (`player-5-7`) | C | 23 | 10/17 | 0/5 | 3/4 | 7 | 16 | 23 | 5 | 1 | 0 | 4 | 1 |
| Quentin Kovacs (`player-5-9`) | SF | 17 | 7/19 | 3/9 | 0/0 | 4 | 11 | 15 | 3 | 2 | 0 | 4 | 4 |

_Game events: 988; action phases: 302; overtimes: 2._

---

## 7. Ratings versus performance (all six games)

These tables put the drawn ratings beside what the game actually produced. **A single game does not establish that a rating has its expected statistical effect** — one game is one sample of a stochastic process, and per-game box scores have wide variance. Attribute sensitivity is a *paired-cohort* question, answered by AC09 evidence (§9), never by reading one box score.

### P1
| Player | Pos | INS | MID | 3PT | FT | PAS | HAN | PER | INT | REB | ATH | IQ | PTS | TOV | STL |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Jonas Cortez | SG | 56 | 74 | 69 | 52 | 64 | 48 | 58 | 46 | 28 | 67 | 44 | 21 | 3 | 2 |
| Jalen Bellamy | SF | 61 | 70 | 63 | 60 | 48 | 55 | 51 | 57 | 46 | 56 | 42 | 24 | 3 | 2 |
| Elias Vasquez | PG | 38 | 51 | 68 | 74 | 53 | 72 | 48 | 49 | 37 | 58 | 62 | 46 | 4 | 3 |
| Ravi Ibarra | PF | 61 | 58 | 61 | 46 | 62 | 27 | 37 | 67 | 60 | 50 | 58 | 8 | 1 | 0 |
| Elias Kovacs | C | 63 | 58 | 37 | 40 | 58 | 29 | 39 | 74 | 55 | 52 | 52 | 23 | 5 | 1 |
| Pavel Marchetti | SF | 50 | 51 | 71 | 55 | 64 | 44 | 52 | 62 | 59 | 63 | 54 | 22 | 4 | 0 |
| Yusuf Ravensworth | PG | 31 | 44 | 56 | 55 | 65 | 73 | 53 | 42 | 38 | 66 | 56 | 23 | 6 | 0 |
| Fabricio Nakamura | C | 55 | 60 | 24 | 33 | 51 | 51 | 50 | 64 | 68 | 52 | 39 | 8 | 0 | 2 |
| Alonso Ferrante | SG | 55 | 70 | 65 | 60 | 57 | 59 | 62 | 65 | 51 | 66 | 54 | 16 | 5 | 0 |
| Elias Eastwick | PF | 64 | 60 | 32 | 47 | 42 | 52 | 62 | 65 | 62 | 49 | 62 | 23 | 5 | 0 |

### P2
| Player | Pos | INS | MID | 3PT | FT | PAS | HAN | PER | INT | REB | ATH | IQ | PTS | TOV | STL |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Milo Delacroix | SG | 50 | 65 | 71 | 48 | 51 | 52 | 39 | 51 | 46 | 49 | 58 | 23 | 5 | 2 |
| Gideon Larkspur | C | 66 | 47 | 27 | 42 | 61 | 32 | 60 | 62 | 55 | 49 | 53 | 6 | 2 | 4 |
| Milo Jansen | SF | 65 | 58 | 54 | 48 | 41 | 71 | 61 | 50 | 60 | 61 | 56 | 17 | 4 | 3 |
| Andrei Rasmussen | PF | 52 | 54 | 34 | 29 | 56 | 47 | 43 | 46 | 52 | 51 | 49 | 6 | 6 | 2 |
| Dante Fairweather | PG | 38 | 49 | 55 | 64 | 57 | 71 | 56 | 54 | 30 | 57 | 71 | 18 | 10 | 1 |
| Alonso Kovacs | PF | 63 | 64 | 27 | 63 | 41 | 44 | 70 | 53 | 57 | 69 | 65 | 9 | 3 | 1 |
| Caleb Fairweather | SG | 47 | 51 | 64 | 63 | 57 | 60 | 39 | 50 | 39 | 55 | 63 | 23 | 2 | 3 |
| Dante Lindqvist | PG | 40 | 52 | 64 | 46 | 86 | 58 | 74 | 51 | 25 | 46 | 51 | 11 | 9 | 1 |
| Jonas Rasmussen | C | 72 | 43 | 27 | 40 | 40 | 16 | 48 | 70 | 87 | 55 | 69 | 12 | 9 | 1 |
| Oren Sandoval | SF | 70 | 59 | 68 | 58 | 59 | 61 | 73 | 52 | 47 | 59 | 51 | 20 | 5 | 4 |

### P3
| Player | Pos | INS | MID | 3PT | FT | PAS | HAN | PER | INT | REB | ATH | IQ | PTS | TOV | STL |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Rafael Calloway | SF | 56 | 58 | 70 | 58 | 62 | 54 | 53 | 57 | 36 | 72 | 49 | 30 | 4 | 1 |
| Kasimir Valdez | PG | 27 | 63 | 39 | 73 | 70 | 63 | 59 | 38 | 42 | 59 | 62 | 40 | 6 | 0 |
| Malik Sinclair | SG | 47 | 52 | 68 | 44 | 65 | 49 | 49 | 45 | 35 | 50 | 64 | 24 | 4 | 1 |
| Emil Lindqvist | C | 72 | 43 | 24 | 39 | 45 | 38 | 48 | 65 | 59 | 56 | 54 | 32 | 1 | 2 |
| Felix Ravensworth | PF | 50 | 49 | 44 | 46 | 61 | 46 | 44 | 67 | 67 | 49 | 47 | 15 | 4 | 0 |
| Quentin Cortez | SF | 64 | 56 | 67 | 49 | 43 | 47 | 54 | 53 | 57 | 56 | 44 | 36 | 4 | 0 |
| Emeka Halloran | C | 58 | 55 | 47 | 43 | 55 | 54 | 52 | 65 | 74 | 45 | 50 | 28 | 2 | 0 |
| Rafael Ibarra | SG | 57 | 57 | 74 | 56 | 58 | 67 | 67 | 44 | 24 | 80 | 57 | 45 | 2 | 4 |
| Elias Gallardo | PG | 29 | 58 | 63 | 59 | 66 | 88 | 45 | 42 | 19 | 58 | 56 | 28 | 3 | 1 |
| Kasimir Dunmore | PF | 56 | 47 | 51 | 38 | 46 | 48 | 31 | 53 | 48 | 58 | 45 | 15 | 3 | 0 |

### P4
| Player | Pos | INS | MID | 3PT | FT | PAS | HAN | PER | INT | REB | ATH | IQ | PTS | TOV | STL |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Jonas Cortez | SG | 56 | 74 | 69 | 52 | 64 | 48 | 58 | 46 | 28 | 67 | 44 | 41 | 2 | 1 |
| Jalen Bellamy | SF | 61 | 70 | 63 | 60 | 48 | 55 | 51 | 57 | 46 | 56 | 42 | 30 | 3 | 2 |
| Elias Vasquez | PG | 38 | 51 | 68 | 74 | 53 | 72 | 48 | 49 | 37 | 58 | 62 | 15 | 11 | 0 |
| Ravi Ibarra | PF | 61 | 58 | 61 | 46 | 62 | 27 | 37 | 67 | 60 | 50 | 58 | 18 | 3 | 1 |
| Elias Kovacs | C | 63 | 58 | 37 | 40 | 58 | 29 | 39 | 74 | 55 | 52 | 52 | 14 | 1 | 1 |
| Pavel Marchetti | SF | 50 | 51 | 71 | 55 | 64 | 44 | 52 | 62 | 59 | 63 | 54 | 29 | 3 | 1 |
| Yusuf Ravensworth | PG | 31 | 44 | 56 | 55 | 65 | 73 | 53 | 42 | 38 | 66 | 56 | 15 | 8 | 2 |
| Fabricio Nakamura | C | 55 | 60 | 24 | 33 | 51 | 51 | 50 | 64 | 68 | 52 | 39 | 15 | 1 | 1 |
| Alonso Ferrante | SG | 55 | 70 | 65 | 60 | 57 | 59 | 62 | 65 | 51 | 66 | 54 | 32 | 3 | 0 |
| Elias Eastwick | PF | 64 | 60 | 32 | 47 | 42 | 52 | 62 | 65 | 62 | 49 | 62 | 23 | 4 | 0 |

### P5
| Player | Pos | INS | MID | 3PT | FT | PAS | HAN | PER | INT | REB | ATH | IQ | PTS | TOV | STL |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Jonas Cortez | SG | 56 | 74 | 69 | 52 | 64 | 48 | 58 | 46 | 28 | 67 | 44 | 23 | 2 | 2 |
| Jalen Bellamy | SF | 61 | 70 | 63 | 60 | 48 | 55 | 51 | 57 | 46 | 56 | 42 | 17 | 7 | 1 |
| Elias Vasquez | PG | 38 | 51 | 68 | 74 | 53 | 72 | 48 | 49 | 37 | 58 | 62 | 33 | 12 | 1 |
| Ravi Ibarra | PF | 61 | 58 | 61 | 46 | 62 | 27 | 37 | 67 | 60 | 50 | 58 | 16 | 8 | 2 |
| Elias Kovacs | C | 63 | 58 | 37 | 40 | 58 | 29 | 39 | 74 | 55 | 52 | 52 | 10 | 2 | 1 |
| Milo Delacroix | SG | 50 | 65 | 71 | 48 | 51 | 52 | 39 | 51 | 46 | 49 | 58 | 33 | 5 | 1 |
| Gideon Larkspur | C | 66 | 47 | 27 | 42 | 61 | 32 | 60 | 62 | 55 | 49 | 53 | 10 | 2 | 2 |
| Milo Jansen | SF | 65 | 58 | 54 | 48 | 41 | 71 | 61 | 50 | 60 | 61 | 56 | 24 | 3 | 2 |
| Andrei Rasmussen | PF | 52 | 54 | 34 | 29 | 56 | 47 | 43 | 46 | 52 | 51 | 49 | 29 | 3 | 1 |
| Dante Fairweather | PG | 38 | 49 | 55 | 64 | 57 | 71 | 56 | 54 | 30 | 57 | 71 | 25 | 9 | 2 |

### P6
| Player | Pos | INS | MID | 3PT | FT | PAS | HAN | PER | INT | REB | ATH | IQ | PTS | TOV | STL |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Jonas Cortez | SG | 56 | 74 | 69 | 52 | 64 | 48 | 58 | 46 | 28 | 67 | 44 | 32 | 1 | 3 |
| Jalen Bellamy | SF | 61 | 70 | 63 | 60 | 48 | 55 | 51 | 57 | 46 | 56 | 42 | 28 | 4 | 3 |
| Elias Vasquez | PG | 38 | 51 | 68 | 74 | 53 | 72 | 48 | 49 | 37 | 58 | 62 | 25 | 9 | 2 |
| Ravi Ibarra | PF | 61 | 58 | 61 | 46 | 62 | 27 | 37 | 67 | 60 | 50 | 58 | 21 | 4 | 2 |
| Elias Kovacs | C | 63 | 58 | 37 | 40 | 58 | 29 | 39 | 74 | 55 | 52 | 52 | 23 | 4 | 0 |
| Pavel Ferrante | PF | 47 | 39 | 44 | 38 | 49 | 49 | 44 | 60 | 62 | 55 | 47 | 26 | 0 | 0 |
| Ravi Kovacs | PG | 33 | 44 | 50 | 55 | 66 | 61 | 56 | 52 | 23 | 53 | 56 | 34 | 11 | 3 |
| Jalen Grimsby | SG | 55 | 46 | 67 | 52 | 46 | 69 | 55 | 31 | 48 | 47 | 40 | 28 | 7 | 1 |
| Teodor Bellamy | C | 77 | 38 | 40 | 50 | 48 | 26 | 50 | 66 | 49 | 52 | 65 | 23 | 4 | 1 |
| Quentin Kovacs | SF | 64 | 56 | 57 | 57 | 50 | 52 | 64 | 61 | 49 | 66 | 38 | 17 | 4 | 2 |

### What these tables show, and what they cannot show

**Consistent with the model's documented weightings:**

- **Ball-handling concentration.** Point guards carry by far the heaviest turnover load in these samples: `player-4-7` (PG, HAN 71) 10 turnovers in P2; `player-6-4` (PG, HAN 58) 9; `player-6-5` (C, HAN **16**) 9. Because the ballhandler weight is `position base + ballHandling×3 + passing + IQ`, a low-handling centre still receives roughly a third of a point guard's weight — so his 9 turnovers are mechanically reachable, not a violation of the weighting. It is, however, an eye-test question whether a HAN-16 centre should handle that often.
- **Assist distribution.** team-1 recorded 34 assists on 49 made field goals in P1, spread as PG 8, C 8, SG 7, SF 6, PF 5 — near-uniform rather than concentrated on the primary handler, because assists are credited to the *passer* of a made shot whose weighting is `passing×3 + IQ×2 + position bonus` with the shooter excluded. Whether that spread is realistic is an eye-test question for the owner.
- **Steal–perimeter-defense relationship.** In P2 the four-steal performances came from `player-6-6` (SF, PER 73, ATH 59) and `player-4-2` (C, PER 60) rather than the highest-PER guards, which is within the documented `perimeterDefense×3 + athleticism×2 + position bonus` draw but shows the position bonus materially matters.
- **Rebounding.** Centres and power forwards dominate defensive rebounds; the interior positions hold the largest rebounding ratings.

**Cannot be judged here:**

- Whether a *specific* rating has the expected marginal effect (needs AC09's paired design).
- Whether shot selection matches a player's strengths at the possession level (no play-by-play stored).
- Whether minutes/usage load is realistic (minutes **NOT MODELED**).

---

## 8. Game-specific anomaly explanations (evidence-based)

### P2 — 70–75, 55 turnovers, 44 steal turnovers (arm TOV mean 35.66, p95 45)

| Question | Answer from the ledger |
|---|---|
| Steals vs other causes | 22 steal turnovers + 22 non-steal + 6 offensive foul + 5 shot-clock = 55 |
| Who generated the steals | team-4 credits 12 steals, team-6 credits 10; `player-4-2` 4, `player-6-6` 4, `player-4-3` 3, `player-6-2` 3, `player-4-1` 2, `player-4-5` 2, `player-6-1` 1, `player-6-4` 1, `player-6-5` 1, `player-4-7` 1 |
| Who committed them | `player-6-5` 5 stolen, `player-4-1` 4, `player-4-7` 3, plus spread; total 22 |
| Concentrated in particular players or phases? | **Players:** yes — the two PGs (`player-4-7`, `player-6-4`) and one centre (`player-6-5`) carry 28 of the 55 total turnovers between them. **Phases:** spread across 246 action phases (2.24 turnovers per 10 action phases; the arm mean is 35.66/244.5 ≈ 1.46, so this game is ~1.5× the typical turnover density), and *zero* fresh-phase shot-clock violations occurred, so the game was not stalled on clock resets. |
| Does it suggest a model weakness? | **No correctness defect.** Every turnover is a typed, sequenced, attributed event; accounting reconciles; `team.TOV == Σ player.TOV` holds. The scoring suppression is turnover-driven, not shot-quality-driven: both teams shot poorly (eFG 0.378 and 0.407) *and* lost the ball a lot. **Realism limitation:** 22 steal turnovers is ~1.7× the arm mean (13.22) and the joint mechanism (many steals → fewer shots → low score) can compound in a way real basketball also shows, but the *magnitude* of the steal share of turnovers (40.0% here vs 37.1% arm-wide) is worth the owner's eye. |

### P3 — 141–152, 56 personal fouls, eFG 0.650

| Question | Answer from the ledger |
|---|---|
| Scoring contributions | team-2: 2×(52−17) + 3×17 + 20 = 141 ✓; team-7: 2×(55−20) + 3×20 + 22 = 152 ✓ — arithmetic explains the score exactly, no hidden points |
| Shooting efficiency | team-2 52/96 (54.2%), team-7 55/97 (56.7%), 3P 37/79 (46.8%), eFG 0.650 (arm 0.523; 99.7th percentile) |
| Free throws and fouls | 63 FTA (arm p95 ≈ 60, arm max 89); 56 personal fouls (arm max 63); FT/FGA 0.326 vs arm 0.196 |
| Is the high score mechanically explainable? | **Yes.** Across the arm, combined points correlate 0.839 with eFG, 0.459 with possessions, 0.141 with FT/FGA. This game is an efficiency outlier on the dominant axis plus an elevated free-throw rate — the two documented scoring paths — not a broken clock or an unbounded loop (913 events, 276 action phases, 0 overtime). |

### P4 — 13 shot-clock violations (arm mean 4.17, p95 8, max 13)

| Question | Answer from the ledger |
|---|---|
| Distribution by possession context | **fresh: 0 violations in 208 phases** · offensive-rebound reset: **7 in 29** (24.1% vs arm 7.41%) · retained-after-foul: **6 violations, all at the 14 s clock** in 13 phases (46.2% vs arm 14.22%) |
| Were documented clock rules violated? | **No.** Fresh phases start at 24 s and the longest A1 bracket is 22 s, so a fresh-phase expiry is structurally impossible — and zero occurred. All 13 violations arise from *short-clock* continuations (14 s reset states), which are exactly where the clock can expire legitimately. The horn and reset precedence tests (AC04) pass. |
| Interpretation | Both short-clock contexts were elevated ~3× *in the same game*. That is one shared cause — long duration draws on 14 s clocks — not two independent anomalies. Arm-wide tail probability for a game this extreme under an independent-process approximation is ≈4×10⁻⁴; one such game in 1,120 is expected. **Plausible statistical outlier with a known structural mechanism**, unchanged from the T015 finding. |

### P5 — 13 offensive-foul turnovers (arm mean 4.43, p95 8, max 13)

| Question | Answer from the ledger |
|---|---|
| Distribution by team | team-4 (home) 6, team-1 (away) 7 — evenly split, so not one team's lineup collapsing |
| Distribution by player | `player-1-4` 3, `player-1-8` 2, `player-4-7` 2, `player-4-5` 2, `player-1-2` 1, `player-1-3` 1, `player-4-1` 1, `player-4-3` 1 — spread across eight players, no single player above 3 |
| Do the fixed 170 bp base and `[100, 1000]` clamp explain the outlier? | **Partly.** The per-game rate here is 13/249 = 5.22% of action phases against an arm rate of 1.77%. The formula `clamp(170 − (offIQ−50)×3 + (defIQ−50)×2 + (offATH−50)×2, 100, 1000)` can lift a specific lineup matchup well above the 170 bp base through the IQ/ATH terms, so a 2–3× game-level elevation is reachable by design. What the clamp does **not** do is bind: with 170 bp base the floor (100 bp) requires a ~+70 bp IQ/ATH swing, and the binding frequency of that floor is **not measured** in this evidence (§11, limitation L5). |
| Verdict | **Plausible statistical outlier.** Tail probability ≈7×10⁻⁴ per game; one occurrence in 1,120 matches expectation. No rules violation: attribution is to the offending player, `team.TOV` reconciles, and the action-phase denominator is verified. |

### P6 — Double overtime, 128–129 (6 periods, 2 OT)

| Question | Answer from the ledger |
|---|---|
| Period scores | P1 26–15, P2 39–25, P3 20–36, P4 16–25, **OT1 13–13, OT2 14–15** |
| Overtime progression | Regulation ended 101–101; each overtime is a full 300 s period; the second overtime ended 1 point apart, and the game terminated with `GameEnded` after 988 events |
| Valid termination | `overtimes = 2 ≤ maxOvertimes 10`; `periodsPlayed = 6 ≤ 4 + 10`; 988 ≤ `maxEvents` 50000; reducer replay and accounting reconciliation both pass |
| Are the OT statistics plausible? | **Yes, with a caveat.** 224 FGA across 6 periods (37.3/period) matches the regulation rate (184 / 4 = 46/period is not directly comparable because overtime pacing differs, but no discontinuity appears). The caveat is that the model has no fatigue, substitutions or foul-out rule, so a 6-period game costs players nothing — a **realism limitation**, explicitly outside frozen M002 scope. |

### Classification of the four investigated games

| Game | True simulation defect | Plausible statistical outlier | Realism limitation |
|---|---|---|---|
| P2 (55 TOV, 70–75) | No | Yes — 40% steal share, arm tail | Ballhandler weighting lets a HAN-16 centre carry heavy turnover load |
| P3 (293 pts, 56 PF) | No | Yes — efficiency tail, arm max | No fatigue from 63 FTA; no foul-out |
| P4 (13 SC) | No | Yes — short-clock tail, shared cause | Known 14 s-reset × 10–22 s bracket interaction (structural, documented since T015) |
| P5 (13 OF) | No | Yes — tail probability ≈7×10⁻⁴ | Clamp-floor binding frequency unmeasured |
| P6 (2 OT) | No | No — 18/1,120 games reach OT | No fatigue/substitutions/foul-out in extra periods |

**No simulation defect was found in any of the six games.** Every aggregate reproduced exactly, every ledger replayed, every accounting identity held, and no boundedness or clock rule was breached.


---

## 9. AC09 attribute sensitivity — original limitation and current v4 evidence

### 9.1 Original limitation (historical, preserved)

The first T014 run (seeds 1–200, simulation v1) did **not** pass AC09: experiment **E4 (`ballHandling`)** came out **INCONCLUSIVE** — mean difference **+0.24594**, 95% bootstrap CI **[−0.09193, +0.58251]**, raw and Holm p = **0.1503**, i.e. the effect ran opposite to the pre-registered direction and was not distinguishable from zero. Every other experiment passed. That result stands unchanged in `t014-sensitivity-report.md` and `t014-statistical-summary.json` and must not be re-scored.

### 9.2 Current v4 attribute-sensitivity evidence

| Generation | Seeds | E1 3PT% | E2 FT% | E3 REB share | E4 TOV/100 | E5 opp eFG | E6 lineups | Verdict |
|---|---|---|---|---|---|---|---|---|
| v1 historical (sim v1) | 1–200 | PASSED | PASSED | PASSED | **INCONCLUSIVE** (+0.246, Holm 0.1503) | PASSED | PASSED | AC09 NOT passed |
| v2 rerun (sim v2) | 1–200 | PASSED | PASSED | PASSED | PASSED (−0.435, CI [−0.766, −0.088], Holm 0.0124) | PASSED | PASSED | 6/6 |
| v4 development (sim v4) | 1–200 | PASSED | PASSED | PASSED | PASSED (−0.830) | PASSED | PASSED | 6/6 |
| v4 fresh held-out (sim v4) | 10001–10200 | PASSED (+0.0737) | PASSED (+0.1062) | PASSED (+0.0133) | PASSED (−0.4537) | PASSED (−0.0633) | PASSED (+28.46) | 6/6, all Holm p = 0.000600 |

All four generations use the frozen T014 protocol (200 paired seeds per experiment, +20 rating delta, 10,000-resample percentile bootstrap seed 20261029, 10,000-permutation sign-flip test seed 424242, Holm across six, 95% CIs excluding zero in the expected direction). The v4 fresh run is recorded in `amendment-004-heldout/t014-v4-fresh-raw.json` and re-verified by recomputation in `verify_heldout.py`.

**Owner-relevant point:** the later passes *describe v2 and v4*; they do not overwrite the v1 E4 finding, which is why AC09 is still `PENDING OWNER REVIEW` rather than PASS.

### 9.3 Why a single game cannot judge a rating

One game gives one box score per player; per-game variance dominates any rating effect. The v4 E4 effect, for example, is **−0.45 turnovers per 100 started possessions** — far smaller than the game-to-game turnover spread visible in this packet (P2 had 55 total turnovers, P6 had 48, P3 had 33). A single box score therefore says essentially nothing about whether `ballHandling` shifts turnover rate; only the paired 200-seed design can. Judge the *qualitative* contents of this packet with your eyes, and judge *rating effects* with §9.2's statistics.

---

## 10. AC10 calibration — original limitation and current v4 evidence

### 10.1 Original limitation (historical, preserved)

The T015 calibration run (1,120 games, simulation **v2**) satisfied **8 of 9** frozen provisional bands. The failing band is preserved exactly as recorded:

| Metric | Value | Frozen band | Verdict |
|---|---|---|---|
| Turnovers per 100 completed possessions | **24.7594** | `[7, 24]` | **above band** |

All other bands were within range: per-team median points 97 `[85,130]`, median FGA 83 `[70,105]`, 3PA share 0.4153 `[0.2,0.55]`, FG% 0.4501 `[0.36,0.57]`, FT% 0.6192 `[0.55,0.9]`, FTA/FGA 0.1914 `[0.1,0.5]`, OREB% 0.2763 `[0.12,0.4]`, assisted-FG share 0.5427 `[0.25,0.85]`. AC10 was and remains **not passed**.

### 10.2 Current v4 calibration evidence (Amendment 004, qualified)

Fresh held-out cohort: 2,240 games (1,120 v3 + 1,120 v4), 600 fresh seeds 10001–10600, all nine frozen Amendment 004 gates verified from raw rows:

| Gate | Metric | Frozen envelope | v4 held-out | 95% CI (DOF-corrected) | Verdict |
|---|---|---|---|---|---|
| G1 | Offensive fouls / team-game | `[1.80, 2.60]` | 2.2143 | `[2.1430, 2.2855]` | PASS |
| G2 | Offensive-foul share of TOV | `[0.100, 0.160]` | 0.1242 | `[0.1205, 0.1279]` | PASS |
| G3 | TOV / 100 completed possessions | `[15.0, 19.5]` | 17.4285 | `[17.2218, 17.6353]` | PASS |
| G4 | Shot-clock violations / game | `[3.0, 5.5]` | 4.1714 | `[4.0387, 4.3042]` | PASS |
| G5 | Completed possessions / team-game | `[100.0, 106.0]` | 102.2929 | `[101.9880, 102.5977]` | PASS |
| G6 | Team median FGA | `[88.0, 95.0]` | 92.0 | `[91.0, 92.0]` (pigeonhole) | PASS |
| G7 | 3PA / FGA | `[0.380, 0.450]` | 0.4134 | `[0.4106, 0.4161]` | PASS |
| G8 | eFG% | `[0.510, 0.540]` | 0.5230 | `[0.5187, 0.5274]` | PASS |
| G9 | T014 E1–E6 (fresh seeds) | all expected sign, Holm p < 0.05 | 6/6 PASSED | Holm p = 0.000600 | PASS |

**D1 qualification (must travel with this table).** The frozen analysis script omitted the per-component small-sample DOF factor required by the pre-registered method, so the original held-out verdict is preserved as **`INCONCLUSIVE — EVIDENCE OR EXECUTION ISSUE`**. The owner then recorded a **conditional procedural exception** (`OWNER-D1-DISPOSITION.md`): `QUALIFIED HELD-OUT EVIDENCE ACCEPTED FOR FURTHER M002 REVIEW — D1 PROCEDURAL EXCEPTION RECORDED`. An independent from-scratch audit later reproduced all 66 estimators within 5.55×10⁻¹⁷, found 0 negative variances, and confirmed no gate verdict or paired-delta conclusion changes under the correction. These gate results are therefore **qualified evidence**, not an unqualified pre-registered pass.

**Realism caution:** G3's 17.4285 turnovers per 100 completed possessions is within the Amendment 004 envelope but remains above NBA-scale turnover rates on a like-for-like definition. Passing a frozen internal envelope is not proof of NBA realism.

---

## 11. Decisions the owner must make

| # | Decision | What would settle it | Status |
|---|---|---|---|
| D-1 | **AC09** — accept attribute-sensitivity evidence? The v1 E4 failure is historical; v2 and v4 (dev + fresh) pass 6/6 | Your judgement that the later generations satisfy the AC09 intent, and that v1 is correctly preserved as a superseded finding | **OPEN** |
| D-2 | **AC10** — accept calibration realism? T015's v2 band breach stands; v4 passes all nine Amendment 004 gates under D1 qualification | Your judgement that v4 evidence + this gameplay packet is enough for M002, and that NBA-level realism is not being claimed | **OPEN** |
| D-3 | **D1** — does the conditional exception continue to apply for acceptance, or is a new pre-registered cohort required? | Your call; the corrected analysis is reproducible but was not outcome-blind | Recorded, re-confirm |
| D-4 | **Gameplay plausibility** — do the six games above read like basketball? Specifically: the HAN-16 centre's turnover load (P2), the near-uniform assist spread (P1), the 40% steal share of turnovers (P2), and the 56-foul / 63-FTA game (P3) | Your eye test; the packet is the evidence | **OPEN** |
| D-5 | **Evidence scope** — accept the declared limitations (single league/8 rosters, Android NOT MEASURED, clamp-floor binding unmeasured, shot-zone split unmeasured, no minutes/fatigue/subs) or authorize further measurement | Your scope call | **OPEN** |

**Nothing above is decided for you.**

---

## 12. Review worksheet (leave blank until you decide)

| AC | Requirement (short) | Evidence location | Owner verdict |
|---|---|---|---|
| AC01 | Headless pure-Dart game | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC02 | Input/version validation | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC02b | Seed identity | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC03 | Determinism/replay | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC04 | Clocks/timing | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC04b | A1 durations | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC05 | Event causality | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC06 | Accounting | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC07 | Vocabulary | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC07b | Ledger boundary | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC07c | Attribution | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC08 | Boundedness | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| **AC09** | Attribute sensitivity | §9 above | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| **AC10** | Calibration realism | §10 above | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC11 | M001 preservation | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC11b | Fingerprints | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC12 | Desktop performance | `t016-performance-report.md` + correction addendum | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| AC13 | Scope | `acceptance-report.md` §2 | ☐ PASS ☐ FAIL ☐ CONDITIONAL |
| Android | Runtime performance | **NOT MEASURED** | ☐ DEFER ☐ AUTHORIZE MEASUREMENT |

**Milestone decision:** ☐ ACCEPT M002 ☐ ACCEPT WITH CONDITIONS ☐ REJECT / REVISE
**Conditions (if any):** ______________________
**Signed / date:** ______________________

This packet does not close T019, does not sign off AC09 or AC10, and does not declare M002 complete.
