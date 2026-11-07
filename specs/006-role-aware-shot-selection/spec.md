# Specification 006 — Role-Aware Shot Selection v1 (DRAFT, rev 3)

> **Status: DRAFT — NOT FROZEN — NOT AUTHORIZED FOR IMPLEMENTATION.**
> Revision 2 of 2026-11-07 on `design/m006-role-aware-shot-selection`, branched from `develop/m002`
> `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`. Revision 1 example tables compared raw weights and
> were wrong; §3.3 now reports normalized probabilities. No criterion has been run or passed.

## 1. Purpose

M005 closed the possession engine, participation, tactical rotations and app surfaces. The M002
conditions and the deferred-realism backlog (`M003-BACKLOG.md` Priority 1) require role-aware player
decision-making before any broader realism claim. M006 v1 changes **who shoots and from where**,
using existing attributes and canonical court slots.

## 2. Current behaviour (v6, verified in source)

```text
usage(p) = positionBase[slot]                      # PG 260 … C 170
         + 3 × max(0, bestShot(p) − 50)
         + 2 × (ballHandling − 50)
         +     (basketballIQ − 50)                 # floor 60, normalised 10000

inside   = 2400 + 22·(insideScoring−50) + 10·(athleticism−50) + slotInside + phaseInside
midrange = 2500 + 26·(midrange−50)                          + slotMid    + phaseMid
three    = 3600 + 24·(threePoint−50)                        + slotThree  + phaseThree
each floored at 200 and normalised to 10000; half-court phase used unless stated.
slotInside = [−400,−250,0,600,900]  slotMid = [100,200,150,0,−300]  slotThree = [250,350,200,−400,−900]
phaseInside = [700,0,−300]  phaseMid = [−300,0,100]  phaseThree = [−400,0,200]   (transition/early/half-court)
```

Draw order per possession: phase duration (A1) → category → actor → zone → make → foul → assist or
block. Turnover, offensive-foul and non-shooting-foul actors are drawn from a separate ball-handler
score. `FieldGoalAttempt` persists `shooterId` and `shotValue` (2/3) only.

## 3. What M006 v1 changes

### 3.1 Derived offensive-role signal (non-persistent)

**Revised after review.** The revision-1 creation score included `slotBase[slot]`, which made the
classification largely positional: a weak point guard scored 650 against an elite playmaking centre
at 555, so the point guard stayed “primary”. The approved-direction default is therefore
**position-free**:

```text
creation(p) = 3·ballHandling + passing + basketballIQ      # ties break on canonical court-slot order
```

Ranking the five players on court at the moment of a shot gives the primary-creation slot (rank 0)
and secondary (rank 1); lower ranks get factor 1.0. The classification is recomputed whenever the
active five changes, including every substitution, and the simulator must compute it from its
current `TeamOnCourt`.

The role is a **weight-shaping classification**, not a simulated ballhandler. It does not decide
turnovers, offensive fouls or non-shooting-foul actors (those keep their independent draw), and it
does not model possession-level ball movement. No acceptance rule requires the primary-creation
player to out-shoot every secondary or neutral player; see §4.

Implementation sequencing: the role helper, usage policy and zone policy are added as dormant,
unit-tested functions while production keeps v6 behaviour; activation, the version bump and the
fixture migration land together in one later task (`plan.md` §1).

### 3.2 Usage policy

```text
usage(p) = currentRawUsage(p) × roleFactor(rank(p))
roleFactor defaults: rank 0 → 1.35, rank 1 → 1.15, ranks 2–4 → 1.00   (owner decision DD-M006-02)
```

Normalisation restores the sum to 10000; the single actor draw is unchanged.

### 3.3 Zone-willingness policy

The revision-1 curve (`50` below median, `30` above) was audited on normalised probabilities and is
insufficient for weak perimeter guards. The corrected default is the steeper piecewise curve:

```text
ability(p) = 70·(p − 50)  when p < 50
           = 30·(p − 50)  when p ≥ 50
three = 3600 + ability(threePoint) + slotThree + phaseThree, floored at 200
inside and midrange unchanged
```

**Normalised audit (half-court phase, no draws involved):**

| Archetype (slot) | Attributes inside/mid/three/ath | v6 inside/mid/three % | v7 inside/mid/three % | Δ three | Relative |
|---|---|---|---|---|---|
| Weak PG (PG) | 40/45/30, ath 55 | 19.9 / 33.5 / 46.5 | 22.7 / 38.1 / 39.3 | −7.3 pp | −15.7% |
| Weak SG (SG) | 45/50/35, ath 60 | 21.8 / 33.2 / 45.0 | 23.8 / 36.2 / 40.1 | −4.9 pp | −10.9% |
| Non-shooting C (C) | 80/35/20, ath 65 | 48.2 / 24.2 / 27.6 | 58.4 / 29.3 / 12.3 | −15.3 pp | −55.5% |
| High-three C (C) | 75/55/80, ath 60 | 37.6 / 25.1 / 37.3 | 36.9 / 24.6 / 38.5 | +1.1 pp | +3.1% |
| High-three F (PF) | 70/65/78, ath 65 | 31.8 / 28.9 / 39.3 | 31.3 / 28.4 / 40.3 | +1.0 pp | +2.5% |
| Median shooter (SF) | 50/50/50, ath 50 | 23.7 / 31.1 / 45.2 | 23.7 / 31.1 / 45.2 | 0.0 pp | 0.0% |

Phase check (early phase, three share): non-shooting C 25.1% → 16.9% (−8.2 pp); weak PG 43.9% →
39.9% (−4.1 pp); stretch C 35.3% → 36.4% (+1.2 pp). The curve is phase-stable in direction.

Residual: a weak-everywhere guard still takes ~39% of his attempts from three because his interior
weights are equally weak. Two stronger alternatives are recorded in `design-decisions.md` DD-M006-03
(breakpoint 55 curve; ability-relative penalty). A multiplicative factor centred on 60 was rejected
because it collapsed the median shooter from 45.2% to 24.8%.

### 3.4 Event schema

Event schema stays **3**. No new event type, no persisted zone field. Canonical ledgers expose
shooter and 2/3-point value only; inside-versus-midrange is **not** measurable from canonical output
and must not be claimed. An optional debug-only shot-decision observer (DD-M006-05) may expose the
drawn zone and weights to tests without entering the ledger or fingerprint.

### 3.5 Versioning

simulation **7**, fingerprint **5**, landing atomically with activation in T04 — no earlier commit
changes a version constant; rules 3, schema 3, duration model 2, `xorshift32-v1` unchanged; M001
identifiers unchanged. No v6/v7 ledger or whole-game draw-count
equality is claimed. Historical v1–v6 fixture files are untouched; M006 adds v7 fixtures. The
historical fixture migration strategy is in `verification-plan.md` §2.

### 3.6 Determinism contract

No new random draws; every action branch keeps its documented draw order (category, actor, zone,
make, foul, assist/block). Different weighted choices legitimately change downstream game paths and
draw counts. Required proofs: repeat-run identity, Dart VM/Chrome parity, documented intentional v6
differences, reliable typed cross-version rejection.

## 4. Role, usage and actors — explicit distinctions

| Concept | What it is | What it is not |
|---|---|---|
| Primary-creation classification | Deterministic ranking of the five players on court by position-free creation score | Not a simulated ballhandler; not a persisted player role |
| Shooter usage | Normalised draw weights for “who attempts the shot” | Not an assist, turnover or foul attribution |
| Turnover/offensive-foul/non-shooting-foul actor | Independent draw from the ball-handler score, unchanged | Not influenced by the role multiplier |
| Possession-level ball handling | Not implemented | The role classification must not be described as it |

Role acceptance is verified by incremental weight changes for identical attributes, correct primary
and secondary assignment, pre-normalisation ordering, recomputation after substitutions and the
absence of any multiplier below 1.0. A high-usage scorer whose creation rank is neutral keeps the
same raw weight; normalised dilution is reported, not treated as a violation.

Metrics must classify a player **at the moment of each shot**, replaying substitutions from the
ledger, not by starting lineups.

## 5. Scope exclusions

Fatigue, injuries, manual play calling, coaching AI, defensive schemes, trades, contracts, seasons,
persistence, possession-level ball movement, turnover or assist redistribution, new PRNG algorithms,
real-world player data, Flutter gameplay UI, unrelated probability tuning.

## 6. Open decisions

DD-M006-01 (position-free creation score), DD-M006-02 (role multipliers), DD-M006-03 (curve choice),
DD-M006-04 (schema 3), DD-M006-05 (observer), DD-M006-06 (evaluation protocol; partially OPEN), plus
the historical migration approval implied by DD-M006-07.
