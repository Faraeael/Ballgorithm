# M006-T06G — Next Playable Vertical Slice Recommendation

- **Date:** 2026-11-09
- **Status:** READ-ONLY PRODUCT & ARCHITECTURE ASSESSMENT.
- **Repository:** `Faraeael/Ballgorithm`
- **Branch:** `impl/m006-t06g-final-disposition`
- **Focus:** Product gap analysis and scoping the smallest end-to-end playable user experience.

---

## 1. Product Context & Strategic Pivot

For six milestones (M001–M006), development focused almost exclusively on mathematical foundations: deterministic PRNG, event-sourced ledgers, clock decrement laws, turnover hazards, player participation, rotation policies, and shot selection probability curves.

While the simulation core is technically robust and regression-tested, **Ballgorithm is not yet a playable management simulation game**.
- Current app launch initializes a hardcoded league (`seed: 20261028`) in memory.
- There is no concept of a user franchise, season schedule, standings, persistent roster edits, or game-to-game progression.
- Games are simulated in an ad-hoc exhibition sandbox with no lasting stakes.

In accordance with owner guidance, priority must pivot from additional micro-level probability experiments to **delivering visible, end-to-end playable player value**.

---

## 2. Assessment of Existing Capabilities vs. Gaps

The target playable loop requires six sequential touchpoints:
$$\text{Create/Load League} \to \text{Manage Team/Roster} \to \text{Set Lineup/Minutes} \to \text{Simulate Game} \to \text{Review Box Score} \to \text{Update Standings/Return}$$

| Target Workflow Step | Existing Flutter & Core Capability | Missing Gap for Playable Game |
|---|---|---|
| **1. Create or Load League** | `LeagueGenerator` creates valid 8-team leagues from integer seeds. `LeagueScreen` renders team list and seed. | No UI to input a custom seed, generate a new league, or persist/load saved leagues from disk. App re-creates the same default league on each launch. |
| **2. View Team and Players** | `RosterScreen` displays full 12-player rosters with position badges. `PlayerProfileScreen` displays detailed ratings, attribute bars, and bio. | No concept of a "User Team". The player is a detached observer without an assigned franchise to manage. |
| **3. Select Starting Lineup & Minutes** | `GameSetupScreen` offers starter slot pickers and balanced/starter-heavy/custom rotation sliders conserving the 240-minute team total. | Lineup choices and rotation minutes exist only ephemerally on `GameSetupScreen`. They cannot be saved to the team or carried over between games. |
| **4. Simulate a Game** | `GameScreen` and `GameRunner` execute simulation headlessly in a worker isolate with typed failure handling. | Fully operational exhibition runner. Missing: scheduling next matchup from a calendar rather than picking opponents manually. |
| **5. View Score & Box Score** | `GameResultView` renders scoreboard, period table, team stats table, player box scores, foul outs, and disclosures. | Fully operational and verified on mobile viewports (360x640 to 430x932). |
| **6. Return to Management & Standings** | "Return to League" button pops back to `LeagueScreen`. | Game outcomes vanish upon exiting. No standings table (W-L), no point differentials, no cumulative player season statistics. |

---

## 3. The Highest-Priority Missing Playable Feature

The single highest-priority missing feature that breaks game feel is:
$$\mathbf{State\ Persistence\ \&\ Standings\ Progression}$$

Without standings and game memory, simulating a game has no consequence. Winning 110–108 is identical to losing 110–108 because the team record remains unrecorded.

---

## 4. Minimum Next Milestone Scope (Proposed M007: Playable Season Slice)

We recommend defining **Milestone 007: Single-Season Playable Slice** as the smallest complete vertical slice that converts Ballgorithm from a technical demo into an offline basketball management game:

### Recommended M007 Scope (Strictly Bounded)
1. **Franchise Selection:**
   On first launch or new league, user selects 1 of the 8 generated teams as their managed franchise.
2. **Persistent Team Strategy:**
   Save preferred starting lineup and rotation minutes on the user's team model.
3. **Round-Robin Schedule & Standings:**
   Generate a balanced 14-game regular season schedule (each team plays the other 7 teams twice: home and away).
   Display a real-time Standings table: Rank, Team, Wins, Losses, Win%, Streak, Point Differential.
4. **"Next Game" Day Flow:**
   Replace manual team picker with a single "Play Next Game" action.
   Simulate the scheduled matchup, record the outcome into standings and box score archives, and advance the calendar.
5. **Local Offline Persistence:**
   Save league state, schedule, standings, and game results to local storage (pure Dart JSON serialization or SQLite) so progress is retained across app restarts.

### Non-Goals for M007 (Defer to M008+)
- No trades, contracts, or financial management.
- No drafting or multi-year scouting.
- No player injuries or multi-game fatigue.
- No in-game play-by-play tactical coaching commands (quick-sim only).
- No network, cloud sync, or multiplayer features.

---

## 5. Architectural Implementation Path

- **Pure Dart Core (`packages/simulation_core`):**
  - Add `SeasonSchedule`, `SeasonGame`, `LeagueStandings`, and `SeasonStandingsRecord` models.
  - Implement deterministic schedule generator from league seed.
  - State reducer updating standings from authoritative `GameResult`.
- **Flutter Client (`lib/`):**
  - Add `StandingsScreen` / tab to `LeagueScreen`.
  - Add "User Franchise" badge and persist selected team ID in `SharedPreferences`.
  - Connect `GameResultView` "Return to League" to persist game outcome into the active season state.
