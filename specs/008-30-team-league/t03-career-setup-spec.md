# M008-T03 Specification — Team Selection & Situation-Driven League Generation

- **Milestone:** M008
- **Task:** T03 (GM Career Setup Sequence & Generation)
- **Status:** APPROVED SPECIFICATION

---

## 1. Product Objective

Implement the initial franchise and situation selection workflow for the Ballgorithm GM Career system:
1. User selects any one of the 30 fictional franchises.
2. User selects the starting competitive situation for that franchise.
3. User confirms league generation.
4. Engine deterministically generates all 30 teams, 360 players, and 360 career profiles, with the user's chosen franchise guaranteed to receive their selected competitive tier.
5. User views a generated roster and league overview preview.

This workflow is an isolated setup preview; full offseason career simulation and 82-game scheduling are deferred to future tasks.

---

## 2. Core Domain Contracts

### 2.1 Career Setup Request (Inputs)
A career generation request is defined by:
- **`selectedTeamId` (`TeamId`):** The stable identifier of the franchise chosen by the player (e.g. `team-1` through `team-30`).
- **`selectedSituation` (`FranchiseSituation`):** The competitive starting situation selected by the player:
  - `tanking`: Rebuilding roster, low current strength, high development upside; opening draft pick #1.
  - `playIn`: Middle-tier competitive roster, moderate current strength; opening draft pick #12.
  - `playoff`: Strong established core, high-quality starters; opening draft pick #20.
  - `contender`: Elite starting five and deep bench, championship-caliber; opening draft pick #30.
- **`seed` (`int`):** PRNG generation seed determining all deterministic draws.

### 2.2 Controlled Situation Allocation (Preserving League Balance)
The 30-team league strictly preserves its competitive macro-balance across all career configurations:
- **Total Tiers:**
  - 7 Tanking teams
  - 9 Play-In teams
  - 9 Playoff teams
  - 5 Championship Contenders
  - Total = exactly 30 teams.

**Allocation Algorithm:**
1. Generate the canonical deterministic tier assignment for all 30 positions using `DeterministicRandom(seed ^ 0x51704710)`.
2. Locate the index of `selectedTeamId` within the catalog (`userIndex`).
3. If `situations[userIndex] == selectedSituation`, the natural assignment already matches; no swap needed.
4. If `situations[userIndex] != selectedSituation`:
   - Scan for the lowest index `swapIndex` where `situations[swapIndex] == selectedSituation` (with `swapIndex != userIndex`).
   - Exchange `situations[userIndex]` and `situations[swapIndex]`.
5. This guarantees that:
   - The user franchise is assigned **exactly** the selected situation.
   - The league totals remain invariant (7/9/9/5).
   - No duplicate teams or unassigned franchises exist.
   - The swap is 100% deterministic and reproducible for the same seed and inputs.

### 2.3 Situation-Driven Roster & Career Profile Generation
- Once situations are assigned, the 360 players are generated using the finalized tier mappings:
  - The user's franchise receives the attribute baselines, star weighting, and player tendences of the chosen situation.
  - The user's franchise receives the age distribution, development upside, and trajectories corresponding to that situation.
- The same franchise can be selected as Tanking, Play-In, Playoff, or Contender across different new careers, generating completely different rosters appropriate to the chosen situation.

### 2.4 User Draft Pick Entitlement
- The opening rookie draft pick (#1, #12, #20, or #30) is awarded as an entitlement metadata contract to the **human-controlled franchise only**.
- AI franchises are not assigned duplicate picks; full 30-team draft order allocation belongs to a future milestone task.

---

## 3. Career Setup Preview UI Flow

The UI preview provides a dedicated, non-destructive preview flow accessible without altering or overriding existing M007 season saves:

- **Screen 1 — Select Team:**
  - Browse and select from all 30 fictional franchises.
  - Displays team name, city/region, and abbreviation.
  - Roster generation has not occurred yet.
- **Screen 2 — Select Starting Situation:**
  - Presents the four competitive tiers: Tanking, Play-In, Playoff, Contender.
  - Displays plain-language explanation, expected roster profile, and guaranteed opening draft pick.
  - User confirms selection.
- **Screen 3 — Generated League Preview:**
  - Executes deterministic generation in memory.
  - Header: Selected team name, situation badge, guaranteed opening draft pick.
  - Roster Table: 12 generated players with name, position, age, current overall rating, and development potential ceiling.
  - League Summary: Breakdown of competitive tiers across the 30 teams (7 Tanking, 9 Play-In, 9 Playoff, 5 Contender).
  - Explicitly labeled as a preview; does not save or overwrite the active M007 season.
