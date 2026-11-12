# M008-T08E Acceptance — Free-Agent Market Valuation & Offer Acceptance

Status: **implemented, verified; owner acceptance pending**.
Date: 2026-11-12. Baseline:
`feat/m008-t08d-free-agent-acquisition` at
`3b9c9551225cff341ba074103682c3b342565d74`.
Branch: `feat/m008-t08e-free-agent-market-policy`.

## 1. Formula

`FreeAgentMarketValueService` uses public OVR, age, position and observable
attributes only:

```
base = 400 + (clamp(OVR,50,90) - 50)^2 * 6
ageBp: <=23 8500 | 24-28 10500 | 29-31 10000 | 32-34 8500 | 35+ 7000
durationBp: 1y 10800 | 2y 10200 | 3y 10000 | 4y 9600
yearOne = min(round10(base * ageBp * durationBp / 1e8),
              maxYearOneForDuration(duration))
clamp 400..8000
```

`maxYearOneForDuration` is 8,000 / 7,619 / 7,257 / 6,911 CU so the 5% schedule
never exceeds 8,000. Estimated value, 85–115% acceptable range, preferred
duration, expected role and public explanation are returned.

## 2. Public information boundary

Only `PublicFreeAgentView` and public franchise/roster/finance state are read.
Hidden potential, trajectory, progression and generation noise are not inputs.
Tests replace hidden potential/trajectory and assert identical valuation and
decision.

## 3. Offer policy

Three-stage outcome:

1. **Invalid terms**: unknown player/team, unsupported category, duration outside
   the category rule, illegal salary, later year above 8,000.
2. **Financially illegal**: roster capacity, cap, cash, phase, already acquired.
3. **Player decision**: two-way eligibility, veteran duration, situation and
   position-depth fit, duration compensation, salary threshold, acceptable.

Salary is dominant; fit is bounded to ±20%; duration adds 3% per year away from
the preferred term. Money can compensate for fit. No random acceptance.

## 4. Duration rules

Shared `FinancialRules.maxDurationForCategory`: standard 1–4, two-way 1–2.
T08D acquisition uses it. Existing signed contracts, including any longer
two-way agreement from a v9 save, remain valid because validation uses stored
terms. No schema change.

## 5. Anti-exploit

- 80+ OVR needs roughly 5.9k–7.6k; 400 CU fails.
- Two-way offers rejected for OVR≥65 or age≥27.
- Off-preferred duration costs 3% per year difference.
- No random acceptance, clock, hash, reroll or persisted offer.
- Identical state/offer → identical decision; order irrelevant.
- Evaluation is read-only: no pool, roster, contract, ledger, profile or cash
  mutation.

## 6. Calibration

Raw evidence: `t08e-market-calibration-raw.md`; summary:
`t08e-market-calibration.md`. Three seeds, 270 unique free agents.

| OVR band | Estimated CU min/median/mean/max |
|---|---|
| <60 | 400/680/650/900 |
| 60–64 | 870/1,230/1,218/1,650 |
| 65–69 | 1,320/1,940/1,992/2,690 |
| 70–74 | 2,120/3,110/3,219/4,050 |
| 75–79 | 3,140/4,680/4,736/5,720 |
| 80+ | 5,920/6,870/6,720/7,619 |

- At the estimated value/preferred duration: 268 acceptable, 2 salary-too-low
  out of 270.
- First acceptable salary: 450/1,900/2,293/6,500 CU (min/median/mean/max).
- No player lacked a legal acceptable salary.
- 89 of 90 short-handed team-seasons can fill the standard shortage under cap
  and cash using valuation floors. The single exception is seed `1604126146`
  `team-23` (shortage 2, cost 910, cap room 600) — the known minimum-roster
  exception case.

## 7. Franchise fit evidence

- Young player: tanking acceptable, contender salary-too-low at the same offer.
- Veteran: tanking salary-too-low, contender acceptable at the same offer.
- Adding two stronger same-position players turns a low offer into `poorFit`.
- Money above the fit-adjusted threshold restores acceptance; it never worsens
  a player-side decision.

## 8. Verification

- Core `dart analyze`: clean.
- Core `dart test`: **886 passed**.
- Root `flutter analyze`: clean.
- Root `flutter test`: **221 passed**.
- T08C financial audit regression: run separately and unchanged.
- Existing acquisition, rookie signing, AI signing and M007 storage suites pass.
- Format check: clean.

## 9. JEV

`jev-latest`: exploitability 0.87, public information 0.96, determinism/read-only
0.91. Recommendation **GO 0.82**, confidence 0.73. Advisory only.

## 10. Remaining gaps

- No offer submission/persistence, Sign button, negotiation, AI bidding or
  acquisition after acceptance.
- Valuation is a design convention, not observed market prices.
- Fit ignores promises about playing time and competition among teams.
- The near-cap team still needs bounded relief, not implemented here.
- No trades, waivers, renewal, expiry, retirement, staff, facilities, dashboard
  or season advancement.

## 11. Recommendation

**GO for owner acceptance of T08E.** The next milestone should implement an
approved offer-submission workflow that calls this evaluator and then the T08D
acquisition engine only on `acceptable`.
