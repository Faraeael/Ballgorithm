# Feature 002: Deterministic Possession-Based Basketball Simulation

Status: **FROZEN — READY FOR IMPLEMENTATION AUTHORIZATION**
Baseline: `Faraeael/Ballgorithm` `main` at `a431aeb5a652b134ce40cf442c7d9ffee874fe79` (M001 closed GO).
Frozen: 2026-10-28. Implementation remains **NOT AUTHORIZED**.
Target: pure Dart `packages/simulation_core`; Android remains the eventual primary UI target.

## 1. Outcome

Given two distinct valid teams from a valid M001 `League`, a game seed, an
explicit ruleset and one valid five-player lineup per team, simulate a complete
game as a reproducible, ordered event ledger. Derive final score, period scores,
player/team box scores and a game summary **from those events**. A successful
M002 does not claim professional-level realism; accounting correctness and
directional statistical evidence are separate gates.

## 2. User stories

- **US1 — Headless result:** simulate a match without Flutter, disk or network.
- **US2 — Inspectable game:** later inspect who scored and why every point and
  statistic was credited.
- **US3 — Reproducibility:** same canonical input, versions and seed produce an
  identical canonical ledger on VM and Chrome/JS.
- **US4 — Basketball causality:** relevant ratings influence outcome categories
  in statistically detectable, directionally expected ways in aggregate.
- **US5 — Extensibility:** tactics, rotations, fatigue and play types can be added
  later without replacing the event/accounting contracts.

## 3. In scope

1. Versioned `GameRules`, `GameInput`, `ActiveLineup`, game IDs, game validation
   failures and immutable results.
2. Explicit five-player lineups, one player at each M001 primary position, in
   canonical order PG, SG, SF, PF, C.
3. Integer-second state machine: four 720-second periods, 300-second overtime
   periods, 24-second initial shot clock, OD-12 resets, bounded overtime.
4. Typed event ledger with explicit game/period/possession boundaries, attempts,
   fouls, free throws, rebounds, turnovers and dead-ball terminations.
5. Shooting fouls: missed shot → awarded FTs with no FGA; made and-one → FGA/FGM
   plus one FT; bonus non-shooting fouls → two FTs at the OD-11 thresholds.
6. Rebound rule: every live missed FG or final FT resolves to exactly one
   offensive or defensive rebound; a zero-clock miss resolves as `DeadBallMiss`
   with no rebound.
7. Event-derived box scores with one authoritative accounting path.
8. Basis-point probability model using the existing attributes; `midrange` is
   explicit; `stamina` is reserved for M003.
9. Typed failures for invalid matchup, lineup, rules, illegal transitions and
   simulation bounds; no silent coercion and no unreported winner on failure.
10. Headless invariant, adversarial, reproducibility, cross-platform,
    skill-sensitivity and aggregate calibration tests.

## 4. Explicitly out of scope

- Flutter match screens, play-by-play UI, animation, Flame, sound, networking,
  database or career saves.
- Substitutions, bench minutes, injuries, fatigue, foul-outs and tactics (M003).
  Fixed lineups and no disqualification are documented deviations.
- Flagrant/technical fouls, reviews, timeouts, jump balls, goaltending,
  3-second violations and special late-two-minute rules.
- Player measurements, salaries, tendencies or new persistent attributes.
- Out-of-bounds and team rebounds: every live miss resolves to one player
  rebound; this simplification must appear in acceptance evidence.
- No intrinsic home-court advantage; home/away are identifiers and presentation
  roles only.
- Season simulation, AI GMs, persistence and migrations.

## 5. Normative definitions

- **Game input:** a pre-validated M001 `League`, distinct home/away team IDs,
  ordered active lineups, raw game seed, rules and versions.
- **Normalized seed:** `seed & 0xFFFFFFFF`; `0` maps to `0x9E3779B9`. Q1 starts
  home when normalized seed is even and away when odd. Starting team alternates
  every period, including overtime. Opening possession consumes no PRNG draw.
- **Event:** immutable typed fact with a monotonic integer `sequence` starting at
  1, period, game clock, shot clock where live, and canonical payload. No
  floating-point payloads; probabilities use integer basis points internally.
- **Game boundary:** explicit `GameStarted`, `PeriodStarted`, `PossessionStarted`,
  `PossessionEnded`, `PeriodEnded`, `GameEnded`. No event may follow `GameEnded`.
- **Possession:** one team's control until a turnover, defensive rebound, made
  FG without attached FTs, made final FT, or period end. An and-one FG keeps the
  possession until its FT resolves; an offensive rebound of a missed final FT
  continues possession. A period-ending possession is not a turnover.
- **Field-goal attempt:** 2/3-point attempt counts once in FGA. A blocked shot is
  an FGA. A missed shooting-foul attempt is not an FGA. A made and-one is FGA and
  FGM.
- **Rebound:** exactly one on-court player after an eligible live miss; offensive
  continues the possession, defensive ends it. A zero-clock miss is
  `DeadBallMiss` and invents no rebound.
- **Free throws:** per attempt FTA/FTM. Only the last FT of a group is
  reboundable, and only when clock remains; otherwise `DeadBallMiss`.
- **Turnover attribution:** every turnover belongs to one active offensive
  player; shot-clock violations go to the designated ballhandler (lineup PG by
  default); offensive fouls to the offender. `team.TOV == sum(player.TOV)`.
- **Clock:** integer seconds. The game clock is non-increasing within a period;
  the shot clock may increase only through an enumerated OD-12 reset. Four
  720-second periods; 300-second OTs; 24-second initial shot clock; dead-ball
  processing and FTs consume 0; clocks freeze during dead balls; no negative
  clocks. Live offensive phases consume durations from the owner-approved,
  uncalibrated and versioned A1 model (transition 15% 2–7 s, early 30% 5–11 s,
  half-court 55% 10–22 s), not one delay per emitted event. A planned duration
  beyond the limiting clock is never clamped and never becomes a legal shot:
  shot-clock expiry yields a turnover, game-clock expiry ends the period, and
  simultaneous expiry gives the horn precedence unless a legal shot or
  qualifying shooting foul began before it. A final-tick attempt when one second
  remains is a deliberate shot consuming that second and may release at zero.
- **Last-second shots:** a shot selected and released during the final available
  tick before the logical horn is legal; resolution is recorded at the resulting
  timestamp, including zero. Simultaneous game/shot-clock expiry gives the horn
  precedence unless a valid shot or qualifying shooting foul began before
  expiry. Legal buzzer shots and awarded FTs complete before `PeriodEnded`.
- **Bonus:** team-foul counts reset each period. Regulation: fifth and later
  qualifying defensive team fouls award two FTs for non-shooting fouls.
  Overtime: fourth and later. Defensive shooting fouls count toward team fouls;
  normal offensive fouls do not; and-ones never receive bonus FTs.
- **Shot clock:** 24 after a made basket, defensive rebound or turnover; 14 after
  an offensive rebound of a missed FG or live missed final FT; retained
  possession after a non-bonus defensive non-shooting foul resets to
  `max(remaining, 14)` capped at 24; never above the configured maximum.
- **Bounds:** 10 overtime periods, 50,000 events per game, 64 consecutive
  zero-clock-advancement events at an unchanged timestamp within a period.
  Exceeding a bound raises a typed simulation failure; never a silent winner.
- **Fingerprint:** SHA-256 over versioned ordered UTF-8 JSON containing the full
  M001 league snapshot, selected team IDs, ordered lineup IDs, raw and normalized
  seed, all rules values and version identifiers. No floats. Unrelated roster
  changes alter the fingerprint by design.
- **Determinism contract:** same canonical input, rules/simulation/event-schema
  versions and seed produce identical canonical encodings on VM and Chrome.
  Different versions need not reproduce each other.

## 6. Acceptance criteria

| ID | Criterion | Minimum evidence |
|----|-----------|------------------|
| AC01 | Complete game from M001 teams without Flutter, IO, DB or network | Headless end-to-end test and import audit |
| AC02 | Reject non-distinct teams, foreign/duplicate/mispositioned lineup players, unsupported rules/versions and invalid seeds with typed failures | Explicit failure tests incl. invalid object construction/fuzz |
| AC03 | Identical canonical input + seed + versions produce identical events/results on repeated VM runs; VM and Chrome agree; fingerprint fixture pinned | Pinned ledger/fingerprint fixtures over league/config, lineups, A1 duration rules, versions and normalized seed; VM/Chrome commands; raw-seed alias documented |
| AC04 | Period/shot-clock bounds, four regulation periods, OT until resolved or typed bound failure; buzzer and zero-clock transitions; A1 duration brackets and overshoot classification | Clock-boundary fixtures from `acceptance-matrix.md` |
| AC05 | Causal possession/score/turnover/rebound transitions; no duplicate/orphan rebounds, FTs or possessions | Replay validator plus edge fixtures |
| AC06 | Every point, period total and box-score count derives from the ledger; player/team totals reconcile | Invariant suite on ≥100 seeds (200 recommended) |
| AC07 | 2/3 makes/misses, steals, blocks, assists, shooting/non-shooting/offensive fouls, FTs, OREB/DREB, and-one ordering are representable and tested | Legal fixture per case + illegal-event rejection |
| AC08 | No unbounded loops or invalid probabilities; typed failures at all three OD-14 bounds; no NaN/Infinity/global RNG | Boundary/property/max-events tests |
| AC09 | Pre-registered paired-seed experiments show directionally consistent aggregate effects with uncertainty excluding no-effect; no individual-game guarantee | 200 paired seeds per experiment, 95% bootstrap CI, Holm correction, effect sizes |
| AC10 | ≥1,000 seeded games reported with provisional bands, outlier diagnostics and owner review; no self-certified realism | Machine-readable report and explicit owner sign-off |
| AC11 | M001 PRNG vectors, default league snapshot and all existing tests unchanged; no M001 engine/schema bump; only approved additive package changes | 44 VM core, 43 Chrome-compatible core, 8 Flutter tests; approved `package:crypto` dependency audit |
| AC12 | Headless, deterministic, bounded and measured against the provisional targets | ≤60 s/1,000 games desktop, p95 ≤100 ms/game, ≤128 MiB incremental, environment recorded |
| AC13 | Scope and limitations (fixed lineups, no foul-outs, one-second granularity, no home advantage, rebound simplification) documented | Scope check and risk report |

**Implementation gate:** owner approval of this specification and a separate
implementation authorization (T003). **Completion gate:** AC01–AC13 with owner
approval of AC09–AC10, not merely green tests.

## 7. Design review gates

- RG-01: Event vocabulary, field schemas and replay/reducer semantics.
- RG-02: Clock, dead-ball, bonus and overtime rules.
- RG-03: Fixed-lineup limitation and the future M003 lineup provider interface.
- RG-04: Metric targets and calibration provenance.
- RG-05: Simulator, rules, event-schema and fingerprint versioning.

Detailed resolutions are in `design-decisions.md`; the decision dispositions and
the closed A1/A2 items are in `review-findings.md`. The A1 duration distribution
and A2 `package:crypto` dependency are owner-approved specification decisions.
This specification is frozen for implementation authorization; implementation
remains unauthorized until a separate instruction.
