# M006-T06 Stage A — Statistical Interpretation Addendum

- **Date:** 2026-11-09
- **Status:** METHODOLOGY CORRECTION ADDENDUM (Companion to `t06a-development-pilot-report.md`).
- **Scope:** Corrects the formal statistical interpretation of exploratory development pilot evidence. The originally published Stage A report remains untouched.

---

## 1. Context and Objective

The Stage A development pilot evaluated 200 paired simulations on development seeds 2001–2200. This addendum provides the necessary statistical discipline to prevent conflating exploratory pilot observations with confirmatory decisions.

---

## 2. Methodological Corrections (Points A–I)

### A. Exploratory Confidence Intervals Are Not Confirmatory Decisions
The bootstrap percentile confidence intervals reported in Stage A reflect sample variability within a single exploratory cohort of 200 development seeds. Because the test protocol, endpoints, and sample size were not frozen prior to examining these data, these intervals cannot be used to declare confirmatory hypothesis tests "passed" or "accepted."

### B. A Confidence Interval Containing Zero Is Not Proof of Equivalence
In the Stage A report, guardrails such as points per game (95% CI `[-2.04, +2.32]`), eFG% (`[-0.29 pp, +0.64 pp]`), and turnovers per 100 (`[-0.18, +0.40]`) had confidence intervals that spanned zero.
- **Correction:** Failing to reject the null hypothesis of zero difference ($H_0: \delta = 0$) does **not** prove that the two versions are equivalent ($\delta \approx 0$).
- "Absence of evidence of a difference is not evidence of absence." The width of the interval represents unresolved uncertainty, not zero impact.

### C. Confirmatory Guardrails Require Explicit Equivalence Bounds (TOST / Two One-Sided Tests)
In Stage B confirmatory evaluation, guardrails must be tested using formal equivalence testing frameworks:
- Pre-specify an equivalence margin $[-\Delta, +\Delta]$ based on basketball realism constraints.
- Equivalence is proven **only if the entire $(1 - 2\alpha)$ or $(1 - \alpha)$ confidence interval falls strictly within $[-\Delta, +\Delta]$**.
- Simply observing that the point estimate is near zero or that zero lies within the interval fails the standard of confirmatory evidence.

### D. Prohibition on Outcome-Dependent Case Selection or Replacement
All 200 cases in Stage A were predetermined. In Stage B, the evaluation case set (league seed, rosters, starting lineups, rotation plans, rules, and game seeds) must be immutable before running the first game.
- No game may be excluded, substituted, or re-run because of an unexpected or undesirable basketball outcome.
- If a seed encounters an engine crash or illegal state, it represents an engine defect, not an excludable outlier.

### E. Evidence Sufficiency Must Rely on Minimum Attempt Thresholds, Not Favorable Subsampling
The stretch-big metric exhibited severe insufficiency (only 40/200 paired games had $\ge 10$ attempts).
- Thresholds must be fixed before simulation.
- Filtering or post-hoc threshold adjustment (e.g. lowering the attempt floor to artificially inflate the sample of eligible games) introduces severe selection bias and is strictly forbidden.
- When eligible attempt counts fall below pre-registered cohort minimums, the result must be reported as **INSUFFICIENT**.

### F. Separation of the Mean of Within-Game Proportions from Attempt-Weighted Pooled Proportions
Two distinct estimators were reported:
1. **Mean of per-game proportions:**
   $$\bar{r} = \frac{1}{N} \sum_{g=1}^N \frac{Y_g}{M_g}$$
   where $Y_g$ is attempts in category and $M_g$ is total attempts in game $g$. This weights each game equally, regardless of attempt count.
2. **Attempt-weighted pooled proportion:**
   $$\hat{R} = \frac{\sum_{g=1}^N Y_g}{\sum_{g=1}^N M_g}$$
   This weights each attempt equally, meaning games with more attempts contribute more heavily.
- **Correction:** The paired differences $d_g = r_{v7}(g) - r_{v6}(g)$ and their standard deviation apply to the per-game proportion estimator ($\bar{r}$). The pooled proportion $\hat{R}$ has a different sampling distribution. Stage B protocols must declare whether the primary estimand is the mean per-game difference or the pooled cohort ratio.

### G. Exploratory p-Values Must Not Be Presented as Confirmatory
The informal mention of $p < 10^{-4}$ in the Stage A summary was derived post-hoc on development data.
- In Stage B, p-values and decision rules will only be valid if evaluated once on genuinely held-out seeds under pre-registered hypotheses and formal familywise error control.

### H. Sample Size Projections Must Account for Decision Criteria, Multiplicity, and Power
The simple sample size formula $N \approx (z_{\alpha/2} \cdot s_d / E)^2$ used in Stage A estimates the sample required to achieve a half-width precision $E$ for a single confidence interval.
- **Correction:** For a formal hypothesis test with statistical power $(1 - \beta) = 0.90$ or $0.80$, the sample size formula must include $z_\beta$:
  $$N \ge \left(\frac{(z_{\alpha/2} + z_\beta) \cdot s_d}{\delta - E_0}\right)^2$$
- Furthermore, under Holm-Bonferroni correction across four primary endpoints, the most stringent test requires $\alpha_1 = 0.05 / 4 = 0.0125$ ($z_{\alpha_1/2} \approx 2.50$). Stage B power calculations must incorporate these corrections.

### I. Matchup-Specific Variability vs. General Realism
All 200 games in Stage A evaluated a single fixed matchup (`team-1` vs `team-2`) under a single generated league seed (`20261028`).
- **Correction:** These simulations measure **within-matchup stochastic engine variance**.
- They do **not** establish general basketball realism across the space of possible generated leagues, player attribute distributions, coaching rotation strategies, or stylistic matchups.
- Broad claims of game-wide realism cannot be inferred from a single-matchup pilot cohort.

---

## 3. Mandatory Guidelines for Stage B Protocol Drafting

1. Explicitly designate **four primary endpoints** as the confirmatory family with Holm step-down error control ($\alpha = 0.05$).
2. Separate the main generated-league cohort from the synthetic stretch-five cohort into two non-overlapping evaluation contexts.
3. Formulate guardrails as explicit two-one-sided equivalence tests (TOST) with fixed margin thresholds.
4. Base power calculations on $90\%$ power under multiplicity-adjusted significance thresholds.
