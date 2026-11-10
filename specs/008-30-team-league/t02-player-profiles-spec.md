# M008-T02 Specification — Player Age, Potential & Development Profiles

- **Milestone:** M008
- **Task:** T02
- **Status:** APPROVED SPECIFICATION

---

## 1. Product Objective

Extend the 30-team league architecture with persistent, deterministic player career profiles covering age, development potential, and career progression trajectories.

Career profiles are isolated from simulation-relevant player attributes to ensure that `GameFingerprint` and `GameSimulator v7` execution remain byte-identical and decoupled from career metadata.

---

## 2. Core Domain Contracts

### 2.1 Player Career Profile Model
Each of the 360 generated players in a 30-team league receives a `PlayerCareerProfile`:
- **`playerId` (`PlayerId`):** Stable identity matching the player's core identity (`player-{teamIndex}-{playerIndex}`).
- **`age` (`int`):** Professional age within the valid biological range of `19..38` inclusive.
- **`potential` (`int`):** Rating ceiling on a `0..100` scale.
  - *Definition:* Potential represents the hypothetical upper-bound ability ceiling a player could reach under favorable development conditions.
  - *Constraint:* Potential must be $\ge$ the player's current overall ability (`overallRating`), but cannot exceed 100.
  - *Non-Guarantee:* Potential is NOT an immediate gameplay bonus, does not boost current simulation performance, and does not guarantee that a player will reach that ceiling.
- **`trajectory` (`DevelopmentTrajectory`):** Enum defining career progression curve:
  - `earlyBloomer`: Reaches peak early (age 21–24), slower late growth, earlier decline.
  - `steady`: Balanced, predictable progression peaking around age 25–28.
  - `lateBloomer`: Slower early development, bursts in mid-to-late 20s (age 26–30), extended prime.
  - `volatile`: High-variance progression; boom-or-bust outcome.

### 2.2 Situation-Based Age and Potential Stratification
Career generation reflects franchise competitive situations while allowing realistic exceptions:

1. **Tanking / Rebuilding:**
   - Focus: Young prospects with high development upside.
   - Age distribution: Mean ~22.5 (majority 19–24), with 1–2 veteran mentors (age 30–33).
   - Potential distribution: High proportion of players with significant growth margin (+15 to +30 above current).
2. **Play-In Contender:**
   - Focus: Mixed roster of prospects and experienced rotation pieces.
   - Age distribution: Mean ~25.5 (range 20–34).
   - Potential distribution: Balanced upside and established ability.
3. **Playoff Team:**
   - Focus: Prime-age core ready to win now.
   - Age distribution: Mean ~27.0 (majority 24–29), plus select developmental prospects.
   - Potential distribution: Moderate growth margin; starters near peak capability.
4. **Championship Contender:**
   - Focus: Veteran stars and playoff-tested depth.
   - Age distribution: Mean ~29.0 (majority 27–34), with 1–2 young energetic bench pieces.
   - Potential distribution: Starters at or near peak (potential close to current ability); low overall development upside.

### 2.3 Determinism and Stream Isolation
- **Separate PRNG Stream:** Career profiles are generated using an independent seed derivation:
  $$\text{careerSeed} = (\text{leagueSeed} \oplus \text{0xCA5EE800}) \ \& \ \text{0x7FFFFFFF}$$
- **Zero PRNG Cross-Talk:** Because the career stream is completely disjoint from the attribute/name generator, the 360 player names, positions, attributes, and roster order for any given seed are 100% identical to M008-T01.
- **Legacy M001 Preservation:** Legacy 8-team leagues do not require career profiles; golden snapshots and simulation fingerprints remain byte-identical.

### 2.4 Future Rookie ID Compatibility Contract
- Inaugural 30-team players use: `player-{teamNumber}-{rosterIndex}` (e.g. `player-1-1` to `player-30-12`).
- Future rookie draft entrants will use: `player-rookie-{draftYear}-{overallPick}` (e.g. `player-rookie-2027-1`).
- The `player-rookie-` prefix guarantees zero identity collision across multiple seasons.

---

## 3. Draft Pick Guarantee Clarification

The draft picks associated with `FranchiseSituation` are clarified:
- Tanking: Pick #1
- Play-In: Pick #12
- Playoff: Pick #20
- Contender: Pick #30
- **Contract Rule:** These numbers represent the opening draft pick guaranteed to the **PLAYER-SELECTED FRANCHISE** in GM Career mode. They are NOT assigned to all AI franchises within the same tier (which would create illegal duplicate picks). Draft order allocation logic is deferred to future milestone tasks.
