# M006-STAGE-B-CORRIGENDUM-APPROVED — Confirmatory Protocol Corrigendum (FROZEN — OWNER APPROVED)

- **Date:** 2026-11-09
- **Status:** FROZEN — OWNER APPROVED 2026-11-09.
- **Repository:** `Faraeael/Ballgorithm`
- **Branch:** `impl/m006-t06g-confirmatory-execution`
- **Governing Baseline:** Stage B Freeze `cacfd7a8583b7c4baa7f3f8d769f701d10809b2d`.
- **Preceding Audits:** `t06e-execution-integrity-audit.md` and `t06f-corrigendum-recommendation.md`.

---

## 1. Owner Approval of Corrigendum Option 1A

By formal execution authorization on 2026-11-09, the human repository owner formally **approves and freezes Corrigendum Option 1A**.

The historical Stage B freeze documents (`t06d-stage-b-confirmatory-protocol-frozen.md` and `M006-STAGE-B-OWNER-DECISION.md`) remain preserved as historical records. This document serves as the governing addendum for confirmatory execution.

---

## 2. Locked Specification of Context B Primary Endpoint (Endpoint 3)

### Population B Locked as Primary Estimand
- **Qualifying Players:** Registered starting Centers `player-1-8` (Aurora Comets) and `player-2-5` (Ironvale Forge) only.
- **Qualifying Occupied Slots:** Attempts while actively occupying Slot 3 (`Position.pf`) or Slot 4 (`Position.c`).
- **Exclusion:** All other players, including perimeter wings (e.g. Rafael Calloway) temporarily rotated into PF, are strictly excluded from Population B.
- **Primary Estimand ($\bar{d}_{\text{popB}}$):**
  $$\bar{d}_{\text{popB}} = \frac{1}{N_{\text{defined}}} \sum_{g=1}^{N_{\text{defined}}} \left( \frac{\text{registeredCenterBigThreePa}_{v7}(g)}{\text{registeredCenterBigFga}_{v7}(g)} - \frac{\text{registeredCenterBigThreePa}_{v6}(g)}{\text{registeredCenterBigFga}_{v6}(g)} \right)$$
  - Evaluated across all games with positive denominators in both simulation arms ($M_g > 0$).
  - Zero-denominator games ($M_g = 0$) are mathematically undefined, counted, reported, and omitted from ratio averaging without replacement.
  - Games below 10 FGA are **never filtered post-hoc** from the primary effect estimate.
- **Non-Inferiority Bound:** $-\Delta = -0.015$ ($-1.5$ percentage points).
  $$H_{0,3}: \delta_{\text{popB}} \le -0.015 \quad \text{vs.} \quad H_{1,3}: \delta_{\text{popB}} > -0.015$$

---

## 3. Locked Context B Evidence-Sufficiency Requirements

The exposure sufficiency requirement for Context B is locked as follows:

1. **Gate 1 (Defined Ratios):**
   At least **200 of 250 paired games (80.0%)** must have defined Population B ratios in both simulation arms ($M_{v6} > 0$ and $M_{v7} > 0$).
2. **Gate 2 (Same-ID Dual-Arm Exposure Floor):**
   At least **150 of 250 paired games (60.0%)** must have the **SAME registered Center player ID** record $\ge 10$ field-goal attempts across their occupied PF/C slots in both v6 and v7 on that seed.
   - Specifically: $((\text{regCenter1BigFga}_{v6} \ge 10 \land \text{regCenter1BigFga}_{v7} \ge 10) \lor (\text{regCenter2BigFga}_{v6} \ge 10 \land \text{regCenter2BigFga}_{v7} \ge 10))$.
   - The owner explicitly accepts this revised $60.0\%$ standard, acknowledging that it is less restrictive than the preliminary $64.0\%$ gate ($160/250$), based on the observed $62.5\%$ ($125/200$) development rate where Centers split time across C and PF.
3. **Insufficiency Decision Rule:**
   If either Gate 1 or Gate 2 fails, Context B returns **INSUFFICIENT**. No post-hoc threshold adjustment or case replacement is permitted.

---

## 4. Invariant Stage B Parameters Confirmed

All other parameters from the frozen Stage B protocol remain 100% invariant:
1. **Context A Cohort:** $N = 750$ paired games on default M001 league (`20261028`), seeds `10001–10750` inclusive (`t06d-context-a-confirmatory-manifest.csv`).
2. **Context B Cohort:** $N = 250$ paired games on synthetic Center roster, seeds `11001–11250` inclusive (`t06d-context-b-confirmatory-manifest.csv`).
3. **Four Primary Hypotheses:**
   - Endpoint 1 (Primary Creator Share, Context A): $H_0: \delta \le +0.030$.
   - Endpoint 2 (Weak-Shooter 3PA Share, Context A): $H_0: \delta \ge -0.035$.
   - Endpoint 3 (Population B Retention, Context B): $H_0: \delta \le -0.015$.
   - Endpoint 4 (Secondary Creator Share, Context A): $H_0: \delta \le +0.005$.
4. **Holm Multiplicity Control:** Evaluated by paired Student's $t$-tests with dynamic step-down sorting across all 4 endpoints ($0.0125, 0.0166667, 0.025, 0.05$).
5. **Strict Guardrail Margins (Context A TOST at $\alpha = 0.05$):**
   - Points: $[-2.5, +2.5]$ pts.
   - Pace: $[-1.5, +1.5]$ poss.
   - eFG%: $[-1.0\text{ pp}, +1.0\text{ pp}]$.
   - Turnovers/100: $[-0.75, +0.75]$.
   - Free Throw Attempts: $[-1.75, +1.75]$ FTA.
6. **Integrity Gates:** 100% reducer validity and 100% box score accounting reconciliation required.
