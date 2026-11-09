# M006-T06B — Stage B Confirmatory Protocol (DRAFT PROPOSAL)

- **Date:** 2026-11-09
- **Status:** DRAFT PROPOSAL FOR OWNER REVIEW (Stage B is NOT frozen; Stage C is NOT authorized).
- **Scope:** Complete statistical protocol specification for future confirmatory evaluation of M006 Role-Aware Shot Selection v1.
- **Governing Freeze:** `d5f9f7d16372cb523f149d3536d972ed5f83e36b` (`verification-plan.md` §5).

---

## 1. Overview & Architectural Separation of Evaluation Contexts

To address the empirical reality that the default M001 league generator produces rosters without nominal stretch-five Centers, Stage B proposes **two clearly separated, non-overlapping evaluation contexts**:

1. **Context A: Main Generated-League Cohort ($N = 500$ paired games)**
   - Evaluates three primary endpoints: Primary Creator Shot Share, Secondary Creator Shot Share, and Weak-Shooter 3PA Share.
   - Evaluates macroeconomic guardrails: Points, Pace, eFG%, Turnovers/100, Free Throws, and Accounting.
2. **Context B: Constructed Stretch-Five Cohort ($N = 250$ paired games)**
   - Evaluates the fourth primary endpoint: Stretch-Big Perimeter Retention.
   - Verifies positional integrity and opportunity preservation while occupying Center.

The two cohorts are executed, evaluated, and reported separately. Their attempt counts and ratios must **never be pooled**.

---

## 2. The Four Primary Endpoints and Multiplicity Control

In accordance with frozen decision DD-M006-06 and `verification-plan.md` §5, exactly **four primary hypothesis tests** form the confirmatory family. Familywise error rate is strictly controlled at $\alpha = 0.05$ using the **Holm-Bonferroni step-down procedure**:

| Rank $i$ | Null Hypothesis ($H_{0,i}$) | Alternative ($H_{1,i}$) | Context | Target Significance Level ($\alpha_i$) |
|---|---|---|---|---|
| 1 | $\delta_{\text{prim}} \le +3.0\text{ pp}$ | $\delta_{\text{prim}} > +3.0\text{ pp}$ | Context A | $\alpha / 4 = 0.0125$ |
| 2 | $\delta_{\text{weak}} \ge -3.5\text{ pp}$ | $\delta_{\text{weak}} < -3.5\text{ pp}$ | Context A | $\alpha / 3 \approx 0.0167$ |
| 3 | $\delta_{\text{stretch}} \le -1.5\text{ pp}$ | $\delta_{\text{stretch}} > -1.5\text{ pp}$ (non-inferiority) | Context B | $\alpha / 2 = 0.0250$ |
| 4 | $\delta_{\text{sec}} \le +0.5\text{ pp}$ | $\delta_{\text{sec}} > +0.5\text{ pp}$ | Context A | $\alpha / 1 = 0.0500$ |

Neutral player shot share is reported descriptively as a complementary conservation metric ($\sum \text{shares} = 100\%$) and is not tested as an independent hypothesis.

---

## 3. Detailed Endpoint Specifications

### Endpoint 1: Primary Creator Shot Share (Context A)
- **Estimand:** Mean paired difference in per-game primary creator attempt share:
  $$d_{\text{prim}}(g) = \frac{\text{primary FGA}_{v7}(g)}{\text{team FGA}_{v7}(g)} - \frac{\text{primary FGA}_{v6}(g)}{\text{team FGA}_{v6}(g)}$$
- **Direction of Desirable Change:** Positive ($\delta_{\text{prim}} > 0$).
- **Minimum Meaningful Effect Threshold:** $\delta_0 = +3.0$ percentage points.
- **Margin Rationale:** The primary creator multiplier is 1.35. A $+3.0$ pp shift represents a meaningful rebalancing of offensive volume toward the designated playmaker without monopolizing the offense.
- **Statistical Method:** One-sided paired $t$-test or paired bootstrap test comparing mean difference against $\delta_0 = +0.030$.
- **Observed Development Variance:** $s_d = 0.0336$.

### Endpoint 2: Secondary Creator Shot Share (Context A)
- **Estimand:** Mean paired difference in per-game secondary creator attempt share:
  $$d_{\text{sec}}(g) = \frac{\text{secondary FGA}_{v7}(g)}{\text{team FGA}_{v7}(g)} - \frac{\text{secondary FGA}_{v6}(g)}{\text{team FGA}_{v6}(g)}$$
- **Direction of Desirable Change:** Positive ($\delta_{\text{sec}} > 0$).
- **Minimum Meaningful Effect Threshold:** $\delta_0 = +0.5$ percentage points.
- **Margin Rationale:** The secondary creator multiplier is 1.15. Volume should increase measurably above neutral without competing with the primary creator.
- **Statistical Method:** One-sided paired test against $\delta_0 = +0.005$.
- **Observed Development Variance:** $s_d = 0.0304$.

### Endpoint 3: Weak-Shooter 3PA Share (Context A)
- **Estimand:** Mean paired difference in perimeter attempt share among players with `threePoint < 40` across eligible games:
  $$d_{\text{weak}}(g) = \frac{\sum_{\text{weak}} \text{3PA}_{v7}(g)}{\sum_{\text{weak}} \text{FGA}_{v7}(g)} - \frac{\sum_{\text{weak}} \text{3PA}_{v6}(g)}{\sum_{\text{weak}} \text{FGA}_{v6}(g)}$$
- **Eligibility Rule:** Game is eligible if combined weak-shooter FGA $\ge 20$ in both simulator arms.
- **Direction of Desirable Change:** Negative ($\delta_{\text{weak}} < 0$).
- **Minimum Meaningful Effect Threshold:** $\delta_0 = -3.5$ percentage points.
- **Margin Rationale:** The steepened preference curve below rating 50 was designed to reduce perimeter chucking by non-shooters by at least 3.5 to 5.0 pp.
- **Statistical Method:** One-sided paired test on eligible games against $\delta_0 = -0.035$.
- **Observed Development Variance:** $s_d = 0.0828$.

### Endpoint 4: Stretch-Big Perimeter Retention (Context B)
- **Estimand:** Mean paired difference in perimeter attempt share among PF/C occupants with `threePoint >= 70` across eligible games in the constructed stretch-five cohort:
  $$d_{\text{stretch}}(g) = \frac{\sum_{\text{stretch}} \text{3PA}_{v7}(g)}{\sum_{\text{stretch}} \text{FGA}_{v7}(g)} - \frac{\sum_{\text{stretch}} \text{3PA}_{v6}(g)}{\sum_{\text{stretch}} \text{FGA}_{v6}(g)}$$
- **Eligibility Rule:** Game is eligible if at least one stretch center records $\ge 10$ FGA in both arms.
- **Direction of Desirable Change:** Non-inferiority ($\delta_{\text{stretch}} \ge -1.5$ percentage points).
- **Margin Rationale:** High-three big men must NOT be suppressed by the piecewise preference curve. Retaining their v6 perimeter share within a tolerance margin of $1.5$ pp establishes that stretch-five capability is preserved.
- **Statistical Method:** One-sided non-inferiority test comparing the lower bound of the $(1 - 2\alpha_3)$ CI against $-\Delta = -0.015$.
- **Observed Development Variance:** $s_d = 0.0703$.

---

## 4. Confirmatory Guardrails (Equivalence Testing)

All guardrails in Context A are evaluated using **Two One-Sided Tests (TOST)** at significance level $\alpha = 0.05$ (equivalent to requiring the 90% confidence interval to fall entirely within the equivalence bounds $[-\Delta_{\text{guard}}, +\Delta_{\text{guard}}]$):

| Guardrail | Estimand | Equivalence Margin ($[-\Delta, +\Delta]$) | Rationale | Observed Development SD ($s_d$) |
|---|---|---|---|---:|
| **Points per game** | $d_{\text{pts}}(g) = \text{PTS}_{v7}(g) - \text{PTS}_{v6}(g)$ | $[-2.5\text{ pts}, +2.5\text{ pts}]$ | Preserves team scoring environment | $15.94$ |
| **Pace (Possessions)** | $d_{\text{poss}}(g) = \text{Poss}_{v7}(g) - \text{Poss}_{v6}(g)$ | $[-1.5\text{ poss}, +1.5\text{ poss}]$ | No artificial clock deceleration | $7.46$ |
| **eFG%** | $d_{\text{efg}}(g) = \text{eFG}_{v7}(g) - \text{eFG}_{v6}(g)$ | $[-1.0\text{ pp}, +1.0\text{ pp}]$ | Overall shooting efficiency unchanged | $0.0338$ |
| **Turnovers per 100** | $d_{\text{tov}}(g) = \text{TOV100}_{v7}(g) - \text{TOV100}_{v6}(g)$ | $[-0.75, +0.75]$ | Ball security mechanics unchanged | $2.10$ |
| **Free Throw Attempts** | $d_{\text{fta}}(g) = \text{FTA}_{v7}(g) - \text{FTA}_{v6}(g)$ | $[-1.75, +1.75]$ | Whistle volume unchanged | $9.25$ |
| **Reducer Validity** | Valid event ledgers | $100.0\%$ pass rate | Zero illegal event sequences | — |
| **Box Score Reconciliation** | Exact accounting identity | $100.0\%$ pass rate | Inviolable simulation invariant | — |

---

## 5. Sample Size and Power Calculations

### Context A (Main Cohort: $N = 500$ Paired Games)
- **Primary Creator Share ($s_d = 0.0336$):**
  At $N = 500$, $\text{SE} = 0.00150$. For testing $H_0: \delta \le 0.030$ against true effect $\delta = 0.043$ at $\alpha_1 = 0.0125$ ($z_{\alpha_1} = 2.24$):
  $$z = \frac{0.043 - 0.030}{0.00150} = 8.67 \implies \text{Power} > 0.9999$$
- **Weak-Shooter 3PA Share ($s_d = 0.0828$):**
  Assuming $99\%$ eligibility ($N_{\text{elig}} \approx 495$), $\text{SE} \approx 0.00372$. For testing $H_0: \delta \ge -0.035$ against true effect $\delta = -0.0517$ at $\alpha_2 = 0.0167$ ($z_{\alpha_2} = 2.13$):
  $$z = \frac{-0.035 - (-0.0517)}{0.00372} = 4.49 \implies \text{Power} > 0.9999$$
- **Scoring Guardrail ($s_d = 15.94$):**
  $\text{SE} = 0.713$ pts. 90% CI half-width is $1.645 \times 0.713 = 1.17$ pts. Falls comfortably inside $\pm 2.5$ pts margin with power $> 0.96$.

### Context B (Constructed Stretch-Five Cohort: $N = 250$ Paired Games)
- **Stretch-Big 3PA Share ($s_d = 0.0703$):**
  With expected eligibility rate $\approx 70\%$ ($N_{\text{elig}} \approx 175$), $\text{SE} \approx 0.00536$.
  For testing non-inferiority against $-\Delta = -0.015$ with true effect $\delta = +0.0236$ at $\alpha_3 = 0.025$ ($z_{\alpha_3} = 1.96$):
  $$z = \frac{0.0236 - (-0.015)}{0.00536} = 7.20 \implies \text{Power} > 0.9999$$

---

## 6. Zero-Denominator Handling & Insufficiency Stop Rules

1. **Undefined Metric Handling:**
   - A game with zero eligible attempts yields an undefined ratio (`null`).
   - If either arm has a null value, the paired difference for that game is undefined.
   - Undefined games are excluded from that metric's paired difference distribution without replacement.
2. **Insufficiency Stop Rule:**
   - Context A is declared **INSUFFICIENT** if weak-shooter eligible games $< 400 / 500$ (80%).
   - Context B is declared **INSUFFICIENT** if stretch-center eligible games $< 160 / 250$ (64%).
   - If either threshold is breached, confirmatory testing stops immediately and an owner review is required. No case substitution, seed re-sampling, or threshold relaxation is permitted.

---

## 7. Predefined Failure Decisions

The evaluation fails (verdict **FAIL**) if any of the following occur:
1. After Holm-Bonferroni step-down correction, any of the four primary hypotheses fails to reject its null.
2. Any guardrail 90% confidence interval extends beyond its equivalence bounds $[-\Delta, +\Delta]$.
3. Any game produces an illegal event sequence or fails ledger-to-box-score accounting reconciliation.
4. An unapproved seed substitution, case exclusion, or gameplay change occurs.
