# M008-T08C-P1 Acceptance — Contract Immutability & Financial Transaction Integrity

Status: **implemented, verified; owner acceptance pending**.
Date: 2026-11-12. Baseline: `9dacd9c08a550438ab8c5b9a4f672553a949af95`.
Branch: `fix/m008-t08c-p1-contract-integrity`.

## 1. Root cause

`GmCareer.copyWith()` invoked `FinancialMigration.reconcile()` whenever the league,
profiles, rookie ledger or current year changed. That function rebuilt every contract
from the current roster: legacy salary from current OVR and duration from current age.
Validation independently recomputed the same expected values. Any copy could therefore
rewrite committed terms, and any fabricated roster addition received a generated legacy
contract instead of failing.

## 2. Repair

- `FinancialMigration.bootstrapFromCareerState()` is bootstrap-only. It runs when a
  career is created or a v1–v7 save has no financial section. It is never called by
  `copyWith`.
- `GmCareer.copyWith()` preserves the existing `CareerFinances` unless the caller passes
  an explicit replacement.
- `FinancialTransactions.addContract()` is the only runtime insertion boundary. It adds
  one contract and schedule, preserves every existing record, and rejects overlapping
  employment for one player.
- `FinancialTransactions.signRookie()` builds the linked rookie record through
  `addContract`; `RookieSigningService` applies it atomically with roster, profile and
  ledger changes.
- T08D acquisition must call `addContract` with source `freeAgent` and an explicit
  agreed first-year salary. No legacy regeneration path remains.
- Validation now checks immutable terms only: schedule shape, bounds, 5% raise, two-way
  250, legacy bootstrap band membership and 1–2-year duration, exact rookie scale from
  the historical pick, ownership, category, links, cap, budget and cash. Current OVR and
  age are not read. Schema stays v8; no signing-time snapshot was needed.

## 3. Files changed

Production:

- `lib/src/finance/financial_migration.dart` — bootstrap-only, no prior-state path.
- `lib/src/finance/financial_transactions.dart` — new transaction boundary.
- `lib/src/finance/career_finances.dart` — immutable-term validation; no OVR/age read.
- `lib/src/finance/financial_rules.dart` — approved legacy band membership set.
- `lib/src/career/gm_career.dart` — copyWith preserves finances; bootstrap at creation.
- `lib/src/career/rookie_signing_service.dart` — explicit financial transaction.
- `lib/simulation_core.dart` — export.

Tests and fixtures:

- `test/career/contract_immutability_test.dart` — 13 focused regressions.
- `packages/simulation_core/test/support/financial_fixtures.dart` and
  `test/support/financial_fixtures.dart` — explicit bootstrap fixtures for
  roster-mutating tests.
- Updated T05R/T07A/T07C/T07D, draft migration and T08C tests to supply explicit
  financial records when they add players.

Evidence:

- `specs/008-30-team-league/t08c-p1-contract-integrity-spec.md`.
- `specs/008-30-team-league/t08c-financial-audit.md` (regenerated, unchanged).

## 4. Evidence of immutability

Focused tests prove:

- unrelated team update preserves contract and schedule JSON byte-for-byte;
- OVR change does not change salary or invalidate the contract;
- age change does not change duration, start year or source;
- fabricated roster addition without a contract is rejected with `contractMissing`;
- duplicate overlapping employment is rejected by `addContract`;
- a simulated `freeAgent` contract keeps its source and schedule across unrelated
  copies;
- an unauthorized salary rewrite is rejected;
- save/load is byte-stable.

## 5. Rookie signing

Human and AI paths both use `RookieSigningService` and the same transaction. Tests show
one signing adds exactly one contract/schedule and preserves all earlier JSON. Two
sequential human signings preserve the first contract. One AI decision preserves every
existing contract.

## 6. Attribute and age changes

Unrelated copies with changed attributes or profiles succeed without financial
mutation. The strict contract rules still reject invalid duration, raise, ownership,
rookie link, duplicate, cap, budget or cash states.

## 7. Migration compatibility

- v1–v7 saves regenerate deterministic bootstrap records only when `finances` is absent.
- Native v8 requires `finances`; missing or malformed data is rejected.
- `FreeAgentPool` bytes and M007 storage behavior are unchanged.

## 8. Financial audit

The committed 24-league audit reproduces the accepted Variant A figures exactly:

- pre-draft cap 6,950–40,400;
- post-draft cap 7,750–40,400;
- post-draft cash 7,750–40,400;
- 0 over-cap rosters at 41,000;
- one roster (`team-23`) with 600 room needing the 200 CU bounded exception;
- 48 career validations.

No salary or financial limit was changed.

## 9. Verification

- Core `dart analyze`: clean.
- Core `dart test`: **853 passed**.
- Root `flutter analyze`: clean.
- Root `flutter test`: **216 passed**.
- Format check: clean.
- Audit tool: clean analyze; regenerated evidence unchanged.

## 10. JEV review

`jev-latest` returned: contract immutability 0.96, validation integrity 0.92, T08D
boundary sufficiency 0.86, recommendation **GO** (0.93). Judge output is advisory; test
results are the acceptance evidence.

## 11. Remaining risks

- Legacy values remain a bootstrap convention, not market value.
- Staff commitments remain one-year records; season advance needs the renewal gate.
- T08D still must implement roster-capacity and acquisition checks as an atomic command;
  the boundary exposes the mechanism, not the command.
- Future-year negative projections are not persisted state.
- No negotiation, bidding, trades, expiry, renewal, waivers, UI or season advancement.

## 12. Recommendation

**GO for T08D free-agent acquisition**, limited to the explicit financial transaction
boundary and full-career validation. No merge of protected branches and no T08D work is
included here.
