# M006-T06F — Corrigendum Recommendation and Evidence Assessment

- **Date:** 2026-11-09
- **Status:** RECOMMENDATION FOR OWNER DECISION (Corrigendum NOT Approved; Stage C BLOCKED).
- **Repository:** `Faraeael/Ballgorithm`
- **Branch:** `impl/m006-t06f-center-reconciliation`
- **Baseline:** Stage B Freeze `cacfd7a8583b7c4baa7f3f8d769f701d10809b2d`.
- **Governing Freeze:** `d5f9f7d16372cb523f149d3536d972ed5f83e36b` (`verification-plan.md` §5).

---

## 1. Executive Recommendation

### Question: Should Corrigendum Option 1 Be Approved?
**RECOMMENDATION: YES, WITH A MINOR EXPOSURE FLOOR CALIBRATION.**

The evaluation-tooling audit and rerun of development seeds 3001–3200 confirm:
1. **Population B is mathematically sound and contractually faithful:**
   Measuring registered Centers (`player-1-8` and `player-2-5`) across their active on-court big slots (PF and C) directly tests the frozen M006 design intent (`verification-plan.md` §3: `threePoint >= 70 at PF/C slots`).
2. **Statistical non-inferiority is overwhelmingly supported:**
   Across all 200 development games, Population B showed a mean perimeter attempt share increase of **$+1.77$ percentage points** ($s_d = 0.09392$), comfortably ruling out the non-inferiority bound of $-\Delta = -1.5$ pp ($t = 4.917, p = 9.19 \times 10^{-7}$).
3. **Prospective power at $N = 250$ is $> 99.9\%$** under the unconditional all-defined variance.
4. **Exposure Sufficiency Calibration Required:**
   In development, Population B achieved **62.5% (125/200)** paired dual-arm exposure.
   Because $62.5\%$ is slightly below the preliminary $64.0\%$ threshold ($160 / 250$), enforcing $160 / 250$ risks a false **INSUFFICIENT** gate failure due to random attempt variance. Calibrating the threshold to **$\ge 150 / 250$ (60.0%)** (or expanding the cohort to $N = 275$) makes the gate robust.
5. **Manifests Remain Valid:**
   Both Context A (`t06d-context-a-confirmatory-manifest.csv`, seeds 10001–10750) and Context B (`t06d-context-b-confirmatory-manifest.csv`, seeds 11001–11250) remain **100% valid and unmodified**.

---

## 2. Evidence Comparison Across the Three Populations (Seeds 3001–3200, $N = 200$)

All three populations were evaluated simultaneously on the identical corrected synthetic roster:

| Dimension | Population A: Registered Center, C Slot Only | Population B: Registered Centers, PF/C Slots (Recommended) | Population C: General Stretch Bigs, PF/C Slots |
|---|---|---|---|
| **Qualifying Players** | `player-1-8`, `player-2-5` | `player-1-8`, `player-2-5` | Any player with $3\text{PT} \ge 70$ |
| **Occupied Court Slots** | Slot 4 (Center) only | Slot 3 (PF) or Slot 4 (Center) | Slot 3 (PF) or Slot 4 (Center) |
| **Includes Wing Rotations?** | **NO** | **NO** | **YES** (includes Rafael Calloway, etc.) |
| **Total Attempts (v6 $\to$ v7)** | 2,453 $\to$ 2,289 FGA | 3,362 $\to$ 3,293 FGA | 5,254 $\to$ 5,063 FGA |
| **Per-Game Attempts / Team** | $\approx 11.5$ to $12.3$ FGA/gm | $\approx 16.5$ to $16.8$ FGA/gm | $\approx 25.3$ to $26.3$ FGA/gm |
| **Defined Games ($M_g > 0$)** | 200 / 200 (100.0%) | 200 / 200 (100.0%) | 200 / 200 (100.0%) |
| **v6 Mean 3PA Share** | 34.77% | 35.24% | 35.92% |
| **v7 Mean 3PA Share** | 36.30% | 37.00% | 37.82% |
| **Mean Paired Diff ($d_g$)** | **+1.53 pp** | **+1.77 pp** | **+1.90 pp** |
| **Paired SD ($s_d$)** | 0.10656 | 0.09392 | 0.08785 |
| **One-Sided $p$-value ($-\Delta = -1.5$ pp)** | $4.02 \times 10^{-5}$ | $9.19 \times 10^{-7}$ | $6.63 \times 10^{-8}$ |
| **Prospective Power at $N = 250$ ($\alpha = 0.0125$)** | $98.74\%$ | **$99.94\%$** | $99.99\%$ |
| **Paired Exposure ($\ge 10$ FGA in both arms)** | **26 / 200 (13.0%)** | **125 / 200 (62.5%)** | **149 / 200 (74.5%)** |

### Why Population A Fails the Sufficiency Requirement
Under the balanced rotation plan, starting Centers split time between Slot 4 (Center, ~17 min) and Slot 3 (Power Forward, ~15 min). Restricting attempts strictly to Slot 4 divides their shot volume in half, yielding only 26 paired games with $\ge 10$ FGA.

### Why Population B is Defensible
Population B captures 100% of the field-goal attempts taken by the registered Centers while playing frontcourt big positions, while strictly excluding perimeter wings and guards.

---

## 3. Same-ID vs. Any-ID Exposure Disambiguation

In Task 4, the owner requested distinguishing between:
- **Interpretation A:** Any registered Center qualifies in v6 AND any registered Center qualifies in v7 ($\ge 10$ FGA).
- **Interpretation B:** The SAME registered Center ID qualifies in both v6 and v7 on that seed.

### Empirical Development Finding:
- Team 1 Center (`player-1-8`): qualified in both arms in **124 of 200 games (62.0%)**.
- Team 2 Center (`player-2-5`): qualified in both arms in **5 of 200 games (2.5%)**.
- Interpretation A (Any Center in both): **125 of 200 games (62.5%)**.
- Interpretation B (Same Center in both): **125 of 200 games (62.5%)**.

**Conclusion:**
Interpretation A and Interpretation B produce an **identical count of 125 games (62.5%)**. The distinction does not alter the sample size in this matchup because Team 1's Center accounted for almost all dual-arm qualifications.
- We recommend **Interpretation B** (requiring the same Center ID to achieve $\ge 10$ FGA in both arms) as the more rigorous standard.

---

## 4. Final Owner Decision Required

To unblock Stage C confirmatory execution, the owner must formally issue one of the following decisions:

1. **Option Corrigendum-1A (Calibrated Floor, Recommended):**
   Approve Corrigendum Option 1 with Gate 2 exposure floor set to **$\ge 150 / 250$ paired games (60.0%)**.
2. **Option Corrigendum-1B (Sample Expansion):**
   Approve Corrigendum Option 1 maintaining the 160-game floor by expanding Context B from $N = 250$ to **$N = 275$ paired games** (seeds 11001–11275).
3. **Option Corrigendum-2 (Combined Slot 4 Attempt Floor):**
   Maintain strict Slot 4 Center attempts with combined team attempts $\ge 10$ FGA on $\ge 150 / 250$ games (60.0%).

**Current Readiness Disposition:** **BLOCKED** pending owner selection.
