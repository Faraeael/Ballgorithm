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
   40,000 CU. Two-way salaries do not consume cap.
2. **Operating budget** — committed recurring non-player expenses (staff, facility
   maintenance, operations) ≤ the franchise's annual operating budget.
3. **Cash solvency** — after any transaction, projected end-of-season cash =
   `cash + revenue − payroll − operating expenses` must be ≥ 0. Construction is a cash
   payment and must leave cash ≥ 0.

Player signing therefore checks cap and cash. Staff/facility commitments check operating
budget and cash. A player can fit the cap but fail the cash check (rejected); a facility
can fit cash but fail the operating budget via its maintenance (rejected). Cap space
cannot pay staff; operating budget cannot pay players.

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
| Salary cap | 40,000 CU |
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
| 42–45 |
| 46–49 | 800 | same |
| 50–53 | 1,100 | same |
| 54–57 | 1,500 | same |
| 58–61 | 2,000 | same |
| 62–65 | 2,600 | same |
| 66–69 | 3,300 | same |
| 70–73 | 4,100 | same |
| 74–77 | 5,000 | same |
| 78+ | 6,000 | same |

Estimated initial payrolls (illustrative, from base ratings):

| Situation | Estimated payroll | Cap room |
|---|---|---|
| Tanking | ~8,100 | ~31,900 |
| Play-In | ~15,400 | ~24,600 |
| Playoff | ~23,900 | ~16,100 |
| Contender | ~38,900 | ~1,100 |

The legacy table is a **migration convention** requiring explicit owner approval; it must
not be presented as simulated market value. Remaining years are capped at two so the
bootstrap does not invent long commitments.

**Normalization gate (mandatory before implementation):** generate the payroll table for
all 30 franchises from their actual rosters and publish it. Every team must (a) be at or
below the 40,000 cap, (b) be able to add at least one minimum-salary player, and (c) keep
cash ≥ 0 for the first season under the proposed revenue and budget. If any check fails,
revise the band table or starting finances with owner approval before enabling finances.
If no table passes, fall back to a flat minimum legacy salary for one season (documented
as a deliberate bootstrap, not market value) and let renewals establish the market.

---

## 4. Financial contract model

Two layers, no contradictory authority:

1. **Domain contract** (existing/new): identity, player, team, category, start year,
   duration, draft reference (`RookieContract` now; `FreeAgentContract` future).
2. **Financial schedule** (`ContractFinancials`, future): keyed by domain `contractId`
   and `playerId`; stores `annualSalaries` (length = duration), `guaranteedYears`,
   `signedYear`, `source` (rookie / freeAgent / extension / trade / legacy).

Rules:

- `RookieContract` remains unchanged in this milestone; financial schedules reference it.
- Duration is authoritative in the domain contract; the schedule length must match.
- One active financial schedule per contract; one active contract per player per team.
- Free agents get a future `FreeAgentContract` domain record plus financial schedule.
- Extensions create a new contract record; they never mutate historical schedules.
- Trades move `teamId` on the contract/schedule without changing amounts.
- Payroll = sum of standard schedules for the season; two-way salaries tracked separately.
- A missing schedule for a contracted player is a validation error, never zero.

Migration v7→v8 (future, owner-approved):

1. Add `TeamFinances` per franchise (section 5).
2. Create legacy schedules for all rostered players (section 3.6).
3. Create rookie schedules for every `RookieContract` from its pick/category.
4. Add free-agent pool initial identity snapshot and empty transaction ledger.
5. Strict v8 decode; v7 migrates deterministically; no zero salaries; no roster changes.

---

## 5. Starting finances by situation (proposal)

| Situation | Operating budget | Staff baseline | Maintenance | Cash reserves | Annual revenue |
|---|---|---|---|---|---|
| Tanking | 18,000 | 7,000 | 2,000 | 10,000 | 42,000 |
| Play-In | 21,000 | 8,500 | 2,500 | 13,000 | 47,000 |
| Playoff | 24,000 | 10,000 | 3,000 | 16,000 | 52,000 |
| Contender | 27,000 | 11,500 | 3,500 | 19,000 | 57,000 |

Illustrative annual net before discretionary spending (revenue − payroll − staff −
maintenance):

| Situation | Net |
|---|---|
| Tanking | +24,900 |
| Play-In | +20,600 |
| Playoff | +15,100 |
| Contender | +3,100 |

Sensitivity (illustrative):

| Scenario | Tanking | Play-In | Playoff | Contender |
|---|---|---|---|---|
| Base net | 24,900 | 20,600 | 15,100 | 3,100 |
| Revenue −10% | 20,700 | 15,900 | 9,900 | −2,600 |
| Payroll +10% | 24,090 | 19,060 | 12,710 | −790 |
| Both | 19,890 | 14,360 | 7,510 | −6,490 |
| Premium staff (+4,100) | 20,800 | 16,500 | 11,000 | −1,000 |

A contender at the cap can run a deficit under a revenue dip; cash reserves (19,000)
provide roughly a three-season runway before distress rules apply. These are design
estimates, not verified game outputs.

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

## 9. Multi-year and balancing scenarios (illustrative)

1. **Rebuilding** — 31,900 cap room, 10,000 cash. Signs two young free agents at 2,000
   each: payroll 12,100, cap room 27,900, cash still positive. Can later add a training
   upgrade (5,000) but maintenance rises.
2. **Play-In filling two vacancies** — 24,600 room; two rotation FAs at 3,000: payroll
   21,400; net still +14,600. No cap or cash problem.
3. **Playoff depth** — 16,100 room; one 4,000 veteran: payroll 27,900; fine.
4. **Contender pursuing a max veteran** — 1,100 room; 8,000 salary requires shedding
   6,900 elsewhere. Cap rejects the signing; no waiver system exists yet.
5. **Facilities instead of a player** — contender with 19,000 cash: training upgrade
   5,000 + medical 4,000 = 9,000 cash, maintenance +1,100/year; cannot also add a max
   free agent without shedding salary.
6. **Expensive coaching** — contender premium staff 11,800 + maintenance 3,500 = 15,300
   inside 27,000 budget; leaves 11,700 for operations and upgrades.
7. **Multi-year overcommitment** — contender with 42,000 payroll guaranteed three years
   and revenue −10%: year 2 net −2,600; year 3 cash falls; distress rules eventually
   block signings and upgrades.
8. **Cannot afford the minimum roster** — minimum salary 400 × 2 vacancies = 800; cap is
   not the obstacle. If cash would go negative, the league minimum-roster provision
   allows two minimum deals and advances up to 800 CU against next season's distribution.
   This is bounded, recorded and repaid; it is not unlimited money.

---

## 10. Economic safety invariants

- Money is `int` CU in `0..1,000,000`; no floating point, no NaN, no negative balances.
- Percentages use basis points and deterministic rounding.
- Contract schedules are contiguous, length = duration, startYear ≥ 1, salary within
  category bounds; standard salaries ≤ 8,000, two-way exactly 250.
- Standard payroll per team per season ≤ 40,000; two-way payroll ≤ 3 × 250.
- Operating commitments ≤ operating budget; cash ≥ 0 after any mutation.
- One active contract per player; one schedule per contract; no duplicate obligations.
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
| D2 | CU unit, integer storage, cap 40,000, max 8,000, min 400, two-way 250 |
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
