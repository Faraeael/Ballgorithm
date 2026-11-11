# M008-T08A Specification — Persistent Free Agent Pool

Status: implemented on `feat/m008-t08a-free-agent-pool` (baseline `0a45f51`).
Scope: the free-agent universe only. No acquisition, contracts, salaries or UI.

## 1. Objective

Add a persistent, deterministic population of 90 unsigned free agents to every GM
career, independent of the 360 rostered players and 90 draft prospects, with stable
identities, full attributes and protected career profiles.

## 2. Data ownership

- `FreeAgentPool` is the single authoritative free-agent collection in `GmCareer`.
- Each `FreeAgentEntry` owns a `Player` and its `PlayerCareerProfile`.
- Free agents never appear in any `Team.roster`, `RookieSigningLedger`, `DraftRights`,
  `AiRookieSigningState` or `LeagueCareerProfiles`.
- Career profiles for free agents stay inside their entries until a future authorized
  transaction moves the player to a franchise; that transaction will move the profile
  into `LeagueCareerProfiles` and add a contract/roster membership.
- Free agents are not draft prospects: no projected rank, scouting grade or rights.

## 3. Generation

`FreeAgentGenerator` uses one isolated stream:

```
DeterministicRandom((seed ^ 0xFA5E0001) & 0x7FFFFFFF)
```

No existing league, draft, profile or AI stream is touched. Draw order:
name-pair shuffle, position shuffle, then per entry age, target base, 12 attribute
noise draws (Irwin-Hall(3) × 18), potential margin, trajectory.

Pre-registered rules:

| Property | Rule |
|---|---|
| Count | exactly 90 |
| Positions | 18 per position, shuffled |
| Age bands | 35% 20–23, 40% 24–29, 25% 30–36 |
| Target base overall | young 56–70, prime 62–80, veteran 58–75 |
| Attributes | position archetype offsets, noise, clamped 20–95 |
| Potential margin | ≤21: 8–28; 22–24: 4–18; 25–28: 1–8; ≥29: 0–2 |
| Trajectory | uniform across the four trajectories |
| Identity | `free-agent-1` … `free-agent-90`, stable per index |
| Names | unique within the pool; names are not identity |

## 4. Public contract

`PublicFreeAgentView` exposes id, names, position, age, attributes and overall rating
only. Hidden potential and trajectory never leave `FreeAgentEntry`. No new scouting
system is introduced.

## 5. Persistence

- Schema v7 adds `freeAgentPool`; v7 requires it.
- v1–v6 decode deterministically generates the pool from the career seed and stores it
  on the next save. League, draft order, draft class, selections, rights, contracts,
  AI decisions, rosters, profiles and the human franchise are preserved untouched.
- Once saved, the pool is canonical state and is never regenerated on load.
- Validation rejects: missing/malformed v7 pool, wrong size, duplicate IDs, ID
  collisions with rosters/prospects/contracts/rights/decisions/profiles, invalid ages
  (outside 20–36), invalid potential (< overall or > 100), malformed attributes,
  profile/player mismatch, and fewer than 12 free agents at any position.
- Atomic saves, backup recovery and M007 isolation are unchanged.

## 6. Future contract/finance boundary (documentation only)

A later acquisition system will create a `FreeAgentContract` record carrying contract
id, player id, franchise id, category, duration and salary obligations, keyed into
team payroll and budget/cap rules. Rookie contracts remain a separate ledger; both
will feed one payroll model. Staff, coaching and facilities costs will use the same
budget authority. T08A defines no salary, cap or budget numbers and creates no
zero-cost contracts.

## 7. Acceptance Criteria

- **AC-T08A-01** Every new career has exactly 90 free agents.
- **AC-T08A-02** Identical seeds produce identical pools; different seeds differ.
- **AC-T08A-03** Free-agent IDs are unique.
- **AC-T08A-04** No free-agent ID matches a rostered player.
- **AC-T08A-05** No free-agent ID matches a draft prospect.
- **AC-T08A-06** All five positions are present with at least 12 each.
- **AC-T08A-07** Attributes are valid integers within 0–100.
- **AC-T08A-08** Every free agent has a valid career profile (potential ≥ overall).
- **AC-T08A-09** Ages are within 20–36.
- **AC-T08A-10** Free agents have no franchise ownership or contract.
- **AC-T08A-11** Existing league rosters are unchanged.
- **AC-T08A-12** The rookie draft order, class, selections and rights are unchanged.
- **AC-T08A-13** Existing human and AI signings are unchanged.
- **AC-T08A-14** Save/load preserves the pool byte-for-byte.
- **AC-T08A-15** v1–v6 saves migrate without data loss.
- **AC-T08A-16** A persisted pool is never regenerated on load.
- **AC-T08A-17** Corrupted v7 pool data is rejected.
- **AC-T08A-18** Public evaluation exposes no hidden potential or trajectory.
- **AC-T08A-19** M007 storage remains isolated.
- **AC-T08A-20** League readiness reporting is unchanged by the pool.
- **AC-T08A-21** Core and Flutter regression suites pass.

## 8. Non-goals

Free-agent signing, bidding, negotiations, salaries, cap, AI offers, transfers,
waivers, expiration, two-way conversion, retirement, development, new drafts,
coaching, staff, facilities, season advancement, free-agency UI.
