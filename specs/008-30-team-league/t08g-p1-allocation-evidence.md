# T08G-P1 Allocation Evidence

Reproducible raw files:

- `t08g-p1-allocation-before.md`
- `t08g-p1-allocation-after.md`
- `t08g-market-evidence.md` (after correction, with human competition)

Tool: `packages/simulation_core/tool/t08g_p1_allocation_diagnostics.dart`.

## 1. Method

Three seeds × four human situations. Each row resolves both market rounds. The
“market-only” scenario starts at career year 1. The “offseason” scenario first
completes the rookie draft and all AI rookie signing decisions, then runs both
market rounds. No human free-agent offer is staged in the allocation diagnostic,
isolating AI allocation.

## 2. Before

| Metric (market-only range) | Value |
|---|---|
| AI offers | 235–260 |
| Unique AI targets | 24–33 |
| Max offers per player | 20–26 |
| AI acquisitions | 24–33 |
| AI teams losing every offer | 9–13 |
| Remaining free agents | 55–66 |
| Standard vacancies | 40–46 |
| Outbid results | 205–228 |
| Player rejections | 0 |
| Financially unavailable | 0 |
| Cap-bound teams | 4–5 |
| Cash-bound teams | 0 |

Offseason sequence before: 155–195 AI offers, 26–31 unique targets, 26–31
acquisitions, 6–10 losing teams, 19–25 vacancies.

**Root cause:** excessive candidate concentration. Supply was 90; finances were
not binding for cash; only 4–5 teams were below the minimum-salary cap floor.
The same top 24–33 players received up to 26 offers each.

## 3. After

| Metric (market-only range) | Value |
|---|---|
| AI offers | 107–124 |
| Unique AI targets | 70–72 |
| Max offers per player | 3–5 |
| AI acquisitions | 70–72 |
| AI teams losing every offer | 0 |
| Remaining free agents | 18–20 |
| Standard vacancies | 3–7 |
| Outbid results | 36–55 |
| Player rejections | 0 |
| Financially unavailable | 0 |
| Cap-bound teams | 4–5 |
| Cash-bound teams | 0 |

Offseason sequence after: 79–89 AI offers, 46–51 unique targets, 46–51
acquisitions, 0–5 losing teams, 3–7 vacancies.

## 4. Correction applied

- AI teams evaluated in deterministic hash order rather than league order.
- Candidate sort includes a global target-count penalty.
- Two-way offers capped at one per AI team per round.
- Existing reservation model unchanged: cap, cash, two-way/standard/total roster.

This is a diversification correction, not a supply or salary change. It does not
force every team ready: 3–7 standard vacancies remain in market-only, and 2–6
teams remain below 14 in some full-competition scenarios.

## 5. Competitive evidence after correction

`t08g-market-evidence.md` includes human offers. Example seed 20261028 Tanking:
125 AI offers, 71 AI buys, 1 human buy, 18 remaining, readiness 0→28, below 14
30→2. Seed 1604126146 Play-In: 108 AI offers, 70 AI buys, 1 human buy, 19
remaining, readiness 0→24, below 14 30→6.

AI does not force league-wide readiness; meaningful situation differences and
cap constraints remain.

## 6. Limitations

- AI offers are near acceptable maxima, so player-side rejection is rare.
- The two-round design still leaves some roster vacancies.
- The distribution of outcomes reflects a design policy, not observed market
  prices.
- Financial feasibility is not an acquisition guarantee.
