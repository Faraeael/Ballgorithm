# Specification 006 — Role-Aware Shot Selection v1 (DRAFT)

> **Status: DRAFT — NOT FROZEN — NOT AUTHORIZED FOR IMPLEMENTATION.**
> Written 2026-11-07 on `design/m006-role-aware-shot-selection`, branched from `develop/m002`
> `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`. No acceptance criterion below has been run or passed.
> Nothing here authorizes a code change, a version bump, a fixture, calibration or a release.

## 1. Purpose

M005 accepted the possession engine, participation rules, tactical rotations and the app surfaces.
The M002 conditions (`M002-OWNER-ACCEPTANCE.md` §7) and the deferred-realism backlog
(`specs/002-possession-simulation/M003-BACKLOG.md` Priority 1) require player decision-making to
become role-aware before any broader realism claim.

M006 v1 changes **who shoots and from where**, using only existing attributes and canonical court
slots. It does not simulate ball movement, play calls or coaching; it shapes deterministic
probabilities.

## 2. Current behaviour (v6, verified in source)

Shooter selection (`shotUsageWeights`):

```text
usage(p) = positionBase[slot]              # PG 260 … C 170
         + 3 × max(0, bestShot(p) − 50)    # best of inside/midrange/three
         + 2 × (ballHandling − 50)
         +      (basketballIQ − 50)
floored at 60, normalised to 10000. The actor draw uses these weights.
```

Zone selection (`_shotZoneWeightsForSlot`), drawn **after** the shooter, from that shooter's own
ratings:

```text
inside   = 2400 + 22·(insideScoring−50) + 10·(athleticism−50) + slotInside[−400…900] + phaseInside
midrange = 2500 + 26·(midrange−50)                          + slotMid[100…−300]   + phaseMid
three    = 3600 + 24·(threePoint−50)                        + slotThree[250…−900] + phaseThree
each floored at 200, normalised to 10000.
```

Turnover, offensive-foul and non-shooting-foul actors use a separate ball-handler score
(`slotBase[420…180] + 3·ballHandling + passing + basketballIQ`). The zone draw happens after the
actor draw; make, foul, assist and block draws follow in a fixed order.

Consequences relevant to M006:

- There is no role concept. Two players with identical attributes behave identically except for slot
  position bonuses.
- Three-point volume is ability-sensitive but weakly differentiated: a centre with `threePoint` 20
  still takes roughly a quarter of his attempts from three, because the 3,600 base and the −900
  centre bonus dominate the −24-per-point slope.
- Nothing separates a legitimate stretch-five from a non-shooting big; both use the same linear term.
- `FieldGoalAttempt` persists `shooterId` and `shotValue` (2 or 3) only. Inside versus midrange is
  not serialised, so that split is not recoverable from a canonical ledger.

## 3. What M006 v1 changes

### 3.1 Derived offensive-role signal (non-persistent)

Per active five, rank the players by an explicit **creation score** built only from existing data:

```text
creation(p) = slotBase[slot] + 3·ballHandling + passing + basketballIQ   (same score the foul
actor already uses, documented below as the creation ordering)
```

The top-ranked player is the **primary-creation slot**; the others are secondary. Ties break on
canonical court-slot order.

This is a *classification used to shape weights*. It is **not** a simulated possession-level
ballhandler, not a persistent `Player` field, and it does not decide who turns the ball over or
commits an offensive foul; those keep their existing independent draw. The specification must say
this wherever the role is described.

### 3.2 Usage policy (P1-1, P1-4)

Shooter usage gains a role component applied to the existing raw weights before normalisation:

```text
usage(p) = currentRawUsage(p) × roleFactor(rank(p))
roleFactor defaults: rank 0 → 13500 bp, rank 1 → 11500 bp, ranks 2–4 → 10000 bp
(provisional; owner decision DD-M006-02)
```

No new draw is introduced. Normalisation restores the sum to 10000, preserving the existing actor
draw.

### 3.3 Zone-willingness policy (P1-2, P1-3)

Replace the linear `24·(threePoint−50)` term with a piecewise ability curve, keeping the position
bonus, phase bonus and floor:

```text
ability(p) = 50·(p − 50)  when p < 50     # steep below-median penalty
           = 30·(p − 50)  when p ≥ 50     # moderate reward above median
three = 3600 + ability(threePoint) + slotThree + phaseThree, floored at 200
inside and midrange terms unchanged
```

Effect at the design points (illustrative, not calibrated):

| Shooter | `threePoint` | Old three weight | New three weight | Intended direction |
|---|---|---|---|---|
| Centre, non-shooter | 20 | 1980 | 1200 | materially fewer threes |
| Centre, stretch | 80 | 3420 | 3600 | perimeter volume retained |
| Guard, weak | 35 | 3240 | 2850 | fewer threes |
| Guard, strong | 75 | 4200 | 4350 | slightly more threes |

Deliberately not proposed: a position ban on threes, a hard role gate, or any threshold that zeroes
a zone. The stretch-big outcome is an explicit acceptance criterion, not a side effect.

### 3.4 Event schema

Event schema stays **3**. M006 v1 adds no event type and no persisted shot-zone field. Canonical
ledgers therefore expose shooter identity and 2/3-point attempts only. Inside-versus-midrange
attribution is **not** measurable from canonical fixtures and must not be claimed.

Optional non-persistent instrumentation, if approved (DD-M006-05): a debug-only shot-decision
observer on the simulator, mirroring `onPhaseTrace`, that reports the drawn zone and weights to a
test callback without entering the ledger or the fingerprint.

### 3.5 Versioning

| Identifier | v6 | M006 v1 target | Reason |
|---|---|---|---|
| `gameSimulationVersion` | 6 | **7** | Weighted shot behaviour changes |
| `gameFingerprintVersion` | 4 | **5** | Version-bearing canonical input |
| `gameRulesVersion` | 3 | 3 | No clock, foul, bonus or possession-rule change |
| `gameEventSchemaVersion` | 3 | 3 | No serialisation change |
| `gameActionDurationModelVersion` | 2 | 2 | A1 durations untouched |
| PRNG | `xorshift32-v1` | unchanged | No new randomness source |
| `coreEngineVersion` / `snapshotSchemaVersion` | 1.0.0 / 1 | unchanged | M001 untouched |

All v1–v6 fixtures remain historical evidence and are never rebaselined. M006 adds new v7
fixtures.

### 3.6 Determinism contract

- No new random draws. Category, actor, zone, make, foul and assist/block draws keep their
  documented order inside each action branch.
- Because weighted choices differ, downstream game paths may diverge and whole-game draw counts
  need **not** match v6. No v6/v7 byte equality is claimed.
- Required proofs: same-input/same-seed repeat-run identity, Dart VM/Chrome parity, no-plan-mode
  determinism, and an explicit list of intentional v6 differences.

## 4. Acceptance intent (directional)

1. Weak perimeter shooters take materially fewer threes than in v6.
2. Legitimate high-`threePoint` forwards and centres keep meaningful perimeter volume.
3. Different lineups produce measurably different shot distributions by role.
4. The change is sound, deterministic and replayable, with no rules or schema drift.
5. Historical evidence and M001–M005 contracts are untouched.

No NBA-realism, calibration or device-performance claim is made.

## 5. Scope exclusions

Fatigue, injuries, manual play calling, coaching AI, defensive schemes, trades, contracts, seasons,
persistence, possession-level ball movement, turnover or assist redistribution, new PRNG algorithms,
real-world player data, Flutter gameplay UI and unrelated probability tuning are excluded.

## 6. Open decisions (owner approval required)

| ID | Decision | Default proposal |
|---|---|---|
| DD-M006-01 | Role derivation: creation-score ranking versus another attribute formula | creation score above |
| DD-M006-02 | Role multipliers for usage | 135/115/100 bp |
| DD-M006-03 | Zone curve: piecewise ability slope versus multiplicative factor | piecewise |
| DD-M006-04 | Keep schema 3 and accept unmeasured 2-point split | keep 3 |
| DD-M006-05 | Debug shot-decision observer allowed | yes, non-persistent |
| DD-M006-06 | Evaluation thresholds and seeds | pre-registered before any cohort |

## 7. Non-goals and non-claims

This draft does not freeze a contract, does not authorize implementation, and does not assert any
statistical result. Every acceptance row is **NOT RUN**.
