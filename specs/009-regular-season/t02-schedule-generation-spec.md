# M009-T02 — Deterministic 82-Game Regular-Season Schedule

Status: owner-authorized implementation contract. The 30-franchise schedule terms are already approved. T02 creates and persists scheduled fixtures only; it does not simulate games.

## 1. Objective and boundaries

Generate, validate, persist, and display the approved 82-game schedule for an entered M009 career. Keep M007's eight-team season model, generator, codec, and `SeasonStorage` unchanged. Use `GmCareerStorage` only. Do not advance the year, mutate franchise/player/financial data, generate game results, or invoke possession simulation.

## 2. Audited contracts

- M009-T01 uses `GmCareer` schema v15 and stores season ID, year, schedule seed, frozen 30-team identities, and an empty result ledger in `RegularSeasonState`.
- `RegularSeasonEntryService` and `OffseasonReadinessGate` are authoritative for entry. T02 must reject blocked careers and must not weaken T01 checks.
- `GmCareerController` serializes commands, blocks after uncertain writes, writes through `GmCareerStorage`, and publishes only after successful persistence.
- M007 `SeasonSchedule`, `SeasonRound`, `SeasonFixture`, `SeasonCodec`, and `SeasonStorage` serve an eight-team/14-round domain. T02 uses separate career schedule types and does not modify those types or the M007 generator.
- Core `season_seed.dart` exposes stable `deriveGameSeed(leagueSeed, homeIndex, awayIndex, rematchIndex)`. Its bit-field formula remains unchanged. For 30 canonical team indices (0–29) and round values (1–82), fields remain disjoint; the six requested seeds produced 71,340 distinct, nonzero values across all ordered non-self matchups and rounds in a deterministic preflight check.
- Core `DeterministicRandom` is xorshift32-v1 and supports a separate local instance. Schedule selection must not consume or mutate any game-simulation PRNG instance.
- The approved contract is 30 franchises, 82 games/team, 41 home and 41 away, 1,230 total fixtures, 12 four-game opponents (2H/2A), 17 two-game opponents (1H/1A), reciprocal counts, and no conference/division structure.

## 3. Canonical schedule construction

1. Validate exactly 30 unique, nonempty franchise IDs. Sort IDs by ordinal `TeamId.value`; input order must not affect output.
2. Build a 29-round circle-method round robin. Each round is a perfect matching of 15 games; every unordered pair appears once. Fix canonical team 0 and rotate the other 29 indices.
3. Order each round's 15 pairings by `(lowerTeamIndex, higherTeamIndex)`. Set orientation deterministically from round and canonical pair indices.
4. Append a second 29-round cycle with every home/away assignment reversed.
5. Shuffle the 29 round indices once with a new local `DeterministicRandom(scheduleSeed)` and Fisher–Yates. Select the first 12 without replacement. The later round-ordering pass prevents consecutive rematches without changing the selected set.
6. Append those 12 selected matchings using their first-cycle orientations, then append the same 12 matchings in the same order with home/away reversed. Each selected pairing receives two additional games, one home and one away.
7. Order the 82 planned rounds with a deterministic greedy pass. At each slot, choose the unused candidate with the fewest franchises repeating home/away status from the prior round; skip any candidate with the same opponent matching as the prior round. Break ties by candidate order. Fail if no candidate remains that avoids a consecutive rematch.
8. Number resulting rounds 1–82 and fixture positions 0–14. Round order is stable for a persisted seed. No dates or travel/rest calendar is invented.

The first 58 candidates contain two complete reciprocal round robins. The 24 extra candidates repeat the 12 seeded matching rounds once in each home/away orientation. Greedy ordering changes only round order, never matchups or orientation. It prevents immediate rematches and locally minimizes consecutive same-venue assignments at each choice. The validated result yields 82 rounds × 15 fixtures = 1,230 fixtures; every pair appears twice or four times; each team has 41 home and 41 away games.

## 4. Fixture identity and seeds

Every fixture stores:

- Stable ID: `'$seasonId-r$roundNumber-f$fixturePosition'`.
- Season ID and season year.
- Round number and zero-based fixture position.
- Home and away `TeamId`.
- Game seed derived by the existing core `deriveGameSeed`, using the persisted schedule seed, canonical home/away team indices, and round number.
- Status. T02 fixtures are all `scheduled`; no completed status or result is accepted until a later approved result lifecycle.

The schedule stores season ID, year, persisted schedule seed, and immutable rounds. It stores no copied rosters. Canonical JSON preserves round and fixture list order. A SHA-256 fingerprint is calculated from canonical schedule JSON and is not an independent authority.

## 5. Validation and corruption handling

Strict validation rejects rather than repairs:

- Wrong team count, duplicate/empty team IDs, season ID/year/seed mismatch.
- Wrong round count/order, fixture count/order, or fixture season metadata.
- Unknown IDs, self-matchups, duplicate team participation in a round, duplicate fixture IDs, or wrong fixture ID/seed.
- Any game result or non-`scheduled` fixture in T02.
- Any deviation from 1,230 fixtures, 82 appearances/team, 41 home/41 away, 29 opponents/team, 12 four-game and 17 two-game opponents, reciprocal matchup counts, or required home/away matchup splits.
- Persisted fixture ordering/content that differs from deterministic regeneration for the stored seed and frozen opening IDs.

Native v16 schedule decode validates the stored object against the canonical generated schedule. It never writes generated data back or silently replaces corrupt data. Encoding validates an existing schedule before writing.

## 6. Explicit generation and persistence

Add one pure core generation service and one controller command. Command preconditions: `regularSeason` phase; valid v16 career/state; schedule absent; result ledger empty; all 30 frozen team identities still match; no controller recovery obligation. Generation occurs only on the explicit `Generate Schedule` action; loading a save never generates fixtures.

The command adds the complete immutable schedule to `RegularSeasonState`, validates the resulting career, writes through `GmCareerStorage`, then publishes. Repeat generation is rejected. A pre-promotion or uncertain post-promotion write failure leaves in-memory state unpublished, blocks further commands, and requires explicit reload. Reload must recover the exact schedule or the prior unscheduled state; it must not produce a second ordering. Existing contracts, roster, financial state, M008 history, and M007 storage remain unchanged.

## 7. Schema v16 migration

- Upgrade `GmCareer` and `GmCareerCodec` to v16.
- Accept valid v1–v15 saves. In v15 regular-season saves, preserve season ID, year, seed, team identities, and empty result ledger; add `schedule: null`. Do not generate fixtures during migration.
- Require the v16 regular-season schedule field; null means not generated. Non-null schedules undergo strict structural and canonical validation.
- Preserve all existing league, draft, contract, free-agency, clearance, hardship, staff, facility, and finance data.
- Opening-offseason careers remain opening-offseason. M007 `SeasonCodec` and `SeasonStorage` remain untouched.

## 8. Read-only queries

`RegularSeasonSchedule` exposes fixtures for a team, home fixtures, away fixtures, fixtures for a round, head-to-head history, next scheduled fixture, remaining scheduled games, and completed-game count. Queries preserve schedule order. T02 schedules contain 82 team fixtures, one next game, 82 remaining games, and zero completed games. No query advances a cursor or creates results.

## 9. Flutter behavior

Before generation, `RegularSeasonOverviewScreen` shows `Schedule not generated` and an explicit `Generate Schedule` action. During generation, disable the action and show progress. On success show team, year, 0–0 record, 82 scheduled games, next opponent/home-away/round, five upcoming fixtures, and `View Full Schedule`. Add a team schedule screen with all 82 games in a lazy list; include round, opponent, home/away, and scheduled status. A league-wide schedule screen is optional and omitted unless the existing UI makes it inexpensive.

Do not render all 1,230 fixtures at once. Do not add a Play Game button, dates, scores, or results. Preserve Ballgorithm styling and existing M007 navigation/storage behavior. Verify 360×640 and 393×852 layouts.

## 10. Diagnostics and performance evidence

For seeds `20261028`, `1604126146`, `987654321`, `314159265`, `271828182`, and `8675309`, report total rounds/fixtures; per-team home/away and opponent-count distributions; duplicate IDs; round collisions; maximum home/away streaks; minimum repeated-opponent round gap; and canonical SHA-256 fingerprint.

For career integration, use T01's six known ready active-human cases and two known blocked cases. Ready cases may generate; blocked cases must remain blocked. Do not alter M008 readiness/financial policy.

Measure on the development host: generation time, validation time, encoded schedule bytes, and career save/load time where practical. These are observations, not Android performance claims. Keep diagnostics deterministic; never assert timing thresholds.

## 11. Acceptance criteria

1. Exactly 30 canonical unique team IDs; changing input order preserves byte-identical schedule output.
2. Exactly 82 ordered rounds, 15 fixtures each, 1,230 total.
3. Every team appears once per round and plays exactly 82 games: 41 home, 41 away.
4. Every team plays all 29 opponents; exactly 12 opponents four times and 17 twice.
5. Four-game matchups are 2H/2A; two-game matchups are 1H/1A; pair counts are reciprocal.
6. No self-matchups, duplicate IDs, unknown IDs, repeated team-round participation, missing rounds, or out-of-season fixtures.
7. IDs, game seeds, ordering, and fingerprint are stable for a persisted seed; different seeds still produce legal schedules.
8. Schedule is immutable, all statuses are scheduled, and results remain empty.
9. Stored schedule must equal deterministic regeneration; malformed/tampered saves reject without repair.
10. T01 ready careers can explicitly generate once; blocked careers cannot generate; repeat and concurrent requests cannot replace the committed schedule.
11. v1–v15 migration preserves data; v15 regular-season state loads with no schedule and no auto-generation; corrupt v16 schedule rejects.
12. Save-before-publish, pre-promotion failure, post-promotion uncertainty, explicit reload, exact resume, and duplicate rejection pass. No financial, contract, roster, or M007 storage mutation.
13. All required team/round/opponent/next-game/remaining/completed queries return correct schedule-order results.
14. UI shows correct pre/post-generation states, five upcoming fixtures, and a lazy 82-game team schedule; no Play Game action or fabricated result.
15. UI fits 360×640 and 393×852 without overflow.
16. All six seed diagnostics report valid mathematics and reproducible fingerprints; known T01 ready/blocked cohort integration remains intact.
17. Core and Flutter analyze/test/format gates pass, including M007 schedule/storage regressions.
18. No regular-season simulation, year advance, M007 schedule edit, M008 policy change, Android-device modification, or M009-T03 work.

## 12. Non-goals and next gate

No game simulation, results, box scores, standings, stats, player development, fatigue, injuries, trades, contracts/financial changes, dates/travel/rest, playoffs, rollover, or T03 gameplay integration. T03 must introduce the validated result lifecycle before completed fixtures or nonempty game-result ledgers are accepted.
