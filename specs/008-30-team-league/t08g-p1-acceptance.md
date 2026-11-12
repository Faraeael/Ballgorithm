# M008-T08G-P1 Acceptance — Market Integrity & Allocation Repair

Status: **implemented, verified; owner acceptance pending**.
Date: 2026-11-12. Baseline:
`feat/m008-t08g-competitive-free-agency` at
`9bae14a132a2fb57578a586e097507a516f49e9c`.
Branch: `fix/m008-t08g-p1-market-integrity`.

## 1. Confirmed root causes

1. Pairwise 10% salary-band ranking was not a total ordering and could cycle.
2. Round 2 erased active Round 1 offers/outcomes/order; acquisitions survived
   but competitive history did not.
3. Outcome validation did not require one result per offer or match result
   player/team to the offer.
4. The controller exposed an immediate signing command outside the shared market.
5. AI offers concentrated on 24–33 unique players: 235–260 offers, max 26 per
   player, 9–13 AI teams losing every offer, 40–46 vacancies. Cash was not
   binding; only 4–5 teams were cap-floor constrained.

## 2. Ranking correction

Single additive integer utility:

```
utility = salary * 10 + fitBasisPoints - |duration - preferred| * 100
```

Fit is the public T08E situation/position-depth score (max ±2,000); duration
costs at most 300. Ranking is `(utility desc, FNV(player/team/round) desc,
offerId)`. A scalar score is a total order, so antisymmetry and transitivity hold
by construction and no comparator cycle is possible. Salary remains dominant;
fit can decide near-equal offers. No financial constant changed.

## 3. Durable round history

Schema v12 adds immutable `FreeAgentMarketRoundRecord` snapshots: round, season,
submitted human/AI offers, resolution order, every outcome/winner/reason. On
completion the snapshot is appended once; Round 2 clears only active state.
History survives save/load and is retained across Round 2. v11 round history that
was already discarded is not invented; v11 migrates with empty history and
existing acquisitions/offers intact.

## 4. Strict validation

- Every resolved player has exactly one outcome per submitted offer.
- No duplicate results; result player/team must match the offer.
- Winner references an accepted submitted offer; at most one accepted.
- Accepted outcome requires acquisition, contract and schedule.
- Rejected outcome requires a matching formal rejection attempt.
- Outbid/financially unavailable do not create rejection attempts.
- Cursor equals the resolved prefix; completed outcomes cover the full order.
- Round history is contiguous and cannot exceed completed rounds.
- Attempt-limit overflow now throws a typed error instead of silently skipping.

## 5. Human bypass closure

`GmCareerController.submitFreeAgentOffer` removed. Human UI uses start → stage →
prepare → resolve. Historical T08F saves and the low-level
`FreeAgentOfferSubmissionService` remain readable/usable for domain tests and
migration, but no controller/UI immediate-signing entry point exists.

## 6. AI allocation correction

- AI teams processed in deterministic team/round hash order.
- Candidate sort adds a global target-count penalty for diversification.
- Two-way offers capped at one per AI team per round.
- Reservation model unchanged: cap, cash, standard/two-way/total roster.

Measured before → after (market-only):

| Metric | Before | After |
|---|---|---|
| AI offers | 235–260 | 107–124 |
| Unique AI targets | 24–33 | 70–72 |
| Max offers/player | 20–26 | 3–5 |
| AI acquisitions | 24–33 | 70–72 |
| Losing AI teams | 9–13 | 0 |
| Remaining free agents | 55–66 | 18–20 |
| Standard vacancies | 40–46 | 3–7 |

Full draft + AI rookie-signing sequence: 46–51 unique targets and 46–51
acquisitions after correction. AI still does not force readiness; 3–7 vacancies
remain.

## 7. Verification

- Core `dart analyze`: clean.
- Core `dart test`: **917 passed**.
- Root `flutter analyze`: clean.
- Root `flutter test`: **225 passed**.
- T08C financial audit: 48 validations, 0 over-cap.
- T08E calibration: 268 acceptable / 2 salary-too-low at estimate.
- Ranking tests: three-offer cycle, antisymmetry, transitivity, all permutations,
  deterministic repeat.
- Market tests: history persistence, malformed outcome rejection, diversification,
  hidden information neutrality, v1–v11 migration, native v12 strictness.
- Save/recovery tests: prepared offers, interrupted resolution, failed writes,
  duplicate-submission blocking.
- Mobile layouts: existing 360×640 and 393×852 tests pass.

## 8. JEV

Transitivity 0.95, history integrity 0.92, outcome/offer linkage 0.85, AI
allocation 0.93. Recommendation **GO 0.97**, confidence 0.96. This resolves the
prior low integrity review: duplicate-acquisition and outcome-coverage checks plus
the additive ranker were added after it.

## 9. Remaining limitations

- AI offers near accepted maxima, so player rejection remains rare.
- Two rounds still leave a few vacancies; readiness is not forced.
- The design is a calibrated policy, not observed market prices.
- v11 histories discarded before v12 are unavailable and not reconstructed.
- No season advance, extra rounds, trades, waivers, renewal, expiry, relief,
  staff, facilities or development.

## 10. Recommendation

**GO for an offseason clearance gate.** The ranking, history, linkage and
allocation risks identified in T08G are addressed with deterministic tests and
before/after evidence. Proceed to a separately authorized offseason clearance
milestone; do not advance the season here.
