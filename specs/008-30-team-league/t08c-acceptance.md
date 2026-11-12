# M008-T08C Acceptance — Financial Domain Foundation, v8 Migration & Economy Validation

Status: **implemented, verified; owner acceptance pending**.
Date: 2026-11-12.

## 1. Authorization

Owner approved D1–D12 on 2026-11-12, including D12: the 5% annual raise applies to
every standard contract, legacy included. Implementation was authorized on branch
`feat/m008-t08c-financial-foundation`. T08D and later work remain unauthorized.

## 2. Source checkpoint

- Repository: `Faraeael/Ballgorithm`.
- Branch: `design/m008-t08b-r1-financial-validation` → `feat/m008-t08c-financial-foundation`.
- Starting commit: `e97ee5231c24b2b5b35a71e111c3f40792f0aedc` (one documentation commit
  after the prompt's stated `249de83`).
- No production source was modified before approval.

## 3. Changes

New domain:

- `lib/src/finance/financial_rules.dart` — approved constants, legacy/rookie scales,
  raise, situation plans, staff/facility vocabulary, relief bound.
- `lib/src/finance/money.dart` — integer CU validation and bounded arithmetic.
- `lib/src/finance/career_finances.dart` — authoritative aggregate and cross-record
  validation.
- `lib/src/finance/financial_migration.dart` — deterministic v1–v7 migration and
  roster/ledger reconciliation.
- `lib/src/models/player_contract.dart`, `contract_financials.dart`,
  `team_finances.dart`, `staff_commitment.dart`, `facility_state.dart`.

Modified:

- `lib/src/career/gm_career.dart` — finances field, schema v8, validation, copyWith
  reconciliation.
- `lib/src/career/gm_career_codec.dart` — v8 encode/decode, v1–v7 migration.
- `lib/src/validation/validation_result.dart` — typed financial error codes.
- `lib/simulation_core.dart` — exports.
- `test/career/draft_execution_migration_test.dart`,
  `test/career/free_agent_pool_test.dart` — current schema assertions updated.

Evidence and tools:

- `tool/t08c_financial_audit.dart` — reproducible 24-league audit.
- `specs/008-30-team-league/t08c-financial-audit.md` — generated audit output.
- `specs/008-30-team-league/t08b-financial-architecture-spec.md` — D12 record,
  corrected accounting tables, implementation record.
- `test/career/financial_foundation_test.dart` — 15 focused tests.

## 4. Financial rules used

- Currency: integer CU, non-negative stored balances.
- Cap 41,000; minimum 400; maximum 8,000; two-way 250; 5% standard raise.
- Legacy salary bands and 2/1-year durations as approved.
- Rookie scale by pick; two-way flat 250.
- Situation budgets/cash/revenue: 18,000/10,000/42,000; 21,000/13,000/47,000;
  24,000/16,000/52,000; 27,000/19,000/57,000.
- Initial staff 9,500 and facility maintenance 2,800 per franchise.

## 5. Contract architecture

One active `PlayerContract` per rostered player. One `ContractFinancials` schedule per
contract, keyed by contract id. Every signed `RookieContract` links 1:1 through
`PlayerContract.rookieContractId`; the historical record is never rewritten. Trades,
renewals and expiry are not implemented. `RookieContract.teamId` remains the historical
signing franchise; `PlayerContract.teamId` is current employment.

## 6. Payroll evidence

The 30-team reference table is `t08b-financial-architecture-spec.md` §16.10; the
implemented audit reproduces it exactly. Summary of 24 leagues, 720 observations:

- Pre-draft cap payroll: 6,950–40,400.
- Post-draft cap payroll: 7,750–40,400.
- Post-draft cash payroll: 7,750–40,400.
- Contender cap payroll unchanged after signings: 32,600–40,400.
- Cap 41,000: 0 over-cap rosters; 0 cannot add one minimum; 1 roster (`team-23`)
  cannot cover two minimum deals (600 room), requiring a 200 CU bounded exception.
- The 200 CU audited shortfall is distinct from the 800 CU structural maximum.

## 7. Two-way cash-accounting correction

Two-way salaries are excluded from `capPayroll` and included in `cashPayroll`. The
historical R1 after-draft table mixed these; §16.3 now publishes both, and
`CareerFinances` validates the distinction.

## 8. Legacy migration

- v1–v7 saves regenerate the same deterministic finances.
- 360 legacy contracts and 360 schedules per initial career.
- Roster IDs, categories, attributes, profiles, draft history, AI decisions and the
  free-agent pool are unchanged.
- Two-way legacy categories receive the flat 250 schedule rather than a standard band.
- No player rating is mutated to fit the cap.

## 9. Rookie preservation

Existing `RookieContract` records are copied exactly into the linked `PlayerContract`
and schedule. The existing rookie signing workflow now creates employment terms
atomically through career reconciliation, so a signed rookie cannot lack a contract.
Round-trip tests compare the historical record and linked contract JSON.

## 10. Validation

Cap, operating-budget and current-year cash-solvency checks run on every career
validation. Grandfathered payroll is bounded by its stored baseline plus 800 CU.
Duplicate contracts, duplicate team finances, orphan schedules, missing contracts,
wrong ownership, invalid salaries, invalid staff/facility records, broken rookie links
and negative cash projections are typed errors.

## 11. Save migration and corruption tests

- v1–v7 → v8 migration passes for every version.
- v8 without `finances` is rejected.
- Canonical round-trip is byte-stable.
- Free-agent pool serialization is byte-identical across round-trip.
- M007 season save isolation is untouched; the app storage tests pass.

## 12. Regression evidence

- `dart analyze`: no issues.
- `dart format --set-exit-if-changed`: 0 changed files.
- Core tests: **840 passed**.
- Root `flutter analyze`: no issues.
- Flutter tests: **216 passed**.
- Audit tool: no analyzer issues; 48 career validations across 24 leagues.

## 13. Remaining risks

- Legacy salaries are a bootstrap convention, not market value; they expire within two
  years and do not set future prices.
- Staff commitments are one-year records in T08C; season advancement requires the
  renewal gate.
- No season simulation, performance revenue modifiers, staff or facility effects exist.
- No free-agent acquisition, negotiation, waiver, trade, expiry, renewal, construction
  or bailout transaction exists.
- Player-facing financial UI is absent.
- A negative future-year projection is not persisted state; only the current year is
  enforced.

## 14. Recommended T08D scope

Free-agent acquisition only: pool lifecycle correction, acquisition command, contract
creation, profile move, transaction ledger, initial player ID snapshot, cap/cash/budget
checks, atomic persistence and a read-only board. Negotiation, AI bidding, waivers,
trades and staff/facility gameplay remain separate.
