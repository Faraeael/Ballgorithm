# M008-T01 Specification — 30-Team League & Situation-Based Generation

- **Milestone:** M008
- **Task:** T01 (Step 1 of GM Career System)
- **Status:** APPROVED SPECIFICATION

---

## 1. Product Objective

Extend Ballgorithm's deterministic league generation system from the legacy 8-team format to a full 30-franchise league with distinct competitive situations, representing the starting foundation for GM Career mode.

Legacy 8-team league generation must remain 100% byte-identical and backward-compatible.

---

## 2. Core Domain Contracts

### 2.1 League Scale & Team Catalog
- **League Size:** 30 fictional franchises (`team-1` through `team-30`).
- **Roster Size:** Exactly 12 players per franchise (360 total players).
- **Position Coverage:** Each team roster covers all 5 canonical positions (`PG`, `SG`, `SF`, `PF`, `C`).
- **Name Capacity:** 41 first names $\times$ 41 last names = 1,681 distinct pairs, comfortably accommodating 360 unique player names per league without collision.
- **Fictional Branding:** All 30 franchises are completely fictional; no real NBA/NCAA trademarks, logos, or active team branding.

### 2.2 Franchise Competitive Situations
Every franchise in the 30-team league belongs to one of four distinct competitive situations:

1. **Tanking / Rebuilding (`tanking`):**
   - Roster composition: Young, raw prospects with significant weaknesses; low current overall strength (team average attribute ~42–46).
   - Future draft asset contract: Opening draft pick #1.
2. **Play-In Contender (`playIn`):**
   - Roster composition: Middle-tier competitive roster; 1–2 reliable starters, clear positional weaknesses (team average attribute ~48–52).
   - Future draft asset contract: Opening draft pick #12.
3. **Playoff Team (`playoff`):**
   - Roster composition: Established winning core; high-quality starters and solid supporting rotation (team average attribute ~54–58).
   - Future draft asset contract: Opening draft pick #20.
4. **Championship Contender (`contender`):**
   - Roster composition: Elite championship-caliber starting five and deep, reliable bench (team average attribute ~60–65).
   - Future draft asset contract: Opening draft pick #30.

### 2.3 Tier Distribution & Team Identity
- **League Tier Allocation (30 Teams):**
  - Contenders: 5 teams (~17%)
  - Playoff Teams: 9 teams (30%)
  - Play-In Teams: 9 teams (30%)
  - Tanking Teams: 7 teams (~23%)
- **Non-Uniform Rosters:** Teams within the same tier exhibit distinct style profiles (e.g. perimeter shooting, interior defense, playmaking, athleticism) to prevent uniform or clone rosters.
- **Natural Gameplay Realism:** Differences in competitive performance emerge solely from player attributes interacting with the unchanged `GameSimulator v7` physics and probability model. No artificial or predetermined win caps are introduced.

### 2.4 Determinism & Backward Compatibility
- **Deterministic PRNG:** Identical seed + `GenerationConfig(teamCount: 30)` produces identical byte-for-byte serialized output.
- **M001 / M007 Invariant:** When `teamCount == 8`, `LeagueGenerator` executes the exact legacy generation path, preserving the golden 8-team snapshot (`29,263` bytes for seed `20261028`).

---

## 3. Frozen Future Career Integration Contracts (Non-Goals for T01)

The following items are defined for future milestone integration and are **STRICTLY EXCLUDED** from M008-T01:
- No rookie draft implementation (draft pick numbers recorded as metadata only).
- No 82-game schedule or schedule generation (M007 14-round schedule is for 8-team leagues only).
- No play-in tournament or playoff bracket logic.
- No player contracts, salaries, salary cap, or trading.
- No coaching staff or facilities.
- No age or potential attributes (deferred to M008-T02 to avoid breaking serialized contracts prematurely).
