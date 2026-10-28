# Feature 001: League & Player Foundation

## Goal
Create a deterministic, validated fictional basketball league in pure Dart and display a read-only roster in Flutter.

## Scope
- Eight fictional teams, each with 12 players, unique immutable IDs and positions PG/SG/SF/PF/C.
- Domain models: League, Team, Player, PlayerAttributes, Roster, GenerationConfig.
- Explicit 0–100 integer attributes: insideScoring, midrange, threePoint, freeThrow, passing, ballHandling, perimeterDefense, interiorDefense, rebounding, athleticism, stamina, basketballIQ.
- True attributes stored in domain; scouting observations reserved for future milestone, not exposed in UI.
- Seeded generation with stable ordering and explicit PRNG implementation/version.
- Validate league/team/player IDs, membership, roster size, positions, and attribute bounds.
- Flutter read-only league selector, team list, roster screen and player profile.

## User stories
US1: As a manager, I can create a fictional league with a reproducible seed.
US2: As a manager, I can inspect teams and rosters with valid positions and ratings.
US3: As a developer, I can validate a league without launching Flutter.

## Acceptance criteria
AC1: Same seed/config/version yields structurally identical league snapshots across repeated runs.
AC2: Different seeds generally yield distinct player/roster attributes (test with a sample of seeds).
AC3: Exactly 8 teams and 96 distinct players, with exactly 12 assigned to each team.
AC4: All attributes are integers within 0–100, all IDs are unique, every player belongs to exactly one team.
AC5: Invalid configurations and malformed roster/league states return explicit validation failures.
AC6: Dart unit tests run headlessly; Flutter widget tests verify team-to-roster-to-profile navigation.
AC7: Domain module has no Flutter/Flame/database imports.
AC8: No gameplay simulation, contracts, drafts, trades, online features or Flame integration in this milestone.

## Open design decisions
- Choose and document league ruleset, player rating distribution and generated-name corpus before implementation.
- Choose whether position coverage is a hard constraint; default proposal is at least one primary player per position per team.
- Decide initial persistence scope; proposal: snapshot export/import deferred to later milestone, with schema design documented now.
