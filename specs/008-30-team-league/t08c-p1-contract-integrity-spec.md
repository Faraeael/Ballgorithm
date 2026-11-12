# M008-T08C-P1 Specification — Contract Immutability & Financial Transaction Integrity

Status: **repair design and acceptance contract**. No new economic values.
Branch target: `fix/m008-t08c-p1-contract-integrity`.
Baseline: `feat/m008-t08c-financial-foundation` at
`9dacd9c08a550438ab8c5b9a4f672553a949af95`.

## 1. Problem

T08C made `GmCareer.copyWith()` rebuild financial records through
`FinancialMigration.reconcile()` whenever the league, career profiles, rookie ledger or
current year changed. Legacy contracts were reconstructed from current roster state:
salary from current OVR, duration from current age. Validation also recomputed expected
legacy salaries from current attributes.

Failure scenarios:

1. A roster edit rewrites an existing contract's team, source, duration or salary.
2. A free-agent contract created later is regenerated as a legacy contract after an
   unrelated roster copy.
3. Attribute progression makes a valid committed salary fail validation.
4. Age progression rewrites a committed duration.
5. Editing one player regenerates or changes unrelated players' contracts.
6. A fabricated roster addition silently receives a generated legacy contract instead
   of failing for missing employment terms.

These are contract-integrity failures, not cosmetic validation issues. T08D cannot add
acquisition on top of a mutable contract ledger.

## 2. Chosen repair

Separate bootstrap from transactions and make committed records immutable.

### 2.1 Bootstrap only

`FinancialMigration.bootstrapFromCareerState()` creates the initial financial records
for:

- a newly created career, and
- a v1–v7 save that has no financial section.

It uses the approved legacy/rookie rules to value the initial records. It is not called
by `copyWith()` and is not a contract factory for later roster changes.

### 2.2 Copy never reconciles

`GmCareer.copyWith()` preserves the existing `CareerFinances` object unless the caller
passes an explicit replacement/updated aggregate. A roster, profile, draft, pool or AI
state copy never regenerates financial records.

An unauthorized roster mutation therefore fails validation with a typed missing-contract
or ownership error rather than receiving an invented salary.

### 2.3 Explicit financial transactions

A new `FinancialTransactions` boundary performs the only authorized record additions:

- `addContract(...)`: adds exactly one `PlayerContract` and exactly one
  `ContractFinancials`, preserving every existing record; rejects duplicate active
  employment for the same player.
- `signRookie(...)`: builds the rookie contract and approved schedule from the
  historical `RookieContract` and calls `addContract`.

Future acquisition (T08D) can use the same boundary with source `freeAgent` and an
explicit negotiated first-year salary. Acquisition, negotiation, bidding, trades, waivers,
expiry and renewal remain unimplemented.

The transaction returns a new immutable aggregate. The career command applies it
together with roster/profile/ledger changes in one `copyWith()` call; validation runs
inside the constructor. A failed command returns no partially modified career.

### 2.4 Immutable validation

Validation no longer derives legacy salary from current OVR or duration from current age.
It validates the committed record against immutable rules:

- schedule length equals contract duration;
- standard salaries are within 400..8,000 and each later year applies the approved 5%
  raise;
- two-way salaries are exactly 250;
- legacy bootstrap contracts use an approved legacy band value in year one and a
  duration of 1–2 years;
- rookie contracts remain exactly tied to the historical pick, category and duration;
- contract source, start year, team, category and rookie link stay consistent with the
  roster and historical signing record.

No signing-time OVR or age snapshot is persisted. It is unnecessary because the table
is a bootstrap valuation, not a recurring formula. Save schema stays v8.

### 2.5 Rookie signing

Rookie signing atomically creates/updates:

- `RookieContract` in the historical ledger,
- linked `PlayerContract`,
- `ContractFinancials` schedule,
- roster membership,
- career profile.

Existing contracts are byte-stable. Human and AI signing both call
`RookieSigningService`, so they share the same transaction. The service uses the approved
pick scale and the historical contract's duration. Failure leaves the input career
untouched.

## 3. Acceptance criteria

- **AC-P1-01** An unrelated roster/team copy preserves every existing contract and
  schedule byte-for-byte.
- **AC-P1-02** Current OVR changes do not alter salary or invalidate a committed
  contract.
- **AC-P1-03** Current age changes do not alter duration or invalidate a committed
  contract.
- **AC-P1-04** A fabricated roster addition without an explicit contract is rejected.
- **AC-P1-05** Duplicate employment records for one player are rejected.
- **AC-P1-06** Orphan schedules, wrong ownership, wrong category, invalid duration,
  invalid raise, invalid salary and broken rookie links are rejected.
- **AC-P1-07** A generic future contract (source `freeAgent`) is never rewritten as
  legacy by a copy; its source and schedule survive.
- **AC-P1-08** Rookie signing remains atomic and preserves every earlier contract.
- **AC-P1-09** Human and AI rookie signing both pass through the same financial
  transaction.
- **AC-P1-10** v1–v7 migration remains deterministic; v8 strict decode remains strict.
- **AC-P1-11** Cap 41,000, two-way cash accounting, staff 9,500 and facility 2,800 rules
  are unchanged.
- **AC-P1-12** `FreeAgentPool` serialization and M007 save isolation remain unchanged.
- **AC-P1-13** The committed 24-league audit reproduces the accepted payroll figures.

## 4. Non-goals

Free-agent acquisition/UI, AI bidding, negotiation, trades, renewal, expiry, waivers,
season advancement, staff hiring, facility upgrades, dashboard UI, new economic values,
and device changes.
