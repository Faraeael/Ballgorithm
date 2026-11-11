# M008-T04 Specification — Persistent GM Career & Opening Offseason Foundation

- **Milestone:** M008
- **Task:** T04 (Persistent GM Career & Opening Offseason Foundation)
- **Status:** APPROVED SPECIFICATION

---

## 1. Product Objective

Transform the M008-T03 generation preview into a persistent GM Career foundation:
1. User confirms career creation after selecting a franchise and starting situation.
2. The entire 30-team league snapshot, 360 player profiles, user draft entitlement, career identity, and offseason state are saved.
3. User enters the Year 1 Opening Offseason overview.
4. Closing and reopening the app allows resuming the saved career with the exact same franchise, roster, player attributes, player ages, potentials, and draft pick.
5. Absolute storage isolation from the legacy M007 8-team season save.

---

## 2. Core Domain Contracts

### 2.1 Career Phase (`CareerPhase`)
Enumerates career progression phases:
- `openingOffseason`: Initial career state (Year 1). Pre-draft roster review and preparation.

### 2.2 GM Career State (`GmCareer`)
Authoritative career model containing:
- `id` (`String`): Unique career identifier (e.g., `career-<timestamp>-<hash>`).
- `schemaVersion` (`int`): Codec version (currently `1`).
- `generationSeed` (`int`): PRNG seed used at league creation.
- `userFranchiseId` (`TeamId`): The human-controlled franchise ID (`team-1` through `team-30`).
- `originalSituation` (`FranchiseSituation`): Historical starting situation selected at setup.
- `currentYear` (`int`): Career season year (starts at `1`).
- `phase` (`CareerPhase`): Current career lifecycle phase (`CareerPhase.openingOffseason`).
- `league` (`League`): Authoritative 30-team league snapshot with all 360 players.
- `careerProfiles` (`LeagueCareerProfiles`): All 360 player career profiles (age, potential, trajectory).
- `userOpeningDraftPick` (`int`): Guaranteed opening draft entitlement (#1, #12, #20, #30).

### 2.3 Career Codec (`GmCareerCodec`)
Deterministic JSON serializer/deserializer with strict domain validation:
- Validates schema version (`1`).
- Validates 30 unique franchises in league snapshot.
- Validates 360 total players (12 per team).
- Validates user team presence in league snapshot.
- Validates complete career profile coverage for all 360 player IDs.
- Validates guaranteed draft pick matches `originalSituation.userOpeningDraftPick`.
- Validates career year >= 1 and career phase.
- Reconstructs exact league and roster without regenerating from seed.

### 2.4 Storage Layer (`GmCareerStorage`)
Independent storage mechanism strictly isolated from M007 season saves:
- Interface: `read()`, `write(String data)`, `clear()`, `hasSave()`.
- Implementation: `FileGmCareerStorage` targeting `ballgorithm_gm_career.json` (distinct from `ballgorithm_save.json`).
- Atomic writes via `.tmp` file and rename/replace.
- Safe backup retention via `.bak` file.
- Corrupt save handling: reports error, never silently erases.
- Overwrite protection: user confirmation required before replacing an existing career.

### 2.5 Seed Provider
Replaces the 35-minute repeating microseconds mask with an entropy-based non-zero 31-bit seed generator:
- Value in `[1, 0x7FFFFFFF]`.
- Injectable for test determinism.

---

## 3. Acceptance Criteria

- **AC-008-32 (Career State Creation):** New GM Career initialized with valid ID, schema version 1, Year 1, Opening Offseason phase, 30 teams, 360 players, 360 career profiles, and correct user draft pick.
- **AC-008-33 (Save/Load Round-Trip):** Encoding and decoding produces byte-identical or functionally identical `GmCareer` state.
- **AC-008-34 (Roster & Profile Preservation):** Reloading career retains exact player names, attributes, ages, potentials, and trajectories without regeneration.
- **AC-008-35 (Franchise & Situation Preservation):** Selected team ID, original situation, and draft pick persist across reloads.
- **AC-008-36 (Corrupt Save Protection):** Invalid JSON or schema mismatch returns explicit typed error without destroying disk file.
- **AC-008-37 (Atomic Write & Recovery):** Write failure does not corrupt active save; backup can recover prior valid save.
- **AC-008-38 (M007 Storage Isolation):** GM Career operations never read, write, or erase `ballgorithm_save.json`.
- **AC-008-39 (Opening Offseason UI):** Screen displays franchise info, roster table with age/potential, draft pick, and disabled future categories.
- **AC-008-40 (Overwrite Confirmation):** Starting new career with existing save requires explicit user confirmation.
- **AC-008-41 (Responsive Mobile UI):** Offseason UI renders without overflow on 360x640 viewport.
