# Verification Plan 004 — Foundational Player Participation

> **Status:** **DRAFT — NOT FROZEN.** Defines required evidence; nothing here has been run.

## 1. Test layers

| Layer | Purpose | Examples |
|---|---|---|
| Contract | Types, serialization, rules validation | `CourtLineup` invariants; `Substitution` JSON round-trip; rules ranges |
| Reducer acceptance | Legal ledgers parse and replay | Hand-built ledgers per window |
| Reducer rejection | Illegal ledgers fail with typed codes | §3 list |
| Simulator behaviour | Real games produce lawful participation | Foul-out games, depleted fixtures, 5-player leagues |
| Accounting | Minutes and box conservation | Regulation, OT, W1 split, continuation |
| Determinism | Replay and parity | Canonical fixture, repeats, worker/caller |
| Equivalence | Inert without disqualifications | v4 vs v5 event-list identity |
| UI | Display and disclosure | Widget tests at 360/393/430 |
| Statistical | Descriptive effect sizes | Matched-seed cohort (§5) |

## 2. Fixtures

1. **Canonical v5 ledger** — a game with at least one substitution, pinned by digest and full events.
2. **Overtime participation fixture** — OT periods, foul persistence, W5 at OT start.
3. **Five-player league fixture** — bench empty; first disqualification continues; no substitution.
4. **Twelve-player depletion fixture** — constructed ledger where all bench players are exhausted;
   continuation valid, five always on court.
5. **W1 retained-foul fixture** — substitution during an open possession with a pending ceiling.
6. **W0 fixture** — disqualified defender replaced between foul and first free throw.
7. **Horn fixtures** — buzzer shooting foul: made final FT and missed final FT (`DeadBallMiss`).
8. **v4 equivalence fixture** — same seed/lineups, no disqualification, event lists identical.

## 3. Reducer rejection list (each needs a typed code)

1. Substitution while no window is open.
2. Substitution with `gameClock == 0`.
3. Substitution advancing or decreasing the game clock.
4. Substitution changing the shot clock.
5. Substitution with a null shot clock while a possession is open.
6. W1 substitution followed by a possession start above the pending ceiling.
7. W1 substitution that clears the ceiling so a later event is accepted with a higher clock.
8. Substitution inside an FT group not opened by a disqualification.
9. W0 substitution by the wrong team, or after the first FT attempt began.
10. W0 substitution that alters group id, shooter, attempt count or total.
11. Substitution after `PossessionEnded(defensiveRebound)`.
12. Substitution after a live turnover or steal.
13. Substitution after `PossessionEnded(madeFieldGoal)` (W3 deliberately absent).
14. Substitution after `DeadBallMiss`.
15. Substitution after `PeriodEnded` or after `GameEnded`.
16. Out-player inactive; in-player already active; in-player not on roster; duplicate player.
17. Five not maintained (four or six active).
18. `reason: foulOut` with the out-player below the limit.
19. `reason: tactical` with the out-player at/over the limit.
20. Missing mandatory replacement when an eligible bench player exists.
21. Continuation when an eligible bench player exists.
22. Two appearances by the same player in one window (loop bound).
23. Substitution whose period does not match the current period.

## 4. Accounting checks

- Exact conservation per team for every fixture: `Σ seconds == 5 × Σ periodLength(played)`.
- No negative interval; no interval crossing a period boundary without a `PeriodStarted` anchor.
- W1 substitution splits a possession correctly.
- Continuing disqualified player's interval is unsplit.
- Mutated ledger that drops a substitution must fail conservation, not silently pass.

## 5. Statistical plan (pre-registered before running)

**Design:** matched seed and matchup. Each registered game is run under v4 and v5 with identical
inputs; differences are paired per game.

**Primary analysis:** all registered games, intention-to-treat. Per-game paired differences for:

- points per team;
- possessions;
- turnovers;
- FGA, 3PA, FTA;
- personal fouls.

Report per-metric paired mean, paired standard deviation, 95% paired CI, and the distribution of
per-game differences. No filtering on whether a disqualification occurred.

**Descriptive additions (not gates):** disqualifications per game, substitutions per game, minutes
distribution by roster rank, first-divergence event index per game.

**Mechanism check:** for games with no disqualification and default lineups, assert event-list identity
between v4 and v5. Report separately; never used to exclude games from the primary analysis.

**Fresh sample:** conditional on owner approval; seeds drawn from an unused range and recorded before
execution. No AC09/AC10 claims. No NBA realism claim.

## 6. Commands (expected, from the repository root and package)

```text
flutter analyze
flutter test
dart format --set-exit-if-changed lib test

cd packages/simulation_core
dart pub get
dart analyze
dart format --set-exit-if-changed lib test
dart test
```

Chrome-compatible core tests are required when replay, fingerprints or serialization change — M004
changes all three — excluding the IO-dependent `domain_isolation_test.dart` with the exclusion
recorded.

## 7. Evidence artefacts

- `specs/004-player-participation/` acceptance report (created at T10).
- Canonical fixture file with digest.
- Mutation test names mapped to §3 numbering.
- Cohort pre-registration and results.
- UI widget-test names per width.

## 8. Stop rules

Stop and report if: a legal ledger is rejected; minutes do not reconcile; a default-lineup game differs
from v4; the reducer requires rules beyond the documented window/ceiling exemptions; or the cohort
cannot be pre-registered before execution.
