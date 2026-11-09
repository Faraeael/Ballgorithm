# M006-T06G — Evidence Archival Addendum

- **Date:** 2026-11-09
- **Status:** METHODOLOGY & ARCHIVAL ADDENDUM (Companion to Stage C Evidence).
- **Repository:** `Faraeael/Ballgorithm`
- **Branch:** `impl/m006-t06g-final-disposition`
- **Governing Baseline:** Stage C Evidence `c2674a974ec7346bb0266ded80cf168b5c8adb67`.
- **Purpose:** Documenting the raw simulator exports archival status, the Context B Markdown report display artifact, and the primary creator $p$-value numerical underflow.

---

## 1. Archival Status of Raw Simulator Exports

During the single authorized execution of Stage C, exactly 2,000 simulator games (1,000 paired cases) were executed across isolated engine worktrees.

### Verifiable Checksums
The SHA-256 digests of the four raw simulator exports were calculated immediately upon generation and are permanently recorded in `specs/006-role-aware-shot-selection/t06g-stage-c-export-checksums.txt`:

| Artifact | Cohort / Seeds | Simulator Executions | SHA-256 Checksum |
|---|---|---:|---|
| `stage_c_v6_context_a.json` | Context A (10001–10750) | 750 games | `da6c34a686eea1e266b1a13edac0710477a20f622f172c930d4793b870ce7e2b` |
| `stage_c_v7_context_a.json` | Context A (10001–10750) | 750 games | `30f8af93220ed91056d297ccdaebfb63c35737b43605964edcec8676aa6d14d1` |
| `stage_c_v6_context_b.json` | Context B (11001–11250) | 250 games | `ffdaee417100a528223d7ba321869f4852c156095d149b441a09ff45fbed35a2` |
| `stage_c_v7_context_b.json` | Context B (11001–11250) | 250 games | `a62145722cd4c5c173b04c02cb13c40a95522f60a9bac89ed13ad35adac188c2` |

### Permanent In-Tree Evidence
To prevent repository bloat from committing 33 MB of ephemeral JSON lines, the complete per-seed, per-game paired observations are permanently committed in:
- `specs/006-role-aware-shot-selection/t06g-context-a-paired-seeds.csv` (750 paired cases, SHA-256: `3854d3d34bdde4c2b37376837fc1dfefd8d568d9f65d55b9a136daa54ab6c4ac`)
- `specs/006-role-aware-shot-selection/t06g-context-b-paired-seeds.csv` (250 paired cases, SHA-256: `fe51babcb4558c14b14b910abe3405111d1a0487521238e28bb48cab6aba90cd`)
- `specs/006-role-aware-shot-selection/t06g-stage-c-final-decision.json` (SHA-256: `410db1f448237af524858d5fb72f06a78ff73c70f44eaaf48f1192de0e28e849`)

Per the owner's strict directive, **no held-out seeds may be re-executed merely to regenerate local temporary JSON files**.

---

## 2. Context B Markdown Display Artifact Correction

In `t06g-stage-c-final-decision-report.md` §3, the Markdown text rendered:
```markdown
- **Context B Defined Stretch Games:** None / 250 (Pass: `None`)
- **Context B Paired Center Exposure (FGA >= 10):** None / 250 (Pass: `None`)
```

### Root Cause
In `tool/m006_confirmatory_finalizer.py`, the Markdown report string formatter looked up the legacy dictionary keys `stretch_center_defined_count` and `exposure_any_center_count`, whereas `tool/m006_analyze_paired.py` emitted the Corrigendum 1A keys `population_b_defined_count` and `population_b_exposure_same_count`.

### Authoritative Reconciliation
The decision logic itself was completely unaffected and evaluated the correct counts directly. As recorded in `t06g-stage-c-final-decision.json`:
- `population_b_defined_count`: **250 / 250 (100.0%)** (Required: $\ge 200 / 250$, Pass: `true`).
- `population_b_exposure_same_count`: **146 / 250 (58.4%)** (Required: $\ge 150 / 250$, Pass: `false`).
- `context_b_sufficient`: **`false`**.

In accordance with SDD immutability principles, `t06g-stage-c-final-decision-report.md` is preserved verbatim as originally generated, and this addendum provides the explanatory correction.

---

## 3. Primary Creator $p$-Value Numerical Underflow

In `t06g-stage-c-final-decision-report.md` §1, the one-sided $p$-value for Primary Creator Share is displayed as `0.0000e+00`.

### Explanation
The paired Student's $t$-test statistic for Primary Creator Share was $t = 15.008$ on degrees of freedom $df = 749$.
- Under the Student's $t$ cumulative distribution function, the upper-tail probability is:
  $$p = 1 - F_t(15.008; 749) \approx 2.4 \times 10^{-46}$$
- In standard IEEE 754 64-bit floating point arithmetic, $F_t(15.008; 749) = 1.0$, resulting in numerical underflow to $0.0$.
- This indicates extreme statistical significance ($p \ll 0.0125$).
