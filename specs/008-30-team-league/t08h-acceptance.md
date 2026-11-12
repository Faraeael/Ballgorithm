# M008-T08H Acceptance — Offseason Clearance & League Readiness Gate

Status: **implemented, verified; league completion BLOCKED**.
Date: 2026-11-12. Baseline:
`fix/m008-t08g-p1-market-integrity` at
`3e454a929ab6c87b9071e58ea1906eca18ad729e`.
Branch: `feat/m008-t08h-offseason-clearance`.

## 1. Readiness gate

`OffseasonReadinessGate` is read-only and checks draft completion, AI rookie
decisions, both market rounds, unresolved clearance/recovery, career financial
and contract validation, every franchise's `RosterRules` readiness, roster/
contract ownership and pool accounting. Unsigned draft rights are not an
automatic blocker.

Statuses: offseasonInProgress, clearanceRequired, financialExceptionRequired,
readyForConfirmation, cleared. Returns per-team counts/blockers.

## 2. Rejection linkage

Rejected market outcomes now require the formal attempt to match team, player,
season, category, duration, first-year salary and reason code. Historical round
outcomes are revalidated. An unrelated earlier rejection cannot satisfy a later
outcome.

## 3. Cap exception approval and use

Owner approved a bounded minimum-roster exception on 2026-11-12. Implemented:

- 12–13 standard players, 1–2 missing;
- only 400 CU minimum deals;
- exact overage = 400 × missing − cap room, capped 800;
- no premium salary/optional expansion/repeat/cash loan;
- salary cap constant unchanged;
- exception stored on `TeamFinances.capException` and clearance state;
- evaluator, acquisition, clearance reservation and career validation honor the
  exact amount.

Tested exceptions: `team-19:380`, `team-19:60`, `team-23:400`, `team-24:40`,
`team-28:350`, `team-12:220`, `team-21:60`, `team-24:170`, `team-27:210`.
Actual maximum used 400; structural max 800. Cash sufficient; no advances.

## 4. Clearance mechanism

One bounded pass after both rounds: start grants exact exceptions; human offers
are explicit and confirmed; AI offers are sealed/deterministic; resolution uses
T08E, the competitive ranker and T08D acquisition; only standard deals needed to
reach 14; each decision saved; no third market round; history untouched.

Schema v13 persists status, offers, order/cursor, outcomes and exceptions.
v1–v12 migrate with empty clearance; native v13 is strict. No acquisition replay.

## 5. Diagnostics

`t08h-clearance-diagnostics.md`, full sequence (draft → AI rookie signings →
market Rounds 1+2 → readiness → one clearance pass with human offers).

| Seed | Situation | Ready before | Shortage before | Clearance buys | Gate after | Shortage after | Human after |
|---|---|---|---|---|---|---|---|
| 20261028 | Tanking | 28 | 3 | 2 | clearanceRequired | 1 | 0 |
| 20261028 | Contender | 28 | 3 | 1 | clearanceRequired | 2 | 1 |
| 1604126146 | Tanking | 24 | 7 | 2 | clearanceRequired | 5 | 0 |
| 1604126146 | Contender | 25 | 6 | 1 | financialExceptionRequired | 5 | 1 |
| 987654321 | Tanking | 26 | 5 | 2 | clearanceRequired | 3 | 0 |
| 987654321 | Contender | 25 | 6 | 1 | clearanceRequired | 5 | 1 |

Human shortages are filled in most scenarios; remaining human needs in
contender scenarios require additional human choices. No scenario reached
`readyForConfirmation` or `cleared`.

## 6. Remaining blockers

After clearance, one or more franchises remain below 14 because no remaining
free agent accepts a legal 400 CU minimum offer (e.g., KSM cap room 20 with an
approved 380 exception, acceptable offers 0). This is a **player-acceptance**
blocker under the minimum-only relief policy, not a supply or cash problem.
The gate returns `clearanceRequired`/blocked with team-level reasons and refuses
completion. No fictitious player, premium salary, waiver, trade or repeated pass
was introduced.

## 7. Verification

- Core `dart analyze`: clean.
- Core `dart test`: **923 passed**.
- Root `flutter analyze`: clean.
- Root `flutter test`: **226 passed**.
- T08C audit: 48 validations, 0 over-cap.
- T08E calibration: 268 acceptable / 2 salary-too-low at estimate.
- T08G-P1 allocation diagnostics: unique targets 70–72, vacancies 3–7 after
  market; see P1 evidence.
- Clearance tests: premature gate, precise status, exact exceptions, human
  clearance fill, blocked mark-cleared, v12→v13 migration.
- Clearance UI: 360×640 and 393×852; actionable draft blocker.

## 8. JEV

Readiness 0.89, relief 0.93, clearance integrity 0.27; recommendation
CONDITIONAL 0.52 (NO-GO 0.44, GO 0.04), confidence 0.28. Readiness and relief
were accepted as conceptually sound; clearance integrity remains below the bar.
The judge did not provide a concrete reproduction. Additional checks were added
after the review: exact rejection linkage, cap-exception missing-spot bounds,
per-team clearance contract limit, clearance acquisition origin, and a
resolution-time guard preventing optional expansion above 14. The residual low
score is recorded as an open review item, not dismissed.

## 9. Limitations

- League completion is blocked by minimum-only player acceptance for one or more
  AI teams; no premium relief or cash loan was authorized.
- Clearance is one pass; no negotiation, third market round, trades or waivers.
- Existing T08F saves retain historical advantage.
- No season advance, schedule, ages, revenue, contract expiry or renewal.

## 10. Recommendation

**NO-GO for a season-start milestone.** The readiness gate correctly blocks the
league. T08H is accepted as a functional clearance/readiness foundation, but the
remaining AI minimum-offer acceptance blockers require an owner decision on an
additional bounded mechanism (for example premium minimum-relief eligibility or
an approved roster-completion path) before season start.
