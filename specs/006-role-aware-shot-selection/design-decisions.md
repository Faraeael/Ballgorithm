# Design Decisions 006 — Role-Aware Shot Selection v1 (DRAFT, rev 2)

> **Status: DRAFT — proposals only. No owner approval exists.** Revision 2 corrects the rev-1 role
> score and zone table after the normalized-probability and role-bias audit.

## DD-M006-01 — Position-free derived role ranking (revised)

**Proposal.** `creation = 3·ballHandling + passing + basketballIQ`; tie-break canonical court-slot
order. Rank 0 = primary-creation slot, rank 1 = secondary, others neutral. Recompute from the five
players on court whenever the lineup changes.

**Why revised.** The rev-1 score `slotBase + creation` was dominated by `slotBase` (PG 420 vs C 180).
Audit examples:

| Lineup | Rev-1 creation | Rev-1 primary |
|---|---|---|
| Mediocre PG 60/55/55 vs elite wing 85/95/90 | PG 710 vs wing 720 | wing (narrow) |
| Weak PG 45/50/45 vs creator big 70/80/85 | PG 650 vs big 555 | **PG**, despite far weaker creation |
| Weak PG 30/35/35 vs creator big 70/80/85 | PG 580 vs big 555 | **PG** |

The slot base let a catastrophic point guard outrank an elite playmaking big. The position-free
score ranks the big primary in the same lineups (big 375 vs PG 230/195) and keeps ordinary lineups
unchanged.

**Trade-offs.** A roster with a nominal “point guard” who is not its best creator now shifts primary
classification to the actual creator. That is the intended behaviour, but it changes who receives
the usage multiplier and must be reviewed in box scores. Position still influences usage and zones
through the existing position bases and slot bonuses; only the role ranking is position-free.

## DD-M006-02 — Usage multipliers by rank

**Proposal.** `[1.35, 1.15, 1.00, 1.00, 1.00]` before normalisation.

**Audit (position-free ranking).** Baseline five: PG 23.3% → 28.2%, SG 21.7% → 22.4%, others fall
1.5–2.2 pp. Elite-wing lineup: wing 29.3% → 34.9%; mediocre PG 20.7% → 20.9%. Two-creator lineup:
30.2% / 26.0%. Bench-PG substitution line: creator big becomes primary, 23.7% → 28.7%, bench PG
19.1% → 17.1%.

**Trade-offs.** 1.35 concentrates roughly a third of attempts on the primary creator in strong
lineups; 1.15/1.05 would be gentler but may be statistically invisible. Closing the gap between rank
0 and rank 1 reduces concentration; owner choice.

## DD-M006-03 — Zone curve: default and alternatives

**Proposal (default).** Piecewise `70·(p−50)` below 50, `30·(p−50)` above; position/phase bonuses
and floor 200 unchanged.

**Normalized three-point share audit (half-court):**

| Archetype | v6 | Default (70/30) | Alt A: breakpoint 55, 70/45 | Alt B: 70/30 + relative penalty |
|---|---|---|---|---|
| Weak PG | 46.5% | 39.3% (−7.3) | 35.9% (−10.6) | 35.7% (−10.9) |
| Weak SG | 45.0% | 40.1% (−4.9) | 37.2% (−7.7) | 37.0% (−8.0) |
| Non-shooting C | 27.6% | 12.3% (−15.3) | 7.3% (−20.3) | 3.4% (−24.2) |
| High-three C | 37.3% | 38.5% (+1.1) | 39.8% (+2.5) | 38.5% (+1.1) |
| High-three F | 39.3% | 40.3% (+1.0) | 41.4% (+2.1) | 40.3% (+1.0) |
| Median shooter | 45.2% | 45.2% (0.0) | 42.9% (−2.3) | 45.2% (0.0) |
| Elite PG | 49.2% | 50.2% (+1.0) | 51.4% (+2.2) | 50.2% (+1.0) |

- **Alt A (stronger):** steeper reduction for weak guards, but the breakpoint at 55 pulls the median
  shooter down 2.3 pp and pushes non-shooting centres toward near-elimination (7.3%).
- **Alt B (targeted):** adds `min(0, 25·(threePoint − max(insideScoring, midrange)))` so a player is
  penalised only when his three is materially worse than his best two-point option. Weak guards fall
  ~8–11 pp, stretch-bigs are untouched, but a non-shooting centre drops to ~3.4% threes and the
  extra coefficient increases review surface.
- **Rejected:** multiplicative factor centred at 60 (`1 + 0.06·(p−60)` clamped 0.35–1.35). It cut
  the median shooter from 45.2% to 24.8%, an unrelated distortion.

**Residual accepted in the default:** a weak-everywhere guard still takes ~39% threes because his
inside and midrange weights are equally weak. If the owner judges this insufficient, Alt A or Alt B
is the escalation path; the default is chosen because it leaves median and strong shooters stable.

JEV advisory (non-binding, 2026-11-07): piecewise structure preferred 0.71 over role gate 0.16 and
multiplicative 0.13, confidence 0.56. Advisory only.

## DD-M006-04 — Keep event schema 3

No new event type, no persisted zone. Ledgers expose shooter and 2/3 value; inside-versus-midrange
remains unmeasured. A schema change would force new serialisation, fixtures and rejection tests for
a capability v1 does not need.

## DD-M006-05 — Non-persistent shot-decision observer

Debug-only callback mirroring `onPhaseTrace`: reports drawn zone and weights; never enters the
ledger or fingerprint. Alternative: ledger-derived metrics only.

## DD-M006-06 — Evaluation protocol (to be frozen before cohorts)

Metrics, denominators and open thresholds are defined in `verification-plan.md` §3–§5. Controlled,
formula-level expectations (normalized probabilities and usage shares) are deterministic and need no
cohort. Empirical thresholds are **OPEN** until a v6 baseline cohort establishes variance; the
minimum baseline needed is stated there.

## DD-M006-07 — Version boundary and historical fixture migration

simulation 7 / fingerprint 5; rules 3, schema 3, duration 2, PRNG unchanged. No v6/v7 ledger or
draw-count equality; per-branch draw order fixed; repeat identity and VM/Chrome parity required.
Historical fixture migration (no dual engine, no rebaseline) is specified in
`verification-plan.md` §2. This migration plan is itself an owner decision.
