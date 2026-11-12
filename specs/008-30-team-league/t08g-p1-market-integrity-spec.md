# M008-T08G-P1 Specification — Market Integrity & Allocation Repair

Status: repair contract. Baseline:
`feat/m008-t08g-competitive-free-agency` at
`9bae14a132a2fb57578a586e097507a516f49e9c`.
Branch: `fix/m008-t08g-p1-market-integrity`.

## 1. Confirmed findings

1. `CompetitiveOfferRanker` used a pairwise 10% salary band before fit. The
   comparison was not a total ordering and could cycle across three offers.
2. `startRound(2)` cleared active-round offers/outcomes/order. Acquisitions
   survived but the round audit trail was lost.
3. Market outcome validation did not require exactly one result for every
   submitted offer and did not check result team/player against the offer.
4. The controller retained an accessible immediate `submitFreeAgentOffer`
   command, allowing the human to bypass shared market competition.
5. AI generated 235–260 offers per scenario but concentrated them on only 24–33
   unique players; max 26 offers per player, 9–13 AI teams losing every offer,
   40–46 vacancies. This is excessive concentration/poor diversification, not
   player supply or cap/cash shortage (0 cash-bound teams, 4–5 cap-bound).

## 2. Ranking correction

Replace pairwise comparison with an additive integer utility:

```
utility = salary * 10 + fitBasisPoints - |duration - preferred| * 100
```

Fit is the same public situation/position-depth score as T08E (max ±2,000).
Salary is weighted 10 CU per salary CU; duration costs at most 300. Effective
ranking is a total order by `(utility desc, FNV tie-break, offerId)`. An additive
score cannot produce a comparator cycle because it compares a single integer per
offer, independent of the other offer. No salary/financial constant changes.

## 3. Durable round history

Add immutable `FreeAgentMarketRoundRecord` snapshots:

- round number, season;
- submitted human/AI offers;
- resolution order;
- every outcome, winning offer/team and reason codes.

Active-round state remains separate. On completion the snapshot is appended and
never mutated; starting Round 2 clears only active offers/outcomes/order. History
is persisted in schema v12. v1–v11 migrate; v11 round history that was already
discarded remains unavailable and is not invented. Historical acquisitions and
T08F offer records are preserved.

## 4. Strict market validation

For every resolved player:

- each submitted offer has exactly one outcome;
- no duplicate outcomes;
- outcome/result player and team match the offer;
- winner references an accepted submitted offer;
- at most one accepted offer;
- accepted offer has a matching acquisition and contract/schedule;
- rejected result has a matching formal rejection attempt;
- outbid/financially unavailable results do not create rejection attempts;
- cursor equals resolved-prefix length;
- completed outcome list covers the full resolution order;
- round history records are contiguous and cannot exceed completed rounds.

Attempt-limit overflow during resolution is an explicit typed error, not a silent
skip.

## 5. Human bypass removal

Remove `GmCareerController.submitFreeAgentOffer`. New human actions use
`startFreeAgencyRound` → `stageFreeAgentOffer` → `prepareFreeAgencyResolution` →
`resolveFreeAgencyRound`.

Historical T08F accepted offers/acquisitions and `FreeAgentOfferSubmissionService`
remain readable/usable by domain tests and migration tooling, but no controller
or UI path exposes immediate signing.

## 6. AI allocation correction

Measured root cause: concentration, not supply or finances. Bounded correction:

- AI teams are processed in a deterministic team/round hash order, not league
  order.
- Candidate ranking adds a global target-count penalty, so later teams prefer
  uncontested players.
- Two-way offers limited to one per team per round (standard need unchanged).
- Reservation model unchanged: cap, cash, category and total roster checks still
  apply to every portfolio.

No new rounds, no hidden acceptance discounts, no forced signings, no artificial
removal.

## 7. Offseason ordering

Correct order: career generation → completed rookie draft → AI rookie signing
decisions → market rounds 1 and 2. Human does not have to sign all draft rights
before free agency. Diagnostic evidence runs both market-only and full
draft/AI-signing sequences. No season advance.

## 8. Acceptance criteria

- **AC-P1-01** Ranker is antisymmetric, transitive, deterministic and
  permutation-independent; three-offer cycle cannot occur.
- **AC-P1-02** Round 1 history survives Round 2 and save/load immutably.
- **AC-P1-03** Missing/duplicate/wrong-player/wrong-team outcomes are rejected.
- **AC-P1-04** Accepted outcome links one acquisition/contract; rejected outcome
  links one formal attempt; outbid/financial unavailable consume none.
- **AC-P1-05** No controller/UI immediate-signing bypass exists; historical saves
  still load.
- **AC-P1-06** AI offer diversification materially reduces concentration and
  vacancies without forcing readiness.
- **AC-P1-07** Every prepared AI portfolio remains financially safe.
- **AC-P1-08** v1–v11 migrate; native v12 requires market and history.
- **AC-P1-09** Failed writes block; reload resumes; no duplicate acquisitions.
- **AC-P1-10** Existing T08D–T08G, rookie, finance and M007 regressions pass.
- **AC-P1-11** Mobile layouts remain valid.

## 9. Non-goals

Season advancement, extra rounds, cap/salary changes, relief, trades, waivers,
renewal, expiry, staff, facilities, development, new rookie generation, full
calendar.
