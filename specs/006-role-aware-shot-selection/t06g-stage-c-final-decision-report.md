# M006 Confirmatory Evaluation Final Decision Report

- **Final Verdict:** `INSUFFICIENT`
- **Exit Code:** `1`
- **Primary Hypotheses All Rejected:** `False`
- **Guardrails All Passed:** `True`
- **Evidence Sufficiency Satisfied:** `False`
- **Evaluated Stretch Endpoint:** `populationB_registeredCenterBigThreePointShare`

---

## 1. Primary Hypotheses (Holm-Bonferroni Step-Down, alpha = 0.05)

| Endpoint | Context | Observed Mean Diff | t-stat (df) | One-Sided p-value | Sorted Rank | Alpha Threshold | Rejected |
|---|---|---:|---:|---:|---:|---:|---|
| `primaryCreatorShare` | Context A | +4.81 pp | 15.008 (749) | 0.0000e+00 | 1 | 0.0125 | `YES` |
| `weakShooterThreePointShare` | Context A | -5.67 pp | -6.929 (749) | 4.5691e-12 | 2 | 0.0167 | `YES` |
| `populationB_registeredCenterBigThreePointShare` | Context B | +1.39 pp | 4.730 (249) | 1.8843e-06 | 3 | 0.0250 | `YES` |
| `secondaryCreatorShare` | Context A | +0.66 pp | 1.236 (749) | 1.0847e-01 | 4 | 0.0500 | `NO` |

---

## 2. Macroeconomic Guardrails (TOST Equivalence, alpha = 0.05 / 90% CI)

| Guardrail | Observed Mean Diff | 90% CI | Equivalence Bounds | Power Result |
|---|---:|---:|---:|---|
| `points` | +0.4600 | `[-0.4733, +1.3933]` | `[-2.5000, +2.5000]` | `PASS` |
| `pace` | -0.1920 | `[-0.6823, +0.2983]` | `[-1.5000, +1.5000]` | `PASS` |
| `efg` | +0.0013 | `[-0.0007, +0.0034]` | `[-0.0100, +0.0100]` | `PASS` |
| `tov100` | +0.0266 | `[-0.0903, +0.1435]` | `[-0.7500, +0.7500]` | `PASS` |
| `fta` | -0.4467 | `[-0.9581, +0.0648]` | `[-1.7500, +1.7500]` | `PASS` |

---

## 3. Evidence Sufficiency Gates

- **Context A Defined Weak-Shooter Games:** 750 / 750 (Pass: `True`)
- **Context A Paired Weak Exposure (FGA >= 20):** 743 / 750 (Pass: `True`)
- **Context B Defined Stretch Games:** None / 250 (Pass: `None`)
- **Context B Paired Center Exposure (FGA >= 10):** None / 250 (Pass: `None`)

---

## 4. Final Verdict Rationale

- Verdict is **INSUFFICIENT**.
- Evaluation halted because one or more cohort evidence-sufficiency thresholds failed.
- No acceptance or rejection claim is made.
