# M008-T08G Specification — Competitive AI Free Agency & Shared Market Rounds

Status: implementation contract. Baseline:
`feat/m008-t08f-human-free-agent-offers` at
`f22b24138aea550e0101c1877925487fa47d5c49`.
Branch: `feat/m008-t08g-competitive-free-agency`.

## 1. Scope

Two explicit opening-offseason rounds let the human and 29 AI franchises stage
offers for the same available free agents. No player is acquired at staging.
Offers are sealed, then resolved one player at a time through the same T08E
acceptance policy and T08D acquisition engine. No season advance.

The old T08F immediate submission path remains a low-level historical/domain
operation for existing data and tests; the user-facing UI no longer calls it.

## 2. Market-round state

`FreeAgentMarketState` persists:

- status: notStarted, collectingHumanOffers, preparedForResolution, resolving,
  roundComplete, marketComplete, recoveryRequired;
- round 1 or 2;
- season year;
- staged human offers;
- sealed AI offers;
- sorted resolution order;
- resolution cursor;
- per-player outcomes;
- completed-round count.

`FreeAgentMarketOffer` stores offer id, player, team, round, season, category,
duration, first-year salary, source (human/AI). Pending is not accepted.
`FreeAgentMarketOutcome` stores winner and per-offer result: accepted, rejected,
outbid, financiallyUnavailable, invalid.

Round 1 is the opening competition; Round 2 covers remaining players/needs.
Starting a round is explicit. No AI acquisition occurs on load, app open or board
view. No automatic season advance.

## 3. Human staging

Only the human franchise can stage through the UI. A staged offer:

- must be term-valid and financially legal at staging;
- must respect remaining player-side attempts;
- is reserved against cap, cash, standard/two-way/total roster capacity;
- one pending offer per player/team/round;
- does not acquire, does not consume an attempt, and does not reveal the player
  decision.

Pending offers can be cancelled before locking. Locking seals AI offers and
freezes human offers; no edits after lock.

## 4. AI offer policy

`AiFreeAgentOfferPolicy` uses public player data only: OVR, age, position,
observable attributes, market valuation, roster composition, shortages, cap,
cash, contracts and situation. No hidden potential/trajectory/progression,
human intentions or generation data.

For every AI franchise it fills standard roster need first, then two-way need,
within cap/cash/capacity and reservation limits. It uses T08E to ensure the
proposed terms are financially legal and acceptable; it may raise to the public
acceptable maximum if affordable. Candidate ordering depends on situation,
position depth and stable FNV-1a tie-breaks. Offers are persisted before
resolution and are stable after restart. No AI offer is generated for a player
with no remaining player-side attempts for that team.

## 5. Competitive selection

All offers for one player are evaluated with T08E. Results distinguish:

- invalid/financially illegal → financiallyUnavailable (no player attempt);
- player rejection → rejected (durable T08F attempt);
- acceptable losers → outbid (no rejection attempt);
- winner → accepted/acquisition.

Among acceptable offers, the ranker compares annual salary first, then preferred
duration closeness, then public situation/role fit, then a deterministic FNV-1a
tie-break over player/team/round. Team iteration order and human identity do not
decide. If an offer fails at acquisition due to changed financial state, it is
marked financiallyUnavailable and the next ranked offer is tried.

Resolution order is sorted player ID, independent of team order. Exactly one
franchise can acquire a player.

## 6. Acquisition and financial safeguards

A winner goes through `FreeAgentAcquisitionService.acquire` and
`FinancialTransactions.addContract`. Existing contracts are immutable. All
franchises use the same cap (41,000), cash solvency, roster limits, salary
schedule validation, and no relief/waiver/cap bypass. Offers prepared earlier are
revalidated against the current career when resolved.

## 7. Durable resolution

Before resolution, human offers, AI offers, round identity and resolution order
are persisted. Each player decision is saved before the next. The cursor and
outcomes allow restart resume without regenerating AI offers, rerolling winners
or replaying acquisitions. A failed/uncertain write stops resolution and
requires explicit reload.

## 8. Schema v11

Career schema 11 requires `freeAgentMarket`. v1–v10 migrate to a `notStarted`
round-1 state while preserving all existing offers, acquisitions, contracts,
rookies, profiles, staff/facilities and pool entries. Existing T08F direct
signings are not retroactively cancelled or rewritten. Native v11 missing or
malformed market data is rejected.

## 9. UI

Board shows round/status, human pending offers with cancel, start/lock/resolve
actions, public market summary, remaining agents, costs and outcomes. Before
resolution AI offer details are not shown. Results show signed/rejected/outbid/
financially-unavailable outcomes and readiness. Offer form stages pending offers
with terms, schedule, cap/cash/capacity and attempts; confirmation warns AI will
compete. Both 360×640 and 393×852 must fit.

## 10. Acceptance criteria

- **AC-T08G-01** Two explicit rounds with persisted states and no auto-start.
- **AC-T08G-02** Human staging never acquires and consumes no attempt.
- **AC-T08G-03** AI offers are deterministic/sealed/persisted; hidden fields do
  not affect them.
- **AC-T08G-04** Human and AI offers compete; no automatic human/AI winner.
- **AC-T08G-05** Salary and fit influence outcomes; ties are stable and
  team-order-independent.
- **AC-T08G-06** Outbid does not consume a player-side attempt; rejection does.
- **AC-T08G-07** Only one acquisition per player; no duplicate ledger records.
- **AC-T08G-08** Financial/roster rules are shared and revalidated.
- **AC-T08G-09** Resolution progress survives save/restart; no AI regeneration.
- **AC-T08G-10** Failed writes block and require reconciliation.
- **AC-T08G-11** v1–v10 migration and native v11 strictness hold.
- **AC-T08G-12** Existing T08D/E/F and M007 regressions pass.
- **AC-T08G-13** Mobile layouts fit both target sizes.

## 11. Non-goals

Unlimited rounds, full offseason calendar, trades, waivers, extensions, expiry,
retirement, new financial rules, cap increases, staff, facilities, automatic
season advance, automatic relief.
