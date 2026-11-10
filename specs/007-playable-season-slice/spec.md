# M007 Specification — Single-Season Playable Vertical Slice

- **Milestone:** M007
- **Status:** APPROVED DESIGN CONTRACT (Owner Authorized 2026-11-09).
- **Core Priority:** Functional gameplay loop first. Offline basketball management experience.

---

## 1. Product Objective

Transform Ballgorithm from a technical simulation engine into a playable offline basketball management game.

### User Journey
$$\text{Start / Load League} \to \text{Select Franchise} \to \text{Review Roster \& Set Lineup} \to \text{Play Next Game} \to \text{Review Box Score} \to \text{Update Standings} \to \text{Round 14 Champion}$$

The game is offline-first, single-player, deterministic, and requires zero remote services or unapproved dependencies.

---

## 2. Core Domain Contracts

### 2.1 Schedule Architecture
- **League Size:** Exactly 8 generated teams.
- **Season Length:** Exactly 14 rounds.
- **Rounds & Fixtures:** 4 fixtures per round $\implies$ 56 total games.
- **Balance & Symmetry:**
  - Each team plays all 7 other teams exactly twice: once at home, once away.
  - Exactly 14 games per team (7 home, 7 away).
  - Each team plays exactly once per round (no bye rounds, no double-headers).
- **Deterministic Scheduling Algorithm:**
  - Canonical round-robin scheduling (Berger pairing / circle method) over 7 rounds for the first half, with reversed home/away assignments for the second 7 rounds.
- **Seed Derivation:**
  - Each fixture derives its simulation seed deterministically:
    $$\text{fixtureSeed} = \text{deriveGameSeed}(\text{leagueSeed}, \text{homeIdx}, \text{awayIdx}, \text{roundNumber})$$
  - Guarantees zero seed collisions and identical re-runs.

### 2.2 Franchise & Strategy Architecture
- **Franchise Ownership:** User selects and controls exactly one of the eight teams.
- **Persistent Strategy:**
  - Preferred starting five (`CourtLineup`, 5 unique roster players covering all slots).
  - Rotation plan (`RotationPlan`, preset or custom targets conserving 240 team minutes).
  - Automatically loaded for the user's team in every scheduled game.
- **AI Opponents:** Opponent franchises use canonical default starting lineups and balanced rotation presets.

### 2.3 Standings & Tie-Break Contract
- **Standings Table:**
  - Team, Wins ($W$), Losses ($L$), Win% ($W / (W + L)$), Points For ($PF$), Points Against ($PA$), Point Differential ($DIFF = PF - PA$), Current Streak ($W_k$ or $L_k$).
- **Deterministic Tie-Break Hierarchy:**
  1. Wins (descending)
  2. Point Differential (descending)
  3. Points For (descending)
  4. Team ID alphabetical string order (ascending)

### 2.4 Statistics Accumulator Contract
- **Player Season Totals:**
  - Games Played ($GP$), Minutes ($MIN$), Points ($PTS$), Field Goals ($FGM / FGA$), Three-Pointers ($3PM / 3PA$), Free Throws ($FTM / FTA$), Rebounds ($REB$), Assists ($AST$), Steals ($STL$), Blocks ($BLK$), Turnovers ($TOV$).
- **Averages & Rates:**
  - Per-game stats ($PTS/G$, etc.).
  - Shooting percentages are zero-denominator safe (return null when attempts $= 0$).
- **Game Archive:**
  - Store lightweight per-game summaries (teams, scores, period scoring, player box scores) to allow reviewing past games without re-simulation.

### 2.5 Round Progression & Transactional Safety
- **Round Advancement:**
  - User plays their scheduled matchup (via worker isolate and `GameScreen`).
  - The other 3 matchups of the round are simulated headlessly using core `GameSimulator`.
  - All 4 game results are committed in a single atomic transaction.
- **Idempotency & Integrity:**
  - Completed rounds cannot be simulated or committed again.
  - Simulation failure or app crash aborts cleanly without partial state mutation.

### 2.6 Persistence Contract
- **Save Schema Version:** Version 1.
- **Single Active Save Slot:** Saved locally as versioned JSON.
- **Persisted Elements:** Schema version, league seed, user franchise ID, season schedule, current round, saved lineup/rotation, completed game summaries, standings, player totals.
- **Corrupt Save Handling:** If parsing fails, report error; never overwrite or delete player save silently.

---

## 3. UI Navigation & Mobile Viewport

- **Information Hierarchy (360x640 compatible):**
  - **New Season Flow:** Franchise Selection Screen displaying all 8 teams with roster previews.
  - **Season Dashboard:**
    - Header: User team badge, record, standings rank.
    - Next Game Card: Opponent, Home/Away, Round indicator, "Play Next Game" primary action.
    - Navigation: Quick access to Team Management, Standings, and Schedule.
  - **Team Screen:** Complete roster with ratings, player profiles, and "Edit Lineup & Minutes" strategy editor.
  - **League Screen:** Real-time Standings table and 14-round schedule viewer with game box scores.
  - **Game Result:** Integrated `GameResultView` with "Continue Season" return action.
  - **End of Season Screen:** Displayed after Round 14 with Champion banner, final record, final standings, and confirmed "Start New Season" option.
