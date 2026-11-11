# M008-T08B Specification — Franchise Financial System & Contract Economy

Status: **design and approval only**. No financial models, salaries, contracts, UI, schema or
device changes are implemented by this milestone. All numbers are proposals pending owner
approval.

Baseline: `feat/m008-t08a-free-agent-pool` at `493b658`.

---

## 1. Architecture audit findings

Existing persisted state (schema v7):

| Area | Current state | Financial data |
|---|---|---|
| `GmCareer` | League, profiles, draft order/class/execution, rookie ledger, AI decisions, free-agent pool | none |
| `Team` / `Roster` | 30 franchises, 12 contracted players each, category limits | no budget, cash or payroll |
| `Player` | id, names, position, attributes | no contract or salary |
| `RookieContract` | id, player, team, category, start year, duration, draft pick | no salary |
| `RookieSigningLedger` | one contract per signed prospect | no financial terms |
| `FreeAgentPool` | 90 entries (player + profile), exact size and per-position rules | no market state |
| `LeagueReadinessReport` | roster readiness and AI signing aggregates | no money |
| `LeagueGenerator` | deterministic 360 players; no salary draws | no money |
| `CareerSetupService` | deterministic league/profiles/draft/pool | no finances |

Conclusions:

1. No monetary value exists anywhere; nothing may be interpreted as a zero salary.
2. Existing players are not free agents and have no contracts; a migration must create
   explicit financial records, not assume zero cost.
3. `RookieContract` is the authoritative signing record but carries no money; financial
   terms need a linked, validated companion record.
4. `FreeAgentPool.validate()` currently enforces initial-generation rules (90 entries,
   ≥12 per position) as permanent invariants. That will break the first legitimate
   acquisition and must be corrected in the acquisition milestone (section 12).
5. There is no season simulation, revenue, staff or facilities system yet, so all
   financial numbers are design proposals, not verified outputs.

---

## 2. Three economy models compared

### A. Salary cap only
- Player payroll is capped; staff, facilities and operations have no formal budget.
- Pros: simplest to explain; strong competitive-balance signal.
- Cons: coaching/facilities become either free (no tradeoff) or governed by ad-hoc caps;
  no franchise-level opportunity cost; contradicts the planned staff/facilities depth.

### B. Operating budget only
- One annual budget covers payroll, staff, facilities and operations.
- Pros: one number, clear opportunity cost; simple mobile UI.
- Cons: no league-wide player-cost fairness; rich franchises can outbid everyone; roster
  strength becomes a pure budget function; cap-style trade rules become arbitrary.

### C. Combined salary cap + operating budget (recommended)
- **Salary cap** governs player commitments and competitive balance.
- **Operating budget** governs recurring non-player expenses (staff, facilities
  maintenance, operations).
- **Cash reserves** fund one-off capital projects and absorb deficits.
- Pros: matches the planned coaching/facilities systems; two understandable constraints;
  preserves league fairness while creating franchise-level tradeoffs.
- Cons: two limits can confuse players; requires clear UI explanations and AI policy.

**Recommendation: C**, with three independent checks (cap, operating budget, cash
solvency) and no cross-subsidy between cap space and operating budget. The preliminary
preference for C is supported by the repository: facilities and staff are already planned
as separate systems, and a cap-only model would leave them economically meaningless.

---

## 3. Recommended Ballgorithm economy

### 3.1 Money and time units

- Currency: **Credit Unit (CU)**, an abstract integer. 1 CU = 1 credit; display compactly
  (e.g. `12,000 CU`). No real currency, no NBA figures.
- Storage: signed 64-bit `int` in code and JSON; never floating point.
- Percentages: integer basis points (e.g. 5% = 500 bp), rounded down deterministically.
- Seasons: career year integers starting at 1; a contract's salary schedule has exactly
  `durationYears` entries, one per year.

### 3.2 Three financial constraints

1. **Salary cap** — sum of standard-contract salaries for a franchise in a season ≤
   41,000 CU. Two-way salaries do not consume cap.
2. **Operating budget** — committed recurring non-player expenses (staff, facility
   maintenance, operations) ≤ the franchise's annual operating budget.
3. **Cash solvency** — after any transaction, projected end-of-season cash =
   `cash + revenue − payroll − operating expenses` must be ≥ 0. Construction is a cash
   payment and must leave cash ≥ 0.

Three payroll figures are distinct:

- **Cap payroll** = sum of standard-contract schedules only; it is what the 41,000 cap
  constrains.
- **Two-way payroll** = sum of two-way schedules (at most 3 × 250 = 750).
- **Cash payroll** = cap payroll + two-way payroll + any other player payments. Revenue,
  cash solvency and operating expenses use cash payroll.

Two-way salaries never consume cap space, but they are never financially free: they
always reduce cash. Player signing checks cap payroll and cash payroll. Staff/facility
commitments check the operating budget and cash. A player can fit the cap but fail the
cash check (rejected); a facility can fit cash but fail the operating budget via its
maintenance (rejected). Cap space cannot pay staff; operating budget cannot pay players.

### 3.3 Revenue (deterministic)

Annual revenue = league distribution + gate + sponsorship, by situation:

| Situation | League distribution | Gate | Sponsorship | Total |
|---|---|---|---|---|
| Tanking | 30,000 | 7,000 | 5,000 | 42,000 |
| Play-In | 30,000 | 9,000 | 8,000 | 47,000 |
| Playoff | 30,000 | 12,000 | 10,000 | 52,000 |
| Contender | 30,000 | 15,000 | 12,000 | 57,000 |

Future performance modifiers (wins, playoff rounds) adjust gate/sponsorship by published
basis-point steps. No RNG in revenue.

### 3.4 Salary rules

| Rule | Value |
|---|---|
| Salary cap | 41,000 CU |
| Maximum standard salary | 8,000 CU |
| Minimum standard salary | 400 CU |
| Two-way salary | 250 CU (fixed) |
| Salary floor | **none in v1** (documented future anti-tanking lever) |
| Annual raise | 5% (500 bp), rounded down, standard contracts only |
| Guarantee | full guarantee for all scheduled years in v1 |
| Options / bonuses | out of scope |

### 3.5 Rookie scale (by overall pick)

| Pick | Year 1 salary |
|---|---|
| 1–5 | 1,800 |
| 6–10 | 1,500 |
| 11–20 | 1,200 |
| 21–30 | 1,000 |
| 31–60 | 700 |
| Two-way (any pick) | 250 |

Standard rookie contracts receive the 5% annual raise; two-way deals are flat. This is a
Ballgorithm convention, not an NBA scale.

### 3.6 Legacy contracts for existing roster players

Existing 360 players have no salaries. Migration creates explicit legacy contracts using
a published OVR band table (not per-player arbitrary values):

| OVR | Year 1 salary | Remaining years by age |
|---|---|---|
| <42 | 400 | ≤23: 2; 24–29: 2; ≥30: 1 |
| 42–45 | 550 | same |
| 46–49 | 800 | same |
| 50–53 | 1,100 | same |
| 54–57 | 1,500 | same |
| 58–61 | 2,000 | same |
| 62–65 | 2,600 | same |
| 66–69 | 3,300 | same |
| 70–73 | 4,100 | same |
| 74–77 | 5,000 | same |
| 78+ | 6,000 | same |

Actual audited payrolls (24 leagues: 3 seeds × 4 human situations × 2 franchise identities):

| Situation | Mean payroll | Range | Cap room at 41,000 (mean) |
|---|---|---|---|
| Tanking | 8,289 | 6,950–9,500 | 32,711 |
| Play-In | 14,707 | 12,200–16,650 | 26,293 |
| Playoff | 24,177 | 21,200–27,300 | 16,823 |
| Contender | 37,593 | 32,600–40,400 | 3,407 |

After the draft and all AI signings: 10,587 / 16,217 / 24,402 / 37,593. No contender
signed a standard rookie in the audited careers; contender payroll is unchanged.

The legacy table is a **migration convention** requiring explicit owner approval; it must
not be presented as simulated market value. Remaining years are capped at two so the
bootstrap does not invent long commitments.

**Normalization gate (mandatory before implementation):** generate the payroll table for
all 30 franchises from their actual rosters and publish it for owner sign-off. Every team
must:

(a) be at or below the 41,000 cap;
(b) be able to add at least one minimum-salary player (the minimum exception covers the
    remaining two-deal case);
(c) keep cash ≥ 0 for the first season under the proposed revenue and budget;
(d) fall inside its situation payroll band:

| Situation | Band (% of cap) | Band (CU) | Audited range |
|---|---|---|---|
| Tanking | 15–25% | 6,150–10,250 | 6,950–9,500 |
| Play-In | 25–45% | 10,250–18,450 | 12,200–16,650 |
| Playoff | 45–70% | 18,450–28,700 | 21,200–27,300 |
| Contender | 75–100% | 30,750–41,000 | 32,600–40,400 |

If any check fails, revise the band table or starting finances with owner approval before
enabling finances. If no table passes, fall back to a flat minimum legacy salary for one
season (documented as a deliberate bootstrap, not market value) and let renewals establish
the market. The legacy convention is temporary: legacy contracts expire within two years
and do not set future free-agent prices.

---

## 4. Financial contract model (R1 corrected)

Three records, one authority each:

1. **`PlayerContract` — employment and financial authority (new, future).**
   `id` (`contract-<playerId>-<startYear>`), `playerId`, `teamId`, `category`,
   `startYear`, `durationYears`, `source` (`legacy` / `rookie` / `freeAgent` /
   `extension` / `trade`), optional `rookieContractId`. Renewals create a new id;
   historical contracts are immutable. Every rostered player has exactly one
   `PlayerContract`. Financial schedules reference `PlayerContract.id`.
2. **`RookieContract` — historical draft-signing record (existing).**
   Keeps player, selecting franchise, pick, category, start year and duration.
   It is linked 1:1 to a `PlayerContract` for signed rookies and is not a competing
   employment ledger. Existing records are preserved byte-for-byte.
3. **`ContractFinancials` — salary schedule (future).**
   Keyed by `PlayerContract.id`; `annualSalaries` (length = duration),
   `guaranteedYears`, `signedYear`. No other salary source.

Validation:

- Every roster player has exactly one `PlayerContract`; no contract exists for a
  player outside a roster.
- Every signed `RookieContract` maps to exactly one `PlayerContract` with the same
  player, team, category, start year and duration at migration time.
- A financial schedule without a `PlayerContract` is invalid; a contracted player
  without a schedule is invalid. Missing money is never zero.
- One active schedule per contract; one active contract per player.
- Payroll = sum of standard schedules; two-way salaries tracked separately.
- Trades change `PlayerContract.teamId` only. `RookieContract.teamId` (the signing franchise) and
  `DraftRights.owningTeamId` remain historical and are not current-employment checks.
  `DraftSelection.selectingTeamId` is a separate historical draft field.
- Extensions create a new `PlayerContract` and schedule; history is immutable.

Migration v7→v8 (future, owner-approved):

1. Add `TeamFinances` per franchise (section 5).
2. Create one `PlayerContract(source: legacy)` for each of the 360 rostered players
   without a signed rookie record, plus a legacy financial schedule.
3. Create one `PlayerContract(source: rookie)` per existing `RookieContract`, copying
   player, team, category, start year and duration exactly, plus a rookie schedule.
4. Leave the free-agent pool and its validation unchanged; the initial-identity
   snapshot and transaction ledger are deferred to the authorized acquisition
   milestone (T08D).
5. Strict v8 decode; v7 migrates deterministically; no zero salaries; no roster,
   duration, category or signing-history changes.

**Over-cap compatibility:** existing contracts are never invalidated, rewritten,
shortened or waived. If a migrated franchise's payroll exceeds 41,000, it is
`capGrandfathered`: it may only add minimum-salary players through the minimum-roster
exception, and it must become compliant through expiry or a future trade/waiver.
New non-minimum signings are rejected until payroll is at or below the cap.

---

## 5. Starting finances by situation (R1 corrected)

| Situation | Operating budget | Staff (initial) | Maintenance (initial) | Discretionary allowance | Cash reserves | Annual revenue |
|---|---|---|---|---|---|---|
| Tanking | 18,000 | 9,500 | 2,800 | 5,700 | 10,000 | 42,000 |
| Play-In | 21,000 | 9,500 | 2,800 | 8,700 | 13,000 | 47,000 |
| Playoff | 24,000 | 9,500 | 2,800 | 11,700 | 16,000 | 52,000 |
| Contender | 27,000 | 9,500 | 2,800 | 14,700 | 19,000 | 57,000 |

Initial staff and facility charges come from explicit records (sections 6 and 7);
there are no unexplained recurring costs.

Audited annual net before discretionary spending, using actual mean payrolls
(revenue − payroll − staff − maintenance):

| Situation | Net |
|---|---|
| Tanking | +21,411 |
| Play-In | +19,993 |
| Playoff | +15,523 |
| Contender | +7,107 |

Sensitivity using the same audited payrolls:

| Scenario | Tanking | Play-In | Playoff | Contender |
|---|---|---|---|---|
| Base net | 21,411 | 19,993 | 15,523 | 7,107 |
| Revenue −10% | 17,211 | 15,293 | 10,323 | 1,407 |
| Payroll +10% | 20,582 | 18,522 | 13,105 | 3,348 |
| Both | 16,382 | 13,822 | 7,905 | −2,352 |
| Premium staff (+4,100) | 17,311 | 15,893 | 11,423 | 3,007 |

Cash runway: the mean contender has 19,000 cash and a 2,352 deficit under both
shocks, roughly eight seasons. The worst audited contender (40,400 payroll) with
premium staff and revenue −10% runs −6,600/year and turns cash-negative in year 3.
Across 24 audited leagues, base and combined-shock three-year projections produced
zero negative outcomes; a flat-payroll stress (payroll held at year-1 level for three
years) produced one negative outcome. These are audit results, not estimates.

---

## 6. Staff and coaching budget integration

Annual tiers (CU), all within the operating budget:

| Category | Basic | Standard | Premium |
|---|---|---|---|
| Head coach | 1,500 | 2,500 | 4,000 |
| Assistants | 1,000 | 1,800 | 2,600 |
| Player development | 700 | 1,200 | 1,800 |
| Scouts | 500 | 900 | 1,400 |
| Medical | 800 | 1,300 | 2,000 |
| **Total** | **4,500** | **7,700** | **11,800** |

Initial staff roster (every franchise, explicit `StaffCommitment` records): one head
coach at standard 2,500; two assistants at 1,800 each; one development coach at 1,200;
one scout at 900; one medical lead at 1,300 = **9,500**. No unexplained staff charge.

Future effects (interfaces only, no implementation):

- Development tier: multiplier on progression, capped at +15%.
- Scouting: reduces public estimate noise, capped at 40% noise reduction.
- Medical: improves recovery time, capped at 20%.
- Coaching: small tactical modifier, capped; never overrides simulation invariants.

Commitments are multi-year staff contracts; they consume the operating budget and must
fit cash. Firing staff early incurs the remaining guaranteed salary as a cash charge
(future rule, not implemented).

---

## 7. Facilities economy

Levels 1–5 per facility, one-off construction cost from cash, recurring maintenance in
the operating budget:

| Facility | Construction per level | Maintenance per level/year | Effect cap |
|---|---|---|---|
| Training | 5,000 | 600 | development +15% |
| Medical | 4,000 | 500 | recovery +20% |
| Scouting | 2,000 | 300 | noise −40% |
| Arena | 8,000 | 800 | revenue +5% |

Initial facility inventory (explicit `FacilityState` records): training level 2
(maintenance 1,200), medical level 1 (500), scouting level 1 (300), arena level 1 (800)
= **2,800**. No unexplained maintenance charge.

Effects use diminishing returns per level (e.g. 5/9/12/14/15%) and are hard-capped. A
level cannot be bought with cap space; it requires cash and increases recurring
maintenance. Example: a contender with 19,000 cash can fund one training upgrade
(5,000) but the added 600 maintenance competes with premium staff inside the 27,000
operating budget. It cannot automatically afford a max free agent, a premium staff and a
major facility in the same season.

---

## 8. Financial ledger and ownership

- `TeamFinances`: teamId, operatingBudget, cash, revenueBaseline, season.
- `ContractFinancials`: contractId, playerId, teamId, annualSalaries, guaranteedYears,
  source, signedYear.
- `StaffCommitment`: teamId, category, tier, annualCost, startYear, duration.
- `FacilityState`: teamId, facility, level, maintenancePerYear.
- `FreeAgentTransaction`: transactionId, playerId, fromPool, toTeamId, contractId, year.
- All are persisted inside `GmCareer` (schema v8, future); no second save file.
- Ownership: a player has exactly one active contract/team; a contract has exactly one
  schedule; a transaction references exactly one removed free agent.
- The event ledger remains authoritative for games; financial records are career state,
  not game events.

---

## 9. Multi-year accounting and balancing (R1 corrected)

### 9.1 Accounting model

```
cash_t = cash_(t-1) + revenue_t - cashPayroll_t - operating_t - construction_t
cashPayroll_t = capPayroll_t + twoWayPayroll_t
capPayroll_t = sum of standard schedules for year t
twoWayPayroll_t = sum of two-way schedules for year t (max 3 x 250)
operating_t = staff commitments + facility maintenance + baseline operations
```

Four distinct tests:

1. **Current-season affordability** — projected payroll ≤ cap and cash_t ≥ 0.
2. **End-of-season solvency** — cash_t ≥ 0 after every commitment.
3. **Future commitment risk** — committed payroll in years t+1..t+3 compared with
   projected revenue; if a future cash balance is negative while current cash is
   positive, the franchise enters **financial watch**.
4. **Immediate cash expenditure** — construction is paid from cash and must leave
   cash ≥ 0.

**Contract-expiry boundary:** committed projections include only schedules that exist.
A player whose contract expires is not projected. The three-year projection is therefore
a committed-obligation floor, not a complete roster-solvency claim. Renewals,
expirations and replacements are a future lifecycle gate; no season may advance while a
rostered player lacks an active contract. T08C does not implement expiry or renewal.

Financial watch allows normal operations but blocks new multi-year contracts,
premium staff and facility upgrades without an explicit solvency plan. If cash goes
negative at season end, **distress** applies: no non-minimum signings, no upgrades,
minimum-roster exception only, and staff/facility reductions are required in a future
roster-move system. No unlimited money, no automatic bailouts beyond the bounded
minimum-roster relief in the R1 section.

### 9.2 Scenarios (actual audited payrolls)

1. **Rebuilding** — 32,711 mean cap room, 10,000 cash. Two young free agents at 2,000
   each: payroll 12,289, cap room 28,711, cash still positive.
2. **Play-In filling two vacancies** — 26,293 mean room; two rotation FAs at 3,000:
   payroll 20,707, room 20,293.
3. **Playoff depth** — 16,823 mean room; one 4,000 veteran: payroll 28,177, room 12,823.
4. **Contender pursuing a max veteran** — 3,407 mean room (600 for the worst audited
   team); an 8,000 salary requires shedding 4,593 (7,400 worst) elsewhere. Cap rejects
   the signing; no waiver system exists yet.
5. **Facilities instead of a player** — contender with 19,000 cash: training upgrade
   5,000 + medical 4,000 = 9,000 cash, maintenance +1,100/year; cannot also add a max
   free agent without shedding salary.
6. **Expensive coaching** — contender premium staff 11,800 + maintenance 2,800 =
   14,600 inside the 27,000 budget, leaving 12,400.
7. **Multi-year overcommitment** — worst audited contender (40,400 payroll) guaranteed
   for three years, premium staff, revenue −10%: annual net −6,600; cash 19,000 turns
   negative in year 3, triggering financial watch and then distress.
8. **Cannot afford the minimum roster** — two minimum deals cost 800. The worst team
   has 600 cap room, so 200 requires the minimum-roster exception; if cash would go
   negative, league relief advances up to 800 against next season's distribution. Both
   are bounded, recorded and do not bypass the cap for non-minimum deals.

## 10. Economic safety invariants

- Money is `int` CU in `0..1,000,000`; no floating point, no NaN, no negative balances.
- Percentages use basis points and deterministic rounding.
- Contract schedules are contiguous, length = duration, startYear ≥ 1, salary within
  category bounds; standard salaries ≤ 8,000, two-way exactly 250.
- Cap payroll per team per season ≤ 41,000; two-way payroll ≤ 750; cash payroll =
  cap payroll + two-way payroll. Grandfathered over-cap payroll may not increase except
  through the minimum-roster exception (at most two minimum deals to reach 14 standard
  players).
- Operating commitments ≤ operating budget; cash ≥ 0 after any mutation.
- One active `PlayerContract` per rostered player; one schedule per contract; every
  signed `RookieContract` links 1:1 to a `PlayerContract`; no duplicate obligations.
- Missing financial data is a typed validation error, never a zero-cost contract.
- Revenue/expense formulas are pure and deterministic; no RNG, clock or locale.
- Failed transactions return the input career unchanged (pure command pattern).
- v8 validation rejects orphan contracts, team/roster mismatches, schedule length
  mismatches, cap/budget breaches, negative cash and duplicate transactions.
- Human and AI franchises use identical rules; AI policy is deterministic and auditable.

---

## 11. FreeAgentPool lifecycle correction (required for acquisition)

Problem: `FreeAgentPool.validate()` enforces `expectedSize == 90` and `≥12 per position`
as permanent rules. The first acquisition would reduce the pool to 89 and invalidate the
career.

Correction design (implement in the acquisition milestone, not now):

1. Move initial-generation constraints into `FreeAgentGenerator` / career creation.
2. `FreeAgentPool` validates structural integrity only: valid entries, unique IDs, no
   roster/contract ownership; size may shrink to 0.
3. Persist `initialPlayerIds` (90 IDs) with the pool at schema v8, populated from the
   current pool during migration.
4. Add `FreeAgentTransactionLedger`. Validation: current IDs ⊆ initial IDs; every
   removed ID has exactly one authorized transaction (acquisition or authorized event);
   no transaction references a non-initial ID; acquired players are on exactly one roster
   with one contract and one profile moved out of the pool.
5. Never accept arbitrary disappearance; never regenerate removed players.
6. Acquisition is atomic: remove entry, add roster/contract/profile, append transaction,
   validate, persist.

This milestone only documents the correction; T08A validation remains unchanged.

---

## 12. Save migration plan (future v8)

1. Decode v7 strictly as today.
2. Generate `TeamFinances` deterministically from situation and seed (section 5).
3. Create legacy financial schedules for every rostered player (section 3.6).
4. Create rookie schedules for every `RookieContract` (section 3.5).
5. Add `initialPlayerIds` from the current free-agent pool; empty transaction ledger.
6. Encode v8. No league, draft, contract, AI decision, roster or profile changes.
7. v8 requires all financial sections; malformed data is rejected, not zero-filled.
8. Atomic writes, backup recovery and M007 isolation unchanged.

---

## 13. Risks and unresolved decisions

- All numbers are untested; no season simulation exists to validate balance.
- Legacy salary migration is a convention that may distort competitive balance.
- Two hard constraints (cap + budget) can confuse players; UI must explain each check.
- AI financial policy (spending, distress, staff/facility choices) is undesigned.
- Revenue lacks a season model; performance modifiers are placeholders.
- Minimum-roster relief needs a repayment ledger and anti-abuse rule.
- Salary floor, luxury tax, options, bonuses, bird rights and trade matching are future.
- Free-agent lifecycle correction changes validation semantics in a later schema.

---

## 14. Owner approval required

| ID | Decision |
|---|---|
| D1 | Adopt model C (cap + operating budget + cash) |
| D2 | CU unit, integer storage, cap 41,000, max 8,000, min 400, two-way 250 |
| D3 | Legacy salary bands and remaining-year rules |
| D4 | Rookie scale and 5% annual raise |
| D5 | Starting budgets, cash, revenue by situation |
| D6 | Staff tiers and effect caps |
| D7 | Facility costs, maintenance and effect caps |
| D8 | No salary floor in v1; bounded minimum-roster relief |
| D9 | FreeAgentPool lifecycle correction (initial IDs + transaction ledger) |
| D10 | Implementation order below |

---

## 15. Proposed implementation breakdown

1. **T08C — Financial domain foundation**: money type, `TeamFinances`,
   `ContractFinancials`, legacy/rookie schedule generation, validation, schema v8
   migration, no UI.
2. **T08D — Free-agent acquisition**: pool lifecycle correction, acquisition command,
   contract creation, profile move, transaction ledger, read-only board.
3. **T08E — Staff and facilities commitments**: budget allocation, maintenance,
   construction, effect interfaces, no simulation changes.
4. **T08F — Financial dashboard UI**: cap, budget, cash, multi-year commitments.
5. **T08G — AI financial policy**: deterministic spending, distress and facility choices.

Each step requires separate owner authorization; none is authorized by this document.

---

## 16. T08B-R1 validation (2026-11-11)

This section records the correction and the actual generated-league audit. It supersedes
the earlier illustrative estimates where they differ.

### 16.1 Method

- Diagnostic scripts generated 24 leagues: 3 seeds (`20261028`, `1604126146`,
  `987654321`) × 4 human situations × 2 human franchise identities (`team-1`,
  `team-16`). Each league contains all 30 franchises, giving 720 team observations.
- Payroll was computed from actual `Player` overall ratings using the corrected legacy
  table, then recomputed after the draft and all AI rookie signings using the proposed
  rookie scale and actual `RookieContract` durations.
- Temporary scripts lived under `packages/simulation_core/tool/` and were deleted after
  capturing evidence; no production source was modified.

### 16.2 Defects corrected

| Defect | Correction |
|---|---|
| A. Missing 42–45 salary | Restored 550 CU; table is complete and monotonic |
| B. No contract for 360 players | New `PlayerContract` employment record; every rostered player has exactly one; schedules reference it |
| C. Existing rookies vs cap | Existing contracts are never rewritten; over-cap teams are grandfathered and may only add minimum players via the roster exception |
| D. Draft vs employment ownership | `RookieContract.selectingTeamId` and `DraftRights` stay historical; `PlayerContract.teamId` is current employment; trades change only the latter |
| E. Unexplained staff/maintenance | Initial staff roster (9,500) and facility inventory (2,800 maintenance) are explicit records |
| F. 42,000 payroll under 40,000 cap | Cap corrected to 41,000; the example is rewritten around actual audited payrolls |

### 16.3 Actual payroll audit

Pre-draft payroll by team situation (n = team observations):

| Situation | n | Min | Median | Mean | Max |
|---|---|---|---|---|---|
| Tanking | 168 | 6,950 | 8,200 | 8,289 | 9,500 |
| Play-In | 216 | 12,200 | 14,700 | 14,707 | 16,650 |
| Playoff | 216 | 21,200 | 24,400 | 24,177 | 27,300 |
| Contender | 120 | 32,600 | 37,400 | 37,593 | 40,400 |

After the draft and all AI signings:

| Situation | Min | Median | Mean | Max |
|---|---|---|---|---|
| Tanking | 7,750 | 10,650 | 10,587 | 12,000 |
| Play-In | 13,450 | 16,150 | 16,217 | 18,100 |
| Playoff | 21,200 | 24,650 | 24,402 | 27,550 |
| Contender | 32,600 | 37,400 | 37,593 | 40,400 |

No contender signed a standard rookie in the audited careers; two-way signings did not
move the contender aggregate.

Projected payroll in later contract years (legacy durations 2/1, rookie raises 5%):

| Situation | Year 2 min / median / mean / max | Year 3 min / median / mean / max |
|---|---|---|
| Tanking | 7,200 / 10,010 / 10,079 / 12,125 | 0 / 2,755 / 2,516 / 2,755 |
| Play-In | 7,500 / 12,225 / 12,353 / 15,975 | 0 / 1,323 / 1,488 / 2,424 |
| Playoff | 12,600 / 17,300 / 17,335 / 24,060 | 0 / 0 / 0 / 0 |
| Contender | 12,300 / 18,400 / 19,208 / 25,200 | 0 / 0 / 0 / 0 |

Cap room after existing rookie contracts (cap 41,000):

| Situation | Min | Median | Mean | Max |
|---|---|---|---|---|
| Tanking | 29,000 | 30,350 | 30,413 | 33,250 |
| Play-In | 22,900 | 24,850 | 24,783 | 27,550 |
| Playoff | 13,450 | 16,400 | 16,598 | 19,800 |
| Contender | 600 | 3,600 | 3,408 | 8,400 |

### 16.4 Cap compliance

| Rule | Result |
|---|---|
| Cap 40,000 | 1 over-cap team (`team-23`, seed `1604126146`, 40,400); 2 teams unable to add one minimum; 3 teams unable to cover a two-player shortage |
| Cap 41,000 | **0 over-cap teams**; 0 teams unable to add one minimum; 1 team unable to cover a two-player shortage (`team-23`, 600 room vs 800 cost) |
| Minimum-roster exception | Allows up to two minimum deals to reach 14; resolves the remaining team with at most 200 CU overage |
| Grandfathering | Any migrated over-cap payroll is preserved; no non-minimum additions until compliant |

### 16.5 Cash and multi-year solvency

- Base three-year projections: **0 negative** across 720 team observations.
- Combined shock (revenue −10%, payroll +10%, premium staff +4,100, maintenance +1,100):
  **0 negative**.
- Flat-payroll stress (year-1 payroll held for three years, revenue −10%, premium staff):
  **1 negative** (`team-23`, seed `1604126146`), which is the documented financial-watch
  case.

Human franchise payrolls across the 24 audited leagues ranged 8,000–39,200 (all under
41,000), with cap room 800–32,250 and three-year cash 81,700–97,900. Generation-position
effects changed payroll by up to about 4,300 CU between `team-1` and `team-16` in the
same seed/situation, so franchise identity matters.

### 16.6 Contract coverage and migration scenarios

| Scenario | Roster | Legacy contracts | Rookie contracts | Duplicates | Orphans |
|---|---|---|---|---|---|
| New career, no draft | 360 | 360 | 0 | 0 | 0 |
| Completed draft, no signings | 360 | 360 | 0 | 0 | 0 |
| Human two signings | 362 | 360 | 2 | 0 | 0 |
| AI all signings | 395 | 360 | 35 | 0 | 0 |
| Human + AI signings | 397 | 360 | 37 | 0 | 0 |
| Partial AI (20 decisions) | 379 | 360 | 19 | 0 | 0 |
| v6 migration of human+AI | 397 | 360 | 37 | 0 | 0 |

The v6 migration preserved roster IDs, the full signing ledger and AI decisions exactly,
and generated the 90-player free-agent pool. No player disappeared and no contract
duplicated.

### 16.7 Minimum-roster relief (proposal, not implemented)

- **Eligibility:** standard roster below 14; normal cap room cannot fit the remaining
  minimum slots; no outstanding relief debt; over-cap grandfathered teams qualify only
  for minimum deals.
- **Maximum contracts:** two minimum-salary contracts per season.
- **Maximum cap overage:** 800 CU (2 × 400). The audited worst case needs only 200 CU
  (600 room against an 800 two-deal cost); the 200 is the actual exception, not the
  maximum.
- **Cap treatment:** minimum salaries count normally; `minimumRosterException` permits
  at most 800 CU above the cap solely to reach 14 standard players. It never permits a
  non-minimum deal.
- **Cash relief:** if projected cash would go negative, the league advances up to 800 CU,
  recorded as `LeagueAdvance` debt and deducted from next season's distribution.
- **Repayment:** no interest; debt must be cleared before any non-minimum signing.
- **Anti-abuse:** once per season; only when below 14; only minimum salary; teams that
  voluntarily waived players are ineligible in a future waiver system.

### 16.8 Remaining risks

- No season simulation exists; revenue performance modifiers and staff/facility effects
  remain unvalidated.
- The legacy table is a bootstrap convention and may still distort competitive balance.
  JEV scored the legacy gate 0.60 before the situation-band gate and 0.69 after; it
  remains the weakest item. Situation payroll bands and mandatory owner sign-off are the
  mitigation, and D3 may be replaced by a public market-value formula.
- One audited contender needs the minimum-roster exception; the design accepts this as
  intended pressure, not a bug.
- AI financial policy is undesigned; AI teams may hoard cash or overcommit.
- Free-agent supply is sufficient in count (90 vs 35–36 shortage), but acquisition and
  AI demand are not modeled.
- Staff/facility effect caps are proposals without simulation evidence.

### 16.9 Owner approval matrix

| ID | Decision | Status |
|---|---|---|
| D1 | Model C architecture | Provisionally accepted |
| D2 | CU integer money; cap 41,000; max 8,000; min 400; two-way 250 | Requires approval |
| D3 | Legacy OVR table and 2/1-year durations | Requires approval |
| D4 | Rookie scale and 5% raise | Requires approval |
| D5 | Starting budgets, cash, revenue, explicit staff/facility baselines | Requires approval |
| D6 | Staff tiers and effect caps | Requires approval |
| D7 | Facility costs, maintenance, effect caps | Requires approval |
| D8 | No salary floor; bounded minimum-roster relief | Requires approval |
| D9 | `PlayerContract` employment authority and `RookieContract` link | Requires approval |
| D10 | FreeAgentPool lifecycle correction | Requires approval |
| D11 | T08C implementation order and acceptance criteria | Requires approval |

JEV review (`jev-latest`): contract authority 0.88; cap correction 0.86;
relief/lifecycle 0.95; legacy bootstrap 0.60 before the situation-band gate and 0.69
after. The legacy bootstrap remains the weakest item and requires explicit owner
sign-off of the published 30-team table.

**Alternative if D3 is rejected:** implement a read-only public market-value calculator
(OVR + age only, no hidden potential) first, derive legacy salaries from it, and re-run
the 24-league gate. This requires approving the market formula before T08C and replaces
the OVR-band table rather than patching it.


### 16.10 Reference payroll table (seed 20261028, human `team-1`, Play-In)

Pre-draft baseline, CU. `cashPayroll` equals cap payroll here because no two-way
contracts exist yet.

| Team | Abbr | Situation | Std | 2W | Cash payroll | Cap room | Revenue | Staff | Maint | Year-1 cash |
|---|---|---|---|---|---|---|---|---|---|---|
| team-1 | AUR | Play-In | 12 | 0 | 13,450 | 27,550 | 47,000 | 9,500 | 2,800 | 34,250 |
| team-2 | IRV | Playoff | 12 | 0 | 24,500 | 16,500 | 52,000 | 9,500 | 2,800 | 31,200 |
| team-3 | PMT | Playoff | 12 | 0 | 26,300 | 14,700 | 52,000 | 9,500 | 2,800 | 29,400 |
| team-4 | RSC | Playoff | 12 | 0 | 23,600 | 17,400 | 52,000 | 9,500 | 2,800 | 32,100 |
| team-5 | NGL | Contender | 12 | 0 | 32,600 | 8,400 | 57,000 | 9,500 | 2,800 | 31,100 |
| team-6 | SLK | Playoff | 12 | 0 | 26,000 | 15,000 | 52,000 | 9,500 | 2,800 | 29,700 |
| team-7 | VDU | Tanking | 12 | 0 | 7,850 | 33,150 | 42,000 | 9,500 | 2,800 | 31,850 |
| team-8 | CBE | Contender | 12 | 0 | 37,100 | 3,900 | 57,000 | 9,500 | 2,800 | 26,600 |
| team-9 | MCV | Playoff | 12 | 0 | 22,700 | 18,300 | 52,000 | 9,500 | 2,800 | 33,000 |
| team-10 | CRM | Play-In | 12 | 0 | 14,250 | 26,750 | 47,000 | 9,500 | 2,800 | 33,450 |
| team-11 | SPA | Tanking | 12 | 0 | 8,200 | 32,800 | 42,000 | 9,500 | 2,800 | 31,500 |
| team-12 | TLW | Tanking | 12 | 0 | 8,800 | 32,200 | 42,000 | 9,500 | 2,800 | 30,900 |
| team-13 | BSC | Tanking | 12 | 0 | 8,700 | 32,300 | 42,000 | 9,500 | 2,800 | 31,000 |
| team-14 | GCS | Play-In | 12 | 0 | 14,000 | 27,000 | 47,000 | 9,500 | 2,800 | 33,700 |
| team-15 | HPA | Playoff | 12 | 0 | 22,800 | 18,200 | 52,000 | 9,500 | 2,800 | 32,900 |
| team-16 | CLS | Play-In | 12 | 0 | 15,650 | 25,350 | 47,000 | 9,500 | 2,800 | 32,050 |
| team-17 | GBG | Playoff | 12 | 0 | 26,500 | 14,500 | 52,000 | 9,500 | 2,800 | 29,200 |
| team-18 | DMV | Play-In | 12 | 0 | 13,850 | 27,150 | 47,000 | 9,500 | 2,800 | 33,850 |
| team-19 | KSM | Contender | 12 | 0 | 39,300 | 1,700 | 57,000 | 9,500 | 2,800 | 24,400 |
| team-20 | HCN | Play-In | 12 | 0 | 14,750 | 26,250 | 47,000 | 9,500 | 2,800 | 32,950 |
| team-21 | WWR | Tanking | 12 | 0 | 7,700 | 33,300 | 42,000 | 9,500 | 2,800 | 32,000 |
| team-22 | SFS | Contender | 12 | 0 | 37,400 | 3,600 | 57,000 | 9,500 | 2,800 | 26,300 |
| team-23 | OHS | Tanking | 12 | 0 | 8,450 | 32,550 | 42,000 | 9,500 | 2,800 | 31,250 |
| team-24 | CCB | Tanking | 12 | 0 | 8,000 | 33,000 | 42,000 | 9,500 | 2,800 | 31,700 |
| team-25 | FWG | Playoff | 12 | 0 | 25,000 | 16,000 | 52,000 | 9,500 | 2,800 | 30,700 |
| team-26 | BWR | Play-In | 12 | 0 | 15,200 | 25,800 | 47,000 | 9,500 | 2,800 | 32,500 |
| team-27 | ISL | Playoff | 12 | 0 | 24,800 | 16,200 | 52,000 | 9,500 | 2,800 | 30,900 |
| team-28 | CVF | Play-In | 12 | 0 | 15,550 | 25,450 | 47,000 | 9,500 | 2,800 | 32,150 |
| team-29 | SLV | Play-In | 12 | 0 | 14,400 | 26,600 | 47,000 | 9,500 | 2,800 | 33,300 |
| team-30 | VFT | Contender | 12 | 0 | 37,100 | 3,900 | 57,000 | 9,500 | 2,800 | 26,600 |

### 16.11 Proposed T08C acceptance criteria

- **AC-T08C-01** Every one of the 360 initial players has exactly one `PlayerContract`
  and one financial schedule; no roster player is missing or duplicated.
- **AC-T08C-02** Every existing `RookieContract` links 1:1 to a `PlayerContract` with
  identical player, team, category, start year and duration; history is unchanged.
- **AC-T08C-03** Schedule length equals duration; salaries are integers within category
  bounds; missing data is rejected, never zero.
- **AC-T08C-04** Payroll and cap validation use 41,000; grandfathered over-cap teams
  cannot add non-minimum players; the minimum exception is bounded to two deals.
- **AC-T08C-05** `TeamFinances`, staff commitments and facility states are explicit and
  deterministic by situation; budget covers staff + maintenance + allowance.
- **AC-T08C-06** v8 migration from v7 preserves league, draft, contracts, AI decisions,
  rosters, profiles and the free-agent pool; no regeneration.
- **AC-T08C-07** Corrupt financial data is rejected with typed errors.
- **AC-T08C-08** The 24-league audit reproduces the documented payroll distributions and
  the single minimum-roster exception.
- **AC-T08C-09** No signing, staff, facility or UI transaction is implemented.
- **AC-T08C-10** Core and Flutter regression suites pass.

