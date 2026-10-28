# Design Decisions 002 — Proposed resolutions for owner approval

Status: **FROZEN — READY FOR IMPLEMENTATION AUTHORIZATION**
Baseline: `Faraeael/Ballgorithm` `main` at `a431aeb5a652b134ce40cf442c7d9ffee874fe79`.
Frozen: 2026-10-28. Implementation remains **NOT AUTHORIZED**.

These are the proposed M002 decisions assembled from the owner's resolution
instructions. They are **not** independently owner-signed-off until the owner
approves this revised specification. The D-ids below are document decision
proposals; they are distinct from the `RG-xx` review gates in `spec.md` §7 and
from the `OD-xx` decisions.

| ID | Proposal | Reason / trade-off |
|----|----------|--------------------|
| D01 | Typed immutable event ledger; pure replay reducer and derived box scores | Correctness can be proven; later UI/play-by-play reuses the same events |
| D02 | NBA-inspired, configurable four-quarter rules; integer clocks; simple bonus; bounded overtime | Recognizable basketball with an explicit deviation register |
| D03 | Exactly five externally supplied active players per team for the entire game | Prevents M002 expanding into M003 |
| D04 | Reuse `xorshift32-v1` through a new game-local seeded RNG instance | M001 generation sequence and snapshots stay unchanged |
| D05 | `gameSimulationVersion`, `gameRulesVersion` and `gameEventSchemaVersion` are independent of M001 `coreEngineVersion`/`snapshotSchemaVersion` | Game changes never relabel league data |
| D06 | `GameResult` references canonical input identifiers, the event ledger and event-derived box scores | One result path |
| D07 | Probability model uses the existing twelve attributes; no new persistent ratings | Preserves the M001 schema |
| D08 | No wall-clock time or external IO in the core simulation; all loops bounded | Headless tests and mobile feasibility |
| D09 | Calibration evidence is separate from official realism sign-off | Synthetic data cannot earn an unearned "realistic" claim |

## Resolved decisions OD-01…OD-14 (proposed)

### OD-01 — Opening possession

- Normalize the game seed: `seed & 0xFFFFFFFF`; `0` becomes `0x9E3779B9`
  (odd, so the away team starts).
- Q1 starter: even normalized seed → home, odd → away.
- Starting team alternates every subsequent period, including overtime:
  period `n` uses the Q1 starter when `n` is odd and the opponent when `n` is
  even.
- Opening possession consumes **no** gameplay PRNG draw.

### OD-02 — Timing model

- Integer-second ticks; no fractional clocks.
- Four regulation periods of 720 seconds; overtime periods of 300 seconds.
- Initial shot clock 24 seconds; resets per OD-12.
- Every live offensive phase consumes at least one second. Its duration comes
  from the owner-approved, uncalibrated and versioned A1 distribution below,
  subject to the clock-expiry classification. It is not an independent delay
  added to every emitted event.
- Dead-ball processing and free throws consume zero game-clock time; both
  clocks are frozen while the ball is dead.
- The game clock never goes negative and never increases within a period. The
  shot clock never goes negative and never exceeds its configured maximum; it
  may increase only through the enumerated OD-12 resets.
- Last-second shot: an attempt selected and released during the final available
  tick, before the logical horn, is legal. Its resolution is recorded at the
  resulting timestamp, including `0`.
- A shot-clock expiry with no valid released attempt, while game time remains,
  records a shot-clock turnover.
- If game clock and shot clock expire together, the period horn takes
  precedence unless a valid shot or qualifying shooting foul was initiated
  before expiry.
- Any legal buzzer shot and any awarded free-throw sequence complete before
  `PeriodEnded` is emitted.
- **Limitation:** one-second granularity cannot represent sub-second events;
  this is an M002 limitation and must be listed in acceptance evidence.

### OD-03 — Offensive foul

A normal offensive foul:

- charges one personal foul to the offender;
- charges one player turnover to the offender;
- does **not** count as a defensive team foul for the bonus;
- cancels the offensive scoring opportunity;
- creates no field-goal attempt and no points;
- transfers possession.

A normal offensive foul and a counted made basket cannot coexist in the same
action. Flagrant, technical and other special foul exceptions are out of scope.

### OD-04 — Zero-clock free throws

- If a legal shooting foul or bonus award occurs before the horn, the entire
  awarded free-throw sequence is completed even when the game clock reaches
  zero.
- Free throws do not advance game time.
- A missed final free throw at zero produces a `DeadBallMiss` terminal event,
  never a rebound.
- No new live possession begins after the horn.

### OD-05 — Turnover attribution

- Every generated M002 turnover belongs to exactly one active offensive player,
  so `team.TOV == sum(player.TOV)`.
- Shot-clock violations are charged to the designated active ballhandler,
  defaulting to the lineup PG.
- Offensive fouls charge the offending player.
- A steal must link to an opponent turnover and a valid active defender.
- This simplified convention differs from advanced official scorekeeping, which
  can include team-only turnovers. Document it in acceptance evidence.

### OD-06 — Canonical input fingerprint

A matchup is never identified by league ID or raw seed alone. Compute a
versioned canonical fingerprint over:

- the complete M001 league snapshot (`League.toJson` field order);
- selected team IDs;
- ordered active lineup IDs (PG, SG, SF, PF, C);
- raw game seed and normalized PRNG seed;
- every game-rule value;
- simulation, rules, event-schema, PRNG and M001 version identifiers.

The canonical serialization is explicitly ordered UTF-8 JSON containing only
integers, booleans and strings (no floating point). Hash it with SHA-256 and use
the lowercase hex digest. `package:crypto` is **owner-approved (A2,
2026-10-28)** as the SHA-256 implementation: pure Dart, browser-compatible, no
network, no native cryptography, deterministic UTF-8 serialization, identical VM
and Chrome results, and lockfile-pinned at implementation time. It is the first
runtime dependency of `simulation_core` and needs the AC11 dependency exception.
Hashing the whole league means unrelated roster changes alter the fingerprint
even if this game's events would not change; this is recorded as intended
identity semantics.

Pin a fingerprint fixture and compare VM versus Chrome.

### OD-07 — Event schema

- Immutable typed events.
- Explicit `GameStarted`, `PeriodStarted`, `PossessionStarted`,
  `PossessionEnded`, `PeriodEnded`, `GameEnded` events.
- Event IDs are monotonic integers starting at 1; IDs, period numbers, clocks,
  player/team IDs, shot values, free-throw groups and links are canonical and
  deterministic.
- No floating-point values in event payloads. Internally, probabilities use
  integer basis points (`0..10000`) and bounded integer PRNG draws where
  practical.
- Made and-one ordering: `FieldGoalAttempt(made, andOne)` → linked defensive
  `PersonalFoul` → linked `FreeThrowAttempt` → `Rebound` or `DeadBallMiss` if
  the final FT misses. Possession ends only if the final FT is made
  (`madeFinalFreeThrow`), the rebound is defensive, or the miss is a zero-clock
  `DeadBallMiss`; an offensive rebound continues the same possession and starts
  a new phase. `PeriodEnded` follows only when the period is over.
- A missed shooting foul emits the foul and awarded free throws without a
  counted FGA.
- Ordering is enforced by the pure replay reducer; all statistics derive from
  one authoritative accounting path.
- Exact field schemas and illegal transitions are in `plan.md`.

### OD-08 — Performance targets (provisional)

- 1,000 completed games in ≤ 60 s on a documented desktop reference machine
  using optimized Dart execution.
- p95 simulation time ≤ 100 ms/game.
- Incremental memory growth ≤ 128 MiB during the sequential benchmark.
- No unbounded simulation loops.
- Record CPU, OS, Dart version, compilation mode, warmup, sample size, runtime
  distribution and memory method.
- These are provisional acceptance targets, not universal guarantees. If the
  reference environment cannot be established, report measurements and leave
  performance sign-off pending; never fabricate success.
- No Android performance claim without an actual device measurement.

### OD-09 — Attribute usage

- `midrange` is explicitly used for midrange shot selection and conversion.
- Documented influences: `insideScoring`, `midrange`, `threePoint`, `freeThrow`,
  `passing`, `ballHandling`, `perimeterDefense`, `interiorDefense`,
  `rebounding`, `athleticism`, `basketballIQ`.
- `stamina` is reserved for M003 rotations/fatigue and is deliberately unused in
  M002; no fake effect is added.
- The twelve-attribute M001 schema is unchanged.
- Aggregate sensitivity metrics and uncertainty criteria are pre-registered
  before calibration (see `calibration-plan.md`).

### OD-10 — Home advantage

- No intrinsic home-court advantage in M002. Home/away are identifiers and
  presentation roles only.
- Opening possession varies with the seed; calibration reports home/away
  outcomes to detect unintended systematic bias.
- A future simulation-rules version may introduce home advantage.

### OD-11 — Bonus rules

- Team-foul counts reset at the start of every period, including overtime.
- Regulation: the fifth and each subsequent qualifying defensive team foul
  awards two free throws for a non-shooting foul.
- Overtime: the fourth and each subsequent qualifying defensive team foul awards
  two free throws for a non-shooting foul.
- Defensive shooting fouls count toward team-foul totals.
- Normal offensive fouls charge player PF but never count toward the bonus.
- An and-one never receives extra bonus free throws.
- Special late-two-minute rules are omitted; document the simplification.
- Shooting fouls, bonus non-shooting fouls and offensive fouls are distinct,
  separately tested paths.

### OD-12 — Shot-clock resets

- New possession after a made basket: 24 s.
- New possession after a defensive rebound: 24 s.
- New possession after a turnover: 24 s.
- Offensive rebound after a missed FG: 14 s.
- Offensive rebound after a missed final FT (live time only): 14 s.
- Retained possession after a non-bonus defensive non-shooting foul:
  `max(remaining shot clock, 14)` capped at the configured maximum.
- After resolved bonus free throws, apply the normal rebound or
  change-of-possession rule.
- The shot clock never exceeds the configured maximum. No new live possession or
  reset occurs after the period has ended.

### OD-13 — Lineup positions

- Exactly five unique active players, one for each primary position:
  PG, SG, SF, PF, C.
- Every player must belong to the named M001 roster; players cannot appear on
  both lineups.
- Canonical lineup order is PG, SG, SF, PF, C.
- Default selection takes the first eligible player for each position in stable
  roster order.
- No substitutions, fatigue, foul-outs or multi-position assignments in M002.
  These are recorded limitations for M003.

### OD-14 — Simulation bounds

- Maximum 10 overtime periods.
- Maximum 50,000 emitted events per game.
- Maximum 64 consecutive zero-clock-advancement events at an unchanged
  game-clock timestamp within a period.
- Exceeding any limit raises a typed simulation failure; never silently
  terminate or declare a winner.
- Tests must force each bounded failure, and legitimate free-throw/boundary
  sequences must not trip the zero-time guard.

## A1 — Offensive-phase duration (owner-approved 2026-10-28)

### A1 — Approved offensive-phase duration distribution (owner-approved 2026-10-28)

The duration governs a **live offensive phase**, not every emitted event. A
possession may contain multiple offensive phases after offensive rebounds (and
after a non-bonus defensive foul that retains possession). Only the phase's
terminal action advances the game clock; free throws and dead-ball bookkeeping
advance zero seconds.

`gameActionDurationModelVersion = 1` is provisional, uncalibrated and versioned
with `gameRulesVersion`. Changing the weights or brackets requires a rules-version
bump.

| Phase type | Basis points | Share | Duration bracket |
|------------|--------------|-------|------------------|
| Transition | 1500 | 15% | uniform integer 2–7 s |
| Early offense | 3000 | 30% | uniform integer 5–11 s |
| Half-court offense | 5500 | 55% | uniform integer 10–22 s |

Exact draw order per normal offensive phase (two draws before any outcome draw):

1. `typeDraw = rng.nextInt(10000)`: `0..1499` transition, `1500..4499` early,
   `4500..9999` half-court.
2. `offsetDraw = rng.nextInt(count)`, where count is 6, 7 or 13:
   duration = `2 + offsetDraw`, `5 + offsetDraw` or `10 + offsetDraw`.
3. Terminal action and outcome draws follow the probability model's documented
   fixed order: action category, actor, zone, make/miss, foul/and-one, assist,
   block, rebound team, rebound player, free throws. Conditional branches
   document which draws they consume.

A final-tick attempt (see expiry rules) consumes **no** type/duration draws; it
uses the outcome draws directly. Each phase after an offensive rebound or a
retained possession starts a new phase and draws type and duration again.

#### Clock-expiry classification (no silent clamping)

Let `Rg` be game-clock seconds remaining and `Rs` the shot clock at phase start.

| Condition | Resolution |
|-----------|------------|
| `Rg == 0` | Illegal state; period must end. |
| `Rg == 1 && Rs >= 1` | Final-tick attempt: no phase draws; resolve a deliberate shot attempt consuming 1 s, release at 0. Legal under OD-02. Miss → `DeadBallMiss`; shooting foul completes FTs; `PeriodEnded` after resolution. |
| `D <= Rg && D <= Rs` | Phase completes at `D`. If `D == Rg` (and `Rs >= D`), a shot is released at game clock 0 and is legal; resolve before `PeriodEnded`. |
| `D > Rs && Rs < Rg` | Shot clock expires first at game clock `Rg - Rs`; emit shot-clock turnover (OD-05). The planned action is abandoned; it is **not** converted into a shot. |
| `D > Rg && Rg < Rs` | Game clock expires first; period ends at 0 without a terminal action, turnover or rebound. |
| `D > Rg && Rg == Rs` | Horn precedence: period ends at 0. No shot, because no legal release was planned before expiry. |

A shot released exactly at shot-clock zero (`D == Rs`, with game time remaining)
is legal; the violation applies only when no valid attempt was released. Any
shooting or bonus-awarding foul that is the terminal action of a phase initiated
before expiry is resolved at its timestamp, including zero, and its free throws
complete before `PeriodEnded`. A planned duration beyond the limiting clock is
never clamped and never becomes a legal shot. Only the explicit final-tick path, a phase whose `D` equals the remaining
game clock, or a shot at `D == Rs` produces a zero release. Existing precedence
rules (OD-02) still apply to simultaneous expiry when a shot or qualifying
shooting foul was initiated before expiry.

## Probability model contract

Use integer basis points (`0..10000`) and bounded integer draws. Do not assume
twelve attributes uniquely specify NBA-level behavior; define explicit
probabilities, clamps and shot-mix weights, then calibrate.

| Decision | Positive influence | Negative influence | Measure |
|----------|--------------------|--------------------|---------|
| Shooter usage | `insideScoring`, `threePoint`, `ballHandling`, `basketballIQ`, position baseline | opponent pressure | usage share |
| Shot-zone choice | `threePoint` (3PT), `insideScoring`/`athleticism` (rim), `midrange` (midrange) | matchup tendency | 3PA share, interior share |
| Shot success | zone rating (`insideScoring`/`midrange`/`threePoint`), `basketballIQ`, assist quality | assigned defender perimeter/interior defense | eFG%, zone FG% |
| Turnover | opponent `perimeterDefense` | ballhandler `ballHandling`, `passing`, `basketballIQ` | TOV per possession |
| Steal | defender `perimeterDefense`, `athleticism` | ballhandler security | steal-linked TOV share |
| Block | defender `interiorDefense`, `athleticism` | shooter inside skill, IQ | block share of attempts |
| Foul drawn | shooter inside scoring/athleticism | defender discipline proxy using `basketballIQ` | FTA/FGA |
| Rebound | rebounder `rebounding`, `athleticism`, position | opponent rebound weights | OREB% |
| Assist | passer `passing`, IQ; available teammate | isolation selection | assisted-FGM share |
| Free throw | shooter `freeThrow` | none | FT% |

Coefficients and reasoning must be documented; no empirical-data provenance may
be claimed without a checked citation.

## Versioning and compatibility

- M001 `coreEngineVersion = 1.0.0` and `snapshotSchemaVersion = 1` remain
  unchanged.
- M002 adds `gameSimulationVersion = 1`, `gameRulesVersion = 1`,
  `gameEventSchemaVersion = 1`; all are independent of M001.
- The fingerprint schema is versioned separately (`fingerprintVersion = 1`).
- Additive exports and one pure-Dart SHA-256 dependency are the only package
  changes; no M001 model, snapshot, test or documentation changes.
- Persistence and migrations (TD-02/TD-03) remain out of M002.

## Reference definitions, not licensed assets

- Official NBA scoring/timing rules:
  https://official.nba.com/rule-no-5-scoring-and-timing
- Official NBA definitions: https://official.nba.com/rule-no-4-definitions/
- NBA stats glossary: https://www.nba.com/stats/help/glossary

The game is a fictional, NBA-inspired ruleset, not an official rules
certification or likeness license.
