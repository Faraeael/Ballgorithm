# M008-T08H-P2 Amendment — Bounded Hardship Contracts

Status: **owner-approved policy; implementation authorized**.

Baseline: `fix/m008-t08h-p1-clearance-feasibility` at
`32a8cef9b49e337d86711f4d5af7a1308296937a`.
Implementation branch: `feat/m008-t08h-p2-hardship-contracts`.
Owner approval: explicit authorization received in the current T08H-P2 owner instruction. The earlier `approve_exact` claim was unverified and is not relied upon.

This amendment supplements the frozen T08H specification. It does not rewrite
T08H's historical evidence or change its existing ordinary minimum-roster relief.

## 1. Purpose and boundary

After both competitive market rounds and the original bounded clearance finish,
a separate one-time hardship settlement may offer standard contracts to
franchises still unable to reach 14 standard players under current rules.

Hardship settlement is not a third market round. It does not advance the season.
It does not create players, waive acceptance, discount salaries, lend cash, alter
existing agreements, or change the ordinary 41,000 CU salary cap.

## 2. Approved financial policy

- Ordinary cap remains **41,000 CU**.
- Ordinary minimum salary remains **400 CU**.
- Existing ordinary relief remains minimum-only, exact-need, at most **800 CU**.
  `FinancialRules.maximumReliefOverage` remains 800.
- Add separate hardship authority. Combined ordinary plus hardship overage may
  not exceed **1,000 CU per franchise per season**.
- The 1,000 CU ceiling includes ordinary relief. It is not an additional 1,000 CU.
- Approve only the exact hardship amount required by the sealed contract offers.
  For payroll `P`, cap `C`, ordinary relief `E`, and the team’s sealed first-year
  salaries `S`, hardship amount is `max(0, P + sum(S) - C - E)`. Reject the
  authorization if `E + hardship amount > 1,000`.
- Reserve current-year cash for every sealed offer. Reject offers whose total
  projected cash is negative.
- Use existing standard salary bounds, contract duration limits, 5% annual
  raises, full guarantees, and T08E player acceptance without discounts.

P1 observed a maximum total overage of 910 CU: payroll 40,810 CU, cap room
190 CU, ordinary exception 210 CU, and willing salary 1,100 CU. The needed
hardship increment was 700 CU. The 1,000 CU ceiling leaves 90 CU for that case;
it is a prototype ceiling, not a guarantee for other seeds.

## 3. Eligibility and offer selection

A team may receive hardship offers only when all conditions hold:

1. Career remains in the opening offseason; both competitive market rounds and
   original clearance are complete.
2. Team has 12 or 13 standard players and at most two standard vacancies.
3. Existing normal cap room plus approved ordinary relief cannot fund an
   available, player-acceptable standard contract.
4. An available free agent accepts the exact salary and duration under the
   existing public-information evaluator.
5. The contract fits current-year cash, roster capacity, the combined 1,000 CU
   ceiling, and remaining formal player-side attempts.
6. No hardship settlement has already run for this career season.

Only mandatory vacancies may receive offers. Each team submits no more offers
than its vacancy count. No 15th standard signing is permitted.

For each candidate and legal standard duration, find the cheapest salary that
`evaluateWillingness` accepts. Use only public player data and existing
acceptance rules. Select candidate contracts deterministically; prefer the
lowest first-year salary, then lowest guaranteed schedule total, then shorter
duration, then stable player ID. Skip unavailable, previously acquired,
capacity-blocked, cash-ineligible, or attempt-exhausted players.

Human participation requires explicit confirmation of the displayed proposal
terms. A human may decline; the team then remains blocked if it has vacancies.
AI uses the same player-acceptance evaluator, financial rules, and competitive
ranker. No human priority applies. AI decisions use stable deterministic order.

If multiple teams target one player, resolve all acceptable offers with the
existing competitive ranking policy. Record player rejection only when the
player-side evaluator rejects a formally submitted offer. Financially illegal
offers are not player refusals.

## 4. Authorization and transaction integrity

Persist hardship settlement state separately from `OffseasonClearanceState`.
Use a distinct hardship offer type, authorization record, outcome, status, and
resolution cursor; do not encode hardship as market round 4 or append it to
completed clearance history.

Each team authorization records team, season, exact additional amount, existing
ordinary relief, the 1,000 CU combined ceiling, initial shortage, reason, exact
sealed offer/contract references, and unused/consumed state. One authorization
covers only its listed offers in this one settlement. Track actual relief used.

Keep `TeamFinances.capException` as ordinary relief. Treat hardship authority as
a separate source of truth in the career aggregate. Career validation must
cross-check every authorization against the exact team, current season, initial
shortage, sealed offers, current contracts, acquisition origin, and resolution
outcomes. Only validated hardship authority may be passed to cap validation.

`FreeAgentAcquisitionService` must require explicit `AcquisitionOrigin.hardship`
and the exact active hardship offer authorization. Generic and ordinary
clearance acquisitions cannot spend hardship relief. Reject cross-team,
wrong-season, forged, stale, duplicate, over-ceiling, optional-roster, or
already-consumed authorizations. A hardship acquisition must conserve player,
contract, schedule, acquisition, formal-attempt, offer-result, and authorization
identity in one valid career transition.

## 5. Settlement, persistence, and recovery

The settlement is one bounded, deterministic resolution sequence. Persist each
complete player resolution before starting the next. Store offers, auth records,
outcomes, cursor, acceptance records, and acquisition linkage in the career.
Only completed atomic resolution states may be saved; no replay or duplicate
result is allowed after interruption.

Use career schema **v14** for the new required hardship state. Decode valid
schemas v1–v13 with empty hardship state; keep native v13 strict for its existing
required fields; require the hardship field for native v14. Preserve all
historical contracts, finances, draft records, free-agent market/clearance
history, and v13 acquisition origins.

On uncertain write failure, block further career commands until explicit reload.
Inject a failure after one committed player resolution, exercise a subsequent
write/promotion failure, reload the saved career, reconcile the persisted cursor,
and finish. Compare final roster, contract identities/schedules, acquisition
history, authorizations, outcomes, and cursor against uninterrupted execution.

Hardship relief applies only to the authorized opening-season transaction path.
Contract schedules and future guaranteed salary obligations remain unchanged.
No hardship exception automatically renews in a later season. Season transition,
contract expiry, and renewal remain out of scope.

## 6. Readiness and user interface

`OffseasonReadinessGate` blocks while an eligible hardship settlement is
unresolved, while recovery is required, or while any franchise violates roster,
contract, financial, cash, ownership, pool, or transaction integrity rules.
An empty or completed settlement does not waive roster minimums. All 30 teams
must pass before `readyForConfirmation`; explicit human confirmation remains
required to mark offseason cleared. That action must not advance the season.

For an eligible human team, show its vacancies, payroll, normal room, ordinary
relief, exact proposed additional authority, combined overage, exact contract
terms and future salary schedule, projected cash, and explicit confirm/decline
controls. Show blockers for ineligible or still-short teams. Do not expose hidden
potential, trajectory, or internal acceptance thresholds as negotiation advice.
Preserve 360x640 and 393x852 usability.

## 7. Acceptance criteria

1. Only eligible teams receive hardship offers or authorizations.
2. Ordinary 41,000 CU cap and 800 CU ordinary relief rule remain unchanged.
3. Combined overage never exceeds 1,000 CU; multiple offers cannot stack beyond
   that total.
4. Player acceptance is mandatory and evaluated independently from financial
   legality.
5. Generic acquisitions cannot spend hardship authority.
6. Optional 15th-player hardship acquisition is rejected.
7. Player ownership, contract count, contract schedule, cash, and future
   commitments remain consistent.
8. Authorization is team-, season-, offer-, and contract-specific; forged,
   duplicate, stale, replayed, cross-team, or consumed use is rejected.
9. Human and AI offers compete under the same deterministic ranking rules.
10. Human participation requires explicit confirmation; decline leaves vacancies
    blocked.
11. Deterministic runs use seeds 20261028, 1604126146, and 987654321 across
    Tanking, Play-In, Playoff, and Contender human situations.
    Pre-registered held-out diagnostic seeds: `314159265`, `271828182`, and
    `8675309`. These seeds will not be used to adjust the approved policy.
12. At least three additional seeds are recorded before evaluation and remain
    held out from policy adjustment.
13. Diagnostics report pre/post readiness, vacancies, eligible teams, offers,
    refusals, outbids, acquisitions, exact ordinary/hardship relief, additional
    unmet amount, projected cash, future commitments, and remaining blockers.
14. Unresolved economics stay blocked; no forced positive result.
15. Save-failure injection proves reload reconciliation and deterministic
    continuation after an uncertain write.
16. Schema v14 rejects missing/corrupt native hardship state and preserves valid
    v1–v13 careers without rewriting existing agreements.
17. Readiness requires draft, AI rookie decisions, both market rounds, original
    clearance, and any started hardship settlement to be complete; all teams
    pass roster, contract, finance, cash, ownership, pool, and recovery checks.
18. No season advancement, cash loan, salary discount, new player, new market
    round, new waiver/trade mechanism, or automatic future hardship renewal.
19. Existing T08D–T08H-P1 regressions, M007 save isolation, required root/core
    checks, and both UI viewport sizes pass.

## 8. Evidence and review gates

Record exact commands, tool outputs, seed/situation results, test environments,
source changes, JEV findings, and unresolved risks in a separate P2 evidence
report. JEV is review input only; deterministic validation and injected failure
tests remain mandatory. Do not start the regular season or another milestone.
