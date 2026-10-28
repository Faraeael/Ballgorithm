# Acceptance Matrix 002 — proposed test fixtures

Status: **FROZEN — READY FOR IMPLEMENTATION AUTHORIZATION**
Frozen: 2026-10-28. Implementation remains **NOT AUTHORIZED**.

Minimum cases; implementation adds adversarial cases discovered later. Use
scripted event durations/outcomes where possible so fixtures do not depend on the
probability model.

| Target | Required fixtures and assertions |
|--------|----------------------------------|
| AC01 headless | Two M001 teams, valid lineups, full game in `dart test`; no Flutter imports, no file/network writes. |
| AC02 validation | Same team both sides; foreign player; duplicate player; player in the wrong position; same player on both lineups; inaccessible roster; unknown rules/version; invalid seed range policy; empty IDs. Typed `GameValidationCode` failures. |
| AC02b seed identity | Seed 0 → normalized `0x9E3779B9`, away starts; even seed home starts, odd away; seeds `s` and `s + 2^32` produce identical events but different fingerprints; no PRNG draw consumed by opening possession. |
| AC03 determinism | Same input/seed 20 repetitions identical; pinned ledger fixture; pinned SHA-256 fingerprint fixture; VM/Chrome comparison; different seeds generally differ. Verify the A1 draw order: type draw then duration draw per phase, and no duration draws for a final-tick attempt. |
| AC04 clocks | 720→0 per period; 300-second OT; 24-second violation; ORB reset 14; final-FT ORB reset 14; DREB/made-basket/turnover reset 24; under-14 non-bonus foul reset `max(remaining,14)` capped 24; shot clock and game clock expiring together (horn precedence unless shot/foul began first); last-tick shot made; last-tick shot missed `DeadBallMiss`; buzzer shooting foul completes FTs; Q4 tie→OT; OT tie→second OT; 11th OT typed failure. |
| AC04b A1 durations | Type boundaries at draws 0/1499/1500/4499/4500/9999; bracket minima/maxima 2/7, 5/11, 10/22; `D == Rg` shot releases at 0; `D == Rs < Rg` shot released at shot-clock 0; `D > Rs < Rg` → shot-clock turnover at `Rg-Rs`, no FGA; `D > Rg < Rs` → period end at 0, no FGA/TOV/rebound; `D > Rg == Rs` → horn, no shot; `Rg == 1` final-tick shot consumes 1 s and releases at 0; a bonus/shooting foul that is the terminal action at 0 completes its FTs; no silent clamping of `D`; new phase after OREB/non-bonus foul draws type+duration again; changing weights/brackets requires a rules-version bump. |
| AC05 causality | Made 2/3 ends possession; made and-one keeps possession until FT resolves; missed FG + OREB retains, + DREB changes; missed final FT + OREB/DREB when live; a live missed and-one FT or missed shooting-foul final FT with an OREB continues the **same** possession and starts a new phase with no `PossessionEnded`; a DREB or made final FT ends it; zero-clock missed final FT `DeadBallMiss`; no duplicate rebound per miss; no post-`GameEnded` event; no new possession after the horn. |
| AC06 accounting | Hand-authored ledger replays to exact player/team/period totals; 100+ whole games reconcile every equation (below). |
| AC07 vocabulary | 2PT/3PT make/miss; blocked FGA; steal; assist; missed 2FT/3FT shooting foul without FGA; and-one ordering (FG → foul → FT → rebound/dead-ball → possession end only on make/DREB/dead-ball; OREB continues); offensive foul; non-bonus and bonus defensive non-shooting fouls; OT bonus at 4th team foul. |
| AC07b ledger boundary | `GameStarted`, `PeriodStarted`, `PossessionStarted/Ended`, `PeriodEnded`, `GameEnded`; no floats; schema version present; illegal ordering rejected by the reducer. |
| AC07c attribution | `team.TOV == sum(player.TOV)`; shot-clock TO to lineup PG by default; offensive foul TO to offender; assist/steal/block links valid; foreign/bench attribution rejected. |
| AC08 boundedness | 50,001st event fails; 65th consecutive zero-clock event at an unchanged timestamp fails; legitimate 3-FT + timeout-free dead-ball sequences stay below the guard; 11th OT fails; invalid probability inputs fail; no NaN/Infinity. |
| AC09 directional skills | E1–E6 from the calibration plan: 200 paired seeds each, 95% bootstrap CI excludes zero in the expected direction, Holm correction; aggregate only, no per-game monotonicity. |
| AC10 calibration | ≥1,000 games, full mandatory table, seed list, outlier diagnostics, example games, owner sign-off; no automatic realism verdict. |
| AC11 M001 preservation | 44 VM core tests, 43 Chrome-compatible core tests (`domain_isolation_test.dart` uses `dart:io`), 8 Flutter tests pass; default league snapshot and pinned PRNG vectors unchanged; `coreEngineVersion`/`snapshotSchemaVersion` unchanged; dependency audit for `package:crypto`. |
| AC11b fingerprint | Full-league hash changes when an unrelated roster changes; lineup order changes the hash; seed/rules/version changes the hash; A1 weights/brackets and duration-model version are included; canonical field order independent of map iteration; lowercase hex; VM/Chrome identical. |
| AC12 performance | 1,000 games ≤ 60 s desktop optimized Dart; p95 ≤ 100 ms/game; ≤ 128 MiB incremental; environment and warmup recorded; no Android claim without device measurement. |
| AC13 scope | Only simulation core, tests and M002 docs change; no Flutter UI, networking, persistence, season, AI GM, contracts, tactics or rotations. |

## Accounting equations (test for every game)

For player `p` and team `t`:

```text
FGM = 2PM + 3PM
FGA = 2PA + 3PA
0 <= 2PM <= 2PA
0 <= 3PM <= 3PA
0 <= FTM <= FTA
PTS = 2*2PM + 3*3PM + FTM
REB = OREB + DREB
team.METRIC = sum(player.METRIC) for player-credited metrics
team.TOV = sum(player.TOV)
team.PF = sum(player.PF)
team.PTS = sum(player.PTS) = sum(team.periodPoints)
```

Additional invariants:

- Each made FG has exactly one shooter; an assist is a different on-court teammate.
- Each steal pairs with exactly one opponent turnover; each block is a missed FGA.
- Each live missed FG or reboundable final FT has exactly one rebound or one
  `DeadBallMiss`, never both.
- Team fouls reset each period; bonus FTs per OD-11 do not create FGA or FG points.
- And-one = one made FGA/FGM + exactly one FT; no bonus FTs.
- Offensive foul = PF + player TOV, no FGA/points, possession transfer, no team
  bonus count.
- `GameClock` never negative or increasing within a period; `ShotClock` within
  `0..24` (or configured max) and increases only via an enumerated OD-12 reset;
  sequence IDs strictly increasing.

## Accounting corner cases

- Missed shooting foul: 2 or 3 FTs, zero FGA.
- Blocked 3PT: 3PA + BLK, never 3PM; then rebound/dead-ball.
- Steal: opposing TOV only; never self-team TOV.
- Offensive foul on a made basket: no counted basket and no coexistence; the
  action is an offensive foul only.
- Non-bonus non-shooting foul: possession retained, shot clock reset, no FTs.
- Bonus free throws after the horn: completed; missed final FT at zero is
  `DeadBallMiss`.
- End of period: possession ends without phantom TOV or rebound.
- One event never adds points twice (made and-one FG plus foul).
- Bench/unused players have zero stats; no minutes exist in M002.
- Zero-opportunity players aggregate to 0 without division errors.

## Test harness discipline

- Commit deterministic fixture inputs; property tests log failing seeds.
- Fail immediately with typed game validation errors; never repair a ledger.
- Distinguish algorithmic consistency from calibration and human judgement.
- Acceptance reports list exact commands, counts, platform, versions and skipped
  validations.
