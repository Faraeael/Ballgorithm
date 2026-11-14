# M009-T04 — Full-Season Reliability & Historical Game Integrity

**Status:** Implementation authorized; specification established before production changes.
**Scope:** Regular-season career persistence, historical result validation, full-season reliability evidence.
**Non-goals:** Game-balance changes, playoffs, roster/economic progression, season rollover, M007 changes.

## Problem

Schema v17 validates each completed game by rebuilding its `GameInput` from the current career roster and current simulation-version constants. Legitimate future roster changes can invalidate an old result, and a simulation upgrade can reject a result produced by an older supported engine. Rebuilding game inputs also repeats full-league serialization during season validation.

## Decision

Schema v18 stores immutable game-time simulation evidence:

- Store each distinct canonical simulation `League` snapshot once, keyed by SHA-256 of its canonical JSON.
- Store each result's exact canonical `GameFingerprint` payload template with only the `league` value replaced by a unique snapshot reference.
- Preserve fixture identity, original input fingerprint, seed, existing result/box-score values, and the complete simulation/rules/event/fingerprint/PRNG/core-engine/league-schema version tuple.
- Validate player ownership and box-score player identities against the persisted game-time league snapshot, never the current roster.

- Exact `GameFingerprint.canonicalPayload` order: `fingerprintVersion`, full canonical `league`, `homeTeamId`, `awayTeamId`, `homeLineup`, `awayLineup`, `gameSeed`, `normalizedSeed`, `rules`, optional `rotationPlan`, and `versions` (`simulation`, `rules`, `eventSchema`, `prng`, `coreEngine`, `leagueSchema`). Rules include `rulesVersion`, `periods`, `periodSeconds`, `overtimeSeconds`, and `maxOvertimes`. Store full game-time league once; preserve remaining canonical payload unchanged.
- Reconstruct the original canonical payload from the result template and snapshot, then verify its fingerprint. Require the stored snapshot digest and canonical JSON to agree.
- Keep the current v17 game profile supported: simulation 7, rules 3, event schema 3, fingerprint 5, PRNG `xorshift32-v1`, core engine `1.0.0`, league schema 1. Add explicit validators for future profiles; reject unknown profiles without rerunning or relabeling results.
- Migrate v17 results only after legacy v17 validation succeeds against their unchanged career state. Capture the already-validated input, confirm its original fingerprint, preserve the result exactly, and do not simulate again. v1–v16 saves remain result-free and never auto-start a season.

Content addressing and fingerprints establish internal save consistency, not authenticity against an attacker who can rewrite an unsigned local save and recompute every digest. The persisted league snapshot—not its hash—is the historical ownership evidence.

The independent JEV review selected the deduplicated snapshot design (B, confidence 1.0). It assessed migration safety at 0.67; implementation must therefore enforce the legacy-validation-and-exact-fingerprint gate above and provide migration tests. JEV assessed that hashes do not authenticate attacker-rewritten unsigned saves (noul 0.05).

## Acceptance criteria

1. A completed result remains valid after current roster membership or player attributes change, provided its immutable stored evidence remains valid.
2. Historical result ownership, lineup ownership, fixture/team identity, seed, box-score players, and result fingerprint validate from game-time evidence.
3. Result validation does not reconstruct historical inputs from the current roster after v18 migration.
4. The original fingerprint and all existing score, period, box-score, and version values remain unchanged through migration and save/load.
5. Unknown or unsupported result-version profiles fail closed; supported historical metadata remains distinct from current engine constants.
6. Valid v1–v16 careers migrate without generated results. Valid v17 careers migrate only after old-state validation and exact evidence/fingerprint reconciliation. Corrupt v17 results are rejected.
7. Native v18 saves reject missing, malformed, orphaned, or inconsistent snapshots/evidence, duplicate results, and fixture/result disagreement.
8. No game is rerun or result regenerated during migration, validation, or reload. M007 season storage and behavior remain unchanged.
9. Seed `20261028`, situation `Play-In`, completes all 82 rounds and exactly 1,230 games. No skipped, repeated, or partial round; every franchise plays 82 games; league totals are 1,230 wins and 1,230 losses; no year advancement or playoffs.
10. Uninterrupted and checkpointed runs at rounds 1, 10, 25, 41, 60, 81, and 82 produce identical results, standings, schedule, contracts, identities, and final canonical career serialization.
11. Pre-promotion and post-promotion uncertain-write recovery at early, middle, and late progression reconciles through explicit reload and matches uninterrupted execution without automatic retries or duplicate games.
12. Diagnostics report validation, simulation, serialization, decode, save-promotion, standings, schedule-query time, encoded size, and measurable memory at 0, 15, 150, 375, 615, 900, and 1,230 games.
13. Basketball quality diagnostics report requested distributions and OVR-versus-wins observations without changing simulation parameters.
14. Overview, standings, schedule, results, and box-score screens remain usable at 360x640 and 393x852 for early, midseason, and complete saves. Historical full-season data are not all rebuilt into widgets at once.
15. Core and Flutter analysis/tests, migration, recovery, schedule, and M007 isolation gates pass. The final diff contains only T04 work plus any preserved user changes.

## Verification record

- Baseline: `feat/m009-t03-season-gameplay`, commit `2acf18a769cbabf27a12dcce8d753e53dd0fe044`.
- T04 branch: `feat/m009-t04-full-season-reliability`.
- Existing T03 evidence: core tests 952 passed; Flutter tests 234 passed; analyses clean; six ready-career Round 1 save/reload cases and one sequential Rounds 1–3 case. These are baseline evidence, not T04 completion evidence.
- Preserved user file at start: `specs/008-30-team-league/t08g-p1-allocation-current.md` (untracked; out of T04 scope).
