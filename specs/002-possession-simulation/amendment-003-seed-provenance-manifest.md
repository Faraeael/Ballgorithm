# Amendment 003 Seed Provenance Manifest (DRAFT / EXPERIMENTAL)

> **DRAFT — NOT APPROVED — EXPERIMENTAL PREREQUISITE ONLY**
>
> Baseline: `develop/m002` @ `b03a1b5e4448be0181271f72748d6c7e2e44767d`
> Purpose: Pre-registered, reproducible seed assignments, exact cluster
> reconciliations, and frozen quantitative guardrails for the proposed four-cohort
> comparative evaluation of Amendment 003 Draft B.

## 1. Schedule and Matchup Structure

- League Fixture: `LeagueGenerator().generate(GenerationConfig(seed: 20261028))` (M001 snapshot, 8 teams).
- Teams: 8 teams sorted lexicographically by `TeamId.value`: `team-1` through `team-8` (indices $i, j \in [0, 7]$ with $i < j$).
- Unordered Pairs: 28 pairs in lexicographic order:
  $$\text{pairIndex}(i, j) = \sum_{k=0}^{i-1}(7 - k) + (j - i - 1) \in [0, 27]$$
- Directed Matchups: Each pair is played in both orientations (orientation $o \in \{0, 1\}$):
  - $o = 0$: `home = teams[i]`, `away = teams[j]`
  - $o = 1$: `home = teams[j]`, `away = teams[i]`
  - Directed Matchup Index: $m = 2 \cdot \text{pairIndex} + o$, where $m \in [0, 55]$.
- Games per Matchup: 20 seed slots ($s \in [0, 19]$).
- Global Slot Index: $i = 20 \cdot m + s$, where $i \in [0, 1119]$.
- Games per Cohort: $56 \times 20 = 1,120$ games.

## 2. Experimental Arms and Game Accounting

The evaluation is organized into four distinct cohorts across two experimental arms:

| Cohort ID | Model / Rules | Seed Cohort | Game Count | Data Source |
|---|---|---|---|---|
| **Arm 1A** | Baseline v2 (current frozen code) | Development (`dev`) | 1,120 | **Reused** from frozen T015 calibration sample (`t015-game-sample.csv`) |
| **Arm 1B** | Candidate v3 (Amendment 003 Draft B) | Development (`dev`) | 1,120 | **New execution** required |
| **Arm 2A** | Baseline v2 (current frozen code) | Held-Out (`heldout`) | 1,120 | **New execution** required |
| **Arm 2B** | Candidate v3 (Amendment 003 Draft B) | Held-Out (`heldout`) | 1,120 | **New execution** required |

- **Total Planned Evaluations:** $4 \times 1,120 = 4,480$ game outcomes.
- **Historical Games Reused:** Exactly 1,120 games from T015 (Arm 1A).
- **New Game Simulations to Run:** Exactly 3,360 games (Arm 1B, Arm 2A, Arm 2B).
- **Pairing Guarantee:**
  - Arm 1A and Arm 1B share identical inputs: `(homeTeam, awayTeam, seed, rules)` for every slot $i \in [0, 1119]$.
  - Arm 2A and Arm 2B share identical inputs: `(homeTeam, awayTeam, seed, rules)` for every slot $i \in [0, 1119]$.
  - Initial possession conditions and starting PRNG states are perfectly paired between baseline and candidate within each cohort.

## 3. Seed Generation Formulas & Verified Properties

### 3.1 Historical Development Arm (`dev`)
- Formula:
  $$\text{seed}_{\text{dev}}(m, s) = 1 + ((97 \cdot m + 17 \cdot s) \bmod 200)$$
- Exact Enumeration Verification:
  - Range: $1 \dots 200$ inclusive.
  - Distinct Seeds: Exactly 200 unique seeds.
  - Seeds per Matchup: Exactly 20 distinct seeds per directed matchup ($\gcd(17, 200) = 1$).
  - Repetition Distribution: 53 seeds used 6×, 50 used 5×, 45 used 4×, 44 used 7×, 8 used 8× (min reuse 4, max reuse 8).
  - Provenance: Identical to T015 calibration manifest; explored in T013, T014, and T015.

### 3.2 Corrected Held-Out Arm (`heldout`)
- Formula:
  $$i = 20 \cdot m + s \quad (i \in [0, 1119])$$
  $$\text{seed}_{\text{heldout}}(i) = 2001 + ((137 \cdot i + 23) \bmod 600)$$
- Exact Enumeration Verification:
  - Total Slots: 1,120 matchup-seed slots.
  - Range: $2001 \dots 2600$ inclusive.
  - Distinct Seeds: **Exactly 600 distinct seeds**.
  - Seeds per Matchup: **Exactly 20 distinct seeds** per directed matchup ($\gcd(137, 600) = 1 \land \gcd(137 \cdot 20, 600) = 20$).
  - Repetition Distribution: **520 seeds used exactly twice (2×), 80 seeds used exactly once (1×)**.
  - Zero seeds used $\ge 3$ times.

### 3.3 Prior-Exposure Audit & Disjointness
- Verified absence from historical runs:
  - Historical development corpus (T013, T014, T015): $[1, 200]$.
  - Diagnostic corpora and local stress test runs: $[1, 1300]$.
  - Pinned ledger seeds: 1, 42, 99, 20261029.
- Overlap Verification:
  $$\{\text{seed}_{\text{dev}}\} \cap \{\text{seed}_{\text{heldout}}\} = \emptyset \quad (\text{overlap } = 0)$$
  $$\{\text{seed}_{\text{diagnostic}}\} \cap \{\text{seed}_{\text{heldout}}\} = \emptyset \quad (\text{overlap } = 0)$$
- Normalized Seed Invariant: All seeds $\in [2001, 2600]$ are strictly positive 32-bit integers; raw seed equals `GameInput.normalizedSeed`.

## 4. Statistical Clustering and Paired Analysis Strategy

Game outcomes within each cohort are not independent observations:
- **Pairing Unit:** Primary comparison is paired by slot index $i \in [0, 1119]$ (identical home team, away team, orientation, and seed) between Baseline v2 and Candidate v3 within each cohort:
  $$\Delta_i = X_{\text{candidate}}(i) - X_{\text{baseline}}(i)$$
- **Crossed-Clustering Structure:**
  - The design is **not** hierarchically nested (seeds are not nested within matchups, nor matchups within seeds). Seeds recur across matchups ($4\dots 8\times$ in Dev, $1\dots 2\times$ in Held-Out) and matchups recur across seeds ($20\times$).
  - Treating seed clusters as nested within separate matchups falsely assumes seed independence across matchups.
  - The correct variance estimator must account for two-way non-nested cross-clustering by both `seed` ($S$) and `matchup` ($M$).
- **Multiway Cluster-Robust Variance Estimation (Cameron-Gelbach-Miller):**
  - For the paired mean difference $\bar{\Delta}$, the multiway cluster variance estimator is:
    $$\hat{V}_{\text{multi}}(\bar{\Delta}) = \hat{V}_S(\bar{\Delta}) + \hat{V}_M(\bar{\Delta}) - \hat{V}_{S \cap M}(\bar{\Delta})$$
    where:
    - $\hat{V}_S$: standard one-way cluster variance clustered on `seed` ($N_S = 200$ clusters in Dev, 600 in Held-Out).
    - $\hat{V}_M$: standard one-way cluster variance clustered on `matchup` ($N_M = 56$ clusters).
    - $\hat{V}_{S \cap M}$: standard variance clustered on the intersection cell $(S \cap M)$, which equals the independent observation variance since each seed appears at most once per matchup.
  - Small-sample correction adjustments: DOF adjustments $G / (G - 1) \cdot (N - 1) / (N - K)$ applied to each component.
  - Paired 95% confidence intervals: $\bar{\Delta} \pm 1.96 \cdot \sqrt{\hat{V}_{\text{multi}}(\bar{\Delta})}$.
- **Multiplicity Policy:** Pre-registered Holm-Bonferroni correction applied across the primary statistical evaluation family.
- **Sub-bin Diagnostic Reporting:** Post-hoc sub-bin deviations (such as single-clock-second cells) are reported strictly as descriptive diagnostics, never as proven causal defects.
## 5. Frozen Quantitative Guardrails and Rejection Thresholds

The following explicit numerical thresholds are frozen prior to running new simulations. Any violation triggers immediate rejection of the candidate model:

### 5.1 Pace and Possessions
- **Completed Possessions per Team-Game:** Must fall within $[95.0, 108.0]$ (baseline: 100.71).
- **Possession Pace Delta:** Mean paired increase must fall within $+2.5\%$ to $+7.0\%$ ($+2.5 \dots +7.0$ possessions/team-game). An increase $>+8.0\%$ or any net decrease is a **rejection trigger**.

### 5.2 Scoring and Shooting Efficiency
- **Team Median Points:** Must remain within frozen band $[85, 130]$ (baseline: 97.0).
- **Combined Points:** Mean combined points must remain within $[185.0, 225.0]$ (baseline: 199.6). Zero games outside $[90, 340]$.
- **Field Goal Attempts (FGA):** Team median FGA must remain within $[75, 95]$ (frozen band: $[70, 105]$; baseline: 83.0).
- **3-Point Rate ($3\text{PA} / \text{FGA}$):** Aggregate share must remain within $[0.370, 0.460]$ (baseline: 0.4153).
- **Effective Field Goal Percentage (eFG%):** Must remain within $[0.480, 0.540]$ (baseline: 0.5098).

### 5.3 Turnover Composition and Rates
- **Total Turnovers per 100 Completed Possessions:** Must fall within $[15.0, 23.5]$ (frozen band: $[7.0, 24.0]$; baseline: 24.76).
- **Steal Turnover Rate:** Per-phase steal turnover rate must remain within $[4.5\%, 5.5\%]$ (baseline: 4.85%; 12.17/game).
- **Non-Steal Turnover Rate:** Per-phase non-steal turnover rate must remain within $[4.8\%, 5.8\%]$ (baseline: 5.18%; 12.98/game).
- **Offensive Foul Share:** Offensive fouls must constitute $\le 24.0\%$ of total turnovers (baseline: 20.17%; 10.06/game).

### 5.4 Shot-Clock Violations by Context
- **Overall Shot-Clock Violations:** Must fall within $[2.0, 6.0]$ per game (baseline: 14.65/game).
- **OREB 14 s Context Violations:** Per-phase violation rate (overshoot + exact expiry) must fall within $[5.0\%, 10.0\%]$ (baseline: 34.08%).
- **Retained Foul Context Violations (Floor 14 s):** Per-phase violation rate must fall within $[10.0\%, 16.0\%]$ (baseline: 34.61%).

### 5.5 Shooting-Zone and Action Distribution
- **Rim / Inside FGA Share:** Must remain within $\pm 3.0$ percentage points of baseline (baseline inside share: $\approx 42.5\%$).
- **Midrange FGA Share:** Must remain within $\pm 2.5$ percentage points of baseline (baseline midrange share: $\approx 16.0\%$).
- **Action Selection Invariance:** Per-phase action selection formulas are identical by construction; any aggregate distribution shift must be statistically explained by phase survival and clock state ($p > 0.05$ under phase-adjusted goodness-of-fit).

### 5.6 Attribute Sensitivity (T014 Re-run)
- Experiments E1, E2, E3, E5, and E6 must reproduce statistically significant positive effects ($p < 0.01$).
- E4 (`ballHandling`) point estimate must not show significant perverse inversion.

## 6. Execution Protocol and Holdout Integrity

- The held-out seed schedule is frozen by this document.
- Simulation of the held-out arm must be executed in a single batch only after candidate model implementation is verified on the development cohort.
- Results from the held-out arm must be published as observed, without post-hoc threshold adjustment or selective seed filtering.
