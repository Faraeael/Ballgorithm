# M008-T08E Specification — Free-Agent Market Valuation & Offer Acceptance

Status: implementation contract. Baseline:
`feat/m008-t08d-free-agent-acquisition` at
`3b9c9551225cff341ba074103682c3b342565d74`.
Branch: `feat/m008-t08e-free-agent-market-policy`.

## 1. Scope

A deterministic, public-information valuation and acceptance policy for free
agents. It estimates market salary, expected role, preferred duration and a
player decision for a hypothetical offer. It does not submit, persist or execute
offers, and does not acquire players. T08D acquisition remains the only transfer.

## 2. Contract duration consistency

Authoritative new-contract rule:
`FinancialRules.maxDurationForCategory`:

- standard: 1–4 years;
- two-way: 1–2 years.

T08D acquisition uses this rule. Validation of already signed contracts remains
based on their stored duration (1–4), so any longer two-way agreement created
before this rule remains valid and is not rewritten. No save schema change is
needed for this policy.

## 3. Valuation formula

`FreeAgentMarketValueService` inputs only `PublicFreeAgentView`: OVR, age,
position, observable attributes. Hidden potential, trajectory, progression,
generation noise and future results are unavailable by type.

```
base = 400 + (clamp(OVR, 50, 90) - 50)^2 * 6
ageBp: <=23 8500; 24-28 10500; 29-31 10000; 32-34 8500; 35+ 7000
durationBp: 1y 10800; 2y 10200; 3y 10000; 4y 9600
yearOne = round10(base * ageBp * durationBp / 10000 / 10000)
yearOne = min(yearOne, maxYearOneForDuration(duration))
yearOne = clamp(yearOne, 400, 8000)
```

`maxYearOneForDuration` prevents the 5% schedule from crossing 8,000 CU:
8,000 / 7,619 / 7,257 / 6,911 for 1–4 years. This removes invalid
"estimated" offers at maximum salary.

Output `MarketValuation`: estimated annual salary, acceptable minimum 85% and
maximum 115% (capped to the schedule maximum), preferred duration, expected role
(starter OVR≥78, rotation ≥70, bench ≥62, developmental below), public
explanation.

## 4. Acceptance policy

`FreeAgentOfferEvaluator` first checks terms and financial legality, then player
acceptance.

1. **Invalid terms**: unknown player/team, unsupported category, duration outside
   the category rule, salary outside 400–8,000, two-way not exactly 250, later
   schedule year above 8,000.
2. **Financially illegal**: wrong phase, roster capacity, cap, cash insolvency,
   already acquired. Distinct status from player rejection.
3. **Player decision**:
   - two-way is inappropriate for OVR ≥65 or age ≥27;
   - age ≥35 rejects durations above two years;
   - fit adjustment: situation (tanking favours young, contender favours
     veterans, playoff favours veterans slightly) plus same-position depth;
   - required salary = acceptable minimum adjusted by fit, then increased by 3%
     per year of distance from preferred duration;
   - salary below required → salary-too-low, poor-fit when the fit penalty is at
     least 1,200 bp, or unfavourable-duration when only duration compensation is
     missing;
   - salary at or above required → acceptable.

Salary is the strongest factor; fit and duration modify the threshold. A bad fit
can be overcome with money. No random acceptance.

## 5. Anti-exploit

- OVR drives value quadratically; 80+ OVR minimum offers fail.
- Fit penalties are bounded; they cannot make a minimum offer acceptable to an
  elite player.
- Two-way offers are restricted to young/low-OVR players.
- Duration preference cannot be gamed with a zero-cost long contract; each
  off-preferred year raises the required salary.
- The evaluator returns a decision only; no acceptance probability, no reroll,
  no clock, no hash codes.
- Identical career state + identical offer = identical decision. Evaluation order
  is irrelevant. Evaluation never mutates state.

## 6. Public-information boundary

Only `PublicFreeAgentView`, roster composition, franchise situation, financial
state and rulebook are read. Hidden career profiles are not read. Tests change
hidden potential/trajectory in the pool and assert the same valuation and decision.

## 7. AI compatibility

The evaluator is franchise-neutral. Human and AI teams use the same command and
thresholds. No privileged acceptance modifier exists. A future AI bidding service
can call the same pure evaluator.

## 8. Acceptance criteria

- **AC-T08E-01** Valuation is deterministic and OVR/age/duration sensitive.
- **AC-T08E-02** Hidden potential/trajectory cannot change valuation or decision.
- **AC-T08E-03** Standard duration 1–4; two-way 1–2; existing longer two-way
  agreements remain valid.
- **AC-T08E-04** High-value players reject exploitative minimums; lower-tier
  players accept reasonable offers; more money monotonically improves acceptance
  until a hard financial rule blocks the offer.
- **AC-T08E-05** Position depth and franchise situation affect acceptance without
  making weaker franchises automatically rejected.
- **AC-T08E-06** Financial illegality is distinct from player rejection.
- **AC-T08E-07** Evaluation never mutates pool, roster, contracts, finances,
  ledger, draft or profiles.
- **AC-T08E-08** All 30 franchises are supported by the same evaluator.
- **AC-T08E-09** Save/load does not change valuation or decisions.
- **AC-T08E-10** Existing T08D acquisition, rookie signing, finance, M007 and
  regression suites remain green.
- **AC-T08E-11** Calibration evidence covers the three seeds and four situations,
  with distributions and financial feasibility reported separately from
  acquisition outcomes.

## 9. Non-goals

No offer submission/persistence, human sign/offer UI, negotiation rounds, AI
bidding, auctions, acquisition after acceptance, waivers, trades, renewal,
expiry, staff, facilities, cap changes, dashboard or season advancement.
