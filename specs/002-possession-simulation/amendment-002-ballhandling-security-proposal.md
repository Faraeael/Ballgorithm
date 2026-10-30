# Amendment 002 — Individual ball-handling security (mathematical contract)

**STATUS: APPROVED FOR CONTROLLED EXPERIMENT — NOT CALIBRATED — NOT RELEASED**

Base: `82c66d3425fc091cffc66bab6ece22e3670ae68b` (`develop/m002`, T014).
Owner decision (experimental): architecture **C** with **Candidate B** parameters,
implemented as simulation v2. This approval covers a controlled experiment only:
not calibration, not AC09 acceptance and not release. Original v1 T014 evidence
stays published; v2 results are stored in separate artifacts.
Owner direction: **Candidate C** is the preferred architecture. This document
finalizes its mathematics. It does not authorize implementation, does not set
calibrated coefficients and changes no code, test, rules, schema, PRNG stream,
version constant or golden fixture.

Independent assessment (owner-run JEV Playground; model assessment, not proof):
Candidate C preferred 84%; conceptual soundness 1.46/2; implementation readiness
0.24/2; dominant risk "double-counting `ballHandling`" 81%. The readiness score
is consistent with the open parameter slots and owner decisions in §12.

## 1. Problem statement (unchanged)

The frozen T008 model decides possession loss from five-player **team averages**
(`probability_model.dart:520-536`) and then attributes it with weights dominated
by `ballHandling` (`684-690`, `729-773`). A better handler therefore faces a
slightly lower team rate but a **higher** share of blame, and the steal-share
term mostly relabels a turnover. Individual security and individual involvement
are the same term twice.

## 2. Historical E4 evidence (preserved verbatim)

`player-1-3`, PG of `team-1`, `ballHandling` 72→92, seeds 1–200,
`GameRules.standard`: baseline mean 11.62235, intervention 11.86828, mean paired
Δ **+0.24594**, 95% CI **[−0.09193, +0.58251]**, Holm p **0.15028**, dz 0.101,
**INCONCLUSIVE**. Subtypes (PG): steal 364→367, nonSteal 378→396, shot clock
1367→1376, offensive foul 279→295. AC09 remains unpassed. These numbers are the
historical v1 record and are not recomputed by this document.

## 3. Exposure versus security

Two separate quantities per player `i`:

- **Exposure** `e_i` — how often this player is the one who initiates a live
  possession. Determined by **role**, not by ball security.
- **Security** `h_i` — conditional basis-point hazard of losing the ball on a
  live possession he initiated. Determined by handling, decision quality and
  opponent pressure.

A higher `ballHandling` **must** lower `h_i` at fixed exposure, defense and other
player attributes. That is a conditional, per-opportunity statement. It does not
guarantee fewer turnovers in any single simulated game, and it cannot guarantee a
lower season or experiment total, because total turnovers also depend on how many
possessions the player initiates, on shot-clock violations, on offensive fouls
and on branch history.

### 3.1 Exposure specification

Raw integer weight, evaluated once per lineup per possession:

```
E_raw_i = clampMin(1,
            posBase[i]
          + γ_pass · (passing_i − 50)
          + γ_iq   · (basketballIQ_i − 50)          [+ optional γ_bh · (ballHandling_i − 50)]
          + roleBonus_i )
```

- `posBase` = the existing positional bases PG 420, SG 320, SF 280, PF 220, C 180
  (`probability_model.dart:118`) as *slots*; retention reviewed in §12.
- `γ_pass`, `γ_iq` ≥ 0 are unresolved integer slots (§12). They express
  playmaking role and decision-making responsibility.
- The `γ_bh` slot **defaults to 0**: ball handling is deliberately excluded
  from exposure so that it cannot be counted a second time. A non-zero value is
  permitted only as an owner-approved variant with the monotonicity test in §8.4
  passing.
- `roleBonus_i` ≥ 0 is an optional, explicitly documented positional/role term;
  default 0.
- `E_raw_i` is clamped to at least 1, but the clamp alone does **not** guarantee
  a positive normalized weight (see the allocation rule).

**Positive allocation to exactly 10,000** — replaces the legacy truncate-and-
remainder rule for exposure, because that rule can map a positive raw weight to
zero (example `[1, 10000, 10000, 10000, 10000]` gives `0, 2499, 2499, 2499,
2503`):

```
k        = number of active players (5)
remBudget= 10000 − k                       // 9995
extra_i  = E_raw_i · remBudget ~/ total    // truncating integer division
leftover = remBudget − Σ extra_i           // 0 ≤ leftover ≤ k − 1
r_i      = E_raw_i · remBudget − extra_i · total   // exact fractional numerator
add +1 to the `leftover` players with the largest r_i,
ties broken by lower canonical index (PG, SG, SF, PF, C)
E_i      = 1 + extra_i
```

Properties: `E_i ≥ 1` for every active player; `Σ E_i = 10000`; only integer
arithmetic and comparisons of `r_i` are used; no RNG is consumed. The deviation
from the exact share `t_i = E_raw_i · 10000 / total` obeys the proven bound
`−k < E_i − t_i < 2` (numerically `|E_i − t_i| < 5`), **not** a 2 bp bound: the
mandatory 1 bp floors cost the dominant slot up to `k − 1` basis points (example
in §19). Worked example: the vector above allocates
`E = [1, 2500, 2500, 2500, 2499]` (exact proportional shares would be
`[0.25, 2499.9, 2499.9, 2499.9, 2499.9]`).

Rationale for excluding `ballHandling` from exposure: involvement is a role and
coaching decision, while handling is a skill at protecting the ball. Keeping them
separate is the whole point of Candidate C and closes the JEV "double counting"
risk. Shot usage already rewards handling (`probability_model.dart:422-446`) in a
different decision, which remains unchanged.

## 4. Individual security hazard

```
h_i = clamp(
        B_h
      + α    · (ballHandling_i − 50)          α < 0
      + β_p  · (passing_i − 50)               β_p < 0
      + β_q  · (basketballIQ_i − 50)          β_q < 0
      + δ_pd · (oppAvgPerimeterDefense − 50)  δ_pd > 0
      + δ_ath· (oppAvgAthleticism − 50)       δ_ath > 0
      + phaseBonus[phase],
      h_min, h_max )
```

- Units: integer basis points.
- `B_h`, `α`, `β_p`, `β_q`, `δ_pd`, `δ_ath` are **unresolved integer slots**.
  Only signs are fixed. No calibrated number is proposed here.
- `phaseBonus` slots default to the existing `_turnoverPhaseBonus`
  `[250, 100, 0]` (`probability_model.dart:131`); changing them is a calibration
  act, not part of this amendment.
- `h_min`, `h_max` slots default to the existing turnover clamps 150/2500.
- Defense uses **team averages** because M002 has no individual defender matchup
  for turnover pressure; this is existing, approved semantics and is not
  player-specific double counting.
- Rounding: all terms are integers; the final clamp returns the first value
  inside `[h_min, h_max]`, evaluated in the order written.

**Team-average terms:** the existing five-average turnover probability is
replaced, not retained as an additive context term, because adding a team average
to a player mixture would reintroduce the dilution this amendment removes. Team
execution context enters through `B_h` (a slot that may be expressed as a
function of team-level inputs) and through the offense/defense attribute terms
already inside `h_i`. Any future proposal to reintroduce a separate team average
is a new amendment.

Double-count analysis is in §11.

## 5. Team hazard

```
H = clamp( floor( Σ_i (E_i · h_i) / 10000 ), h_category_min, h_category_max )
```

- Let `A = Σ_i (E_i · h_i)`, so `A ≤ 5·10^8`, safe in Dart's 64-bit integers
  and far below any 32-bit boundary that could be crossed by intermediate
  products.
- The unclamped floor is `H_u = A ~/ 10000`, hence `A = 10000 · H_u + r` with
  integer remainder `0 ≤ r ≤ 9999`. The exact mixture mean is `A / 10000`; the
  truncated category probability differs from it by less than 1 basis point.
- `h_category_min/max` slots default to the existing category clamp 150/2500;
  the clamp is applied after the floor.
- **Identity, stated precisely:** without the category clamp,
  `H = floor(Σ E_i h_i / Σ E_i)` because `Σ E_i = 10000`. The equality is exact
  only up to that floor; `10000 · H` is **not** generally equal to `A`, and the
  remainder `r` is not re-distributed into any category. Tests must assert
  `H_u = A ~/ 10000` and `|H_u − A / 10000| < 1`, never the false equality
  `A = 10000 · H`.

### 5.1 Category-selector validity

`selectAction` (`probability_model.dart:175-213`) draws one
`categoryDraw ∈ [0, 10000)` and compares against cumulative windows: turnover
`H`, offensive foul `OF`, non-shooting foul `NSF`, then shot as the residual.

Integer clamps bound the windows: `H ≤ 2500`, `OF ≤ 1000`
(`probability_model.dart:559-573`), `NSF ≤ 2200` (`574-591`). Worst-case sum
5700 < 10000, so the shot window stays positive and no category can overflow the
draw domain. Because every window is the result of a clamp to `[min, max]` with
`min ≥ 0`, `max ≤ 2200`, and `H ≥ 150`, the cumulative sums are strictly
increasing and the resulting distribution is a valid probability vector for every
legal roster and defense. Tests must assert these invariants for rating extremes
(§8.4).

## 6. Turnover actor selection

Posterior weight of player `i` given that a live turnover occurred:

```
P(i | live turnover) = (e_i · h_i) / Σ_j (e_j · h_j)
```

Exact integer implementation — positive allocation, not truncate-to-last-slot:

```
a_i   = E_i · h_i                       // 1 ≤ a_i ≤ 10^8 per player
A     = Σ a_i                           // 5 ≤ A ≤ 5·10^8
share = allocatePositive(a, 10000)      // same algorithm as §3.1:
                                        //   min 1 each, floor shares over A,
                                        //   leftover by exact remainder r_i,
                                        //   ties by canonical PG→C order
draw  = rng.nextInt(10000); select i where the cumulative crosses draw
```

`allocatePositive` guarantees `share_i ≥ 1` and `Σ share_i = 10000`, so no
player with a positive hazard can be silently excluded by rounding. The legacy
`_normalize` remainder-to-last-slot rule is **not** used for exposure or actor
weights in this contract.

Properties and boundary rules:

- **Positive weights:** `h_min ≥ 1` and `E_i ≥ 1` imply `a_i ≥ 1`; with the
  positive allocation every actor keeps `share_i ≥ 1`, so no player can be
  silently excluded by rounding.
- **Zero hazards:** impossible under the contract (`h_min ≥ 1`). If a future
  owner sets `h_min = 0`, a zero-hazard player would receive weight 0 and the
  allocation must fall back to exposure-only weights; that variant is out of
  scope and requires a new amendment.
- **Overflow:** bounded as above; tests assert `A > 0` and `A ≤ 5·10^8`.
- **Normalization:** one `nextInt(10000)` draw over weights summing to exactly
  10,000, produced by the positive allocation; exact proportional posterior
  `a_i / A` is approximated within the proven `−k < share_i − 10000·a_i/A < 2`
  bound (numerically `|share_i − 10000·a_i/A| < 5` for five players), not within
  2 bp.
- **Rounding effect:** realized selection probability is `share_i / 10000`,
  whose absolute deviation from `a_i / A` is below `5·10⁻⁴` (proven bound
  `−k < δ < 2` in basis points). The category
  probability separately uses `floor(A / 10000)`; the two draws therefore share
  the same weights but are **not** algebraically identical, and no test may
  assert exact equality between `Σ a_i` and `10000 · H`.
- **Ties:** equal `r_i` values are broken by canonical lineup order; the
  cumulative comparison uses the resulting fixed shares, so the outcome is
  deterministic for a given draw value.
- **Boundary values:** `h_i` at `h_min`/`h_max`, exposure at `E_i = 1` with the
  remaining 9,996 concentrated in one slot, all-equal ratings, and the
  `[1,10000,10000,10000,10000]` allocation example are enumerated in §10.

Consistency with §5, stated without pretending exact equality:
`A = Σ a_i = 10000 · H_u + r` with `0 ≤ r ≤ 9999`, so the category probability is
`H_u = A ~/ 10000` (floor) and the exact mixture posterior is `a_i / A`. The
actor draw uses the positive allocation of `a_i`, which reproduces `a_i / A`
within the same proven `(−k, +2)` basis-point window, so the actor distribution
integrates to the team hazard up to (a) the sub-1-basis-point floor in the
category draw and (b) the < 5-basis-point allocation rounding in the actor draw. Neither effect is re-distributed
across categories or players.

If the category clamp binds, the category probability becomes the clamp value
while the posterior still uses the unclamped `a_i`, so the two diverge by the
clamp amount; the clamp is provably inactive for the default slots within legal
rating ranges, and tests must fail loudly if a future slot change activates it.

**Why a better handler is not blamed more:** `ballHandling` appears only in
`h_i` (negatively). Raising it lowers `h_i`, which lowers both `H` and `a_i`,
while `e_i` is unchanged. The player's share of blame therefore falls weakly, and
any increase in his total credited turnovers can only come from an increase in
the number of possessions he initiates (`e_i`) or from the untouched
shot-clock/offensive-foul components — never from the rating itself.

## 7. Unrelated turnover mechanisms (unchanged)

| Mechanism | Treatment in Amendment 002 |
|---|---|
| Offensive-foul actor | Keep current `_ballHandlerScore` weights and current window; not moved into `h_i` |
| Non-shooting-foul drawn-by actor | Keep current weights; unchanged |
| Steal versus nonSteal | Keep `stealShareBasisPoints` formula, clamps and draw position; only the actor feeding it changes |
| Shot-clock violations | Keep the frozen PG attribution (`spec.md:91-94`, `game_simulator.dart:411-422`, `427-441`); high frequency and the 14 s/10–22 s interaction remain T015 realism concerns |
| Bonus free-throw resolution | Untouched (orchestrator) |
| Offensive rebounds / retained possessions | Untouched; 14 s and floor resets unchanged |
| A1 action-duration selection | Untouched; brackets, weights and versions unchanged |

Moving offensive fouls or shot-clock violations into the new hazard would change
approved semantics and requires a separate amendment.

## 8. Deterministic contract

### 8.1 Draw schedule

Live possession (`selectAction`) order is preserved:

| Step | Draw | Present now | In Candidate C |
|---|---|---|---|
| 1 | category `nextInt(10000)` | yes | yes; compares against the new `H` |
| 2 | actor `nextInt(10000)` over normalized weights | yes | yes; weights become `E_i·h_i` |
| 3 | steal-share `nextInt(10000)` | yes | yes; unchanged formula |
| 4 | defender `nextInt(10000)` | only when steal | only when steal |

So a `nonSteal` turnover consumes **3** draws and a `steal` consumes **4**, in
both the current and proposed contract. No additional draws are required.
`drawPhaseDuration`, final-tick handling, rebounds, free throws and fouling
paths are untouched.

### 8.2 Divergence with an unchanged draw schedule

The schedule is unchanged, but the **probability weights are not**, so decisions
can flip: a category draw that produced a turnover may now produce a shot, which
consumes a different number of later draws (zone, make, foul check, assist or
block), or vice versa. Changed branches then shift every subsequent draw of that
game. Canonical ledgers **may** change; equally, a given seed may produce an
identical ledger if no decision flips. Neither "all goldens change" nor "the
golden stays identical" may be asserted.

## 9. Versioning and compatibility

| Constant | Proposal | Reason |
|---|---|---|
| `gameEventSchemaVersion` | **stay 2** | no wire-format, field or enum change; reducer and accounting untouched |
| `gameSimulationVersion` | **review and bump to 2** | canonical gameplay probabilities change |
| `gameRulesVersion` | stay 1 | `GameRules` fields and clamps unchanged |
| `gameFingerprintVersion` | stay 1 | payload structure unchanged |
| `gameActionDurationModelVersion` | stay 1 | A1 untouched |
| `coreEngineVersion` / `snapshotSchemaVersion` | unchanged | M001 untouched |

Consequences of the simulation-version bump:

- `GameFingerprint.canonicalPayload` embeds `versions.simulation`
  (`game_fingerprint.dart`), so **all input fingerprints change** even though
  `gameFingerprintVersion` stays 1. Fingerprints recorded in
  `t014-paired-results.csv` are v1 artifacts and must not be compared with v2
  runs.
- Ledgers carry `gameSimulationVersion` in their header and
  `GameEventLedger.fromJson` rejects other versions, so archived v1 ledgers are
  historical artifacts; they are not replayable under v2 without an explicit
  compatibility decision.
- The T012 fixture and its pinned digest will no longer validate.
- Cross-platform determinism tests must be rerun; the contract stays integer-only
  so VM/Chrome parity remains achievable.
- Historical T014 results remain valid **as the v1 record**; a v2 rerun is a new
  experiment with the same methodological protocol, not a reproduction of the
  same bytes.

### 9.1 Controlled golden-regeneration proposal (not executed here)

1. Owner authorizes regeneration separately, after implementation review.
2. Regenerate with a documented, one-off command on the frozen v2 code; record
   the new complete ledger and SHA-256.
3. Replace `t012_canonical_ledger_fixture.dart` and its pinned constants in one
   reviewed commit; keep the v1 digests in `t012-canonical-ledger.md` as
   historical evidence.
4. Rerun VM and Chrome golden tests; both must pass before merge.
5. Never auto-update goldens on test failure.

## 10. Required implementation tests

1. **Conditional hazard monotonicity:** for fixed exposure, defense, phase and
   other ratings, increasing `ballHandling` strictly decreases `h_i`; clamps
   exercised at both ends.
2. **Exposure/security separation:** increasing only `e_i` can raise `H` while
   `h_i` is unchanged; the reverse cannot happen.
3. **Posterior consistency:** actor weights sum to exactly 10,000, every
   `share_i ≥ 1`, `−5 < share_i − 10000·a_i/A < 2`, and the empirical actor
   distribution matches `share_i/10000` within binomial bounds; `H` must satisfy
   `H_u = A ~/ 10000` and `|H_u − A/10000| < 1`, with no assertion of
   `A = 10000·H`.
4. **Extremes:** all-0 and all-100 ratings, defenses at 0 and 100, synthetic
   exposure vectors at the legal extremes (`E_i = 1` for four players with the
   fifth at 9,996), and the raw vector `[1,10000,10000,10000,10000]` which must
   allocate `[1,2500,2500,2500,2499]`; `h_i` and `H` stay inside clamps and
   windows and no actor share is zero.
5. **Category validity:** for every enumerated extreme, `H + OF + NSF ≤ 10000`
   and cumulative windows are strictly increasing.
6. **Accounting:** `team.TOV == Σ player.TOV`; subtype decomposition exhausts
   steal, nonSteal, shot clock and offensive foul; no negative or orphan counts.
7. **No double counting:** removing `ballHandling` from exposure (contract
   default) keeps monotonicity in §10.1 and produces no second handling term in
   actor weights.
8. **Determinism:** same seed and input produce byte-identical ledgers on VM and
   Chrome; draw-count audit asserts 3 draws for `nonSteal` and 4 for `steal`.
9. **Preserved semantics:** shot-clock attribution remains the PG; Amendment 001
   `nonSteal` wire values and reducer rules unchanged; offensive-foul actor
   weights unchanged.
10. **Full T014 rerun:** the frozen E1–E6 protocol, seeds 1–200, bootstrap seed
    20261029, permutation seed 424242 and six-hypothesis Holm correction are
    executed unchanged. AC09 passes only if E4 now shows a decrease with an
    interval excluding zero and Holm p < 0.05 **and** E1/E2/E3/E5/E6 do not
    regress.
11. **Diagnostic reporting:** the rerun must publish the E4 subtype split
    (steal, nonSteal, shot clock, offensive foul) so any movement is attributed
    rather than assumed. A rerun that improves only the live component, leaving
    E4 inconclusive, is a legitimate and reportable outcome.

Candidate C is **not promised to pass AC09**. Shot-clock violations (≈57% of the
baseline PG turnovers) and offensive fouls (≈12%) sit outside the security
mechanism, so the total-rate effect can stay small.

## 11. Double-counting analysis

| Attribute | Exposure | Security | Steal share | Shot usage | Verdict |
|---|---|---|---|---|---|
| `ballHandling` | **0 by contract** | yes (negative) | yes (existing) | yes (existing) | Counted once in turnover security; usage and steal share are separate decisions, documented |
| `passing` | yes (role) | optional slot | yes (existing) | no | Potential overlap; constrained by §12 decision and monotonicity tests |
| `basketballIQ` | yes (role) | optional slot | no | yes (existing) | Same treatment as passing |
| `perimeterDefense` / `athleticism` (opponent) | no | yes (pressure) | yes (existing steal weighting) | no | Defensive side only; averaged team pressure is existing semantics |
| position | yes (`posBase`) | no | bonus only | bonus only | Role only |

Safeguards:

1. `γ_bh = 0` is the contract default and a required test case.
2. If `γ_pass` or `γ_iq` is nonzero, the implementation must document each as a
   distinct effect (involvement versus decision security) and pass the
   fixed-exposure monotonicity and exposure-only tests in §10.
3. No attribute may appear twice within the same additive formula.
4. A review checklist item records each attribute, its formulas and its role.

## 12. Open parameters and owner decisions

| # | Item | Status |
|---|---|---|
| 1 | `B_h` base hazard (integer bp) | OPEN — calibration or design derivation required before implementation |
| 2 | `α` (ball-handling slope, negative) | OPEN |
| 3 | `β_p`, `β_q` (passing/IQ security slopes) | OPEN |
| 4 | `δ_pd`, `δ_ath` (opponent pressure slopes) | OPEN |
| 5 | `γ_pass`, `γ_iq` (exposure slopes) and `roleBonus` | OPEN |
| 6 | `γ_bh` (ball handling in exposure) | DECIDED default 0; non-zero variant needs explicit approval |
| 7 | `posBase` values (retain 420/320/280/220/180) | OPEN — retain by default |
| 8 | `h_min`, `h_max`, category clamp | OPEN — retain 150/2500 by default |
| 9 | `phaseBonus` retention | OPEN — retain `[250,100,0]` by default |
| 10 | Offensive-foul actor: keep current weights (proposal) or switch to exposure | OWNER DECISION |
| 11 | Shot-clock attribution policy | OWNER DECISION — proposal keeps frozen PG rule |
| 12 | `gameSimulationVersion` bump and canonical-golden regeneration | OWNER DECISION |
| 13 | Whether T015 may run before or after Amendment 002 implementation | OWNER DECISION — recommendation: after, to avoid calibrating a model that is about to change |

§14 below supplies provisional candidate values for slots 1–5 and 8. They remain
**unapproved design candidates**; approval of one set is decision 1 in §22.

## 13. Implementation readiness

**NOT READY FOR IMPLEMENTATION.** The architecture is fixed and its invariants
are specified, but items 1–5 and 7–9 in §12 are uncalibrated parameter slots, and
items 10–13 are owner decisions. This matches the independent readiness score
(0.24/2) and the identified double-counting risk, which §3.1 and §11 close at the
contract level but cannot close numerically until coefficients are approved.

Readiness requires: owner-approved slot values (or an approved derivation), the
versioning decision, and authorization of a separate implementation task.


## 14. Candidate coefficient sets (provisional, uncalibrated)

Shared exposure parameters proposed in §15: `posBase` kept, `γ_pass = 2`,
`γ_iq = 1`, `γ_bh = 0`, `roleBonus = 0`. Hazard shape from §4; only the slots
below differ.

| Slot | A — conservative | B — balanced | C — strong |
|---|---|---|---|
| `B_h` (base, bp) | **1083** | **1093** | **1103** |
| `α` (ballHandling) | −7 | −10 | −14 |
| `β_p` (passing) | −3 | −4 | −5 |
| `β_q` (basketballIQ) | −3 | −4 | −5 |
| `δ_pd` (opp. perimeter defense) | 5 | 7 | 10 |
| `δ_ath` (opp. athleticism) | 2 | 3 | 4 |
| `phaseBonus` | [250, 100, 0] | [250, 100, 0] | [250, 100, 0] |
| `h_min`, `h_max` | 150, 2500 | 150, 2500 | 150, 3000 |
| Category `H` clamp | 150, 2500 | 150, 2500 | 150, 3000 |

`B_h` is not arbitrary: each candidate's base is chosen so the exposure-weighted
mixture equals the legacy half-court hazard **1054 bp** for the E4 reference
lineup with neutral defense (`D = 0`). That isolates the structural change from a
pace/level change, because a different mean hazard would silently raise or lower
team live turnovers independent of individual sensitivity. The derivation is
`B_h = 1054 − round(Σ E_i · rest_i / 10000)`, where `rest_i` is the non-base part
of `h_i` for the baseline roster. These values remain **uncalibrated design
candidates**, not approved coefficients.

## 15. Exposure parameters and E4 involvement shares

Proposed exposure slots: `posBase = [420, 320, 280, 220, 180]` (retained),
`γ_pass = 2`, `γ_iq = 1`, `γ_bh = 0`, `roleBonus = 0`.

Roles: position base encodes rotation/initiation hierarchy; `passing` encodes
playmaking responsibility; `basketballIQ` encodes decision-making
responsibility; `ballHandling` is deliberately absent because it measures
security, not involvement.

E4 lineup raw weights: `[438, 342, 268, 252, 198]` (total 1498), all positive.
Positive allocation:

| Slot | Raw | `E_i` | Exact proportional |
|---|---|---|---|
| PG | 438 | **2924** | 2923.90 |
| SG | 342 | **2283** | 2283.04 |
| SF | 268 | **1789** | 1789.05 |
| PF | 252 | **1682** | 1682.24 |
| C | 198 | **1322** | 1321.76 |
| total | 1498 | **10000** | 10000 |

Largest deviation 0.24 bp **for this roster**; the general guarantee is the
proven `(−k, +2)` basis-point window (|error| < 5), not a 2 bp bound. Leftover 2
allocated by remainder, ties by canonical order. Comparison with the legacy handle shares (28.3/21.5/20.1/15.9/14.2%):
similar shape, slightly flatter and PG-led, now a role statement rather than a
handling statement.

## 16. Analytical feasibility per candidate (E4 reference lineup, D = 0)

Half-court values; transition and early offense add +250/+100 to every `h_i`.

| Candidate | `h_i` baseline (PG…C) | `H` | PG actor share | `h_PG` at 92 | `H` after | PG share after | live index |
|---|---|---|---|---|---|---|---|
| A | 884, 1073, 1078, 1184, 1200 | 1054 | 2452 | 744 | 1013 | 2147 | 0.842 |
| B | 813, 1081, 1083, 1243, 1263 | 1054 | 2255 | 613 | 995 | 1800 | 0.754 |
| C | 720, 1091, 1083, 1325, 1347 | 1054 | 1997 | 440 | 972 | 1323 | 0.611 |

`live index = (H_after / H_before) × (share_after / share_before)` for the PG.
Per-phase live-index bands: A 0.842–0.877, B 0.754–0.811, C 0.611–0.711.

Projected E4 effect (analytic only): with the observed baseline PG subtype mix
(live 31.07%, shot clock 57.24%, offensive foul 11.68%) and the other components
treated as unchanged in their conditional rate,

```
net index ≈ 0.6893 + 0.3107 × live index
```

| Candidate | net index | projected Δ TOV/100 | implied z (SE ≈ 0.172) |
|---|---|---|---|
| A | 0.950–0.963 | −0.43 to −0.57 | ≈ −2.5 to −3.3 |
| B | 0.922–0.941 | −0.68 to −0.90 | ≈ −4.0 to −5.2 |
| C | 0.879–0.910 | −1.05 to −1.40 | ≈ −6.1 to −8.1 |

These are **projections, not predictions of AC09 success**. They ignore branch
divergence, changed possession counts, clamp interplay and the fact that
shot-clock violations and offensive fouls remain credited under unchanged rules.
The published E4 result stays INCONCLUSIVE until an authorized rerun.

Individual passing/IQ effects at half court (candidate B): PG passing +20 →
`h_PG` 813→733, `H` 1054→1030, share 2255→2079. PG IQ +20 has the identical
numeric effect under this set because `β_p = β_q`.

Defense constant: tables use `D = 0`. A non-zero `D` shifts every `h_i` equally
before clamping; the E4 deltas are unchanged except where a clamp activates
(§18).

## 17. Exposure/security separation proof (fixed other terms)

Using candidate B, half court, E4 roster:

| Manipulation | `H` | PG actor share |
|---|---|---|
| Baseline | 1054 | 2255 |
| Exposure-only: PG passing +20 (`E_PG` 2924→3107; hazard held fixed) | **1048** | **2410** |
| Security-only: PG passing +20 (hazard 813→733; `E` held fixed) | **1030** | **2079** |
| Combined passing +20 | 1023 | 2226 |

Reading: more involvement raises the actor share and slightly lowers `H` (because
the exposed player is safer than the team mean); better security lowers both `H`
and the actor share; the two effects are separable and neither is used to fake
the other. At fixed exposure, raising `ballHandling` strictly lowers `h_i`
(`α < 0`) and therefore both `H` and the player's posterior share. Full-game
monotonicity is **not** asserted: branch divergence, shot-clock and offensive
fouls can move totals either way.

## 18. Rating-boundary and clamp analysis (candidate-specific defense ranges)

The defense constant is `D = δ_pd·(PD−50) + δ_ath·(ATH−50)`, so each candidate has
its own legal range: **A ±350, B ±500, C ±700**.

| Candidate | D range | all-0 offense, D=−max | all-0 offense, D=+max | all-100 offense, D=−max | all-100 offense, D=+max | pre-clamp max |
|---|---|---|---|---|---|---|
| A | ±350 | 1633, 1483, 1383 | 2333, 2183, 2083 | 333, 183, **83** | 1033, 883, 783 | 2333 |
| B | ±500 | 1743, 1593, 1493 | **2743, 2593**, 2493 | **−57, −207, −307** | 943, 793, 693 | 2743 |
| C | ±700 | 1853, 1703, 1603 | **3253, 3103, 3003** | **−547, −697, −797** | 853, 703, 603 | 3253 |

Triples are ordered transition, early offense, half court. Bold values cross a
clamp.

| Candidate | Clamp activations (5 cases: transition / early / half, offense at 0 or 100) |
|---|---|
| A | floor (`150`) at all-100 offense, half court, D=−350 (unclamped 83) — 1 case |
| B | ceiling (`2500`) at all-0 offense, transition and early, D=+500 (2743/2593) — 2 cases; floor at all-100 offense, all phases, D=−500 (−57/−207/−307) — 3 cases |
| C | ceiling (`3000`) at all-0 offense, all phases, D=+700 (3253/3103/3003) — 3 cases; floor at all-100 offense, all phases, D=−700 (−547/−697/−797) — 3 cases |

Clamp activations are boundary-only (rating 0 or 100 combined with the extreme
defense of that candidate) and must be covered by tests: in this corner
enumeration A clamps in 1 player-phase case, B in 5, C in 6 (§23.3 shows B also
clamps over interior handling ranges under near-extreme inputs). This is one
reason C is not recommended. Pre-clamp values remain far below any integer
limit.

## 19. Integer, normalization and rounding error analysis

- Exposure and actor allocation: min-1 largest-remainder; every share ≥ 1, sums
  exactly 10000. Exact error bound: `−k < share_i − t_i < 2` basis points, so
  `|error| < 5` for five players. The mandatory floors make a sub-2 bp claim
  false: with `E = [9996,1,1,1,1]` and `h = [3000,150,150,150,150]` the dominant
  exact posterior share is 9999.800 bp while the allocator must leave 1 bp to
  each other slot and can give it only 9996, an error of 3.800 bp. The bounds
  hold for every legal roster; the E4 allocation happens to be tighter
  (≤ 0.25 bp) but that is not a general property.
- Hazard: pure integer arithmetic; each term is a product of an integer
  coefficient and a rating delta in `[−50, +50]`. Pre-clamp extremes over the
  candidate's own legal defense range: A ≤ 2333, B ≤ 2743, C ≤ 3253; minima are
  83, −307 and −797 before the floor. All clamp to `[h_min, h_max]`.
- `A = Σ E_i·h_i ≤ 5 · 10^4 · 3 · 10^3 = 1.5 · 10^8`; `a_i ≤ 3 · 10^7` for the
  proposed sets (generic bound 10^8 when `h_max = 10000`). Far inside Dart's
  64-bit int; no double arithmetic is used anywhere.
- `H_u = A ~/ 10000`, remainder `r = A − 10000·H_u ∈ [0, 9999]`; `H_u` differs
  from the exact mean by < 1 bp and `r` is dropped, never reallocated.
- Actor shares are the positive allocation of `a_i`; realized probability
  `share_i/10000` differs from the exact posterior `a_i/A` by < 5·10⁻⁴.
- No test may assert `A = 10000·H`; the documented relation is
  `A = 10000·H_u + r`.

## 20. Double-counting matrix (final)

| Attribute | Exposure role | Security role | Other existing use | Overlap verdict |
|---|---|---|---|---|
| `ballHandling` | none (`γ_bh = 0`) | `α < 0` | shot usage, steal share | counted once in turnover causality; other uses are distinct decisions |
| `passing` | `γ_pass = 2` (involvement) | `β_p < 0` (security) | steal share, assist weighting | deliberate dual role, separated analytically in §17 and constrained by tests |
| `basketballIQ` | `γ_iq = 1` (responsibility) | `β_q < 0` (security) | shot usage, offensive fouls | same as passing |
| opponent `perimeterDefense`, `athleticism` | none | `δ > 0` | steal weighting, conversion defense | defensive pressure only |
| position | `posBase` | none | usage/rebound/steal/foul bases | role only |

Rules enforced: no attribute twice in one additive formula; `ballHandling` never
in exposure; passing/IQ dual use documented and covered by the separation tests
in §17; owner may set `γ_pass = γ_iq = 0` to remove dual use entirely, at the cost
of flatter involvement.

## 21. Recommended provisional set

Recommendation: **Candidate B**, with the option for the owner to demote it to A
if turnover-level preservation outweighs individual responsiveness.

Why B: it keeps the reference-lineup mean hazard at the legacy 1054 bp, gives a
clear per-player security response (`α = −10`), produces a live-turnover index of
0.75–0.81 for the E4 intervention (materially larger than the 1/5-diluted 0.97
legacy effect), avoids clamp activation for the E4 roster and mid-rated rosters
while clamping only under near-extreme defense/involvement combinations
(§23.3), and keeps the category bounds and draw schedule intact. C overstates
individual slope, hits the hazard floor at legal extremes and widens the
category window.

Limitations, stated explicitly:

- All slots are uncalibrated design values; they are not approved coefficients.
- No claim is made that B passes AC09; the projection is analytic and ignores
  divergence, shot-clock and offensive-foul components.
- The attribution shape at baseline changes (PG share 2827 → 2255 under B), which
  will move player turnover counts and must be reviewed as a role-realism change.
- The reference matchup (team-1 vs team-2) is one fixture; other rosters may
  stress clamps.

## 22. Remaining owner decisions and future checklist

Owner decisions still open:

1. Approve candidate B (or A/C), i.e. the slots in §14.
2. Confirm exposure parameters §15 (`γ_pass = 2`, `γ_iq = 1`, `γ_bh = 0`), or
   remove the passing/IQ dual role.
3. Decide the exposure `posBase` retention (proposed: keep).
4. Decide whether C's wider category clamp is ever acceptable (proposed: no).
5. Approve `gameSimulationVersion = 2` and the separate T012 golden regeneration.
6. Keep offensive-foul actor weights, shot-clock PG attribution, free throws,
   rebounds, A1 durations, event schema v2 and Amendment 001 unchanged
   (recommended).
7. Authorize a separate implementation task; no implementation is authorized by
   this document.

Future implementation/review checklist: unit tests from §10; the added tests for
§17 separation, §18 clamps, §19 rounding bounds; full T014 E1–E6 rerun with
unchanged metrics and seeds; subtype reporting for E4; team/player reconciliation;
VM/Chrome determinism; canonical-ledger review and separately authorized golden
regeneration; T015 realism measurement only after the model is stable.


## 23. FINAL TARGETED PARAMETER REVIEW (Candidate B)

Status remains **PROPOSED — NOT IMPLEMENTED**. Nothing below authorizes
implementation, and no coefficient was tuned against T014 outcomes.

### 23.1 Contract verified

Positive min-1 largest-remainder allocation, exact `H_u = A ~/ 10000` floor with
remainder `r`, the corrected `(−k, +2)` basis-point allocation window, candidate-
specific defense ranges (A ±350, B ±500, C ±700), explicit clamp cases and the
statement that no E4 improvement is guaranteed are all present in §§3–19. No
remaining inconsistency was found except the two corrected below (actor/clamp
divergence wording; the γ=0 sensitivity threshold).

### 23.2 Candidate B as reviewed

`B_h = 1093`, `α = −10`, `β_p = −4`, `β_q = −4`, `δ_pd = +7`, `δ_ath = +3`,
phases `[250, 100, 0]`, `h ∈ [150, 2500]`. Exposure: `posBase` 420/320/280/220/180,
`γ_pass = 2`, `γ_iq = 1`, `γ_bh = 0`. Actor posterior `E_i·h_i` with positive
allocation. Category windows unchanged (`OF ≤ 1000`, `NSF ≤ 2200`).

New invariant proved in this review: because every `h_i ∈ [150, 2500]`, the
exposure-weighted mean `H_u` is also in `[150, 2500]`, so the **category clamp
never binds** for Candidate B; only individual clamps can activate. Category sum
`2500 + 1000 + 2200 = 5700 < 10000` keeps the shot window positive.

### 23.3 Clamp stress matrix (synthetic ratings, all three phases)

Exposure is normalized per roster; hazardous rows show pre-clamp values.

| Scenario | pre-clamp h range | players at a clamp | E share range | actor share range | H (trans/early/half) |
|---|---|---|---|---|---|
| E4 balanced, D=0 | 813–1513 | 0 | 1322–2924 | 1534–2383 | 1304 / 1154 / 1054 |
| all 0, D=0 | 1993–2243 | 0 | 449–4029 | 450–4028 | 2243 / 2093 / 1993 |
| all 100, D=0 | 193–443 | 0 | 1521–2626 | 1521–2626 | 443 / 293 / 193 |
| all 0, D=+500 | 2493–2743 | all 5 players in transition and early (ceil) | 449–4029 | 450–4028 | 2500 / 2500 / 2493 |
| all 100, D=−500 | −307 to −57 | all 5 players in all phases (floor) | 1521–2626 | 1521–2626 | 150 / 150 / 150 |
| all 50, D=±500 | 593–1843 | 0 | 1268–2957 | same as E | 843–1843 |
| strong PG, weak rest | 193–1883 | 0 | 744–4709 | 952–3250 | 954–1204 |
| weak PG, strong rest | 193–1883 | 0 | 1710–2435 | 752–6355 | 439–689 |
| high BH / low passing | 813–1063 | 0 | 1072–3214 | 1073–3213 | 813–1063 |
| low BH / high passing | 1233–1483 | 0 | 1429–2747 | 1429–2747 | 1233–1483 |
| high IQ / low BH | 1233–1483 | 0 | 1359–2839 | 1359–2839 | 1233–1483 |
| low IQ / high BH | 813–1063 | 0 | 1182–3070 | 1182–3070 | 813–1063 |
| high fictional (80) | 553–803 | 0 | 1444–2727 | 1444–2727 | 553–803 |
| low fictional (20) | 1633–1883 | 0 | 928–3401 | 929–3400 | 1633–1883 |
| all 100, D=+500 | 693–943 | 0 | 1521–2626 | 1521–2626 | 943 / 793 / 693 |

Findings:

- Of the 15 scenarios, **2 clamp** (all-0 with D=+500; all-100 with D=−500).
  Counting player-phase instances: 5 players × 2 phases + 5 players × 3 phases =
  **25 clamped instances out of 225 (11.1%)**. The E4-shaped, generated-looking
  and mid-rated scenarios clamp zero times, but that is not evidence about the
  generated league.
- Saturation is **not confined to exact 0/100 ratings**. The ceiling clamps
  whenever `1093 − 10(BH−50) − 4(p−50) − 4(q−50) + D + phase > 2500`. With
  `D = +500`, `passing = IQ = 0`, transition: `BH ≤ 24` clamps (BH = 1 gives
  2733 bp; BH = 24 gives 2503), early: `BH ≤ 9` clamps, half court: none. The
  floor behaves symmetrically: with `D = −500`, `passing = IQ = 100`, half court
  clamps for `BH ≥ 55`, early for `BH ≥ 65`, transition for `BH ≥ 80`.
  Untested interior combinations can therefore also clamp; the table is a sample,
  not an exhaustive boundary map.
- Because clamps are per-player and applied before the mixture, category hazard
  cannot clamp (§23.2), so category and posterior never diverge through the
  category bound; they can only differ by the documented allocation window and
  by individual clamping compressing the hazard spread (visible in the strong/
  weak PG rows where actor shares widen to 6355 because teammates differ in
  security).
- Saturation does not make skill ineffective along the sampled interior rows
  (rows 1, 6–14), but near-extreme combinations (defense near max, passing/IQ
  near min or max) can clamp over ranges of handling ratings, flattening further
  skill differences. Prevalence across the M001 generated league is unmeasured.
- **Not measured:** clamp incidence across the 1,000-game M001 generated league;
  T015 must measure it rather than assume these synthetic frequencies.

### 23.4 Passing / basketballIQ overlap (Candidate B, half court)

PG (`E_raw` 438 baseline, `h` 813) and C (`E_raw` 198, `h` 1263):

| Change | PG E / h / H / share | C E / h / H / share |
|---|---|---|
| baseline | 2924 / 813 / 1054 / 2255 | 1322 / 1263 / 1054 / 1594 |
| passing +1 | 2933 / 809 / 1052 / 2254 | 1334 / 1259 / 1054 / 1594 |
| passing +10 | 3017 / 773 / 1039 / 2244 | 1436 / 1223 / 1051 / 1671 |
| passing +20 | 3107 / 733 / 1023 / 2226 | 1548 / 1183 / 1047 / 1749 |
| IQ +1 | 2928 / 809 / 1052 / 2249 | 1328 / 1259 / 1053 / 1587 |
| IQ +10 | 2970 / 773 / 1040 / 2206 | 1380 / 1223 / 1050 / 1607 |
| IQ +20 | 3017 / 733 / 1027 / 2153 | 1436 / 1183 / 1045 / 1625 |

Fixed-exposure monotonicity holds for both attributes: `h_i` falls by 4 per point
and `H` falls; the actor share falls at fixed exposure.

Full-contract behaviour: the share changes as
`(1 − E_share_i) · (γ/E_raw_i − 4/h_i)`, so a player is credited **more** often
when `h_i > (4/γ)·E_raw_i`:

- PG: passing threshold `E_raw < h/2` → 438 < 406 is false, so the share falls
  (2255 → 2226); IQ threshold `E_raw < h/4` → 438 < 203 false, share falls
  further (→ 2153).
- C: 198 < 631 (passing) and 198 < 316 (IQ) are true, so the C's share **rises**
  (1594 → 1749 passing, → 1625 IQ) while his hazard and team hazard fall.

Interpretation: for the initiator, security dominates; for a low-involvement
player, added playmaking responsibility raises his exposure faster than better
decisions protect him. This is exposure-driven and legitimate under the contract,
but it is a real incentive effect: improving passing/IQ can increase credited
turnovers for low-usage players even though per-possession risk fell.

Sensitivity alternative (`γ_pass = γ_iq = 0`, position-only exposure): PG 2289 →
2111 and C 1525 → 1443 for +20 passing, i.e. attribution always falls with
skill. The cost is that playmaking role no longer influences involvement at all.
This comparison is informational; switching is an owner decision, not part of the
recommended set.

Verdict on overlap: passing/IQ have **defensibly distinct roles** (involvement
vs decision security) and neither is counted twice inside one formula. The
observable "credited more while safer" case is bounded to players whose exposure
is low relative to their hazard and is a role effect, not a security inversion.
`ballHandling` remains single-purpose.

### 23.5 Allocation and probability consistency

- Exposure and actor weights: min-1 largest-remainder, sums exactly 10000, ties
  by canonical order; `E_i ≥ 1`, `share_i ≥ 1`.
- Error window `−k < share_i − 10000·a_i/A < 2` (|error| < 5 bp). Extreme case
  `E = [9996,1,1,1,1]`, `h = [3000,150,150,150,150]`: exact dominant posterior
  9999.800 bp, allocated 9996, error **3.800 bp** — inside the bound, outside a
  2 bp claim.
- `A ≤ 1.5·10^8`; per-player `a_i ≤ 3·10^7`; Dart 64-bit safe.
- `H_u = A ~/ 10000`, remainder dropped; category clamp provably inactive
  (§23.2); `H + OF + NSF ≤ 5700`.
- No negative or over-10000 category probability is constructible.

### 23.6 Mechanism check

Separates exposure from security; better handlers are not systematically blamed
(share falls for the PG while `h` falls); individual handling drives conditional
security; opponent pressure preserved through `δ_pd/δ_ath`; accounting, steal/
non-steal contract, offensive-foul policy, A1 durations, 14-second resets and
shot-clock PG attribution unchanged. Shot-clock attribution remains ≈57% of
baseline PG turnovers and lies outside the mechanism; it dampens but does not
determine E4 outcomes in either direction.

### 23.7 Candidate B versus Candidate A

A is numerically the legacy slopes applied per player with neutral base 1083. In
the §18 boundary enumeration A clamps in 1 player-phase case versus B's 5 (plus
the interior ceiling ranges quantified in §23.3), and its E4 live index is 0.84
versus B's 0.75, i.e. a smaller individual-security response. A does not fix the
passing/IQ involvement overlap (same `γ` contract) and does not remove any B
defect; no specific B problem was demonstrated that A solves. B remains the
recommendation; A stays the fallback if the owner prefers weaker responsiveness
and fewer extreme clamps.

### 23.8 Accepted limitations and required actions

Accepted: `ballHandling` contributes only to security; passing/IQ dual role with
the documented threshold effect; individual clamp saturation under near-extreme
input combinations (not only literal 0/100 corners; ranges quantified in §23.3);
unchanged shot-clock block; attribution shape changes at baseline (PG share
2827 → 2255 under B).

Requires action before implementation: owner approval of B's slots, decision on
`γ_pass/γ_iq` (keep 2/1 or set 0), approval of `gameSimulationVersion 2` and the
separate T012 golden-regeneration plan; a separate implementation task; T015
measurement of clamp incidence and turnover realism across the generated league.

### 23.9 Readiness assessment

| Property | Verdict |
|---|---|
| MATHEMATICALLY VALID | YES — formulas, normalization, bounds, clamps and draw schedule are fully specified and stress-checked |
| BASKETBALL-PLAUSIBLE | YES with the passing/IQ role caveat documented; no exposure/security inversion for the primary handler |
| STATISTICALLY CALIBRATED | NO — coefficients are design candidates; E4/AC09 remain unpassed until the authorized rerun |

Final readiness: **CONDITIONAL GO for controlled implementation**, conditional on
owner approval of the §14/§23.2 parameters, the `γ` decision, the version bump
and the golden-regeneration authorization. It is not a GO to merge a changed
canonical model, and it is not a claim that AC09 will pass.
