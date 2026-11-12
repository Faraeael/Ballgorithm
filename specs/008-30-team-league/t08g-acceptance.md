# M008-T08G Acceptance — Competitive AI Free Agency & Shared Market Rounds

Status: **implemented, verified; owner acceptance pending**.
Date: 2026-11-12. Baseline:
`feat/m008-t08f-human-free-agent-offers` at
`f22b24138aea550e0101c1877925487fa47d5c49`.
Branch: `feat/m008-t08g-competitive-free-agency`.

## 1. Market-round architecture

Schema v11 adds `FreeAgentMarketState`:

- states: notStarted, collectingHumanOffers, preparedForResolution, resolving,
  roundComplete, marketComplete, recoveryRequired;
- two rounds only, season year, human staged offers, sealed AI offers, sorted
  resolution order, cursor, per-player outcomes and completed-round count.

Starting a round is explicit. Loading/app-open/board-view never starts a round,
generates AI offers or acquires a player. Round 1 is the opening competition;
Round 2 covers remaining players/needs. No season advance.

## 2. Human staging

Human offers are pending, not accepted. Staging checks terms and financial
legality, remaining player-side attempts, duplicate pending offers, and
reservations against cap, cash, standard/two-way/total roster capacity. It does
not acquire or consume an attempt. Offers can be cancelled before locking;
locking seals AI offers and freezes human terms.

## 3. AI policy

`AiFreeAgentOfferPolicy` uses public OVR/age/position/attributes, market value,
roster needs, situation, cap, cash and contracts. It never reads hidden
potential/trajectory/progression or human intentions. AI fills standard need
first, then two-way need, respecting shared cap/cash/roster reservations. Offers
are persisted before resolution and deterministic after restart. FNV-1a
tie-breaks avoid input-order dependence.

## 4. Competitive selection

Every offer is evaluated by T08E against the current career:

- invalid/financially illegal → financiallyUnavailable, no attempt;
- player rejection → durable attempt;
- acceptable loser → outbid, no attempt;
- winner → acquisition + accepted offer.

Acceptable offers rank by salary, preferred-duration closeness, public
situation/role fit, then deterministic FNV(player/team/round). Human identity
and iteration order do not decide. One acquisition per player. Failed
acquisition attempts fall through to the next ranked offer as
financiallyUnavailable.

## 5. Financial safeguards

All franchises use the same 41,000 cap, 400–8,000 standard salaries, 250 two-way,
5% raise, roster limits, cash solvency and contract rules. Offers are
revalidated at resolution. No relief, waiver, cap bypass or artificial discount.
Existing contracts are immutable.

## 6. Durable resolution

Human offers, AI offers, round identity and resolution order are persisted before
resolution. Each player decision is saved before the next. Cursor/outcomes
persist; restart resumes without regenerating AI offers or replaying acquisitions.
Failed/uncertain writes block commands until explicit reload. Duplicate
resolution submissions are rejected; one player cannot have two acquisition
records.

## 7. Schema migration

- v1–v10 migrate to notStarted round 1.
- Existing T08F offers/acquisitions/contracts/rookies/pool remain.
- Existing direct signings are not retroactively cancelled or rewritten.
- Native v11 missing/malformed market is rejected.
- M007 isolation unchanged.

## 8. Deterministic evidence

`t08g-market-evidence.md`, three seeds × four situations, two rounds. Selected
results:

| Seed | Situation | Human offers | AI offers | Outbids | Human buys | AI buys | Remaining | Ready before→after | Below 14 before→after |
|---|---|---|---|---|---|---|---|---|---|
| 20261028 | Tanking | 2 | 260 | 227 | 2 | 33 | 55 | 0→6 | 30→24 |
| 20261028 | Contender | 2 | 260 | 228 | 1 | 32 | 57 | 0→5 | 30→25 |
| 1604126146 | Play-In | 2 | 235 | 205 | 2 | 30 | 58 | 0→3 | 30→27 |
| 987654321 | Playoff | 2 | 236 | 210 | 1 | 26 | 63 | 0→0 | 30→30 |

AI does not force league readiness; one seed still has all 30 teams below 14
after two rounds. Human and AI can both win competitive players in controlled
tests. Outbids are not player rejections.

## 9. Verification

- Core `dart analyze`: clean.
- Core `dart test`: **912 passed**.
- Root `flutter analyze`: clean.
- Root `flutter test`: **228 passed**.
- T08C audit: 48 validations, 0 over-cap.
- T08E calibration: unchanged (268 acceptable / 2 salary-too-low at estimate).
- T08F immediate service and market staging coexist; new UI uses market only.
- 360×640 and 393×852 tests pass.
- League Summary screen lists completed acquisitions and per-franchise
  standard/two-way counts, cap/cash payroll and readiness without hidden data.

## 10. JEV

Fairness 0.92, outbid/rejection separation 0.90, recommendation GO 0.92/0.88
confidence. Integrity self-assessment was low (0.17/0.16) despite deterministic
replay/duplicate tests; the judge saw a residual risk not reproduced by tests.
Treat as an open review item, not an acceptance claim. Duplicate-acquisition
validation and outcome consistency checks were added after the first review.

## 11. Remaining risks

- AI policy generates many offers and a large outbid volume; player-side
  rejection is rare because AI offers near acceptable maxima.
- Market readiness remains modest and is not forced.
- Two-round rule is provisional; no full offseason calendar.
- Existing T08F saves retain the historical human-first advantage.
- No trades, waivers, renewal, expiry, relief, staff, facilities or season
  advance.

## 12. Recommendation

**CONDITIONAL GO** for T08G: market mechanics, fairness and persistence tests
pass; the residual JEV integrity concern must be resolved or explicitly accepted
before a full offseason/season-advance milestone. Next milestone should be a
focused market-integrity review plus offseason clearance, not more acquisition
features.
