# M008-T08D Specification — Free-Agent Acquisition Engine & Market Lifecycle

Status: implementation contract. Baseline:
`fix/m008-t08c-p1-contract-integrity` at
`d07f632a5ae64c583d3a54895ed9d4f3f6b9241c`.
Branch: `feat/m008-t08d-free-agent-acquisition`.

## 1. Scope

One atomic domain command moves one eligible free agent from the persistent pool
into one franchise roster with an explicit contract, financial schedule, profile
and acquisition record. The command works for any franchise. It does not choose
AI offers, negotiate, bid or value the market.

## 2. Market state

`FreeAgentPool` now stores:

- `entries`: currently available players.
- `initialPlayerIds`: frozen 90 generated identities.
- `acquisitions`: authoritative acquisition ledger.

Initial generation still requires 90 entries with at least 12 per position and is
enforced by `FreeAgentGenerator` through `validateInitialGeneration()`. Ongoing
market validation requires only structural integrity: valid entries, unique IDs,
current IDs ⊆ initial IDs, no acquired player still available, and every initial
ID accounted for by exactly one of available or acquired.

Removed players are never regenerated. Position counts may fall below 12 after
legal acquisitions.

## 3. Acquisition record

`FreeAgentAcquisition`: transactionId, playerId, teamId, contractId, seasonYear,
category, origin (`initialPool`). Transaction IDs are deterministic
`free-agent-acquisition-<playerId>-<season>`. Duplicate transaction IDs or a
second acquisition of the same player are rejected.

## 4. Command

`FreeAgentAcquisitionService.acquire(career, teamId, freeAgentId, category,
durationYears, agreedFirstYearSalary)`.

Preconditions:

1. opening offseason;
2. player exists in the available pool and lacks an acquisition record;
3. franchise exists;
4. category is standard or two-way;
5. duration is 1–4 for standard, 1–2 for two-way (T08E shared rule; existing
   signed longer two-way agreements remain valid);
6. two-way salary is exactly 250; standard first-year salary is 400–8,000;
7. every scheduled year remains ≤ 8,000;
8. prospective roster passes `RosterRules.validateStructure`;
9. standard cap payroll plus the new salary ≤ 41,000;
10. current-year projected cash remains ≥ 0;
11. all existing contracts and schedules are unchanged.

Failures are typed `DomainValidationException`s; the input career is unchanged.
No waivers, conversions, relief, debt or AI offer selection are implemented.

## 5. Atomic mutation

On success the command builds and validates together:

- updated league roster with the existing `Player` object;
- `LeagueCareerProfiles` with the existing profile;
- one `PlayerContract` source `freeAgent` plus schedule via
  `FinancialTransactions.addContract`;
- one ledger record;
- pool entries without the player, with the original identity snapshot intact.

The career constructor validates the complete state before it is returned.

## 6. Schema v9

Career schema becomes 9. `freeAgentPool` serialization adds `initialPlayerIds`
and `acquisitions`. Native v9 requires both sections. v1–v8 decode keeps existing
pool entries exactly, derives the initial snapshot from them, and starts an empty
acquisition ledger. Missing or contradictory v9 data is rejected.

## 7. Controller and persistence

`GmCareerController.acquireFreeAgent` uses the serialized command queue,
rechecks career identity at execution, persists before publishing, blocks after
failed/uncertain writes until a reload, and never replays an acquisition.

## 8. Read-only board

A free-agent screen lists name, position, age, overall and observable attributes,
with position filtering and sorting. It exposes no potential, trajectory, asking
price, offer or sign action. It listens to the authoritative career state.

## 9. Acceptance criteria

- **AC-T08D-01** Initial pool 90, initial identities 90, ledger empty.
- **AC-T08D-02** Standard acquisition: pool 89, roster +1, cap room decreases by
  the agreed salary, cash projection includes salary once, existing contracts
  byte-identical.
- **AC-T08D-03** Two-way acquisition: pool 89, cash payroll +250, cap payroll
  unchanged, standard shortage unchanged.
- **AC-T08D-04** Sequential acquisitions yield 88, 87, etc.; position counts may
  drop below 12.
- **AC-T08D-05** Player ID, name, attributes, age, potential and trajectory are
  preserved exactly; no PRNG is used.
- **AC-T08D-06** Duplicate/missing/unknown/phase, duration, salary, raise,
  capacity, cap and cash failures are typed and non-mutating.
- **AC-T08D-07** Ledger, pool and roster mismatches are rejected.
- **AC-T08D-08** Save/load and restart preserve the pool and ledger exactly.
- **AC-T08D-09** v1–v8 migration and native v9 strictness hold.
- **AC-T08D-10** Readiness shortage falls only for standard acquisitions.
- **AC-T08D-11** Controller duplicate submissions are safe; failed writes block
  further commands until reload.
- **AC-T08D-12** Existing rookie signing, AI signing, M007 isolation and T08C
  financial rules are unchanged.
- **AC-T08D-13** Board hides potential/trajectory and fits 360×640 and 393×852.

## 10. Non-goals

Negotiation, user-facing arbitrary offers, AI bidding, market valuation,
auctions, preferences, waivers, trades, renewal, expiry, retirement, staff,
facilities, dashboard, season advancement, relief, device changes.
