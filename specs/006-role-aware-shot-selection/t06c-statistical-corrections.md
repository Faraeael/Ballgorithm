# M006-T06C — Statistical Corrections Review & Methodology Hardening

- **Date:** 2026-11-09
- **Status:** METHODOLOGY CORRECTIONS REVIEW (Foundational for Stage B Candidate).
- **Task:** M006-T06C — Statistical correctness review and protocol finalization.
- **Baseline:** `impl/m006-t06c-protocol-finalization` at `4e0177bea881813d8cf583646558acfbbdcf50ee`.
- **Primary Data Sources:** `specs/006-role-aware-shot-selection/t06a-development-pilot-paired-seeds.csv` ($N = 200$, seeds 2001–2200) and `t06b-synthetic-stretch-five-paired-seeds.csv` ($N = 200$, seeds 3001–3200).

---

## 1. Correction of Holm-Bonferroni Multiplicity Procedure

### Flaw Identified in Stage B Draft
The preliminary Stage B draft (`t06b-stage-b-confirmatory-protocol-draft.md` §2) displayed a static ranking table:
- Rank 1: Primary Creator ($\alpha / 4 = 0.0125$)
- Rank 2: Weak-Shooter 3PA ($\alpha / 3 \approx 0.0167$)
- Rank 3: Stretch-Big 3PA ($\alpha / 2 = 0.0250$)
- Rank 4: Secondary Creator ($\alpha / 1 = 0.0500$)

**Statistical Correction:**
The Holm-Bonferroni step-down procedure **cannot** assign ranks to hypothesis names prior to observing the data. Multiplicity control requires:
1. Conduct the four specified directional hypothesis tests to obtain unadjusted one-sided $p$-values: $p_1, p_2, p_3, p_4$.
2. Sort the observed $p$-values in ascending order:
   $$p_{(1)} \le p_{(2)} \le p_{(3)} \le p_{(4)}$$
   recording the mapping $\pi(k)$ from sorted position $k$ back to endpoint name.
3. Apply step-down testing:
   - **Step 1:** If $p_{(1)} \le \frac{\alpha}{4} = 0.0125$, reject $H_{0,\pi(1)}$ and proceed to Step 2. Otherwise, stop: fail to reject all hypotheses.
   - **Step 2:** If $p_{(2)} \le \frac{\alpha}{3} \approx 0.01667$, reject $H_{0,\pi(2)}$ and proceed to Step 3. Otherwise, stop: fail to reject $H_{0,\pi(2)}, H_{0,\pi(3)}, H_{0,\pi(4)}$.
   - **Step 3:** If $p_{(3)} \le \frac{\alpha}{2} = 0.0250$, reject $H_{0,\pi(3)}$ and proceed to Step 4. Otherwise, stop: fail to reject $H_{0,\pi(3)}, H_{0,\pi(4)}$.
   - **Step 4:** If $p_{(4)} \le \frac{\alpha}{1} = 0.0500$, reject $H_{0,\pi(4)}$. Otherwise, fail to reject $H_{0,\pi(4)}$.
4. Stopping condition: At the first rank $k$ where $p_{(k)} > \frac{\alpha}{5 - k}$, rejection halts immediately. All remaining hypotheses $j \ge k$ retain their nulls, regardless of whether $p_{(j)}$ would have passed an unadjusted test.
5. Equivalence with Adjusted $p$-Values:
   This step-down procedure is mathematically identical to computing adjusted $p$-values:
   $$\tilde{p}_{(k)} = \max_{j \le k} \min\left(1, (5 - j) \cdot p_{(j)}\right)$$
   and rejecting $H_{0,i}$ if and only if $\tilde{p}_i \le \alpha$.

### Selection of Authoritative Primary Test Statistic
To eliminate ambiguity, Stage B specifies **one single authoritative statistical method**:
- **Test Statistic:** Paired Student's $t$-statistic on per-game differences:
  $$t = \frac{\bar{d} - \delta_0}{s_d / \sqrt{N_{\text{defined}}}}$$
  with degrees of freedom $\nu = N_{\text{defined}} - 1$.
- **Exact One-Sided $p$-Values:**
  - For upper-tail tests ($H_1: \delta > \delta_0$): $p = 1 - F_t(t; \nu)$.
  - For lower-tail tests ($H_1: \delta < \delta_0$): $p = F_t(t; \nu)$.
- Non-parametric paired-game bootstrap intervals (10,000 resamples, fixed seed `20261109`) are reported as secondary robustness checks, but the formal Holm decision is governed deterministically by the paired $t$-test.

---

## 2. Separation of Estimands and Eligibility Safeguards

### Selection Safeguard Principle
Frozen decision DD-M006-06 mandates:
> "Cases are never selected, excluded or replaced based on post-simulation outcomes."

Filtering games post-simulation because they failed an arbitrary attempt threshold (e.g. dropping a game where weak shooters had only 18 attempts instead of 20) violates this principle. If the filter is applied per-arm, it can induce treatment-dependent selection bias.

### Definition of Candidate Estimands
Let $Y_{v7}(g), M_{v7}(g)$ be attempts in category and total attempts in game $g$ under v7, and $Y_{v6}(g), M_{v6}(g)$ under v6.

1. **Estimand A: Mean Paired Per-Game Proportion Difference**
   $$r_g = \frac{Y_g}{M_g}, \quad d_g = r_{v7}(g) - r_{v6}(g), \quad \hat{\theta}_{\text{per-game}} = \frac{1}{N_{\text{defined}}} \sum_{g=1}^{N_{\text{defined}}} d_g$$
   - Units: Percentage points per game.
   - Evaluated over all games where the denominator is positive ($M_g > 0$) in both arms.
   - Measures the expected shift in a typical game.
2. **Estimand B: Difference in Pooled Attempt-Weighted Proportions**
   $$\hat{\theta}_{\text{pooled}} = \frac{\sum_{g=1}^N Y_{v7}(g)}{\sum_{g=1}^N M_{v7}(g)} - \frac{\sum_{g=1}^N Y_{v6}(g)}{\sum_{g=1}^N M_{v6}(g)}$$
   - Units: Overall population proportion difference across the entire cohort.
   - Immune to zero-denominator games as long as $\sum M_g > 0$.

### Adopted Primary Estimand
Stage B adopts **Estimand A (Mean Paired Per-Game Proportion Difference)** as the primary confirmatory estimand for all primary endpoints, with the following immutable rules:
- **Zero-Denominator Rule:** If $M_g = 0$ in either arm, the ratio is mathematically undefined ($0/0$). The game is excluded from that specific metric's per-game difference vector, and the exact count of undefined games is reported.
- **No Post-Hoc Threshold Filtering:** Games with $M_g > 0$ are **never excluded** simply because $M_g$ was small.
- **Cohort-Level Insufficiency Threshold:** Sufficiency is evaluated across the entire cohort. If the number of games with defined denominators falls below the pre-registered floor (Context A: $\ge 400 / 500$; Context B: $\ge 160 / 250$), the cohort is declared **INSUFFICIENT**.
- Estimand B is reported alongside Estimand A as complementary population-level evidence.

---

## 3. Reconciliation of Synthetic Feasibility Evidence

In the Stage A generated-league pilot, weak shooters were abundant (199/200 games had $\ge 20$ FGA), but stretch bigs were virtually absent (only 40/200 games had a PF/C with $\ge 10$ FGA, derived entirely from perimeter players subbed into PF).

In the Stage B synthetic feasibility study (seeds 3001–3200), starting Centers were deterministically given $3\text{PT} \ge 70$. The resulting eligibility data require precise qualification:

| Eligibility Metric | Observed Count | Percentage | Feasibility Criterion Context |
|---|---:|---:|---|
| **player-1-8 (Team 1 C, 3PT 80) $\ge 10$ FGA** | 170 / 200 | **85.0%** | Player-level attempt volume |
| **player-2-5 (Team 2 C, 3PT 78) $\ge 10$ FGA** | 176 / 200 | **88.0%** | Player-level attempt volume |
| **Either Center $\ge 10$ FGA (Single Arm)** | 196 / 200 | **98.0%** | Single-arm game eligibility |
| **Paired Dual-Arm Eligible Games ($\ge 10$ FGA in both v6 & v7)** | 138 / 200 | **69.0%** | Paired difference sample size |

### Reconciliation Verdict
1. The synthetic protocol's original pre-registered threshold ("$\ge 80\%$ eligible games") was satisfied at the **individual player level** ($85.0\%$ and $88.0\%$).
2. However, at the **paired dual-arm level**, only **69.0% (138/200)** of games were eligible simultaneously in both arms.
3. Therefore, the Stage B proposal specifying an insufficiency threshold of **$\ge 160 / 250$ (64.0%)** for Context B is **empirically supported** by the observed 69.0% paired rate, but the feasibility claim must explicitly acknowledge that paired eligibility was $69\%$, not $80\%$.

---

## 4. Recomputed Statistical Power & Joint Guardrail Analysis

### Primary Endpoint Statistical Power
Using observed paired difference standard deviations from Stage A ($N=200$) and Stage B ($N=200$):

| Endpoint | $s_d$ | Null Threshold ($\delta_0$) | Expected Effect ($\mu$) | Cohort $N$ | Power ($\alpha = 0.05$) | Power under Holm Step 1 ($\alpha = 0.0125$) |
|---|---:|---:|---:|---:|---:|---:|
| **Primary Creator Share** | 0.03359 | $+3.0$ pp | $+4.30$ pp | 500 | $> 99.99\%$ | **$> 99.99\%$** |
| **Weak-Shooter 3PA Share** | 0.08280 | $-3.5$ pp | $-5.17$ pp | 495 | $99.78\%$ | **$98.81\%$** |
| **Stretch-Big 3PA Share (Non-Inf)** | 0.07032 | $-1.5$ pp | $+2.36$ pp | 172 | $> 99.99\%$ | **$> 99.99\%$** |
| **Secondary Creator Share** | 0.03041 | $+0.5$ pp | $+1.02$ pp | 500 | $98.57\%$ | **$94.52\%$** |

All four primary endpoints have statistical power $> 94\%$ even under the most penalizing Holm-Bonferroni correction ($\alpha = 0.0125$).

### Guardrail Equivalence Power (Two One-Sided Tests, $\alpha = 0.05$)
Evaluated using the empirical covariance matrix of paired differences from Stage A ($N = 200$):

$$\text{Cov}(d) = \begin{bmatrix}
254.16 & 64.12 & 0.435 & -14.63 & 14.49 \\
64.12 & 55.65 & 0.057 & -0.85 & -2.00 \\
0.435 & 0.057 & 0.00114 & -0.010 & -0.028 \\
-14.63 & -0.85 & -0.010 & 4.39 & -3.37 \\
14.49 & -2.00 & -0.028 & -3.37 & 85.57
\end{bmatrix}$$

Under the initial draft margins at $N = 500$ paired games:

| Guardrail | Observed Mean ($\mu$) | $s_d$ | Draft Margin ($[-\Delta, +\Delta]$) | Acceptance Window for $\bar{d}$ | Marginal TOST Power |
|---|---:|---:|---|---|---:|
| **Points** | $+0.120$ | $15.942$ | $[-2.5, +2.5]$ pts | $[-1.327, +1.327]$ | $93.36\%$ |
| **Pace** | $-0.405$ | $7.460$ | $[-1.5, +1.5]$ poss | $[-0.951, +0.951]$ | $94.92\%$ |
| **eFG%** | $+0.00174$ | $0.03381$ | $[-1.0\text{ pp}, +1.0\text{ pp}]$ | $[-0.0075, +0.0075]$ | $99.99\%$ |
| **Turnovers/100** | $+0.112$ | $2.095$ | $[-0.75, +0.75]$ | $[-0.596, +0.596]$ | $100.00\%$ |
| **Free Throw Attempts** | **$-0.705$** | **$9.250$** | **$[-1.75, +1.75]$ FTA** | **$[-1.070, +1.070]$** | **$81.09\%$** |

### Joint Guardrail Failure Risk
Because all five guardrails must be passed simultaneously to confirm macroeconomic stability:
- Simulating 100,000 draws from the multivariate sampling distribution of the means ($\bar{d} \sim \mathcal{N}(\mu, \Sigma / 500)$) reveals:
  $$\mathbb{P}(\text{Pass ALL 5 Guardrails}) = \mathbf{72.18\%}$$
- Claiming that $N = 500$ provides $> 95\%$ power for all guardrails was statistically incorrect. Free Throw Attempts ($81.1\%$) and Points ($93.4\%$) pull the joint pass probability down to ~72%.

### Trade-Offs for Owner Decision
To raise joint guardrail power to $\ge 90\%$, the owner must choose between:

| Option | Cohort Size $N$ | FTA Margin | Points Margin | Pace Margin | Joint Guardrail Power | Rationale |
|---|---|---|---|---|---:|---|
| **Option A (Current Draft)** | $N = 500$ | $\pm 1.75$ | $\pm 2.5$ | $\pm 1.5$ | **$72.2\%$** | High risk of spurious gate failure on FTA |
| **Option B (Sample Expansion)** | $N = 750$ | $\pm 1.75$ | $\pm 2.5$ | $\pm 1.5$ | **$90.9\%$** | Shrinks standard errors without widening margins |
| **Option C (Sample Expansion)** | $N = 1000$ | $\pm 1.75$ | $\pm 2.5$ | $\pm 1.5$ | **$97.0\%$** | Decisive statistical precision across all metrics |
| **Option D (Margin Refinement)** | $N = 500$ | $\pm 2.25$ | $\pm 3.0$ | $\pm 1.75$ | **$96.2\%$** | Tight basketball bounds; maintains $N = 500$ feasibility |

**Recommendation:** Option D ($\pm 2.25$ FTA represents only $6.4\%$ of 35 game attempts, and $\pm 3.0$ pts represents $1.3\%$ of 224 game points) provides $96.2\%$ joint power while preserving the pre-planned 500-game cohort size.

---

## 5. Realism Boundaries: Kasimir Valdez

In both Stage A and Stage B, Point Guard Kasimir Valdez (`3PT = 39`, `Cr = 321`):
- Increased total attempt volume by $+318$ FGA (15.59 $\to$ 17.50 FGA/36).
- Reduced perimeter attempt share by $-4.6$ pp (42.2% $\to$ 37.6%).
- Maintained flat absolute 3PA volume (1,138 $\to$ 1,133).

**Documented Invariant:**
M006 explicitly decoupled creation ability (which drives usage multipliers) from shot-zone preference (which drives perimeter vs interior allocation).
A creator with poor shooting will naturally take more overall shots, distributing them according to his zone preference curve.
This is an intentional design boundary of the approved M006 specification, not an implementation bug. No coupling or tuning may be introduced during confirmatory testing.
