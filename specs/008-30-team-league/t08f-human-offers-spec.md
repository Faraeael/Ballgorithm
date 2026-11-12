# M008-T08F Specification — Human Free-Agent Offer Workflow & Signing UI

Status: implementation contract. Baseline:
`feat/m008-t08e-free-agent-market-policy` at
`292b7d73eb9d2d3cb7b360fa4d742b3b027e7b72`.
Branch: `feat/m008-t08f-human-free-agent-offers`.

## 1. Scope

The human franchise can browse public free agents, see the T08E market estimate,
propose explicit terms, submit a formal offer, receive the player decision, and
acquire only when T08E accepts. No second valuation model and no direct UI path
to the raw acquisition service.

## 2. Formal offer persistence

`FreeAgentOfferAttempt` stores:

- deterministic offer id (`free-agent-offer-<team>-<player>-<season>-<attempt>`);
- player, team, season;
- category, duration, first-year salary;
- player-side outcome: accepted, salaryTooLow, unfavorableDuration, poorFit,
  inappropriateCategory;
- public reason code;
- attempt number;
- acquisition transaction id only when accepted.

`FreeAgentOfferLedger` is persisted in the career. It enforces unique offer ids,
unique `(team, player, season, attempt)`, contiguous attempt numbers 1–2, at most
two attempts, at most one accepted offer, accepted as the final attempt, and no
acquisition link on a rejection.

Invalid terms and financially illegal proposals are **not** player-side attempts
and are not persisted.

## 3. Attempt policy

Maximum two formal player-side offers per player, per franchise, per opening
offseason:

- first offer may be accepted or rejected;
- one improved second offer is allowed;
- after two player-side attempts the player is blocked for that franchise;
- an identical repeat of a rejected offer is blocked without consuming an
  attempt;
- an acquired player cannot be offered again;
- restarts preserve attempts;
- failed writes consume nothing because the record is only published after a
  successful save;
- invalid/financially illegal offers consume nothing.

This is provisional. It does not model an offseason calendar, negotiation rounds
or competing offers.

## 4. Submission sequence

`FreeAgentOfferSubmissionService.submit`:

1. evaluate the offer through T08E;
2. if invalid terms or financially illegal, return a non-recorded result;
3. check attempt limit and identical-repeat policy;
4. if accepted, call T08D acquisition;
5. if rejected, append a rejection record;
6. append the accepted record linked to the acquisition transaction;
7. return one validated `GmCareer`.

The accepted record and acquisition are committed together in the returned
career. The controller persists that complete state before publishing it.

## 5. Schema v10

Career schema 10 requires `freeAgentOffers`. v1–v9 migrate to an empty ledger.
Free-agent pool, acquisitions, contracts, schedules, rookies, profiles, staff
and facilities are preserved. Native v10 missing/invalid offers are rejected.
M007 save isolation is untouched.

## 6. Controller

`submitFreeAgentOffer` replaces the user-facing `acquireFreeAgent` path. It uses
the serialized command queue, rechecks career identity, persists recorded
results before publication, preserves the prior committed state on failure, and
requires reload after an uncertain write. The low-level T08D service remains
available only to domain code/tests.

## 7. UI

Board: public attributes, OVR, age, position, expected role, market estimate,
remaining attempts, Make Offer. Hidden potential/trajectory never shown.

Offer form: standard/two-way category, category duration limits, salary input,
schedule preview, cap room, cap/cash payroll impact, projected cash, roster
capacity, remaining attempts. No acceptance threshold, fit coefficient or
guaranteed acceptance is displayed. Salary changes do not call the evaluator.
A confirmation dialog is required; Cancel writes nothing.

Results: accepted (persisted acquisition, pool shrink, roster update), rejected
(salary/duration/fit/category explanation, durable record), invalid/financial
(no attempt), or save failure (no published state, reload required).

## 8. Readiness and fairness

Standard acquisition updates roster, cap, cash, pool count, standard shortage and
league readiness. Two-way does not reduce standard shortage. RosterRules remains
the readiness authority. AI free-agent bidding is not implemented; human access
to the market before AI clubs is a documented limitation.

## 9. Acceptance criteria

- **AC-T08F-01** Accepted offer records once, links one acquisition, and shrinks
  the pool by one.
- **AC-T08F-02** Rejected offers persist and do not acquire or change payroll.
- **AC-T08F-03** Two formal player-side attempts maximum; third is blocked.
- **AC-T08F-04** Identical rejected offer is blocked without consuming an attempt.
- **AC-T08F-05** Invalid/financially illegal offers are not recorded.
- **AC-T08F-06** Attempts survive restart; failed save consumes nothing.
- **AC-T08F-07** Acquired player cannot be offered again.
- **AC-T08F-08** Existing contracts/schedules remain byte-identical.
- **AC-T08F-09** Accepted player identity/profile and hidden data stay protected.
- **AC-T08F-10** v1–v9 migration and native v10 strictness hold.
- **AC-T08F-11** UI hides thresholds and potential/trajectory; fits 360×640 and
  393×852.
- **AC-T08F-12** Standard/two-way roster and financial updates are correct.
- **AC-T08F-13** Existing T08D/E, rookie, finance, M007 and regression suites
  pass.

## 10. Non-goals

AI offers/bidding, auctions, negotiation RNG, multi-round calendar, trades,
waivers, renewal, expiry, relief, staff, facilities, dashboard redesign, season
advancement, salary-constant changes.
