# M009-T03 — Regular-Season Game Simulation, Results, and Standings

Status: implementation contract authorized by the M009-T03 owner task. T03 simulates scheduled games only through the existing deterministic M002 `GameSimulator`; it introduces no coaching controls or gameplay tuning.

## 1. Objective and boundaries

Deliver one playable 30-franchise career round at a time. The human GM explicitly confirms; the system simulates all 15 games in the next scheduled round, validates one atomic update, persists before publishing, and exposes results, box scores, and derived standings. A saved round resumes without replaying or duplicating outcomes.

Keep M007's eight-team `SeasonState`, `SeasonSchedule`, `SeasonStorage`, and game controller isolated and unchanged. Do not simulate individual games outside the round command, advance the year, mutate rosters/contracts/finances, or implement playoffs, dates, injuries, development, or coaching controls.

## 2. Audited contracts

- T01 created career schema v15 and a regular-season state with an empty result map. T02 upgraded to v16 and persisted the deterministic 82-round career schedule. V16 schedules contain scheduled fixtures only.
- `GmCareer.validate()` is authoritative for career, roster, employment, financial, and schedule identity. Keep its validation; extend it to the T03 result lifecycle.
- `GameInput.create` validates unique home/away teams, canonical five-player lineups, ownership, rules, and optional rotation plans. `GameSimulator.simulate` uses the input seed and returns only after validating the event ledger and derived box score.
- `GameRules.standard` is the current approved ruleset. `RotationPlan` and the deterministic `balanced` preset already define integer playing-time targets. T03 does not change engine versions, rules, sampling, or PRNG behavior.
- `SeasonGameSummary.fromResult` projects final scores, period scores, and player lines from a validated `GameResult`. `LeagueStandings` / `SeasonStanding` provide the existing deterministic ranking and streak calculation. T03 may reuse these projections but must not copy M007's `SeasonState` or persist independent standings/player totals.
- Existing `RosterCategory.standard` explicitly describes regular-season and active-game eligibility. The current two-way description does not define game-day participation; training-camp contracts are offseason-only.
- `GmCareerController` serializes commands, calls `GmCareerStorage.write`, publishes only after successful write, and requires reload after uncertain failure. T03 must reuse this path. M007 has separate season storage.

## 3. Narrow game-day eligibility and lineups

T03 game-day policy: only `RosterCategory.standard` players enter the simulation roster and can start or substitute. Exclude two-way and training-camp players from the simulation-only league projection. This follows the explicit standard-category active-game rule and avoids inventing two-way eligibility. It does not remove or alter any career roster member, contract, or financial record.

For each team, select the first standard player in canonical roster order at each primary position PG, SG, SF, PF, C, using `CourtLineup.defaultFor`. The existing lineup contract maps these five canonical slots to five distinct owned players; it does not require a matching primary position beyond this default selection. If any slot cannot be filled, reject the complete round without mutation.

Use the existing `RotationPreset.balanced` expansion for every eligible standard player. No hidden potential, trajectory, ambient randomness, or coaching adjustment may affect selection. The 30-team career roster remains authoritative; any filtered team/league objects exist only for immutable `GameInput` construction.

## 4. Career game result record

Persist one immutable career result envelope per fixture, keyed by fixture ID. Each envelope records:

- Fixture ID, season ID/year, home/away team IDs, and exact persisted fixture game seed.
- `GameResult.inputFingerprint` and simulation/rules/event-schema/PRNG version identifiers.
- Compact `SeasonGameSummary` derived from the simulator's validated `GameResult`: final score, winner, period totals, and all player box-score lines.

Do not persist a second event ledger or a second standings/statistics authority. The summary is the career's authoritative result projection; `GameResult.ledger` remains the simulation-time proof and is not serialized. Validate result metadata against the immutable fixture and recomputed deterministic input. Validate score/winner and period reconciliation, box-score arithmetic, team ownership, and player identity against the current career roster.

The schedule's completed status is a persisted convenience mirror, not a separate result authority. A fixture is `completed` iff exactly one result envelope exists for its ID. Completed rounds must form a contiguous prefix; each round is wholly completed or wholly scheduled. Reject partial rounds, duplicate/unknown results, status/ledger disagreement, wrong seeds, wrong team identities, and corrupt box scores.

## 5. Round transaction and progress

`RegularSeasonRoundService.simulateNextRound(career)` is pure with respect to its input. It:

1. Calls full career validation; requires regular-season phase, v17-compatible state, generated canonical schedule, and no unresolved result/recovery state.
2. Finds the first unfinished round. It rejects a completed season and any skipped, partial, or previously completed round.
3. Builds the simulation-only eligible rosters, canonical lineups, and balanced plans.
4. Calls the existing `GameSimulator` exactly once per fixture, with `gameId == fixture.id`, `seed == fixture.gameSeed`, and `GameRules.standard`.
5. Validates all 15 results and constructs a complete new result map and completed-fixture schedule locally.
6. Returns one validated new career. Any simulation, result-validation, or career-validation failure returns no state and commits no partial result.

The controller exposes one confirmation-gated serialized command. Cancel makes no command/write. Confirm simulates one full round, persists the complete career, then publishes success. Disable repeat taps while busy. A failed or uncertain write publishes nothing and requires explicit reload; never rerun automatically. After reload, the round is either fully persisted or fully unplayed. The same prior career and seeds produce byte-identical next-round results.

Progress is derived from the fixture/result lifecycle: completed rounds/games, remaining games, per-team game counts, next unfinished round, human next opponent, and human W-L record. At round 82, require 1,230 results and 82 games/team; reject further simulation. Keep phase and year unchanged. Standings and any season player totals are derived from results on demand; do not persist them as independent state.

## 6. Result validation and standings

For every record require:

- Exact fixture, season, year, home/away identities, game seed, simulation input fingerprint, and supported version metadata.
- Nonnegative unequal final scores; winner matches score.
- Period labels are contiguous regulation quarters followed only by contiguous overtime periods; each team’s period totals sum to final score.
- Player-line map keys match player IDs. Each player is a standard-category member of exactly one participating team; no foreign or cross-team identity.
- Nonnegative statistics; `3PM <= FGM <= FGA`, `3PA <= FGA`, `FTM <= FTA`, `REB == OREB + DREB`, and points reconcile to field goals/free throws. Team player points reconcile to final score.
- Player seconds are bounded by game duration derived from periods played and standard rules.

Derive all 30 `LeagueStandings` from completed fixture summaries in schedule order. Rank by wins descending, point differential descending, points scored descending, then team ID ascending. Preserve the existing `SeasonStanding` streak convention. Do not add conference/division/playoff tie-breaks.

## 7. Persistence and migration

Upgrade career schema to v17.

- Decode valid v1–v16 saves. V16 regular-season careers retain season identity, opening teams, schedule, and empty results; migration does not simulate, complete, reorder, or regenerate fixtures.
- V17 regular-season saves strictly validate the schedule/result lifecycle and every result envelope. Opening-offseason careers remain unsimulated.
- Reject impossible phase/state combinations, duplicate or unknown result IDs, fixture/result mismatches, schedule seed tampering, invalid summaries, and a result map that disagrees with fixture statuses.
- Preserve all existing player, contract, salary, finance, offseason, schedule, and M008 history. Do not modify M007 save code or data.

## 8. Flutter gameplay

On the regular-season overview show current record, current/next round, next opponent and home/away, current derived league position, and one primary action: `Simulate Next Round` (or `Continue to Next Round` after a result). Each activation opens an explicit confirmation dialog. After acceptance and successful persistence, show the human result, updated record, `View Box Score`, `View League Results`, and `View Standings`.

- Box-score screen displays persisted period and player lines; never fabricate stats.
- League results and team schedule derive status/scores from the career result map and use lazy list rendering.
- Standings screen shows all 30 teams with GP, W-L, win percentage, PF, PA, differential, and streak.
- At 82 rounds show `Regular Season Complete`; no further simulation button, season completion, or year advancement.
- Show errors and reload recovery action after failed/uncertain writes. Maintain the existing visual language and verify 360×640 and 393×852. No live animation or Play Game action.

## 9. Deterministic evidence and quality observations

Exercise all six T01 ready active-human careers: `20261028` Play-In/Playoff/Contender and `987654321` Tanking/Play-In/Playoff. Generate the approved schedule, simulate Round 1, save/reload, and reconcile all 15 fixtures. Demonstrate Rounds 1–3 sequentially for at least one career. Keep blocked `271828182` Tanking and `8675309` Contender blocked. No full 82-round simulation is required, but progress logic must accept round 82 and reject round 83.

Record human result, league W-L totals, completed/remaining fixtures, a player-box sample, deterministic fingerprints, and elapsed simulation time. Across executed games, report score ranges/distribution, shooting/free throws, rebounds, turnovers, fouls, minutes, overtime, home wins, and simulation duration. These observations do not approve realism or authorize engine tuning. No Android performance claim.

## 10. Acceptance criteria

1. A pure career adapter creates valid inputs from current authoritative teams, exact fixture seeds, and `GameRules.standard`; it invokes the existing `GameSimulator` only.
2. Only standard-category players can start or substitute. Lineups contain five distinct owned players; balanced rotation plans validate. Hidden profiles and nonstandard players do not leak into the game input.
3. Every simulated game has one fixture-bound result envelope with exact identities, seed, input fingerprint, supported versions, final score, period totals, and real simulator-derived player lines.
4. Native v17 rejects all malformed or mismatched result, fixture, schedule, identity, score, period, box-score, or status data. V1–v16 saves migrate without creating results.
5. One confirmed command simulates exactly the 15 fixtures of the next round; no skipping, partial completion, duplicate completion, year advance, or repeated execution.
6. Any game/result failure leaves the input career unchanged. Persist all 15 outcomes once before publishing; pre-promotion and uncertain post-promotion failures recover through explicit reload without duplicate games.
7. Same career/round/fixture seeds produce byte-identical results; result and schedule identity survive encode/decode.
8. Completed rounds, games, per-team records, next fixture, standings, and box-score views derive solely from validated result envelopes.
9. Standings match wins, losses, win percentage, points, differential, streak, and approved deterministic ranking.
10. Six ready active-human cohorts complete Round 1; one completes Rounds 1–3. Two known blocked cohorts remain blocked and cannot simulate.
11. UI requires explicit confirmation, shows correct results/screens, uses lazy rendering, and fits 360×640 and 393×852 without overflow.
12. Round 82 completes 1,230 games; no 14-round limit exists; round 83 is rejected. No year advancement, rollover, or playoffs.
13. M007 schedule, simulation, storage, and M008 regression gates pass unchanged.
14. Core/Flutter analysis, tests, format, focused integration, migration, recovery, deterministic, and gameplay quality diagnostics pass and are reported with exact output.
15. No coaching controls, engine-rule changes, M008 financial changes, Android device changes, or T03 follow-on work.

## 11. Non-goals and next gate

No direct coaching, tactical interaction, player development, fatigue/injuries, trades/waivers, staff/facility gameplay, contract expiration, revenue, playoffs, rollover, new salary-cap relief, calendar dates, or game balance tuning. T03 does not confer approval for full-season realism or season completion.