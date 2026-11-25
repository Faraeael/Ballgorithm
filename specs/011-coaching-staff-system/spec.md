# M011 — Coaching & Staff System Integration Contract

**Status:** FROZEN DESIGN — M011-T01/T02/T03 complete; targeted technical acceptance recorded in §15. D1–D9 remain owner-approved. Where §1–§12 conflict with §13A, §13A governs.
**Baseline:** `feat/m009-t05c-a-season-history` at `043cb597abaf45a72de26872ee012c5682a1bfc5` (career schema v26)
**Scope:** named staff, head-coach rotation philosophies, coaching delegation, and a small offseason staff market. It reuses `StaffCommitment`/`CareerFinances` (money) and M010 rotations (lineups). There is no second payroll ledger and no new rotation engine.

---

## 1. Existing reusable systems (verified at baseline)

| System | Location | Facts that matter |
|---|---|---|
| Staff money | `models/staff_commitment.dart` | `StaffCommitment {id, teamId, category, tier, annualCost, startYear, durationYears ≤ 5}`. `isActiveIn(year)`. Ids are `staff-<team>-<category>-<index>`. **It has no person identity.** |
| Categories / tiers | `finance/financial_rules.dart` | `StaffCategory {headCoach, assistant, playerDevelopment, scout, medical}`; `StaffTier {basic, standard, premium}`. The source comment says "effects out of T08C scope". |
| Bootstrap staff | `finance/financial_migration.dart::_initialStaff` | Per team: head coach 2,500, 2 assistants 1,800 each, player development 1,200, scout 900, medical 1,300 = **9,500 CU**. Tier is `standard`, **`durationYears: 1`**, `startYear` = career year. |
| Operating money | `finance/career_finances.dart` | `operatingCommitmentsFor` = staff `annualCost` + facility maintenance. Validation enforces `operating ≤ TeamFinances.operatingBudget` (18,000–27,000 by situation) as a hard `budgetBreach` error. `projectedEndOfSeasonCash` = cash + revenue − cash payroll − operating. Every staff commitment must be active in `currentYear`, so **future-start commitments are invalid**. |
| Rollover | `finance/financial_rollover_service.dart` | Year-N staff that are active are charged in the Year-N settlement (`SeasonSettlementRecord.staffExpense`). Commitments not active in N+1 are dropped (`expiredStaff`). Facilities are carried over. Shortfalls become debt; there is no money creation. |
| Spending gates | FA evaluator and acquisition, AI FA policy, clearance, hardship, readiness gate | All read `projectedEndOfSeasonCash`. Operating costs therefore already reduce what a franchise can offer and sign. |
| Rotations | M010 `career_rotation_settings.dart`, `career_rotation_service.dart`, `RegularSeasonGameAdapter._sideFor` | One authoritative adapter: human MANUAL resolves through `CareerRotationService`; everyone else uses `automaticFor` (`CourtLineup.defaultFor` + balanced). History is protected by stored input templates. |

**Baseline finding (affects this design).** Bootstrap staff are 1-year commitments, and nothing in the code base ever renews or creates `StaffCommitment`s. So **from Year 2 onward every franchise has zero staff and zero staff expense**. Today Year-2+ settlements contain `staffExpense: 0`. M011 must either keep this behaviour (staff exist only once hired) or change it on purpose (D1). A staff system that silently restores costs would change multi-season finances, AI free agency, rosters and therefore archives.

## 2. Proposed staff data model

**`StaffMember`** — new person identity; no money stored on it:

```text
StaffMember { id (stable, e.g. "coach-<seedHash>-<n>"), firstName, lastName, age,
              role: StaffCategory, tier: StaffTier, experienceYears,
              philosophy: CoachPhilosophy? (headCoach only),
              teamId?: TeamId, commitmentId?: String }
```

- **Money authority stays `StaffCommitment`.** A member is *employed* if and only if `commitmentId` refers to an active commitment with the same `teamId` and `category`.
- **Invariants:**
  - each commitment has at most one member and each member at most one commitment;
  - at most one employed head coach per team;
  - roles match categories.
- **No salary on the person**, so salary cannot be double counted. `StaffCommitment` keeps its schema (no financial schema bump).
- **Naming existing commitments.** Each anonymous commitment active in the current year gets a deterministic fictional member (name pool × `generationSeed` × commitment id, pure hash, no PRNG draws from game streams). This adds identities, **not expenses**.
- **Philosophy.** Head coaches get a philosophy deterministically from the same hash. Other roles carry `tier` and `experienceYears` only; their effects are deferred (§14).
- **State root:** `GmCareer.staff = StaffState { members (by id), market: StaffMarketState, coachingEnabled: bool }`.

## 3. Head coach behaviour (existing contracts only)

A coach produces a `(CourtLineup, TeamRotationPlan)` for its team from the **standard roster** (`RegularSeasonGameAdapter.standardTeamFor`). The result is validated with `GameInput.validateLineupAndPlan`.

- **No attribute bonuses and no coefficient changes.** Fouls, foul-outs, mandatory-first substitutions and overtime remain engine rules.
- **Starter selection** (shared by all philosophies): for PG, SG, SF, PF, C in order, pick the best-scoring unchosen player whose natural position matches the slot. If none, pick the best-scoring unchosen player (out of position is allowed). Ties go to roster order, then id.

| Philosophy | Starter score | Minutes plan (existing presets / integer custom) |
|---|---|---|
| Balanced | `overallRating` | `balanced` preset (9-man) |
| Star-focused | `overallRating` | `starterHeavy` preset (8-man) |
| Deep rotation | `overallRating` | Custom, 10 players: starters weight 3 (1,728 s), next 5 by OVR weight 2 (1,152 s). Exact 14,400. If fewer than 10 standard players → `balanced`. |
| Defensive-minded | `perimeterDefense + interiorDefense + rebounding`, tie → OVR | `balanced` preset |
| Development-focused | **Deferred (D4).** Minutes do not affect progression today, so the "development" claim would be a fake benefit. |

- **Safety.** If the computed plan fails validation (it should not), the coach uses `CareerRotationService.automaticFor` for that game. The rule is documented and deterministic, never silent mid-season: the staff view shows "coach plan unavailable".
- **Tier/quality.** Tier sets salary only in M011. Any gameplay effect of coach quality is deferred (D3), because it would need simulation changes.

## 4. Management delegation (reconciled with M010)

There are no new modes. M010's `AUTO`/`MANUAL` keep their meaning, and one career-level switch changes who "AUTO" means:

| Requested concept | Representation |
|---|---|
| GM only (delegate to coach) | `userRotation = AUTO` **and** `staff.coachingEnabled = true` → the human head coach decides. |
| GM + coach (user controls) | `userRotation = MANUAL` (M010, unchanged). |
| Hybrid | AUTO (coach) by default. Switching to MANUAL and back **keeps the last manual plan** in `CareerRotationSettings.retainedManual`, so delegating never erases it. Per-game overrides are deferred (D5). |

- **Coaching off** (all existing saves, D2): AUTO = `automaticFor` exactly as today, for all 30 teams.
- **Coaching on:** AUTO human side and **all AI teams** use their employed head coach's philosophy. This gives parity, with no human-only advantage. A team with no employed head coach uses `automaticFor`. This is the *interim* behaviour: no person, no cost, no softlock.
- **When generated / consumed:** computed in `RegularSeasonGameAdapter._sideFor` each time an input is built (single round, batch, Play-In, playoffs). It is a pure function of roster, attributes, coach and philosophy. Coaches change only in `openingOffseason` and rosters are frozen in season, so the plan is constant within a season. Each game's stored input template records exactly what was used.

## 5. Staff recruitment (limited v1)

- **Market:** deterministic candidate pool per `(generationSeed, currentYear)`: 8 head coaches, plus 4 each for assistant, player development, scout and medical.
  - Candidate ids are stable: `staffcand-y<year>-<role>-<n>`.
  - The pool is regenerated, not stored. The only persisted state is people who became members (hired, released, or expired into the pool).
- **Asking salary** is fixed by role and tier. No negotiation.

  | Role | basic | standard | premium |
  |---|---|---|---|
  | Head coach | 1,800 | 2,500 | 3,400 |
  | Assistant | 1,300 | 1,800 | 2,400 |
  | Player development | 900 | 1,200 | 1,600 |
  | Scout | 650 | 900 | 1,200 |
  | Medical | 950 | 1,300 | 1,700 |

  These are proposals (D7); standard = current bootstrap prices.
- **Actions** (offseason only — `openingOffseason`, before regular-season entry; in-season changes deferred):
  - **Hire** (1–5 years): creates a `StaffCommitment{startYear: currentYear}` and links the member.
  - **Renew:** extends an employed member's active commitment `durationYears` (≤ 5 total) at the same `annualCost`.
  - **Dismiss:** unlinks the member, who returns to the pool. **The commitment stays and keeps being paid until it expires** (no buyout, no cancellation, D6).
  - **Replace** = dismiss + hire. Both salaries are paid, which is the real consequence.
- **Affordability gate** (uses existing limits, none changed):
  - `operatingCommitmentsFor(team) + annualCost ≤ operatingBudget`;
  - `projectedEndOfSeasonCash − annualCost ≥ max(0, 14 − standardCount) × minimumSalary`. This keeps money for mandatory roster completion, so clearance cannot be softlocked by staff spending.
  - Failing either rule gives a typed rejection.
- **Commands:** `StaffMarketService` (pure core) + `GmCareerController.hireStaff / renewStaff / dismissStaff`. They use the existing `_runCareerCommand`/`_saveCareerState`, busy rejection and save-failure recovery.

## 6. Financial integration

- **Current cash:** unchanged at hire. Like player contracts, costs are charged at settlement through `staffExpense`.
- **Projected end-of-season cash:** drops by `annualCost` immediately (`operatingCommitmentsFor`), so FA offers, AI policy, clearance and hardship all see the hire.
- **Future obligations:** a commitment stays active `durationYears`. The rollover keeps charging it each completed year. Shortfalls become debt through the existing rules.
- **Expiration:** the existing rollover partition drops expired commitments. The member becomes unemployed and its `commitmentId` is cleared in the same rollover step.
- **Dismissal liability:** the commitment is retained; the dead money is visible in the staff contracts list.
- **No double counting:** salary exists only on `StaffCommitment`; members reference it by id.
- **Consequence of an irresponsible hire:** less offer capacity this offseason, multi-year operating drag, possible settlement debt, and a hard stop at `operatingBudget`.
- **Unchanged:** no cap, debt, hardship or budget limits are altered.

## 7. AI staff management (minimum viable)

Applies only when `coachingEnabled`, at the AI offseason step before free agency (the same place AI rookie signing runs):

1. Each AI team without an employed head coach hires the best-tier head coach it can afford under §5. Candidates are ordered by tier, then experience, then id. It takes 2 years when it can afford them, otherwise 1.
2. Other roles are **not** filled by AI in M011. They have no gameplay effect yet, and adding costs without effects would only hurt AI finances.
3. Expired AI coaches go back to the pool. Vacancies use `automaticFor` until the next offseason. Nothing creates money.

## 8. Persistence and migration (schema v26 → v27)

| Change | Details |
|---|---|
| `GmCareer.staff` (new) | `members` (sorted by id) and `coachingEnabled` (default `false`). The market pool is regenerated, not stored. |
| `CareerRotationSettings` | AUTO may carry an optional `retainedManual` manual payload (strictly validated). M010 malformed/obsolete rules apply to it. |
| Migration | v1..v26 → `coachingEnabled: false`. Every active anonymous commitment gets a deterministic named member. Year-2+ saves (no commitments) get no members. No commitment is added, removed or repriced. |

- **Baseline proof obligation (T02):** with `coachingEnabled: false`, all game-input fingerprints and archive digests equal v26 behaviour. T02 must prove this with the T03A/T03B1 two-season fixtures, as M010 did.
- **Expected checksum changes and causes:** career-JSON SHA goldens (T03A/T03B1 Y2/Y3 career hashes) change because of `schemaVersion: 27` and the new `staff` key. Year-1 careers also gain named members. **Archive digests must not change.** If they do, investigate; never rebaseline.
- **History:** completed games keep their stored inputs. Enabling coaching or changing coaches only affects games simulated afterwards.
- **Rollover:** members and philosophies carry over. Commitment expiry unlinks employment. `retainedManual` and `coachingEnabled` carry over.

## 9. Rollover, vacancies and continuity

- **Identity continuity:** member ids never change. Expired or dismissed members stay in `members` as unemployed until rehired, so their history is kept.
- **Head-coach vacancy:** no softlock, and no interim person is needed. The team uses `automaticFor` (today's behaviour). The UI shows "No head coach — default rotation".
- **Year-2+ migrated careers** start with vacancies (see the §1 finding). Enabling coaching lets teams hire at the next offseason.
- **Unaffordable replacement:** the vacancy persists. The franchise is never forced into debt.

## 10. Android-first UI (Hardwood Command)

- **TEAM tab gets a third sub-view, `STAFF`** (ROSTER & DEPTH · CAP & CONTRACTS · STAFF). No new navigation tab. Existing tokens are reused: `AppPressable`, `HardwoodPrimaryCta`/`HardwoodSecondaryButton`, cards.
- **Contents:**
  - **Head coach card:** name, age, experience, philosophy (with a one-line description of what it actually does), tier, contract years left, annual cost.
  - **Coaching control:** an "Enable Coaching & Staff" confirmation (D2). Then "Coach decides rotation: ON/OFF", which sets AUTO/MANUAL with retained-manual messaging. Deep link to Lineup & Rotation.
  - **Staff contracts list:** active, dismissed-but-still-paid, and expiring.
  - **Operating budget panel:** operating commitments vs budget, projected end-of-season cash, and remaining roster reserve.
  - **Candidate market (offseason only):** role filter, compare (philosophy, tier, experience, salary), and a hire sheet showing the exact before/after budget and cash impact. The confirm button is disabled with the typed reason when unaffordable.
  - **Renew / Dismiss confirmations** state the money consequences ("salary continues until Year N").
- **Layout:** list-first at 360 dp and with large text. Busy and recovery states disable actions (M010 pattern).

## 11. Implementation scope

**T02 — Staff identities, market, finance and migration.** No game-input effect.

- New in `packages/simulation_core/lib/src/career/`:
  - `staff_member.dart`
  - `staff_state.dart`
  - `staff_market_service.dart`
  - `staff_name_generator.dart`
- Modified:
  - `gm_career.dart`, `gm_career_codec.dart` (v27)
  - `career_rotation_settings.dart` (`retainedManual`)
  - `season_rollover_service.dart` (carry members, unlink expired)
  - AI offseason step (AI coach hiring, only when enabled)
  - `simulation_core.dart`
  - `lib/features/career/career_controller.dart` (hire/renew/dismiss/enable)
- **No changes** to `src/simulation/*`, `StaffCommitment` schema, `FinancialRules` limits or rollover settlement math.
- Tests:
  - New: `test/career/m011_staff_*_test.dart` (core), `test/m011_t02_staff_controller_test.dart`.
  - Legacy-fixture key removal (as in M010).
  - Approved career-SHA rebaseline only.

**T03 — Coach policy, delegation and STAFF UI.**

- New:
  - `career/coach_rotation_policy.dart`
  - `lib/features/career/career_staff_view.dart`
- Modified:
  - `regular_season_game_adapter.dart` (`_sideFor`: coach branch when enabled)
  - `career_rotation_service.dart` (resolve AUTO via coach)
  - `career_team_tab.dart`, `career_rotation_screen.dart` (AUTO copy: "Coach: <name>")
- Tests: core policy tests, adapter equivalence, widget tests, Android acceptance.

## 12. Acceptance criteria (proposed)

| ID | Criterion |
|---|---|
| AC-M011-01 | v26 saves load as v27 with `coachingEnabled: false`. Year-1 anonymous commitments become named members. Commitments, costs and cash are byte-equal. |
| AC-M011-02 | Coaching disabled: every game-input fingerprint and the T03A/T03B1 archive digests equal baseline. Only career-JSON SHAs change, for the documented cause. |
| AC-M011-03 | Each commitment has at most one member; each member at most one commitment; at most one employed head coach per team. Salary appears only on commitments. |
| AC-M011-04 | Hire adds exactly one commitment and lowers projected cash by its cost. Rejected when it would exceed `operatingBudget` or the roster-completion reserve (typed reason, nothing written). |
| AC-M011-05 | Dismiss keeps the commitment paying until expiry. Replace charges both salaries. Renew extends duration ≤ 5. |
| AC-M011-06 | Rollover charges active staff in `staffExpense`, unlinks expired members and keeps identities. No money is created and no limits change. |
| AC-M011-07 | Each philosophy produces a valid lineup and plan (5 unique standard starters, 14,400 s, starters > 0, ≤ 2,880 each), deterministically. They differ observably (starters and minutes) on fixed fixtures. |
| AC-M011-08 | Coaching enabled: the human AUTO side and all AI sides use their coach. MANUAL is unchanged. A vacancy uses `automaticFor`. |
| AC-M011-09 | MANUAL → AUTO → MANUAL restores the identical retained manual plan. Nothing is erased without an explicit discard. |
| AC-M011-10 | Completed games, archives and history are unchanged by later coaching changes. |
| AC-M011-11 | AI hires head coaches only when enabled and affordable. No AI team breaches budget or creates debt from hiring. |
| AC-M011-12 | Controller: busy rejection, save-failure recovery and offseason-only staff actions. |
| AC-M011-13 | Android release run: enable coaching, hire a coach, sim a round, and box-score minutes reflect the philosophy. Restart persists. No ANR or crash. |

## 13. Decisions (approved by the owner; originally proposed as below)

| # | Decision | Recommendation |
|---|---|---|
| D1 | Year-1 staff expire and are never renewed (zero staff expense from Year 2). Keep, or auto-renew baseline staff at rollover? | **Keep.** Auto-renew changes every multi-season career's finances, AI FA and archives. Staff costs return only through explicit hiring. |
| D2 | Scope switch `coachingEnabled`: default for existing and new careers; reversible? | **Default `false` for all careers in M011.** Enabled by an explicit user confirmation, **one-way** per career, so commitments are never orphaned. |
| D3 | Gameplay effect of coach tier/quality | **None in M011** (salary only). Revisit with a simulation spec. |
| D4 | Development-focused philosophy | **Defer** until minutes affect progression. |
| D5 | Hybrid per-game overrides | **Defer.** M011 hybrid = AUTO(coach) plus retained manual plan. |
| D6 | Dismissal cost | **Remaining salary keeps being paid**; no buyout mechanic. |
| D7 | Salary table (§5) and market sizes | Approve as listed (standard = bootstrap prices). |
| D8 | AI fills only head coach | **Yes**; other roles deferred until they have effects. |
| D9 | Offseason-only staff actions | **Yes**; in-season firing deferred. |

## 13A. Approved amendments (frozen for M011-T02)

- **D1:** Existing staff expiry and legacy finances are preserved exactly. No auto-renewal; Year-2+ staff expense comes only from explicit hires.
- **D2:** `coachingEnabled` defaults to `false` for new and migrated careers. Activation is an explicit, permanent, league-wide confirmation. It never blocks AUTO/MANUAL rotation switching. Activation itself hires nobody and moves no money.
- **D3:** Coach quality has no gameplay effect in M011. The market offers **standard-tier head coaches only**. Existing tiers and commitments are preserved; no premium upgrades. Supporting-staff (assistant, player development, scout, medical) recruitment and effects are deferred; existing supporting staff stay inspectable as named incumbents.
- **D4/D5:** development-focused philosophy and per-game overrides deferred.
- **D6:** a dismissed coach's commitment stays in `CareerFinances` and is paid until its natural expiry; no buyout. A dismissed coach cannot be re-hired while that commitment exists.
- **D7:** head-coach salary 2,500 per year (the existing standard bootstrap rate); **8** generated candidates per offseason (ids `staffcand-y<year>-hc-<i>`), plus previously employed head coaches who are now unattached. Durations 1–5 years (`StaffCommitment.maxDurationYears`).
- **D8:** AI teams recruit head coaches only, only when coaching is enabled, and only when affordable. Order of the offseason: draft → human rookie signing → AI rookie signing → **AI head-coach recruitment when free-agency round 1 opens** → free agency → clearance → hardship → season entry. AI teams are processed in team-id order and take the first candidate (most experienced, then id) for 2 years. Recruitment is idempotent; a vacancy never blocks season entry.
- **D9:** hire, dismiss, replace and renew are offseason-only (opening offseason, before season entry).

**Affordability (shared by human and AI):** after the transaction, (a) operating commitments (staff + facility maintenance) ≤ operating budget, and (b) projected end-of-season cash − debt ≥ minimum salary × max(0, 14 − standard roster count) (the existing `OffseasonReadinessGate` threshold). Staff costs never enter the player salary cap. Limit: (b) reserves cash for minimum-salary roster spots but cannot guarantee willing free agents exist.

**Renewal:** extends the same commitment in place (same id, start year and annual cost); total duration may not exceed 5 years. After expiry, the coach becomes available and may be hired with a new commitment.

**Schema v27:** adds top-level `staff` (`coachingEnabled`, named `members`). Saves below v27 derive deterministic named incumbents from their existing commitments (identity hash `ballgorithm-staff-identity-v1`, isolated from player-generation and simulation PRNG streams); money is unchanged. `userRotation` may carry `retainedManual` on AUTO (v27+ only); the retained plan never drives game inputs and is re-validated on restore.

## 14. Explicitly deferred

- Effects of assistant, player-development, scout and medical staff, and of coach tier/quality.
- The development-focused philosophy.
- Per-game overrides, live tactics and play-calling.
- In-season hiring or firing, buyouts, negotiation, agents, staff morale or personalities, staff poaching.
- Staff ages progressing or retiring (the age is a stored attribute).
- Facility upgrades and maintenance changes (separate milestone; existing facility costs are preserved).
- Real-world staff names or assets: never.

## 15. Closeout evidence

- Core: 1,083 passed. Flutter: 354 non-endurance tests passed with the four existing exclusions. The final UI adjustment followed the full Flutter run and passed 16 focused regressions. The outstanding T02 diagnostic passed separately (1 test). Core and Flutter analysis, format and diff checks passed.
- Career schema remains v27. Disabled-coaching deterministic fixtures and the two-season T03A/T03B1 archive digests are unchanged. Only v27 career-save hashes changed in those fixtures. Simulation source and `StaffCommitment` salary authority are unchanged.
- Isolated Android release: a disposable career verified activation, staff replacement, operating costs and persistence. A separate eligible fixture verified an actual AUTO round, ten Aurora players with positive minutes, and retained MANUAL restoration across restart. Android postseason was not run; automated fixtures cover postseason. The standard Android release and Windows release compiled from final production source; the standard entry point has no fixture bootstrap. Windows was not launched.
- Clearance limitation: an offseason-only replay of the genuine Android career (seed `161137785`) reproduced the same result on baseline `043cb597abaf45a72de26872ee012c5682a1bfc5` and M011 with coaching enabled and Aurora's replacement hire. The Keystone Monarchs (`team-19`) remained at 13/14 standard players and the league at 29/30 ready. Cap room was −930 CU plus 700 CU authorized relief against a 400 CU minimum deal; projected cash was 21,770 CU. There were 33 eligible free agents, zero financially legal minimum offers, and zero acceptable offers. Keystone retained six bootstrap commitments totaling 9,500 CU annually in both runs. The replacement reduced Aurora's projected cash by 2,500 CU without changing the observed clearance block. No financial rules changed.
