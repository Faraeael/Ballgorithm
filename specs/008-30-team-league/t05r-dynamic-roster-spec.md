# M008-T05R Specification — Dynamic Roster Architecture Foundation

- **Milestone:** M008
- **Task:** T05R (Dynamic Roster Architecture Foundation)
- **Status:** APPROVED SPECIFICATION

---

## 1. Product Objective

Replace the fixed 12-player roster constraint with a flexible, NBA-aligned roster architecture for Ballgorithm's 30-team GM career mode:
1. Preserve the initial 30-team / 360-player generation contract (exactly 12 players per franchise at league creation).
2. Establish formal roster categories: `standard`, `twoWay`, and `trainingCamp`.
3. Support phase-aware roster capacity limits:
   - **Opening Offseason:** Max 15 standard, max 3 two-way, total contracted <= 21. Initial 12-player rosters remain structurally valid.
   - **Regular Season:** Exactly 14–15 standard players, max 3 two-way, 0 training camp, total contracted <= 18.
4. Establish clear distinction between structural validity (within capacity limits) and regular-season readiness (meets minimum standard players and zero training-camp invites).
5. Ensure owned draft rights (`DraftPick` & `RookieProspect`) and free agents remain strictly outside contracted franchise rosters until signed.
6. Upgrade career persistence to `schemaVersion: 3` with backwards-compatible, non-destructive migration from v1 and v2 saves.
7. Maintain 100% compatibility with existing game simulation and rotation expansion engines.
8. Expose read-only roster breakdown in the Year 1 Opening Offseason UI.

---

## 2. Core Domain Contracts

### 2.1 Roster Category (`RosterCategory`)
Enumeration representing player contract designations:
- `standard` (`'standard'`): Full standard player contract (max 15). Eligible for regular season and active game rotation.
- `twoWay` (`'twoWay'`): Two-way developmental contract (max 3). Does not count against the 15 standard-player maximum.
- `trainingCamp` (`'trainingCamp'`): Offseason invitee contract. Permitted only in offseason phases; must be waived or converted before regular season.

### 2.2 Roster Membership (`RosterMembership`)
Immutable player-to-category binding:
- `playerId` (`PlayerId`): Reference to player.
- `category` (`RosterCategory`): Active contract category.

### 2.3 Roster Capacity Rules (`RosterRules`)
Authoritative constants and validation logic:
- Offseason capacity:
  - `maxOffseasonStandard = 15`
  - `maxOffseasonTwoWay = 3`
  - `maxOffseasonTotal = 21`
- Regular-season capacity & readiness:
  - `minRegularSeasonStandard = 14`
  - `maxRegularSeasonStandard = 15`
  - `maxRegularSeasonTwoWay = 3`
  - `maxRegularSeasonTotal = 18`
  - `maxRegularSeasonTrainingCamp = 0`
- Initial generation baseline:
  - `initialGenerationSize = 12` (all `standard`)

### 2.4 Franchise Roster (`Roster`)
Enhanced pure Dart roster model:
- `players` (`List<Player>`): Authoritative list of contracted players.
- `categories` (`Map<String, RosterCategory>`): Authoritative mapping from player ID to category (defaults to `standard` for all players).
- Derived collections: `standardPlayers`, `twoWayPlayers`, `trainingCampPlayers`.
- Derived counts: `standardCount`, `twoWayCount`, `trainingCampCount`, `totalContractedCount`.
- Phase-aware validation:
  - `validateStructure(CareerPhase phase)`: Enforces offseason (<= 15 standard, <= 3 two-way, <= 21 total) or in-season caps.
  - `validateRegularSeasonReadiness()`: Enforces 14–15 standard, <= 3 two-way, 0 training camp.
- Immutable mutations: `withPlayer()`, `withoutPlayer()`, `withCategory()`.

### 2.5 Authoritative Ownership & Mutex
- Every contracted player on `team.players` belongs to exactly that team.
- A player cannot appear on multiple franchise rosters across the 30-team league.
- Unassigned free agents and unsigned draft prospects exist outside `team.players` and consume zero roster slots.

---

## 3. Acceptance Criteria

- **AC-008-56 (Initial Generation Integrity):** New career generation continues to create exactly 30 teams and 360 players (12 standard players per team).
- **AC-008-57 (Dynamic Roster Categories):** Supports `standard`, `twoWay`, and `trainingCamp` membership designations per player.
- **AC-008-58 (Offseason Roster Capacity Limits):** Offseason limits enforced: <= 15 standard, <= 3 two-way, total contracted <= 21. Standard > 15, two-way > 3, or total > 21 is rejected.
- **AC-008-59 (Opening Offseason Compliance):** Opening Offseason permits rosters with 12 standard players, 15 standard players, 15 standard + 3 two-way, and 15 standard + 3 two-way + 3 training camp (21 total).
- **AC-008-60 (Regular Season Readiness Invariants):** Season-readiness validation requires 14–15 standard players, <= 3 two-way players, 0 training camp players, total <= 18. Rosters with < 14 standard or > 0 training camp fail season-readiness check.
- **AC-008-61 (Single Franchise & Category Mutex):** Each contracted player belongs to at most one franchise and occupies exactly one category. Duplicate membership across teams or categories is rejected.
- **AC-008-62 (Draft Rights Separation):** Owned draft rights (`DraftPick`) do not consume contracted roster slots until formally signed.
- **AC-008-63 (Free Agent Isolation):** Uncontracted free agents do not occupy any franchise roster slots.
- **AC-008-64 (Simulation Engine Compatibility):** Game simulation and rotation expander remain stable with variable rosters (5 to 21 players); players beyond active rotation receive 0 target seconds without error.
- **AC-008-65 (Schema Version 3 Migration & Backward Compatibility):** `GmCareer` upgraded to `schemaVersion = 3`. Codec decodes v1 and v2 saves, automatically synthesizing default standard roster memberships without data loss. Re-saving writes v3.
- **AC-008-66 (Save/Load Round-Trip with Dynamic Rosters):** Persisting and loading careers with expanded rosters (e.g. 15 standard, 2 two-way, 1 training camp) preserves exact player assignments and categories.
- **AC-008-67 (M007 Save Storage Isolation):** Storage operations remain strictly isolated; M007 season save is untouched.
- **AC-008-68 (Opening Offseason UI Roster Breakdown):** UI displays current roster composition breakdown (Standard X/15, Two-Way Y/3, Training Camp Z, Total /21) and renders responsively at 360x640.
