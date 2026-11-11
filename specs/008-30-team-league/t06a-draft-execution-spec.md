# M008-T06A Specification — Persistent Rookie Draft Execution Engine

- **Milestone:** M008
- **Task:** T06A (Persistent Rookie Draft Execution Engine)
- **Status:** Implementation specification under task-specific owner authorization; not milestone acceptance.

---

## 1. Product Objective

Implement the deterministic and persistent rookie draft execution engine for Ballgorithm's 30-team GM career mode:
1. Execute exactly 60 selections across two rounds in strict sequence according to the authoritative `DraftOrder`.
2. Support human-controlled selections at user pick entitlements (#1 & #31 Tanking, #12 & #42 Play-In, #20 & #50 Playoff, #30 & #60 Contender).
3. Support AI-controlled selections for all other franchises with situation-driven strategy and roster-need evaluation.
4. Enforce the Critical Fairness Rule: AI evaluators must use only public scouting information and are strictly prohibited from inspecting hidden true potential or development trajectory.
5. Record complete selection history and assign persistent draft rights to selecting franchises.
6. Preserve the non-roster boundary: draft rights do not automatically create player contracts or alter active franchise rosters.
7. Support mid-draft persistence and resumption, ensuring interrupted drafts resume from the exact last committed pick without repeating AI draws.
8. Upgrade save schema to version 4 with backwards-compatible, non-destructive migration from v1, v2, and v3 saves.

---

## 2. Core Domain Contracts

### 2.1 Draft Execution Status (`DraftExecutionStatus`)
Enumerates lifecycle states:
- `notStarted`: Opening draft ready, zero picks executed.
- `inProgress`: Draft started, with zero through 59 committed picks.
- `completed`: Exactly 60 picks executed, draft rights fully assigned.

### 2.2 Draft Selection Record (`DraftSelection`)
Immutable log entry for an executed pick:
- `seasonYear` (`int`): Draft season (`1`).
- `round` (`int`): Selection round (`1` or `2`).
- `overallPick` (`int`): Selection rank (`1..60`).
- `originalOwnerTeamId` (`TeamId`): Original draft entitlement owner.
- `selectingTeamId` (`TeamId`): Franchise that executed the selection (current pick holder).
- `prospectId` (`PlayerId`): Selected rookie prospect.

### 2.3 Draft Rights Ownership (`DraftRights`)
Represents exclusive contractual acquisition rights for an unsigned drafted prospect:
- `prospectId` (`PlayerId`): Prospect subject to draft rights.
- `owningTeamId` (`TeamId`): Franchise holding rights.
- `overallPick` (`int`): Overall pick where prospect was selected.
- `seasonYear` (`int`): Draft year.

*Invariant:* Draft rights do NOT constitute active roster membership. Unsigned prospects consume zero franchise roster slots.

### 2.4 Public Prospect Scouting View (`PublicProspectScoutingView`)
Restricted public scouting snapshot isolating observable data from hidden variables:
- `id` (`PlayerId`): Prospect ID.
- `firstName`, `lastName` (`String`): Identity.
- `position` (`Position`): Canonical position (PG, SG, SF, PF, C).
- `age` (`int`): Biological age (19..22).
- `attributes` (`PlayerAttributes`): Visible attributes.
- `overallRating` (`int`): Visible unweighted overall ability.
- `projectedRank` (`int`): Consensus public board ranking.
- `estimatedPotentialGrade` (`String`): Public scouting grade (A+ through C).
- `estimatedPotentialRange` (`String`): Public scouting ceiling estimate.

*Strict Rule:* Hidden true `potential` and `trajectory` are completely omitted. AI scoring operates exclusively on `PublicProspectScoutingView`.

### 2.5 Draft Execution State (`DraftExecutionState`)
Authoritative persistent aggregate holding:
- `status` (`DraftExecutionStatus`): Active lifecycle phase.
- `selections` (`List<DraftSelection>`): Sequential committed picks (`1..60`).
- `draftRights` (`Map<String, DraftRights>`): Prospect ID to rights mapping.
- Derived queries: `completedSelectionsCount`, `currentOverallPick`, `availableProspects()`, `undraftedProspects()`, `isHumanTurn()`.

---

## 3. Acceptance Criteria

- **AC-008-69 (Sequential 60-Pick Execution):** The engine executes exactly 60 selections in strict overall pick order (1 through 60).
- **AC-008-70 (Unique Prospect Selection):** Every selected prospect is marked unavailable; no prospect can be selected more than once. Exactly 30 prospects remain undrafted upon completion.
- **AC-008-71 (Human Selection Sovereign Command):** Human selections cannot be automated; failed human selections leave state unchanged. Human turn is recognized for all 4 situations (#1/#31 Tanking, #12/#42 Play-In, #20/#50 Playoff, #30/#60 Contender).
- **AC-008-72 (AI Advancement & Human Boundary):** AI auto-advancement advances consecutive AI picks and halts immediately prior to any human-controlled selection.
- **AC-008-73 (Critical Fairness Isolation):** AI draft evaluation operates exclusively on `PublicProspectScoutingView`; hidden `potential` and `trajectory` are inaccessible to the AI scoring function.
- **AC-008-74 (Situation-Driven Strategy):** AI evaluation responds deterministically to franchise competitive situations:
  - Tanking prioritizes high estimated grade and youth.
  - Contender prioritizes immediate overall ability and positional depth.
  - Play-In and Playoff balance immediate fit with future upside.
- **AC-008-75 (Roster Need Sensitivity):** AI scoring weights position depth and positional strength, favoring weak roster areas over congested slots.
- **AC-008-76 (Deterministic Decision Making):** Given identical career seed, draft order, and roster state, AI franchises make byte-identical selection decisions.
- **AC-008-77 (Draft Rights Integrity):** Each executed pick creates an explicit `DraftRights` entry for the selecting franchise without modifying the active franchise roster.
- **AC-008-78 (Active Roster Invariance):** Contracted team rosters (`team.roster.players`) remain completely unchanged throughout draft execution.
- **AC-008-79 (Mid-Draft Persistence & Recovery):** Interrupted drafts save and reload without repeating prior picks or rerunning executed AI decisions.
- **AC-008-80 (Completed State Finality):** Completed drafts (60 picks) reject any additional selection commands with typed errors.
- **AC-008-81 (Schema v4 Migration):** GmCareer upgraded to `schemaVersion = 4`. Saves from v1, v2, and v3 decode cleanly with `DraftExecutionState.initial()` without data loss. Re-saving writes v4.
- **AC-008-82 (M007 Save Isolation):** Draft execution and persistence operations never interact with `ballgorithm_save.json`.

## 4. Implementation plan and boundaries

1. Add immutable draft history and reconciled unsigned rights to the career root.
2. Start explicitly, then execute one human or AI selection per domain command.
3. Save every transition before publishing it through the career controller. Stop AI advancement before the current human-owned pick.
4. Migrate schema v1–v3 to an unstarted draft. Preserve existing migration behavior where v1 has no draft pool.
5. Require schema v4 execution data and reject contradictory history, rights, ownership, year, or lifecycle status.
6. Verify all four full drafts, restricted AI inputs, strategic sensitivity, interrupted persistence, migrations, and existing regression suites.

The selection history is authoritative for progression and availability. The serialized rights map must match every selection exactly; it cannot evolve independently in this milestone.

Original user entitlements remain recorded through original pick ownership. Commands use current ownership, including when a future caller supplies an ownership-adjusted order.

AI scoring uses public overall, projected rank, estimated potential grade, age, position depth and position strength. Seeded per-prospect variation is bounded. No simulation PRNG, league generation, player attributes, roster categories, or M007 versions change.

The domain bulk helper is not a persistence transaction. Applications must use single-pick commands and commit each result separately.

### Migration and rollback

Decoding is read-only. Failed decoding does not write a replacement save. Existing storage retains its atomic promotion and backup behavior.

Schema v4 saves cannot be opened by older readers. Roll back code only with a preserved pre-v4 save; do not down-convert completed draft history.

### Task checklist

- Architecture audit and acceptance criteria recorded.
- Domain execution and public-only strategy implemented.
- Application per-pick persistence and interruption recovery verified.
- Legacy migrations and full regression evidence recorded before publication.

### Deferred scope

No draft UI, timers, trades, contracts, automatic roster intake, free agency, development, or season advancement. T06B requires separate authorization.

## 5. Architectural audit

| Dependency | Preserved boundary |
|---|---|
| `GmCareer` / `GmCareerCodec` | Career root owns execution state; schema v4 adds data without replacing league, profiles, order, or class. |
| `CareerPhase` | Remains Opening Offseason; draft lifecycle is separate. |
| `DraftOrder` / `DraftPick` | Existing 60-pick order remains authoritative; original and current ownership stay distinct. |
| `RookieDraftClass` / `RookieProspect` | Existing 90-player pool remains unchanged; public view omits hidden potential and trajectory. |
| `Team` / `Roster` / `RosterRules` | Contracted membership and category limits remain unchanged. Unsigned rights never add players. |
| `PlayerCareerProfile` | Existing profiles persist without regeneration or modification. |
| `DeterministicRandom` | Draft evaluation uses a separate stable seed mixed with franchise, prospect, and pick identities. Simulation draws remain unchanged. |
| `GmCareerController` | Serializes lifecycle commands and persists each transition before publishing it. |
| `FileGmCareerStorage` | Existing atomic promotion, backup recovery, filenames, and M007 isolation remain unchanged. |

### AI scoring contract

Five public components contribute: consensus rank (`91 - rank`), current overall (`1.5 * (overall - 40)`), estimated grade, youth (`5 * (23 - age)`), and positional need.

Grade values are A+=36, A=30, A-=24, B+=18, B=13, B-=8, C+=4, C=0.

Position depth contributes 24 at zero/one player, 12 at two, zero at three, and -16 at four or more. A position averaging below 50 overall receives eight additional need points.

| Situation | Rank weight | Grade weight | Youth weight | Need weight | Overall weight |
|---|---:|---:|---:|---:|---:|
| Tanking | 0.8 | 1.6 | 1.4 | 0.4 | 0.6 |
| Play-In | 0.9 | 1.1 | 0.9 | 1.1 | 1.0 |
| Playoff | 0.85 | 0.8 | 0.6 | 1.4 | 1.3 |
| Contender | 0.6 | 0.5 | 0.3 | 1.8 | 1.8 |

Each candidate receives deterministic variation in [-3, 3). Equal scores use public rank, then canonical prospect ID. This is an explainable foundation, not calibrated basketball realism.

### Strategic evidence

Seed 20261028, pick 20, equal projected rank 20:

- With an empty positional-depth fixture, Tanking selects the age-19, overall-51, estimated-A guard.
- With the same pool, Contender selects the age-22, overall-66, estimated-B center.
- Four existing guards cause a Contender to choose the center over an otherwise equal guard.
- Four existing centers reverse that choice.
- Reversing candidate input order preserves these choices.
- Changing only hidden potential and trajectory preserves every situation's public score and selected identity.

## 6. Verification record

Environment: Windows x64, Dart 3.12.2, Flutter 3.44.2.

- Core `dart.bat test`: **760 passed**.
- Core `dart.bat analyze`: **PASS**, no issues.
- Core `dart.bat format --output=none --set-exit-if-changed lib test`: **PASS**, 136 files, zero changes.
- Chrome `dart.bat test --platform chrome test/draft/draft_execution_test.dart test/draft/draft_integrity_test.dart test/career/draft_execution_migration_test.dart`: **38 passed**.
- Initial Chrome corruption cases exposed a typed JSON-map iteration failure. Key iteration fixed it; the complete focused Chrome run passed afterward.
- An initial application test assumed repeated starts were idempotent. It now checks the explicit rejection contract and unchanged save count.

All four situation fixtures complete 60 unique picks, retain 30 undrafted prospects, assign 60 matching rights records, and preserve the complete serialized team data. Human decisions are supplied explicitly. Both rounds retain original guaranteed entitlements.

Every-step codec continuation and controller failure tests cover saved progress, failed writes before and after promotion, reload reconciliation, queued stale commands, and no replay of committed selections. Corruption tests reject contradictory status, sequence, year, round, slot, owner, prospect, and rights metadata.

Legacy migration tests compare every pre-existing serialized field; schema v3 mixed two-way/training-camp categories remain intact. Missing or malformed v4 execution metadata fails closed. Writers always emit v4, including explicitly older in-memory career models.

No source changed during the final core or Chrome runs. No Android performance, multi-process save locking, or calibrated AI realism was measured.

### Independent judgment

Initial JEV design reviews flagged residual concurrency/integrity uncertainty. A configured `advisor` invocation was unavailable; a separate slow-model design review identified concrete queue, uncertain-write, and immutable-state safeguards. Those safeguards were implemented and tested.

Final JEV judgment: `publishAfterFlutter`, confidence 0.98, probability 0.99, conditional on passing Flutter regressions. This is not milestone acceptance or filesystem-atomicity certification.

Final application gates:

- Root `flutter.bat test`: **163 passed**, including ten new draft-controller tests and existing career, draft-board, mobile-layout, and M007 regressions.
- Root `flutter.bat analyze`: **PASS**, no issues.
- No production source changed during these final application runs. The earlier failed repeated-start assertion was corrected before the successful full rerun.

### Remaining limitations and next gate

No unresolved failing checks remain in the exercised scope. Storage keeps its existing single-process assumptions and non-atomic copy fallback; this task does not strengthen filesystem guarantees.

Schema v4 is forward-only for older application readers. AI weights are explainable policy choices, not measured realism.

Recommended T06B scope: mobile draft interaction using the existing controller, explicit human confirmation, public-only details, persisted history/rights display, and interrupted-save recovery feedback. Do not add signing or roster intake without separate authorization.
