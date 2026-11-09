# M006-T06G — Stage C Confirmatory Human Basketball Review

- **Date:** 2026-11-09
- **Status:** STAGE C CONFIRMATORY EVALUATION COMPLETED — VERDICT: `INSUFFICIENT`.
- **Repository:** `Faraeael/Ballgorithm`
- **Branch:** `impl/m006-t06g-confirmatory-execution`
- **Governing Baseline:** Pre-execution freeze `5275527e15b69addd0c01ae1ef90e3067674e32b`.
- **Evaluated Cohorts:**
  - Context A: $N = 750$ paired games on default M001 league (`20261028`), seeds `10001–10750`.
  - Context B: $N = 250$ paired games on synthetic Center roster, seeds `11001–11250`.
- **Decision Artifacts:** `t06g-stage-c-final-decision.json` and `t06g-stage-c-final-decision-report.md`.

---

## 1. Executive Summary & Final Confirmatory Verdict

**FINAL FROZEN VERDICT: `INSUFFICIENT`**

Stage C was executed once across 1,000 predetermined paired games (2,000 total simulator executions) without modification, case substitution, or retuning.

### Summary of Observed Findings
1. **Macroeconomic Guardrails: 5/5 PASSED.**
   Under $N = 750$ in Context A, all five strict TOST equivalence guardrails demonstrated conclusive equivalence inside pre-approved margins ($90\%$ Student's $t$ confidence intervals):
   - Points: $+0.46$ pts ($90\%$ CI `[-0.47, +1.39]`, margin $\pm 2.5$).
   - Pace: $-0.19$ poss ($90\%$ CI `[-0.68, +0.30]`, margin $\pm 1.5$).
   - eFG%: $+0.13$ pp ($90\%$ CI `[-0.07 pp, +0.34 pp]`, margin $\pm 1.0$ pp).
   - Turnovers/100: $+0.03$ ($90\%$ CI `[-0.09, +0.14]`, margin $\pm 0.75$).
   - Free Throw Attempts: $-0.45$ FTA ($90\%$ CI `[-0.96, +0.06]`, margin $\pm 1.75$).
   - 100% reducer validity and accounting reconciliation across all 2,000 game ledgers.
2. **Primary Creator Rebalancing: PASSED ($p < 10^{-15}$).**
   Primary creator shot share rose by **$+4.81$ percentage points** (v6 23.01% $\to$ v7 27.82%, $t = 15.008$), decisively exceeding the $+3.0$ pp threshold.
3. **Weak-Shooter Perimeter Suppression: PASSED ($p = 4.57 \times 10^{-12}$).**
   Weak-shooter perimeter attempt share declined by **$-5.67$ percentage points** (v6 36.31% $\to$ v7 30.64%, $t = -6.929$), decisively exceeding the $-3.5$ pp suppression threshold. Non-shooting Center Emil Lindqvist dropped his 3PA share from 33.79% to 23.41% (-10.38 pp, -1,043 threes).
4. **Stretch-Big Perimeter Retention: PASSED ($p = 1.88 \times 10^{-6}$).**
   Genuine registered Center perimeter share increased by **$+1.39$ percentage points** (v6 35.81% $\to$ v7 37.20%, $t = 4.730$), conclusively ruling out the non-inferiority bound of $-\Delta = -1.5$ pp.
5. **Secondary Creator Share: FAILED ($p = 0.1085 > 0.05$).**
   Secondary creator share rose by **$+0.66$ percentage points** (v6 22.56% $\to$ v7 23.22%, $t = 1.236$). Although positive, it fell short of achieving statistical significance against the $+0.50$ pp threshold ($p = 0.1085$), causing Holm step 4 to fail.
6. **Context B Sufficiency Gate: FAILED (INSUFFICIENT).**
   Gate 2 required at least **150 of 250 paired games (60.0%)** to exhibit $\ge 10$ FGA by the same registered Center across PF/C slots in both arms. The observed count was **146 / 250 (58.4%)**, falling 4 games short of the 150 floor.

In accordance with SDD invariants, this result is preserved as **INSUFFICIENT**. No post-hoc threshold relaxation or re-running is permitted.

---

## 2. Answers to Human Basketball Review Questions

### Q1: Did primary creators gain meaningful shot opportunities?
**YES.** Primary creator shot volume expanded substantially and consistently.
- In Context A, primary creator share shifted by **$+4.81$ percentage points** (23.01% $\to$ 27.82%, $t = 15.008$).
- Team 1 primary creator Elias Vasquez (`Cr = 331`): total FGA rose from 11,417 to 13,792 (+2,375 FGA across 750 games; 17.76 $\to$ 21.37 FGA/36). 100% of his attempts occurred while ranked primary (13,792/0/0).

### Q2: Did secondary creators gain enough?
**MARGINAL.** Secondary creator volume increased directionally, but not enough to clear the confirmatory margin.
- Secondary creator share rose by **$+0.66$ percentage points** (22.56% $\to$ 23.22%).
- While directionally positive, the effect size did not achieve statistical significance against the pre-registered $+0.50$ pp threshold ($t = 1.236, p = 0.1085$).
- Team 2 secondary creator Malik Sinclair (`Cr = 276`): took 10,528 FGA in v6 and 10,402 in v7 (16.20 $\to$ 15.85 FGA/36), taking 7,021 secondary attempts. The 1.15 multiplier provided mild elevation over neutral, but did not produce a large net share shift.

### Q3: Did weak three-point shooters reduce perimeter attempts?
**YES.** Weak-shooter perimeter chucking was severely curtailed.
- Weak-shooter 3PA share fell by **$-5.67$ percentage points** (36.31% $\to$ 30.64%, $t = -6.929, p < 10^{-11}$).
- Emil Lindqvist (Center, $3\text{PT} = 24$): took 1,043 fewer three-pointers across 750 games (2,888 $\to$ 1,845), dropping his 3PA share from 33.79% to 23.41% (-10.38 pp).
- Elias Kovacs (Center, $3\text{PT} = 37$): took 444 fewer three-pointers (1,996 $\to$ 1,552), dropping his 3PA share from 31.55% to 27.26% (-4.29 pp).

### Q4: Did genuine stretch centers retain perimeter opportunities?
**YES in behavior, but INSUFFICIENT in paired exposure count.**
- In Context B, genuine Center perimeter attempt share rose by **$+1.39$ percentage points** (35.81% $\to$ 37.20%, $t = 4.730, p < 10^{-5}$).
- Team 1 Center (`player-1-8`, $3\text{PT} = 80$): 3PA share rose from 37.10% to 37.65% (+0.54 pp, +31 threes).
- Team 2 Center (`player-2-5`, $3\text{PT} = 78$): 3PA share rose from 32.70% to 36.05% (+3.35 pp).
- Both Centers preserved their three-point role, demonstrating that the piecewise preference curve does not suppress shooting big men.
- However, because starting centers split time with backup bigs (playing ~17 min at C and ~15 min at PF), only 146 games met the $\ge 10$ FGA dual-arm exposure floor, missing the 150 requirement by 4 games.

### Q5: Did elite scorers remain involved?
**YES.** High-efficiency scorers who did not hold primary creation rank maintained high usage.
- Bastian Delacroix ($3\text{PT} = 79$, $Cr = 310$): took 7,732 FGA in v6 and 7,810 in v7 (+78 FGA; 17.59 $\to$ 17.72 FGA/36).
- Jonas Cortez ($3\text{PT} = 69$, $Cr = 252$): took 8,470 FGA in v6 and 7,510 in v7 (12.93 $\to$ 11.52 FGA/36). As a neutral-ranked scorer, his share diluted proportionally to the primary creator's rise (-1.41 FGA/36), but his scoring opportunities remained substantial.

### Q6: Did team scoring and efficiency remain within approved guardrails?
**YES, WITH HIGHEST PRECISION.**
- All 5 macroeconomic guardrails were well within strict equivalence bounds:
  - Total Points: $+0.46$ pts ($90\%$ CI `[-0.47, +1.39]`, well inside $[-2.5, +2.5]$).
  - eFG%: $+0.13$ pp ($90\%$ CI `[-0.07 pp, +0.34 pp]`, well inside $[-1.0 pp, +1.0 pp]$).
  - Turnovers/100: $+0.03$ ($90\%$ CI `[-0.09, +0.14]`, well inside $[-0.75, +0.75]$).
  - Free Throw Attempts: $-0.45$ FTA ($90\%$ CI `[-0.96, +0.06]`, well inside $[-1.75, +1.75]$).
  - Pace: $-0.19$ possessions ($90\%$ CI `[-0.68, +0.30]`, well inside $[-1.5, +1.5]$).

### Q7: Did the known weak-shooting high-creator limitation remain evident?
**YES.** Kasimir Valdez ($3\text{PT} = 39$, $Cr = 321$):
- As an elite creator ($Cr = 321$), Valdez received primary status whenever on court.
- His total attempt volume expanded from 9,948 to 11,202 (+1,254 FGA across 750 games; 15.34 $\to$ 17.41 FGA/36).
- His three-point attempt share dropped by $-4.08$ percentage points (42.53% $\to$ 38.45%), but because his overall usage expanded, his absolute three-point attempts increased slightly (+76 threes across 750 games).
- This confirms the known v1 design boundary: creator opportunity multipliers are decoupled from shooting skill.

---

## 3. Scope of Claims: What These Results Establish

1. **What is Proven:**
   - In deterministic ratings-based simulation, position-free creator ranking rebalances shot volume toward playmakers without distorting team scoring, pace, turnovers, or free throws.
   - The piecewise preference curve effectively suppresses three-point attempts by non-shooting Centers ($> 1,000$ fewer threes taken by Emil Lindqvist).
   - High-three Centers retain their perimeter volume and are not penalized.
2. **What is NOT Proven:**
   - Universal realism across diverse leagues, custom tactics, or varied rotation schemes cannot be claimed from single-matchup cohorts.
   - Secondary creator volume lift was weak ($+0.66$ pp), failing to reject $H_0: \delta \le +0.50$ pp.
   - Context B did not achieve the pre-registered 150-game exposure threshold (achieving 146).
