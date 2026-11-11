# M008-T05 Specification — Opening Rookie Draft Foundation

- **Milestone:** M008
- **Task:** T05 (Opening Rookie Draft Foundation)
- **Status:** APPROVED SPECIFICATION

---

## 1. Product Objective

Build the persistent rookie draft ecosystem for Ballgorithm's 30-team GM career mode:
1. Complete 2-round, 60-pick opening draft order structured by competitive franchise situation tiers.
2. Guaranteed Year 1 user draft selections matching established franchise situation promises (#1 Tanking, #12 Play-In, #20 Playoff, #30 Contender).
3. Persistent rookie prospect pool of exactly 90 players (ages 19–22, 5 positions, realistic archetype diversity).
4. Public prospect ranking system with realistic evaluation uncertainty that correlates with player quality without perfectly revealing true potential.
5. Estimated potential grade and range presentation in the public UI, keeping internal true potential ceiling and developmental trajectory hidden.
6. Versioned persistence upgrade (`schemaVersion: 2`) with backwards-compatible, deterministic migration from v1 saves.
7. Mobile-first, responsive read-only Draft Board UI accessible from the Year 1 Opening Offseason screen.

---

## 2. Core Domain Contracts

### 2.1 Draft Selection (`DraftPick`)
Immutable model representing one draft entitlement:
- `round` (`int`): Round number (`1` or `2`).
- `pickInRound` (`int`): Selection number within the round (`1..30`).
- `overallPick` (`int`): Absolute selection number (`1..60`).
- `originalOwnerTeamId` (`TeamId`): Franchise that originally owned the selection.
- `currentOwnerTeamId` (`TeamId`): Franchise currently holding the selection (supports future trades; equals original owner in Year 1).

### 2.2 Draft Order (`DraftOrder`)
Ordered collection of exactly 60 `DraftPick` instances:
- Round 1 (overall picks 1–30):
  - Picks 1–7: Tanking franchises (7 teams).
  - Picks 8–16: Play-In franchises (9 teams).
  - Picks 17–25: Playoff franchises (9 teams).
  - Picks 26–30: Contender franchises (5 teams).
  - Guaranteed user slot: Tanking gets #1, Play-In gets #12, Playoff gets #20, Contender gets #30. Other teams within each tier are ordered deterministically by PRNG seed.
- Round 2 (overall picks 31–60):
  - Mirrors Round 1 team order initially (Pick 31 owned by Pick 1 team, ..., Pick 60 owned by Pick 30 team).
  - Guaranteed user slot: Tanking gets #31, Play-In gets #42, Playoff gets #50, Contender gets #60.

### 2.3 Rookie Prospect (`RookieProspect`)
Model representing an eligible draft prospect:
- `id` (`PlayerId`): Unique identifier (e.g., `prospect-y1-1` through `prospect-y1-90`), strictly non-colliding with league player IDs.
- `firstName` (`String`): First name from fictional corpus.
- `lastName` (`String`): Last name from fictional corpus.
- `position` (`Position`): One of the 5 canonical positions (PG, SG, SF, PF, C).
- `age` (`int`): Biological age between 19 and 22.
- `attributes` (`PlayerAttributes`): Standard 12-attribute map (0..100) and unweighted overall rating.
- `potential` (`int`): Internal true ceiling (`overallRating <= potential <= 100`).
- `trajectory` (`DevelopmentTrajectory`): Internal progression curve (`earlyBloomer`, `steady`, `lateBloomer`, `volatile`).
- `projectedRank` (`int`): Public projected draft rank (`1..90`), determined via imperfect noisy evaluation model.
- `estimatedPotentialGrade` (`String`): Public scouting grade (`A+`, `A`, `A-`, `B+`, `B`, `B-`, `C+`, `C`).
- `estimatedPotentialRange` (`String`): Public scouting range (e.g., `85-91`, `74-80`).

### 2.4 Rookie Draft Class (`RookieDraftClass`)
Class container holding:
- `seasonYear` (`int`): Career draft year (`1`).
- `prospects` (`List<RookieProspect>`): Exactly 90 unique prospects sorted by `projectedRank`.

### 2.5 Career Persistence & Migration (`GmCareer` & `GmCareerCodec`)
- Schema upgrade: `schemaVersion = 2`.
- `GmCareer` holds `draftOrder` (`DraftOrder`) and `draftClass` (`RookieDraftClass`).
- `GmCareerCodec.decode()` accepts both schema versions `1` and `2`:
  - When decoding schema `1`: deterministically generates `draftOrder` and `draftClass` using career `generationSeed`, `userFranchiseId`, and `originalSituation`.
  - When decoding schema `2`: deserializes saved `draftOrder` and `draftClass` directly from JSON.
  - Re-saving migrates to schema `2`, ensuring prospects are never regenerated on subsequent sessions.

---

## 3. Acceptance Criteria

- **AC-008-42 (Prospect Pool Completeness & Uniqueness):** Exactly 90 unique prospects generated for Year 1 opening draft, with unique IDs, names, and all 5 canonical positions represented.
- **AC-008-43 (Draft Order Completeness):** Exactly 60 draft picks across 2 rounds (30 per round), with each round containing all 30 franchises without duplicates or omissions.
- **AC-008-44 (Round 2 Mirroring & Ownership):** Round 2 order mirrors Round 1 order initially. Each `DraftPick` tracks `originalOwnerTeamId` and `currentOwnerTeamId`.
- **AC-008-45 (Situation-Tiered Draft Allocation & User Guarantees):** Round 1 allocates picks 1–7 to Tanking, 8–16 to Play-In, 17–25 to Playoff, 26–30 to Contender. The human user is guaranteed pick #1 (Tanking), #12 (Play-In), #20 (Playoff), or #30 (Contender).
- **AC-008-46 (Prospect Age & Physical/Attribute Conformity):** All prospects are aged 19–22. Attributes conform to `PlayerAttributes` system (0–100), with overall rating computed as the unweighted mean.
- **AC-008-47 (Prospect Potential & Development Trajectory):** Internal potential ceiling is in `[overallRating, 100]` with diverse developmental trajectories across archetypes (high-potential projects, immediate role players, high-floor limited ceiling, late bloomers, early peak).
- **AC-008-48 (Public Projected Ranking & Evaluation Uncertainty):** Imperfect evaluation model produces projected rankings (1–90) that correlate with true talent (overall rating and potential) but do not perfectly match true potential sorting.
- **AC-008-49 (Scouting Estimation Grade & Range):** Public prospect evaluation displays estimated potential grades and ranges, never exposing raw true potential or internal noise.
- **AC-008-50 (Deterministic Generation & Seed Sensitivity):** Identical seeds produce byte-identical draft order and prospect pools; different seeds yield distinct classes.
- **AC-008-51 (ID Isolation & Anti-Collision):** Prospect IDs never collide with current or future league player IDs.
- **AC-008-52 (Career Persistence & Round-Trip):** `GmCareer` v2 schema encodes and decodes the complete draft order and draft class without regeneration or data loss.
- **AC-008-53 (v1-to-v2 Schema Migration):** Existing v1 saves seamlessly decode and migrate to v2, deterministically synthesizing the draft order and prospect pool while preserving all existing career data.
- **AC-008-54 (Draft Class Stability on Reload):** Once persisted, the opening prospect class is loaded from disk and never regenerated on career resume.
- **AC-008-55 (Draft Board UI & Mobile Responsive Layout):** Draft board unlocks in offseason overview, providing interactive draft order and prospect pool views at 360x640 without overflow.
