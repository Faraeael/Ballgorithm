# M009-T01 — Regular Season Entry Foundation

Status: owner-authorized implementation contract. The 82-game schedule contract is explicitly approved; fixture generation is deferred to M009-T02.

## 1. Objective

Transition a fully cleared M008 career into its first regular-season state. Reject incomplete or invalid careers without changing their saved state. T01 creates no fixtures and simulates no games.

## 2. Governing contracts and audit

- `GmCareer` is the persistent 30-franchise aggregate at schema v14. Its validator checks team/player identity, roster membership, draft and rookie decisions, market history, clearance, hardship, contracts, financial schedules, cap, and cash.
- `OffseasonReadinessGate` is the sole readiness authority. It evaluates all 30 teams, offseason completion, recovery state, and `GmCareer.validate()`; T01 must not reproduce its rules.
- `RosterRules.validateRegularSeasonReadiness()` requires 14–15 standard players, at most 3 two-way players, no training-camp players, and at most 18 contracted players.
- `CareerPhase` currently contains only `openingOffseason`. M009 adds `regularSeason`; existing career transactions remain offseason-only.
- Existing M007 `SeasonState` and `SeasonSchedule` implement a 14-game, 8-team format. The schedule generator rejects non-8-team leagues. M008-T01 explicitly excluded 82-game schedule generation for its 30-team league. T01 must not reuse or modify M007's season save or schedule implementation.
- `GmCareerStorage` provides serialized career writes, atomic promotion, backup recovery, and isolation from M007 `SeasonStorage`. Controller commands publish state only after successful persistence and require reload after uncertain writes.
- Employment is represented by `PlayerContract`; annual salary schedules and team finances belong to `CareerFinances`. T01 preserves these records and relies on full career validation.

## 3. Authoritative entry conditions

Entry requires all of the following:

1. Rookie draft complete; no AI rookie decisions pending.
2. Both free-agency market rounds complete and no round unresolved.
3. Original clearance complete and explicitly marked cleared.
4. Hardship settlement complete or validly unnecessary; no unresolved settlement.
5. `OffseasonReadinessGate.evaluate(career, recoveryRequired: false)` returns `cleared` with all 30 franchises ready.
6. Full `GmCareer.validate()` succeeds, including roster employment, contract schedules, financial authorization, cash solvency, ownership, and free-agent accounting.
7. Controller has no save-recovery obligation.
8. Career remains in `openingOffseason`, with no existing regular-season state.
9. Human confirms the transition in the UI. Cancel performs no write.

The service re-evaluates the gate at command time. `readyForConfirmation` is insufficient; the existing offseason-cleared confirmation must already be committed. Blocked entry returns the gate's reasons and per-franchise needs. It cannot mutate rosters, contracts, finances, or season state.

## 4. Initial regular-season state

Add a minimal immutable `RegularSeasonState` to `GmCareer`:

- Deterministic season ID derived from persisted career ID and current year.
- Season year equal to `GmCareer.currentYear`; T01 does not increment the year.
- Persisted schedule seed equal to existing `GmCareer.generationSeed`.
- Frozen opening team identities (team ID, name, abbreviation); no player roster copies.
- Empty game-result ledger.
- Zero completed games, derived from the empty ledger.
- No wall-clock timestamp, fixture, standings copy, player-stat copy, or game simulation.

`GmCareer.phase` becomes `regularSeason` exactly once. A season state exists iff phase is `regularSeason`; both state and phase must agree with the career year and team identities. A repeated start is rejected.

## 5. Owner-approved schedule contract — generation deferred

The owner approved this 30-team schedule contract:

- 82 games per franchise; 1,230 total games.
- Every franchise plays all 29 opponents.
- Twelve opponents are played four times each: twice home and twice away.
- The remaining 17 opponents are played twice each: once home and once away.
- Opponent counts are reciprocal; each team finishes 41 home and 41 away.
- No conference or division structure is approved or may be invented.
- Schedule generation must be deterministic from the persisted season seed.

T01 persists the seed only. It generates no schedule, exposes no next-game fixture, and records no result. M009-T02 owns opponent selection, the 1,230-game fixture calendar, collision/reciprocity/home-away validation, and gameplay linkage.

## 6. Persistence and migration

- Upgrade career schema to v15 only as needed for `RegularSeasonState`.
- Migrate valid v1–v14 saves without starting a season or changing existing entities. Legacy saves receive no regular-season state and remain in their saved phase.
- Native v15 saves require the regular-season field. Opening-offseason saves require it to be null; regular-season saves require a fully validated state. Reject mismatched phase/state, malformed identity snapshots, wrong year/seed/season ID, nonempty initial result ledgers, or unknown phase values.
- Preserve league generation, draft history, rookie contracts, player contracts/schedules, free-agent acquisitions/offers, market and clearance histories, hardship authorizations, staff, and facilities.
- Use only `GmCareerStorage`; do not read, write, migrate, or clear M007 season storage.
- Persist before publishing success. A failed or uncertain write leaves the in-memory career unchanged, blocks repeat commands, and requires explicit saved-career reload before reconciliation. Never blindly retry.

## 7. Controller and UI

- Add one serialized season-entry controller command. Require explicit confirmation through the existing app UI; cancellation does not invoke the command.
- Before entry, show `Start Regular Season` only for a cleared, ready career. Otherwise show `Season Start Blocked`, gate reasons, underfilled franchises, pending human actions, and applicable financial restrictions.
- Confirmation summarizes season year and 82-game schedule contract, and states that fixtures are not generated in T01.
- After persistence, show a regular-season overview with franchise, year, regular-season status, roster summary, 0–0 record, current financial overview, and clearly marked future gameplay actions. Show no next-game fixture until T02 generates the schedule.
- Keep the existing M007 8-team app and save isolated. Support 360x640 and 393x852 layouts.

## 8. Acceptance criteria

1. A `cleared` career with 30 ready teams enters regular season through the UI and controller.
2. Every entry condition listed above is enforced by the existing readiness gate and career validator.
3. Draft, AI signing, either market round, clearance, hardship, recovery, roster, contract, cap, cash, ownership, free-agent-accounting, or financial-schedule blockers reject entry.
4. Rejection and dialog cancellation preserve the full career and produce actionable reasons.
5. No schedule or game result is generated; no season year, contract, roster, or financial record changes.
6. The transition sets phase and initial state exactly once; repeat and concurrent requests cannot start a second season.
7. Season ID, year, seed, and frozen team identities are deterministic and validated.
8. Entry preserves all player identities, contracts, schedules, and transaction histories.
9. Initial record is 0–0, results ledger empty, and completed-game count zero.
10. Schema v1–v14 migration preserves data and never auto-starts. Native v15 rejects corrupt or inconsistent season state.
11. Confirmation is explicit; cancel performs no write; successful UI appears only after persisted success.
12. Injected storage failure preserves last committed state, requires reload reconciliation, and cannot duplicate season state.
13. Known ready active-human cohorts reach entry: `20261028` Play-In, Playoff, Contender; `987654321` Tanking, Play-In, Playoff.
14. Known blocked cohorts remain blocked: `271828182` Tanking and `8675309` Contender. No financial policy or 1,000 CU ceiling changes.
15. M007 storage isolation, hardship/free-agency regressions, and responsive UI tests pass.
16. No game simulation, season advancement beyond entry, or M009-T02 work occurs.

## 9. Non-goals

82-game fixture generation; game simulation; box scores; player development; contract expiry or renewal; trades; waivers; new free-agency rounds; cap exceptions; revenue distribution; staff/facility gameplay; playoffs; year rollover.
