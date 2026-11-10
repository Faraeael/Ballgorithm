# M007 Implementation Plan — Single-Season Playable Vertical Slice

- **Milestone:** M007
- **Target Architecture:** Pure Dart core models in `packages/simulation_core/lib/src/season/`, Flutter integration in `lib/features/season/`.

---

## 1. Work Breakdown & Architecture Layers

### Layer 1: Core Season Models (`packages/simulation_core`)
1. `SeasonFixture`: Single scheduled game (round, fixtureIndex, homeTeamId, awayTeamId, seed, completed, result summary).
2. `SeasonRound`: Group of 4 fixtures for one calendar round.
3. `SeasonSchedule`: 14 rounds, 56 fixtures, round-robin generator algorithm.
4. `SeasonStanding`: Record per team with W, L, win%, PF, PA, diff, streak, and tie-break comparator.
5. `SeasonPlayerTotals`: Cumulative box-score stats per player with per-game averages.
6. `SeasonGameSummary`: Lightweight archived box score (teams, scores, player lines).
7. `FranchiseStrategy`: Preferred starting lineup and rotation plan.
8. `SeasonState`: Aggregate root capturing schedule, current round, standings, player stats, user franchise ID, strategy.
9. `SeasonRepository` & JSON serialization: Version 1 schema encode/decode.

### Layer 2: Core Unit & Property Tests
1. `schedule_test.dart`:
   - Exactly 14 rounds, 4 games per round, 56 total games.
   - Each team plays 7 home and 7 away games.
   - Exactly 2 meetings per pair (1 home, 1 away).
   - Each team appears once per round.
   - Unique, deterministic fixture seeds.
2. `standings_test.dart`:
   - Standings update after rounds.
   - Points for, points against, point differential, streak tracking.
   - Exact tie-break sorting hierarchy.
3. `season_stats_test.dart`:
   - Stat accumulation matches individual game box scores.
   - Zero-denominator protection.
4. `season_persistence_test.dart`:
   - Round-trip JSON serialization preserves exact state.
   - Corrupt JSON error handling.

### Layer 3: Flutter State & UI Integration (`lib/`)
1. `SeasonStorage` & `SeasonService`:
   - Abstract storage contract (`read`, `write`, `clear`).
   - `FileSeasonStorage` using local file path, `InMemorySeasonStorage` for tests.
2. `FranchiseSelectScreen`:
   - Initial screen when no active season save exists.
   - Shows 8 teams with ratings and roster preview.
3. `SeasonDashboardScreen`:
   - Franchise header, record, next opponent card with "Play Next Game" CTA.
   - Bottom navigation: Dashboard, Team Strategy, Standings, Schedule.
4. `TeamStrategyScreen`:
   - Integrated starter selection and minute slider editing.
   - Saves strategy back to `SeasonState`.
5. `StandingsScreen`:
   - Mobile-responsive standings table highlighting user team.
6. `SeasonScheduleScreen`:
   - List of 14 rounds with scores and "View Box Score" modal.
7. Game Execution Integration:
   - "Play Next Game" navigates to existing `GameScreen` with user request.
   - On completion, simulates 3 background games, commits round, saves state, and returns to updated dashboard.
8. `EndOfSeasonScreen`:
   - Shown after Round 14 with Champion banner, final standings, and confirmed "New Season" button.

### Layer 4: Flutter Widget & Playable Flow Tests
1. `franchise_select_test.dart`: First launch franchise selection.
2. `season_dashboard_test.dart`: Dashboard rendering, record, next game card.
3. `season_strategy_test.dart`: Lineup and rotation editing and persistence.
4. `season_play_round_test.dart`: Simulating round advances standings and saves state.
5. `season_persistence_flow_test.dart`: App restart reloads active season.
6. `season_end_to_end_test.dart`: Complete 14-round season flow from launch to championship.

---

## 2. Risk Mitigation & Stop Rules

- **Zero Dependency Expansion:** No unapproved packages added to `pubspec.yaml`. Storage uses clean abstraction with pure file I/O and in-memory options.
- **Simulation Invariants Preserved:** `GameSimulator`, rules, versions, fingerprints, and PRNG order remain untouched.
- **Provisional V7 Engine:** M006 remains statistically unaccepted; v7 is used provisionally for development.
