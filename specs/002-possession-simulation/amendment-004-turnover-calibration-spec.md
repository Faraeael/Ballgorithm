# Amendment 004 — Offensive Foul Base Probability Calibration (DRAFT / EXPERIMENTAL)

> **DRAFT — NOT APPROVED FOR PRODUCTION — EXPERIMENTAL SPECIFICATION ONLY**
>
> Baseline: `develop/m002` @ `9f8458ab345ea7c075f3b910b60d7ee964f1c5fe` (Amendment 003 v3)  
> Purpose: Pre-registered, single-parameter calibration of the offensive-foul category base rate.

---

## 1. Context and Problem Statement

Amendment 003 successfully resolved the 14-second reset duration overshoot defect, reducing shot-clock turnovers from 14.65 to 4.17 per game in development and from 14.59 to 4.06 in held-out evaluation. However, two pre-registered guardrails failed:
1. **Pace Delta:** $+2.21\%$ (Dev) and $+2.05\%$ (Held-Out) versus the $[+2.5\%, +7.0\%]$ required increase.
2. **Offensive Foul Turnover Share:** $26.02\%$ (Dev) and $25.67\%$ (Held-Out) versus the $\le 24.0\%$ ceiling.

### 1.1 Correct Model and Statistical Normalization
Unit accounting must be maintained strictly:
- **Game Totals vs Team Averages:** Ballgorithm's simulated games produce **two-team combined totals**. Under v3 held-out:
  - Total Turnovers: $41.81$ per game $\implies \mathbf{20.91}$ turnovers per team-game ($20.37$ per 100 completed possessions).
  - Live Steals: $13.11$ per game $\implies \mathbf{6.56}$ per team-game.
  - Live Non-Steals: $13.91$ per game $\implies \mathbf{6.96}$ per team-game.
  - Combined Live Turnovers: $27.02$ per game $\implies \mathbf{13.51}$ per team-game.
  - Shot-Clock Violations: $4.06$ per game $\implies \mathbf{2.03}$ per team-game.
  - Offensive Fouls: $10.73$ per game $\implies \mathbf{5.37}$ per team-game ($5.23$ per 100 completed possessions).
- **Public NBA Benchmark Reference (2022–24 Regular Seasons, stats.nba.com / Basketball-Reference / Cleaning the Glass):**
  - NBA Team Pace: $\approx 98.5 - 100.5$ possessions per 48 min.
  - NBA Team Turnovers: $\approx 13.5 - 14.2$ per team-game ($\text{TOV}\% \approx 12.5\% - 14.0\%$).
  - NBA Team Live Steal Turnovers: $\approx 7.0 - 7.5$ per team-game.
  - NBA Team Non-Steal / Ball-Handling Turnovers: $\approx 5.5 - 6.5$ per team-game.
  - NBA Team Shot-Clock Violations: $\approx 1.5 - 2.5$ per team-game.
  - NBA Team Offensive Fouls (charging + illegal screens): $\mathbf{\approx 1.8 - 2.4}$ per team-game ($\approx 2.0 - 2.4$ per 100 possessions).
- **Diagnosis:**
  - Ballgorithm's live turnover volume ($\approx 13.51$ per team-game) is very close to standard NBA live turnover volume ($\approx 12.5 - 13.5$).
  - The primary distortion is that **offensive fouls ($\approx 5.37$ per team-game) are $2.2\times$ to $2.9\times$ higher than modern NBA norms ($\approx 1.8 - 2.4$)**.
  - In v2, this excess was masked by the massive shot-clock turnover volume ($14.6$/game), keeping offensive-foul share at $20.1\%$. In v3, when shot-clock turnovers normalized to $4.1$/game, the turnover denominator shrank, causing the invariant $\approx 10.7$ offensive fouls to jump to $25.7\%-26.0\%$ of total turnovers.

---

## 2. Experimental Intervention: Single-Parameter Calibration

### 2.1 Formula and Intervention
Current formula (`probability_model.dart:665–672`):
$$P(\text{OF}) = \text{clamp}(420 - 3(\overline{IQ}_{\text{off}} - 50) + 2(\overline{IQ}_{\text{def}} - 50) + 2(\overline{ATH}_{\text{off}} - 50), 100, 1000) \text{ bp}$$

**Amendment 004 Intervention:**
Change the base probability constant from **420 bp** to **170 bp**:
$$P(\text{OF}) = \text{clamp}(170 - 3(\overline{IQ}_{\text{off}} - 50) + 2(\overline{IQ}_{\text{def}} - 50) + 2(\overline{ATH}_{\text{off}} - 50), 100, 1000) \text{ bp}$$

### 2.2 Preservation Guarantees
- **Probability Clamp:** Maintained strictly at $[100, 1000]$ bp as requested. (Known limitation: with a 170 bp base, lineups with very high offensive IQ and low defense IQ will hit the 100 bp floor more frequently; this is accepted as a provisional experimental boundary).
- **Attribute Slopes:** $-3\cdot IQ_{\text{off}}$, $+2\cdot IQ_{\text{def}}$, $+2\cdot ATH_{\text{off}}$ remain unchanged.
- **Category Ordering:** In `selectAction`, the single draw `categoryDraw = rng.nextInt(10000)` continues to evaluate:
  1. $[0, \text{turnover}) \implies$ Live turnover.
  2. $[\text{turnover}, \text{turnover} + P(\text{OF})) \implies$ Offensive foul.
  3. $[\text{turnover} + P(\text{OF}), \text{turnover} + P(\text{OF}) + P(\text{NSF})) \implies$ Defensive non-shooting foul.
  4. Remaining window $\implies$ Field goal attempt.
- **Timing & Precedence:** All Amendment 003 continuation duration brackets (`fresh`, `oreb`, `retainedFoul`), clock precedence rules, and draw order remain 100% untouched.

---

## 3. Pre-Registered Hypotheses and Guardrails

### 3.1 Primary Hypotheses
1. **Offensive Foul Reduction:** Reducing base probability from 420 bp to 170 bp across $\approx 255$ game phases will reduce offensive fouls from $\approx 10.7$ to $\approx 4.3$ per game ($\approx 2.15$ per team-game), directly into the targeted NBA range $[1.8, 2.5]$.
2. **Turnover Denominator & Share:** Total turnovers will drop from $\approx 41.8$ to $\approx 35.4$ per game. Offensive-foul share of total turnovers will drop from $\approx 25.8\%$ to $\approx 12.0\% - 14.5\%$, clearing the $\le 24.0\%$ ceiling.
3. **Turnover Rate per 100 Possessions:** Total turnovers per 100 completed possessions will fall from $\approx 20.3$ to $\approx 17.0 - 17.5$.
4. **Downstream Conversion:** Phases freed from offensive fouls will flow into field goal attempts ($\approx +6.4$ FGA per game, $+3.2$ per team-game).

### 3.2 Pre-Registered Quantitative Pilot Guardrails (280-Game Paired Cohort)

| Metric | Pilot Acceptance Envelope | Historical v3 Baseline (280 Games) | Expected v4 Outcome |
|---|---|---|---|
| **Offensive Fouls / Team-Game** | **$[1.80, 2.60]$** | $\approx 5.37$ | $\approx 2.15$ |
| **Offensive Foul Share of Total TOV** | **$[10.0\%, 16.0\%]$** | $\approx 25.8\%$ | $\approx 12.5\%$ |
| **Total TOV / 100 Completed Poss** | $[15.0, 19.5]$ | $\approx 20.3$ | $\approx 17.2$ |
| **Shot-Clock Violations / Game** | $[3.0, 5.5]$ | $\approx 4.1$ | $\approx 4.1$ (invariant) |
| **Completed Possessions / Team-Game**| $[100.0, 106.0]$ | $\approx 102.7$ | $\approx 103.0$ |
| **Team Median FGA** | $[88.0, 95.0]$ | $\approx 89.0$ | $\approx 92.0$ |
| **3PA / FGA Ratio** | $[0.380, 0.450]$ | $\approx 0.415$ | $\approx 0.415$ |
| **eFG%** | $[0.510, 0.540]$ | $\approx 0.527$ | $\approx 0.527$ |
| **Attribute Sensitivity (T014 E1–E6)** | All E1–E6 maintain expected sign, $p < 0.05$ | All Passed | All Pass |

### 3.3 Rejection and Rollback Triggers
- Any failure of basic determinism, replay validation, or EventAccounting reconciliation across the 560 games.
- Offensive fouls per team-game failing to drop below $3.0$.
- Offensive foul share of turnovers remaining above $18.0\%$.
- Unintended distortion in 3PA rate ($> \pm 2.0\%$ share shift) or eFG% ($> \pm 1.5\%$).

---

## 4. Versioning and Fixture Policy

- `gameSimulationVersion`: $3 \rightarrow 4$
- `gameActionDurationModelVersion`: 2 (unchanged)
- `gameRulesVersion`: 2 (unchanged)
- `gameFingerprintVersion`: 2 (retained; fingerprint payload embeds `gameSimulationVersion` in `versions`, differentiating v3 from v4 inputs)
- `gameEventSchemaVersion`: 2 (unchanged)
- Historical canonical fixtures (`t012_canonical_ledger_fixture.dart` v1, `..._v2.dart` v2, `..._v3.dart` v3) preserved as immutable regression tests.
- Add `t012_canonical_ledger_fixture_v4.dart` pinned to seed 42 under simulation v4.

---

## 5. Pilot Schedule and Evidence Plan (560 Games)

- Cohort Design: First 5 slots ($s \in [0, 4]$) across all 56 directed matchups ($m \in [0, 55]$) from the Development manifest:
  $$\text{seed}(m, s) = 1 + ((97 \cdot m + 17 \cdot s) \bmod 200)$$
- Total inputs: $56 \times 5 = 280$ distinct paired inputs.
- Arms:
  - Arm 1: Baseline v3 (280 games at historical commit `9f8458a`).
  - Arm 2: Experimental v4 (280 games with 170 bp base).
- Persistent Evidence Deliverables committed to `specs/002-possession-simulation/`:
  - `amendment-004-pilot-sample.csv` (all 280 paired game rows with complete box-score metrics).
  - `amendment-004-statistical-summary.json` (exact aggregate statistics, paired deltas, and multiway cluster CIs).
