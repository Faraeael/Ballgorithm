# M006-T06E — Stage B Confirmatory Protocol Corrigendum Proposal

- **Date:** 2026-11-09
- **Status:** PROPOSED CORRIGENDUM FOR OWNER REVIEW (Stage B Freeze Text Preserved; Stage C BLOCKED Pending Approval).
- **Repository:** `Faraeael/Ballgorithm`
- **Branch:** `impl/m006-t06e-execution-integrity`
- **Governing Freeze:** `cacfd7a8583b7c4baa7f3f8d769f701d10809b2d` (`specs/006-role-aware-shot-selection/t06d-stage-b-confirmatory-protocol-frozen.md`).
- **Audit Reference:** `specs/006-role-aware-shot-selection/t06e-execution-integrity-audit.md`.

---

## 1. Problem Statement & Need for Corrigendum

In accordance with SDD governance, frozen specification and protocol documents are never silently modified. The Stage B freeze decision (`M006-STAGE-B-OWNER-DECISION.md`) remains preserved as a historical milestone record.

However, the execution-integrity audit (`t06e-execution-integrity-audit.md`) revealed a mathematical contradiction in Context B:
- **Frozen Protocol Text (§4, Gate 2):**
  > "At least one genuine Center records $\ge 10$ FGA while occupying Slot 4 in both simulator arms on at least $160 / 250$ paired games (64.0%)."
- **Empirical Reality of Tactical Rotations:**
  Under the balanced rotation plan, starting Centers play ~32 minutes per game, but split time between Slot 4 (Center, ~17 min) and Slot 3 (Power Forward, ~15 min) to accommodate backup bigs.
  Consequently, individual Centers in Slot 4 alone reached $\ge 10$ FGA in only **26 of 200 games (13.0%)**.
  Enforcing Gate 2 as strictly "Slot 4 alone" would guarantee an automatic **INSUFFICIENT** gate failure during Stage C, despite Centers averaging over 13 FGA per game across their on-court playing time.

This proposal offers two clean, pre-declared corrigendum options for owner sign-off.

---

## 2. Proposed Corrigendum Options

### Option Corrigendum-1 (Recommended: Player-Level Big Exposure)
Reconcile Gate 2 to measure genuine registered Centers (`player-1-8` and `player-2-5`) across their active on-court big positions (PF or C):

- **Revised Gate 2 Wording:**
  > "Gate 2: At least one genuine Center (`player-1-8` or `player-2-5`) records $\ge 10$ field-goal attempts across their active on-court big positions (PF or C) in both simulator arms on at least $160 / 250$ paired games (64.0%)."
- **Empirical Development Baseline:** Exactly **138 of 200 games (69.0%)** satisfied this criterion in development. At $N = 250$, expected qualifying games is $\approx 172.5$, safely clearing the 160 threshold ($64.0\%$).
- **Primary Estimand Alignment:** Endpoint 3 evaluates the genuine Centers across all their on-court big attempts (Population 2).

### Option Corrigendum-2 (Combined Slot 4 Attempt Floor)
Maintain the focus strictly on Slot 4 (Center), but evaluate the attempt floor across the team's combined Center slot:

- **Revised Gate 2 Wording:**
  > "Gate 2: Combined field-goal attempts across both teams by Centers while occupying Slot 4 is $\ge 10$ FGA in both simulator arms on at least $150 / 250$ paired games (60.0%)."
- **Empirical Development Baseline:** Exactly **127 of 200 games (63.5%)** satisfied this criterion in development.

---

## 3. Scope of Corrigendum: What Remains Unchanged

This corrigendum proposal is strictly limited to Context B Gate 2 phrasing. All other frozen parameters remain 100% invariant:
1. **Four Primary Hypotheses:** Unchanged ($+3.0$ pp, $-3.5$ pp, $-1.5$ pp non-inf, $+0.5$ pp).
2. **Multiplicity Control:** Dynamic Holm step-down on sorted observed $p$-values ($0.0125, 0.01667, 0.025, 0.05$) remains unchanged.
3. **Macroeconomic Guardrails:** Option B strict margins ($[\pm 2.5\text{ pts}, \pm 1.5\text{ poss}, \pm 1.0\%\text{ eFG}, \pm 0.75\text{ TOV}, \pm 1.75\text{ FTA}]$) remain unchanged.
4. **Cohort Manifests:**
   - Context A manifest (`t06d-context-a-confirmatory-manifest.csv`, seeds 10001–10750) is **fully valid and unchanged**.
   - Context B manifest (`t06d-context-b-confirmatory-manifest.csv`, seeds 11001–11250) is **fully valid and unchanged**.
5. **Held-Out Seeds:** Seeds 10001–10750 and 11001–11250 remain **100% unexecuted**.

---

## 4. Execution Readiness Disposition

- **Current Status:** **BLOCKED** from Stage C execution until the owner formally selects and approves an Option from this corrigendum.
- **Path to Unblock:** The owner can unblock Stage C execution by issuing an explicit instruction approving Option Corrigendum-1 (or Corrigendum-2).
