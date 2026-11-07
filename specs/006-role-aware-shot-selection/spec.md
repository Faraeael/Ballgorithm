# Specification 006 — Role-Aware Shot Selection v1 (DRAFT, rev 4)

> **Status: DRAFT — NOT FROZEN — NOT AUTHORIZED FOR IMPLEMENTATION.**
> Revision 4 (2026-11-07) adds the ability / preference / opportunity / coaching separation and the
> decision contract. Revision 2 replaced a wrong raw-weight table with normalized probabilities;
> revision 3 moved the version bump to activation and corrected the role acceptance rules.
> Baseline `develop/m002` `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`. No criterion has been run.

## 1. Purpose

M005 closed the possession engine, participation, tactical rotations and app surfaces. The M002
conditions and the deferred-realism backlog (`M003-BACKLOG.md` Priority 1) require role-aware player
decision-making before any broader realism claim. M006 v1 changes **who shoots and from where**,
using existing attributes and canonical court slots, without changing shot conversion.

**Design statement.** M006 introduces role-aware offensive opportunity and derived shot preferences,
not independent persistent player tendencies and not a possession-level ball-movement system.

## 2. Current behaviour (v6, verified in source)

```text
usage(p) = positionBase[slot] + 3·max(0, bestShot−50) + 2·(ballHandling−50) + (basketballIQ−50)
           floor 60, normalised to 10000
inside   = 2400 + 22·(insideScoring−50) + 10·(athleticism−50) + slotInside + phaseInside
midrange = 2500 + 26·(midrange−50)                          + slotMid    + phaseMid
three    = 3600 + 24·(threePoint−50)                        + slotThree  + phaseThree
each floored at 200 and normalised to 10000
```

Shot success is a separate function (`shotMakeBasisPoints`) with its own conversion coefficients per
zone; turnover/foul/assist/block use their own scores. The engine already separates usage, zone
preference and success computationally. What M006 adds is a **conceptual separation** of who gets
opportunities from how willing a shooter is by zone, using the same underlying ratings.

## 3. Decision layers

### 3.0 Ability, preference, opportunity, coaching

| Layer | Definition | M006 v1 status |
|---|---|---|
| **Ability** | Likelihood of converting an action (`shotMakeBasisPoints`, free throws, etc.) | Existing formulas, **unchanged** by M006 |
| **Shot preference** | Willingness to attempt inside / midrange / three, derived from existing attributes | New, **non-persistent**, derived; zone selection only |
| **Opportunity** | How often a player is chosen to attempt a shot, from derived creation ranking | New, weight multipliers only |
| **Coaching strategy** | Team-level focus, featured scorers, perimeter/interior emphasis | **Future only**; no configuration or playbook in M006 |

Derived preferences are **not** independently editable personality traits. Genuine player-specific
tendencies that are independent of ability are deferred. All four layers may initially consume the
same rating fields; they remain separate decisions and separate tests.

### 3.1 Derived offensive opportunity (role ranking, non-persistent)

```text
creation(p) = 3·ballHandling + passing + basketballIQ      # position-free; ties by canonical slot order
```

The top-ranked player on court at the moment of a shot is the primary-creation slot, the second is
secondary, the rest neutral. The ranking is a **classification used to shape opportunity weights**,
not a simulated ballhandler; it does not select turnover or offensive-foul actors, and it does not
represent possession-level ball handling. It is recomputed whenever the active five changes,
including substitutions.

Creation ranking is **not** shooting proficiency: an elite scorer with average creation remains
capable of high shot usage.

### 3.2 Opportunity weights

```text
usage(p) = currentRawUsage(p) × opportunityFactor(rank(p))
opportunityFactor: rank 0 → 1.35, rank 1 → 1.15, ranks 2–4 → 1.00   (owner decision DD-M006-02)
```

Normalisation restores the sum to 10000; the single shooter-selection draw is unchanged. No player
receives a factor below 1.0.

### 3.3 Derived shot preferences (zone willingness)

Replace the linear three-point term with the piecewise ability curve; inside and midrange formulas
are unchanged:

```text
ability(p) = 70·(p − 50)  when p < 50
           = 30·(p − 50)  when p ≥ 50
three = 3600 + ability(threePoint) + slotThree + phaseThree, floored at 200
```

**Normalized audit (half-court, no draws):**

| Archetype (slot) | Attributes inside/mid/three/ath | v6 I/M/T % | v7 I/M/T % | Δ three | Relative |
|---|---|---|---|---|---|
| Weak PG | 40/45/30, ath 55 | 19.9 / 33.5 / 46.5 | 22.7 / 38.1 / 39.3 | −7.3 pp | −15.7% |
| Weak SG | 45/50/35, ath 60 | 21.8 / 33.2 / 45.0 | 23.8 / 36.2 / 40.1 | −4.9 pp | −10.9% |
| Non-shooting C | 80/35/20, ath 65 | 48.2 / 24.2 / 27.6 | 58.4 / 29.3 / 12.3 | −15.3 pp | −55.5% |
| High-three C | 75/55/80, ath 60 | 37.6 / 25.1 / 37.3 | 36.9 / 24.6 / 38.5 | +1.1 pp | +3.1% |
| High-three F | 70/65/78, ath 65 | 31.8 / 28.9 / 39.3 | 31.3 / 28.4 / 40.3 | +1.0 pp | +2.5% |
| Median shooter (SF) | 50/50/50, ath 50 | 23.7 / 31.1 / 45.2 | 23.7 / 31.1 / 45.2 | 0.0 pp | 0.0% |

Phase check (early phase): non-shooting C 25.1→16.9%; weak PG 43.9→39.9%; stretch C 35.3→36.4%.
Residual: a weak-everywhere guard still takes ~39% threes; alternatives are recorded in
`design-decisions.md` DD-M006-03.

### 3.4 Decision contract (matches the simulator's real order)

| Step | What happens | PRNG draw? |
|---|---|---|
| 1 | Active lineup and possession context fixed; A1 phase type and duration already drawn | A1 draws precede |
| 2 | Derived creation ranking of the five on court | No — weight calculation |
| 3 | Opportunity weights = raw usage × role factor, normalised | No |
| 4 | Action-category draw: turnover, offensive foul, non-shooting foul or shot attempt | **Yes** — category draw |
| 5 | Shooter selection (only on the shot branch) | **Yes** — actor draw |
| 6 | Shooter-specific zone preference weights, then zone draw | **Yes** — zone draw |
| 7 | Make resolution (`shotMakeBasisPoints` unchanged) | **Yes** — make draw |
| 8 | Made: and-one, assist check, passer; Missed: shooting-foul check, block check, blocker | **Yes** — existing conditional draws |

M006 adds **no randomized stage** and changes no draw order. Steps 2 and 3 are pure weight
calculations; only steps 4 onward consume randomness. Rebound and free-throw draws that follow are
untouched.

### 3.5 Event schema

Event schema stays **3**. No new event type, no persisted zone field. Canonical ledgers expose
shooter and 2/3-point value only; inside-versus-midrange is **not** measurable from canonical output
and must not be claimed. An optional debug-only shot-decision observer (DD-M006-05) may expose the
drawn zone and weights to tests without entering the ledger or fingerprint.

### 3.6 Versioning

simulation **7**, fingerprint **5**, landing atomically with activation in T04 — no earlier commit
changes a version constant; rules 3, schema 3, duration model 2, `xorshift32-v1` unchanged; M001
identifiers unchanged. Historical v1–v6 fixtures are untouched; migration is in
`verification-plan.md` §2.

### 3.7 Determinism

No new draws; per-branch draw order unchanged (see §3.4). Different weighted choices change game
paths and draw counts, so no v6/v7 ledger or draw-count equality is claimed. Required proofs:
repeat-run identity, VM/Chrome parity, documented intentional differences, typed cross-version
rejection.

## 4. Role, preference and actor distinctions

| Concept | What it is | What it is not |
|---|---|---|
| Primary-creation classification | Deterministic ranking of the five on court by position-free creation score | Not a ballhandler; not persisted; not shooting proficiency |
| Shot preference | Derived zone-willingness weights from existing attributes | Not an editable personality trait; not shot accuracy |
| Shooter usage | Normalised draw weights for who attempts the shot | Not an assist, turnover or foul attribution |
| Turnover/offensive-foul/non-shooting-foul actor | Independent draw from the ball-handler score, unchanged | Not influenced by role or preference |
| Shot success | Existing conversion formula | Not changed by M006 |
| Possession-level ball handling | Not implemented | Must not be described as it |

Role acceptance is verified by incremental weight changes for identical attributes, correct
assignment, pre-normalisation ordering, recomputation after substitutions and the absence of any
multiplier below 1.0. No rule requires the primary-creation player to out-shoot secondary or neutral
players.

## 5. Coaching-strategy boundary (future, not M006)

Future work may add a team-level coaching layer: offensive focus, featured scorers, balanced offence,
perimeter emphasis, interior emphasis. It would consume the same opportunity/preference interfaces as
a separate weight layer. M006 introduces no team strategy configuration, playbook, defensive scheme
or coaching AI.

## 6. What this is not (NBA 2K reference discipline)

| Publicly observable reference concept | Ballgorithm reality | M006 proposal | Deferred |
|---|---|---|---|
| Attributes for shooting and creation | Existing ratings drive usage, zones and success | Same ratings, separated into preference and opportunity layers | — |
| Behavioral tendencies | None persisted | Derived, non-persistent preferences only | Editable, ability-independent tendencies |
| Offensive roles | None beyond position bases | Derived creation ranking | Coach-assigned roles, lineups by role |
| Coaching systems | None | None | Offensive focus, featured scorers, emphasis schemes |

NBA 2K's internal probability formulas are proprietary and not reproduced here. Public concepts are
used only as design vocabulary. No NBA-level realism or calibration claim is made.

## 7. Scope exclusions

Fatigue, injuries, manual play calling, coaching AI/strategy configuration, defensive schemes, trades,
contracts, seasons, persistence, possession-level ball movement, turnover or assist redistribution,
new PRNG algorithms, real-world player data, Flutter gameplay UI, unrelated probability tuning.

## 8. Open decisions

DD-M006-01…09 in `design-decisions.md`; empirical thresholds remain OPEN until the development pilot
and owner-approved protocol freeze.
