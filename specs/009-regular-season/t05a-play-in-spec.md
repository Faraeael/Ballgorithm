# M009-T05A — Play-In Tournament

**Status:** Owner-authorized implementation specification (2026-11-14).  
**Scope:** Explicit Play-In entry after a valid completed M009 regular season; three persisted games; qualification handoff for playoff seeds 15–16; Flutter display and save/recovery.  
**Non-goals:** Playoff bracket, playoff games/series, conferences, season rollover, roster/economic progression, regular-season changes, engine probability tuning, M007 changes.

## 1. Objective and governing decisions

Add a Play-In phase to the persistent 30-franchise M009 career. Seeds 1–14 qualify directly, seeds 15–18 contest three games for playoff seeds 15–16, and seeds 19–30 are eliminated. Original regular-season ranking remains available for future home-court rules. The regular-season result ledger and standings remain unchanged. Career year does not advance.

The owner-approved structure is:

| Game | Home | Away | Advancement |
|---|---|---|---|
| G1 | Regular-season seed 15 | Seed 16 | Winner qualifies as playoff seed 15; loser advances to G3 |
| G2 | Regular-season seed 17 | Seed 18 | Winner advances to G3; loser eliminated |
| G3 | G1 loser | G2 winner | Winner qualifies as playoff seed 16; loser eliminated |

G3 is unavailable until valid persisted G1 and G2 results exist. No best-of-seven series or playoff bracket is included; M009-T05B owns the bracket design.

## 2. Audited architecture and boundaries

- `CareerPhase` currently contains `openingOffseason` and `regularSeason`. Add `playIn`; do not add a playoffs phase.
- `GmCareer` owns phase, `regularSeasonState`, and full native validation. Extend it with `playInState`; validate phase/state agreement, frozen ranking, tournament fixtures/results, historical evidence, and advancement.
- `GmCareerCodec` is schema v18. v18 result evidence is deduplicated by historical league snapshot and preserves exact canonical input, fingerprint, versions, seed, and result. v17 migration first validates the legacy result and fingerprint, then captures evidence without simulation. Upgrade to v19; preserve the existing v1–v17 migration branches.
- `RegularSeasonState` owns the only regular-season result ledger. Its standings are derived from that ledger. Never insert Play-In games/results into its schedule or result map.
- `RegularSeasonGameResult` binds results to regular-season fixtures and validates scores, period totals, player lines, and historical metadata. Play-In results need a distinct Play-In identity and validation path while reusing the summary, fingerprint, rules/version profile, and `RegularSeasonGameInputEvidence` contracts. Do not fabricate `RegularSeasonFixture` objects.
- `RegularSeasonGameInputEvidence` captures canonical game input and game-time league membership, then validates it without reconstructing today's roster. Use the same guarantees for every Play-In result.
- `RegularSeasonGameAdapter` supplies standard rules, default eligible lineups, balanced rotations, and the existing `GameSimulator`. Reuse this behavior for Play-In fixtures; do not alter simulation probabilities or regular-season seeds.
- `RegularSeasonRoundService` simulates and validates a complete round as one career transition. Play-In uses a separate one-game-at-a-time service because the games have distinct dependencies and confirmation/save boundaries.
- `LeagueStandings.ranked` is shared with M007 and ranks wins, point differential, points for, then string TeamId. Leave it and all M007 `SeasonState`, `SeasonSchedule`, `SeasonCodec`, and `SeasonStorage` behavior unchanged.
- `GmCareerController` serializes commands. `_saveCareerState` encodes and persists before publishing in-memory state; failures require explicit reload and prohibit retry on stale memory. Reuse this pattern for entry and each game.
- `GmCareerStorage` is the only persistence path. File storage supports atomic promotion and backup recovery. No automatic retry or auto-entry during load.
- `RegularSeasonOverviewScreen` is the M009 entry surface. Route `playIn` careers to a new Play-In screen, not the regular-season round actions.
- T04 explicitly excluded playoffs and M007 changes. Earlier read-only design did not inspect all validation, controller, screen, and M007 paths; this section resolves those audit omissions. `specs/009-regular-season/technical-debt.md` was absent in this checkout and is not treated as authority.

## 3. Frozen ranking

### Inputs and gate

Ranking uses only completed regular-season fixtures and their valid persisted results. Explicit entry requires all of the following:

1. `career.validate()` succeeds and native M009 state is internally consistent.
2. Career phase is `regularSeason`; regular-season schedule exists and matches the career's season identity.
3. Exactly 82 rounds, 1,230 fixtures, and 1,230 valid results exist; every round is complete and every franchise has exactly 82 completed games.
4. No unresolved offseason transactions remain. Re-evaluate the existing `OffseasonReadinessGate` and require `cleared` plus all 30 franchises ready; do not duplicate its rules.
5. Controller has no outstanding save-recovery requirement.
6. Human confirms entry. Cancel performs no write. The service rechecks all conditions at command time.

Entry constructs one immutable `PlayInState`, changes phase to `playIn`, keeps `currentYear` and the entire regular-season state unchanged, validates the complete new career, then persists once before publishing. Duplicate/concurrent entry is rejected by serialized command and phase checks.

### Ordering algorithm

The career-local ranking ruleset identifier is `m009-postseason-seeding-v1`.

1. Build each team's record from `RegularSeasonState.standings`, derived only from the regular-season ledger.
2. Partition teams into groups with identical regular-season wins.
3. Order win groups by wins descending.
4. Within a group of exactly two teams, compare their regular-season head-to-head win counts. Higher count ranks first. If counts are equal, continue to point differential. For groups of three or more, skip head-to-head entirely.
5. Within each group, order remaining ties by point differential descending, total points scored descending, then numeric team ordinal ascending.
6. Parse the entire ID with exact `^team-([1-9]|[12][0-9]|30)$`; reject unknown formats and duplicate ordinals. Require the 30 opening franchise IDs to map bijectively to ordinals 1–30. This matches current generated IDs (`team-1`…`team-30`) and prevents lexicographic `team-10`/`team-2` errors.

Head-to-head counts come only from valid completed regular-season games between the tied pair. A split head-to-head record falls through to point differential. Ranking is calculated once at entry and its ordered 1–30 `TeamId` snapshot is persisted. Validation recomputes the ranking from the immutable regular-season evidence and requires an exact match; the persisted snapshot is not a competing standings table.

## 4. Play-In state and result authority

Add immutable `PlayInState` (or an equivalent career-local aggregate) with:

- season ID and season year, equal to the associated regular-season state;
- frozen original regular-season rank, as the ordered 30 IDs;
- ranking ruleset identifier;
- canonical G1/G2/G3 fixture identities, including IDs, participants, host, seed, and rematch index;
- completed Play-In results keyed by fixture ID;
- deduplicated game-time league snapshots referenced by result evidence;
- completion derived from the authoritative G3 result, not a separately mutable completion flag.

Fixture IDs are deterministic and unique within the career, for example `<seasonId>-playin-g1`, `-g2`, and `-g3`. Fixture participants are derived from the frozen ranking and prior results. G3 participant/home identity is unresolved until G1 and G2 are complete; its persisted canonical fixture is fixed once both results exist. Do not persist a second mutable standings, winners, qualifier, or elimination ledger. Expose those values as validated getters derived from ranking and result records.

Each Play-In result preserves fixture identity, season identity, game-time home/away IDs, seed, input fingerprint, simulation/rules/event/fingerprint/PRNG/core-engine/league-schema versions, historical evidence, period totals, final score, player box score, and winner. Validate against the persisted historical input, not current rosters. Reject unknown versions and malformed/orphaned snapshots. Never regenerate or modify completed results.

## 5. Fixture and seed contract

Reuse `deriveGameSeed` unchanged. It XOR-packs `homeIndex << 16`, `awayIndex << 8`, and `(rematchIndex & 0xFF)`, then masks to 31 bits. Team indices are 0–29 from lexicographically sorted opening IDs, matching schedule generation. Bit fields do not overlap: home uses bits 16–20, away 8–12, rematch 0–7. The fixed career schedule seed makes distinct valid triples produce distinct seeds.

- Regular season remains rematch indices 1–82, unchanged.
- G1 uses 83; G2 uses 84; G3 uses 85.
- Future postseason indices start at 86; T05A rejects indices outside its fixed mapping.
- Stable IDs and fixed indices are independent of game result. G3's participants determine its home/away index inputs only after prerequisites complete.

Validation and tests must assert team index range, exact ID ordering, valid 8-bit index range, unique fixture IDs, pairwise Play-In seed uniqueness, no collision with any of 1,230 regular-season fixture seeds, no change to regular-season seeds, and same seed/result after save/reload.

## 6. Game progression and validation

Entry state has no Play-In results. Only the next legal game may be simulated:

- G1 and G2 are independently legal; each requires explicit human confirmation and persists one result.
- G3 is legal only when valid persisted G1 and G2 results exist and its participants/home court are derived from them.
- Reject wrong phase, stale game identity, duplicate result, unknown fixture, invalid participants, invalid home court, missing confirmation, and any game after tournament completion.
- Build each input with the existing `GameSimulator`, standard `GameRules`, existing eligible-player lineup/rotation path, and deterministic persisted seed. Persist result/evidence atomically before publishing success.
- A result must have a non-tied final score, correct winner, valid period sums, and reconciled player box score.
- Entry and every game command begin from a validated current career and return a new validated career. No partial state is published if simulation, validation, or save fails.

## 7. Qualification derivation

- Seeds 1–14 are the first fourteen entries in the frozen ranking.
- G1 winner is playoff seed 15; G1 loser advances to G3.
- G2 winner advances to G3; G2 loser is eliminated.
- G3 winner is playoff seed 16; G3 loser is eliminated.
- Seeds 19–30 are eliminated at entry.
- A complete tournament has exactly 16 unique playoff qualifiers. No team can occupy both seeds 15 and 16. Top fourteen never reseed.
- Preserve each qualifier's original regular-season rank for T05B home-court decisions.
- Play-In games do not affect regular-season records, standings, schedule, player/season totals, or career year.

## 8. Schema v19 and migration

Set both `GmCareer.currentSchemaVersion` and `GmCareerCodec.currentSchemaVersion` to 19. Add optional-on-disk `playInState` with strict phase-dependent requirements for native v19 saves.

- Every valid v18 career remains loadable: opening offseason; regular season without schedule; scheduled with no results; partially completed; fully completed.
- For v18 input, absent or null `playInState` means null; reject non-null pre-v19 Play-In state. Preserve every prior serialized field and value. Do not auto-enter Play-In. A completed regular season remains eligible for explicit entry.
- v1–v17 migration behavior remains unchanged, including v17 exact legacy validation and evidence capture. No historical game is regenerated.
- Encode native saves as v19. For old schemas, retain established migration ordering; create no Play-In state during migration.
- Native phase invariants: openingOffseason has no regular-season or Play-In state; regularSeason has regular-season state and no Play-In state; playIn has fully completed regular-season state and valid Play-In state for the same season/year. Play-In state is invalid in any other phase.
- Native regularSeason and playIn saves continue to pass the existing offseason-readiness validation. M007 schema and storage remain untouched.

## 9. Controller, storage, and recovery

Add serialized controller commands for `enterPlayIn(confirmed: ...)` and `simulatePlayInGame(expectedGameId, confirmed: ...)`. Both reject a false confirmation, stale career/state, duplicate command, and recovery-required controller. Build/validate next state, encode, write, then publish. On uncertain write, preserve previous in-memory career, mark recovery required, and require explicit `loadCareer`; do not retry automatically. Existing file backup recovery remains authoritative.

Acceptance tests inject cancellation, concurrent/duplicate confirmation, failure before promotion, uncertain write after promotion, explicit reload, and restart at every next-game boundary. Verify no duplicate result/qualification and no automatic simulation on load.

## 10. Flutter surface

Add a Play-In Tournament screen and route `CareerPhase.playIn` to it. The screen shows frozen original ranks, direct seeds 1–14, seeds 15–18, seeds 19–30 elimination, G1/G2/G3 matchups and status, G3 dependencies, host, completed winner/loser, final score, box-score access, and playoff-qualified seeds. Use statuses `Scheduled`, `Completed`, `Qualified`, `Eliminated`.
At regular-season completion, show one explicit `Enter Play-In` action with confirmation; cancellation writes nothing. After uncertain save failure, disable game actions and require `Reload Saved Career`.

Show one primary action for the next legal game. Confirm explicitly before simulation. Disable duplicate taps while the serialized command is active. Cancellation does not invoke a write. Do not expose best-of-seven or bracket UI. Follow existing Ballgorithm components and accessibility conventions. Verify at 360x640 and 393x852.

## 11. Acceptance coverage

1. Complete-season gate: exactly 82 rounds, 1,230 valid results, 82 games/team; incomplete, invalid, or unresolved career rejected.
2. Frozen 1–30 ranking; numeric IDs; two-team head-to-head; tied head-to-head fallback; three-team tied-wins fallback.
3. Qualification boundaries at seeds 14/15 and 18/19.
4. G1/G2/G3 home assignment; all eight winner/outcome combinations; G3 prerequisite enforcement.
5. Seeds 15/16, elimination, uniqueness, preserved original rank, and no top-14 reseed.
6. Seed indices, mapping, fixture ID uniqueness, pairwise distinctness, no regular-season collision, determinism after reload.
7. Historical evidence integrity; box-score/period reconciliation; Play-In does not alter regular-season records or year.
8. Save/restart continuity; cancellation; duplicate confirmation; pre/post-promotion recovery; explicit reload; no auto-simulation.
9. v18 offseason, partial-season, and complete-season migration; v1–v17 regression; no historical reruns.
10. M007 isolation; mobile layouts at 360x640 and 393x852.
11. Core and Flutter analyze/tests; focused integration run with a real completed 82-round career, all three games, final 16 qualifiers, preserved records/year, and save/reload.

## 12. Independent review and delivery gate

Use one focused TypeSafe JEV review for qualification fairness, tie-break semantics, seed collision safety, historical provenance, v18 migration, persistence recovery, and progression/elimination. Record actual verdict and resolve concrete defects. JEV does not replace deterministic tests.

### JEV review (pre-verification)

Model: `jev-latest` resolved to `jev-1.14.0`. Noul estimated probability of a concrete critical defect: ranking 0.22, tiebreak 0.15, seeds 0.14, history/migration 0.15, save/recovery 0.45, progression 0.20. No concrete defect or narrative objection was returned. Save/recovery remains the highest residual concern; deterministic failure/reload tests are still pending. These probabilities are review signals, not proof or approval.

Run core `dart analyze` and `dart test`, root `flutter analyze` and `flutter test`, focused Play-In integration tests, and required real-career save/reload scenario. Report exact observed results. Commit and push only if every critical integrity and acceptance requirement passes; otherwise preserve work and report the exact blocker. Do not start T05B or alter protected branches.
