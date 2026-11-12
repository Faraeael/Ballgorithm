# M008-T08F Acceptance — Human Free-Agent Offer Workflow & Signing UI

Status: **implemented, verified; owner acceptance pending**.
Date: 2026-11-12. Baseline:
`feat/m008-t08e-free-agent-market-policy` at
`292b7d73eb9d2d3cb7b360fa4d742b3b027e7b72`.
Branch: `feat/m008-t08f-human-free-agent-offers`.

## 1. Formal offer persistence

`FreeAgentOfferAttempt` records offer id, player, team, season, category,
duration, first-year salary, player-side outcome, public reason code, attempt
number, and the acquisition transaction id only when accepted.
`FreeAgentOfferLedger` persists in career schema v10 and enforces unique ids and
keys, contiguous attempts 1–2, maximum two per player/team/season, accepted as
the final attempt, and no acquisition link on a rejection.

Invalid terms and financially illegal proposals are not recorded as player-side
attempts.

## 2. Anti-exploit policy

- Maximum two formal player-side offers per player/team/opening offseason.
- After two player-side attempts, the third is blocked.
- Identical repeat of a rejected offer is blocked without consuming an attempt.
- Invalid/financial offers consume nothing.
- Accepted players cannot be offered again.
- Restarts preserve attempts; failed writes consume nothing.
- No random cooldown, reroll or clock input.

## 3. Transaction sequence

`FreeAgentOfferSubmissionService.submit`:

1. T08E evaluation;
2. invalid/financial → non-recorded result;
3. attempt/identical checks;
4. accepted → T08D acquisition, then accepted offer linked to the acquisition;
5. rejected → durable rejection record only;
6. return one validated career.

`GmCareerController.acquireFreeAgent` was removed from the user-facing path.
`submitFreeAgentOffer` uses the serialized queue, rechecks career identity,
persists before publishing, preserves the prior state on failure and requires
reload after an uncertain write.

## 4. UI

Board: public name, position, age, OVR, attributes, estimate, expected role,
remaining attempts, Make Offer.

Offer form: category, category duration, salary, schedule, cap room, proposed
cap/cash payroll, projected cash, roster capacity, remaining attempts.
Confirmation dialog requires explicit Submit; Cancel writes nothing. No exact
threshold, fit coefficient, potential or trajectory is displayed. Salary input
does not call the evaluator.

Outcomes: accepted (saved acquisition, pool shrink, roster update), rejected
(durable reason), invalid/financial (no attempt), save failure (no publication,
reload required).

## 5. Deterministic walkthrough

`t08f-walkthrough.md`, seed `20261028`, four situations:

| Situation | Pool | Accepted | Rejections | Third blocked | Two-way | Shortage |
|---|---|---|---|---|---|---|
| Tanking | 90 → 88 | accepted | rejected, rejected | true | accepted | 2 → 1 |
| Play-In | 90 → 88 | accepted | rejected, rejected | true | accepted | 2 → 1 |
| Playoff | 90 → 88 | accepted | rejected, rejected | true | accepted | 2 → 1 |
| Contender | 90 → 88 | accepted | rejected, rejected | true | accepted | 2 → 1 |

Each accepted offer is linked to one acquisition and survives save/load. The
two-way acquisition does not reduce the standard shortage.

## 6. Schema v10

- Native v10 requires `freeAgentOffers`.
- v1–v9 migrate to an empty ledger.
- Pool, acquisitions, contracts, schedules, rookies, profiles, staff and
  facilities are preserved.
- Missing/corrupt v10 offers are rejected.
- Free-agent pool is not regenerated.

## 7. Verification

- Core `dart analyze`: clean.
- Core `dart test`: **898 passed**.
- Root `flutter analyze`: clean.
- Root `flutter test`: **225 passed**.
- T08C financial audit: 48 validations, 0 over-cap.
- T08D acquisition and T08E market suites pass.
- Width tests: 360×640 and 393×852.
- Format check: clean.

## 8. JEV

Transaction integrity 0.92, replay/exploit 0.94, UI disclosure 0.92.
Recommendation **GO 0.66**, confidence 0.49 (conditional 0.25). Advisory only;
the low confidence reflects the intentionally incomplete league-wide AI market.

## 9. Remaining risks and limitations

- Human clubs act before AI clubs; the market is not league-balanced yet.
- No AI offers, bidding, auctions, negotiation rounds, offseason calendar,
  trades, waivers, renewal, expiry, relief, staff, facilities or season advance.
- Two-attempt rule is provisional.
- The offer UI shows public estimates, not a guarantee of acceptance.
- Readiness remains RosterRules-derived; no automatic season readiness.

## 10. Recommendation

**GO for owner acceptance of T08F.** T08G should add fair AI access to the same
free-agent pool and T08E acceptance policy, then an offseason clearance flow.
