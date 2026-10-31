# M002 — Owner Acceptance Record

> **Date of decision:** 2026-10-31
> **Milestone:** M002 possession simulation (Amendments 001–004)
> **Decision:** **M002 — ACCEPTED WITH CONDITIONS — TECHNICAL POSSESSION-ENGINE FOUNDATION ONLY**
> **Decision maker:** project owner (human)
> **Evidence commit at decision time:** `30238185cae8a81a650df615f828a5e801f5fc64` (`develop/m002`)
> **Model accepted:** `gameSimulationVersion` **4**, `gameRulesVersion` 2, `gameEventSchemaVersion` 2, `gameActionDurationModelVersion` 2, `gameFingerprintVersion` 2, PRNG `xorshift32-v1`
> **Review inputs:** `acceptance-report.md` (AC01–AC13 evidence), `t019-review-packet.md` (six reproduced games + box scores), `t017-regression-scope-report.md` + `t017-closeout-addendum.md`, `t016-performance-report.md` + `t016-provenance-correction-addendum.md`, Amendment 003 waiver/manifest, Amendment 004 specification/recovery/held-out/D1 records, and an advisory JEV Playground evaluation.

---

## 0. Advisory JEV input (non-authoritative)

An advisory JEV Playground evaluation was reviewed before the decision. It is recorded for traceability only; **JEV does not bind this acceptance** and the human owner made the final call.

| Advisory metric | Value |
|---|---|
| QUALIFIED_ACCEPTANCE | 88% |
| CONDITIONAL_HOLD | 11% |
| REJECT_REVISE | 1% |
| Shot-selection blocker probability | 17% |
| Future rework risk (of 4) | 2.44 |

The 17% shot-selection blocker probability and the 2.44/4 rework risk are the substantive advisory signals; they motivate Priority 1 in `M003-BACKLOG.md` (role-sensitive shot selection) rather than any M002 rejection.

---

## 1. What is being accepted, and what is not

**Accepted:** the **technical possession-engine foundation** — a deterministic, replayable, event-sourced half-court possession simulation with frozen contracts, verified invariants, and qualified statistical evidence for the offensive-foul calibration.

**Explicitly NOT claimed by this acceptance:**

1. This is **not an unconditional statistical certification.** Two gates carry conditions (§2, §3) and one experiment leg carries a procedural exception (§4).
2. This is **not approval of NBA-level realism.** M002 has never claimed NBA equivalence; passing internal frozen envelopes is not a realism proof.
3. This is **not approval for production release.** No release, version bump, store readiness or deployment approval is granted here.
4. **Deferred realism improvements remain mandatory project work** before any claim of full simulation realism (§5 / `M003-BACKLOG.md`).

Acceptance is scoped to the possession engine and its evidence. It does not extend to seasons, trades, contracts, coaching AI, tactics, rotations, injuries, saves, networking or Flutter feature work, all of which remain out of M002 scope.

---

## 2. AC09 — Attribute sensitivity: **ACCEPTED** (conditional scope: simulation v4)

- **Decision:** ACCEPTED for the **current simulation v4**, supported by **6/6 successful fresh sensitivity experiments** (seeds 10001–10200, `amendment-004-heldout/t014-v4-fresh-raw.json`; E1 +0.0737, E2 +0.1062, E3 +0.0133, E4 −0.4537, E5 −0.0633, E6 +28.4589; all Holm p = 0.000600; independently recomputed by `verify_heldout.py` from the 1,200 ordered `perSeed` records using a port of the frozen `t014_stats.dart` algorithm).
- **Historical record unchanged:** the **v1 E4 (`ballHandling`) INCONCLUSIVE** outcome — mean +0.24594, 95% CI `[−0.09193, +0.58251]`, Holm p = 0.1503, wrong sign — remains exactly as recorded in `t014-sensitivity-report.md` and `t014-statistical-summary.json`. It is **not** re-scored, retro-fixed or reclassified.
- **What the acceptance means:** the AC09 *intent* (ratings move outcomes in the expected direction, confirmed under a paired design) is satisfied by v4 evidence. It does not mean v1 was correct.
- **Supporting generations:** v2 rerun 6/6 (E4 −0.435, Holm 0.0124); v4 development 6/6 (E4 −0.830); v4 fresh held-out 6/6.

## 3. AC10 — Calibration: **CONDITIONALLY ACCEPTED** (scope: limited M002 foundation)

- **Decision:** CONDITIONALLY ACCEPTED for the **limited M002 foundation**, supported by the v4 Amendment 004 calibration evidence plus human gameplay review.
- **Evidence accepted as qualified:** fresh held-out cohort, 2,240 games (1,120 v3 + 1,120 v4), 600 fresh seeds 10001–10600; all nine frozen Amendment 004 gates pass by point estimate with full 95% CIs inside their envelopes under the DOF-corrected analysis — G1 OF/team-game 2.2143 `[2.1430, 2.2855]`; G2 OF share 0.1242 `[0.1205, 0.1279]`; G3 TOV/100 17.4285 `[17.2218, 17.6353]`; G4 SC/game 4.1714 `[4.0387, 4.3042]`; G5 possessions/team-game 102.2929 `[101.9880, 102.5977]`; G6 median FGA 92 `[91, 92]`; G7 3PA/FGA 0.4134 `[0.4106, 0.4161]`; G8 eFG 0.5230 `[0.5187, 0.5274]`; G9 6/6 PASSED. Zero rollback triggers fired.
- **Historical record unchanged:** the **v2 calibration failure** stands — `tovPer100Completed` **24.7594** against the frozen band `[7, 24]` (above band), with the documented structural cause (14 s reset × 10–22 s A1 bracket). It is **not** converted to a PASS and **not** re-baselined.
- **Why conditional:** the accepted evidence is internal-envelope calibration on **one generated league with eight rosters**, plus a qualified (D1-corrected) inference, plus human review of six games. NBA-scale differences remain (turnovers/100, shot-clock violation frequency). Realism at NBA level is **not** accepted.

## 4. D1 — Protocol deviation: qualified exception **continues to apply**

- The original held-out verdict is **preserved verbatim**: **`INCONCLUSIVE — EVIDENCE OR EXECUTION ISSUE`** (`PROTOCOL-DEVIATION.md`).
- The conditional procedural exception stands: **`QUALIFIED HELD-OUT EVIDENCE ACCEPTED FOR FURTHER M002 REVIEW — D1 PROCEDURAL EXCEPTION RECORDED`** (`OWNER-D1-DISPOSITION.md`).
- Facts attached to the exception, unchanged: the frozen analysis omitted the per-component small-sample DOF factor required by `amendment-003-seed-provenance-manifest.md` §4; the correction was applied after outcomes had been viewed; an independent from-scratch audit reproduced all 66 estimators within 5.55×10⁻¹⁷, found 0 negative variances and 0 conclusion flips.
- The exception is **not** a finding that the frozen analysis was conformant, and it does not erase the INCONCLUSIVE verdict.

## 5. T019 — Human gameplay review: **COMPLETED WITH CONDITIONAL ACCEPTANCE**

- **Review material:** `t019-review-packet.md` — six games selected by a fixed, pre-documented rule (median / lowest / highest combined points, most shot-clock violations, most offensive fouls, most overtimes) from the frozen v4 held-out cohort, each reconstructed deterministically (`tool/t019_game_extract.dart`, one execution per game, **0 aggregate mismatches**, `inputFingerprint` matched, ledger replayed, accounting reconciled).
- **Reviewer findings accepted by the owner:** no simulation defect in any of the six; the outliers are statistical tails with identifiable mechanisms (short-clock continuation for P4, IQ/ATH hazard terms for P5, efficiency tail for P3, exposure×hazard for P2, extra time for P6). Conditional acceptance reflects realism gaps rather than correctness defects.
- **Correction recorded:** the packet's earlier explanation of live-turnover attribution (legacy ballhandler weights) was wrong for v4 and has been corrected to the implemented **exposure × hazard** mechanic, verified against `probability_model.dart`. No basketball logic, evidence, statistic or box score was changed by that correction.
- **What a single game cannot do:** per-game box scores cannot establish a rating's marginal effect; that question is answered only by the paired-cohort AC09 design.

---

## 6. Status taxonomy (kept separate on purpose)

| Category | M002 items |
|---|---|
| **Technical PASS** (verified invariant against a frozen threshold, in-repo evidence) | AC01, AC02, AC02b, AC03, AC04, AC04b, AC05, AC06, AC07, AC07b, AC07c, AC08, AC11, AC11b, AC12, AC13 |
| **Owner acceptance** | AC09 (v4, conditional on scope), T019 review completed |
| **Conditional acceptance** | AC10 (limited foundation), D1-qualified held-out evidence, M002 as a whole |
| **Historical FAIL** (preserved, never converted) | Amendment 003 pace `+2.21%` dev / `+2.05%` held-out vs `+2.5%` minimum; Amendment 003 offensive-foul share `26.02%` dev / `25.67%` held-out vs `≤24.0%`; T015 `tovPer100Completed` 24.7594 vs `[7, 24]`; T014 v1 E4 INCONCLUSIVE |
| **NOT MEASURED** | Android runtime performance; device memory/battery; clamp-floor binding frequency; inside-vs-midrange shot-zone distribution; player minutes (not modelled) |

`acceptance-report.md` (T018) is **not** rewritten: its as-of-report findings stand, including its `PENDING OWNER REVIEW` labels for AC09/AC10. This document records the owner decisions that follow it.

## 7. Conditions attached to this acceptance

1. **AC10 is conditional** — realism claims beyond the limited foundation require the M003+ work in `M003-BACKLOG.md`.
2. **D1 remains visible** — any downstream document citing the held-out gates must carry the qualified-evidence caveat.
3. **Historical failures stay historical** — Amendment 003's two guardrail failures and T015's band breach remain FAIL in every record.
4. **No production claim** — release readiness, store deployment and real-device performance are outside this acceptance.
5. **Deferred realism work is mandatory** before any full-realism claim.

## 8. Consequences

- M002 task ledger: T001–T019 complete; T019 closed on human acceptance dated 2026-10-31.
- Milestone status: **M002 — ACCEPTED WITH CONDITIONS**.
- No code, coefficient, clock, threshold, fixture or historical raw evidence changed by this record.
- M003 is **not** started; `M003-BACKLOG.md` is planning input only and assigns nothing to a frozen milestone.
