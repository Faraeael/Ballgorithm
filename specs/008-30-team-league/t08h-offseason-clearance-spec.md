# M008-T08H Specification — Offseason Clearance & League Readiness Gate

Status: implementation contract. Baseline:
`fix/m008-t08g-p1-market-integrity` at
`3e454a929ab6c87b9071e58ea1906eca18ad729e`.
Branch: `feat/m008-t08h-offseason-clearance`.

## 1. Scope

A read-only authoritative readiness gate plus one bounded compliance pass after
both competitive market rounds. It identifies shortages, distinguishes causes,
allows a single clearance pass, records exact cap exceptions, and blocks
offseason completion until every franchise satisfies roster and financial rules.
No season advance.

## 2. Rejection linkage

For every rejected market outcome, validation now requires the matching formal
attempt with the same team, player, season, category, duration, first-year
salary and reason code. An unrelated earlier rejection is not evidence. The same
rule applies to archived Round 1/2 outcomes and clearance outcomes.

## 3. Readiness gate

`OffseasonReadinessGate.evaluate(career, recoveryRequired)` is read-only and
returns a structured status plus per-team needs. It checks:

- draft complete;
- no pending AI rookie decisions;
- both market rounds complete, no unresolved round;
- no clearance resolution in flight and no recovery obligation;
- full career validation (contracts, schedules, cap, budget, cash, ownership,
  pool accounting);
- every team passes `RosterRules.validateRegularSeasonReadiness`;
- unsigned draft rights are not an automatic blocker.

Statuses: offseasonInProgress, clearanceRequired, financialExceptionRequired,
readyForConfirmation, cleared. Per-team diagnostics include standard count,
required players, cap room, cash, projected cash, eligible/affordable/acceptable
free agents, unsigned rights and blockers.

## 4. Cap exception

Owner approved a bounded minimum-roster exception on 2026-11-12:

- only a 12–13 standard roster missing 1–2 players;
- only 400 CU minimum deals;
- exact cap overage = `400 × missing − cap room`, capped at 800;
- no premium salary, no optional expansion above 14, no repeat;
- no cash advance (cash is sufficient in tested cases);
- salary cap constant remains 41,000;
- exception stored on `TeamFinances.capException` and in clearance state;
- evaluator, acquisition and career validation honor only the exact amount.

## 5. Clearance pass

`OffseasonClearanceService` starts after both rounds, grants exact exceptions,
collects explicit human offers, seals deterministic AI compliance offers, then
resolves one player at a time. Only standard contracts needed to reach 14 are
allowed. It uses T08E evaluation, competitive ranking, T08D acquisition and
T08F attempt rules. Player identity, contracts, schedules and histories are
preserved. No third market round; one bounded pass.

## 6. Persistence

Schema v13 adds `OffseasonClearanceState`: status, season, pending/sealed offers,
resolution order/cursor, outcomes and exact cap exceptions. Each decision is
saved before the next; restart resumes without replay. v1–v12 migrate with empty
clearance/exception state; native v13 requires clearance. Existing market
history and acquisitions remain immutable.

## 7. Confirmation gate

`markCleared` re-evaluates the gate. It refuses unless status is
readyForConfirmation. It persists `cleared` only. It does not increment year,
advance season, expire contracts, change ages, process revenue or reset free
agency. A blocked league returns precise reasons.

## 8. UI

Offseason overview shows clearance status and navigation. Clearance screen shows
gate status/reasons, shortages/blockers, human offers with explicit confirmation,
available players with salary input, pending offers, resolution, outcomes and a
Confirm Cleared action only when ready. Hidden data is not shown. 360×640 and
393×852 supported.

## 9. Acceptance criteria

- **AC-T08H-01** Rejection linkage requires exact terms/reason, not any earlier
  rejection.
- **AC-T08H-02** Premature draft/AI/market/recovery states block readiness.
- **AC-T08H-03** Roster, contract, cap, cash and pool validity are enforced.
- **AC-T08H-04** Standard 14 minimum; two-way and training-camp players do not
  satisfy it.
- **AC-T08H-05** Exact approved cap exception only; maximum 800; no premium or
 repeat; no cash loan.
- **AC-T08H-06** One bounded clearance pass; no unlimited rounds.
- **AC-T08H-07** Human and AI offers compete under T08E/ranker; no priority.
- **AC-T08H-08** Clearance preserves identity/contracts and records one
  acquisition per player.
- **AC-T08H-09** v1–v12 migration; native v13 strict; save/resume deterministic.
- **AC-T08H-10** Completion gate blocks while any franchise fails; no season
  advance.
- **AC-T08H-11** UI shows actionable blockers and fits both widths.
- **AC-T08H-12** Existing T08C–T08G-P1, financial, rookie and M007 tests pass.

## 10. Non-goals

Season advance, schedule, trades, waivers, expiry, renewal, retirement,
development, new draft class, unlimited market rounds, staff/facilities, new
salary values.
