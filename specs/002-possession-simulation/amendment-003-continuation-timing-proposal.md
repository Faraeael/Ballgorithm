# Amendment 003 — Context-specific offensive continuation timing (DRAFT)

> **DRAFT — NOT APPROVED — IMPLEMENTATION NOT AUTHORIZED**
>
> This document is a proposal for owner review. It is not a specification, it is
> not approved, and it authorizes no code, test, fixture, version, threshold or
> task-status change. Every duration bound below is an uncalibrated design
> assumption. No candidate behaviour in this document has been measured.

| Item | Value |
|---|---|
| Proposal | Amendment 003 to Feature 002 (design only), **Draft B** |
| Baseline | `develop/m002` @ `b03a1b5e4448be0181271f72748d6c7e2e44767d` (T015 commit `06e080e30bbfb489e5d41cd10fb81550d627f745` + docs commit `b03a1b5`) |
| Repository state | clean tree; `amendment-003-continuation-timing-proposal.md` and seed manifest untracked |
| Author | drafting agent (documentation only) |
| Status | DRAFT — owner decision requested in §9 |
| Supersedes | Draft A of this same file (untracked, never committed) |
| Affected artefacts if later approved | `game_rules.dart`, `probability_model.dart`, `game_simulator.dart`, version constants, canonical golden, T012 fixture tests |
| Not affected | M001 generation, PRNG algorithm, event schema, accounting, bands, historical outputs |

### Revision history

| Draft | Change | Disposition |
|---|---|---|
| A | Changed continuation timing **and** action-profile weights (OREB 4500/4000/1500), which altered inherited turnover hazards and shot-zone modifiers | **Superseded.** Withdrawn in §5.4 |
| B (this) | Changes continuation **timing only**. Baseline `PhaseKind` weights 1500/3000/5500 are preserved in every context, and the same `PhaseKind` is passed to the unchanged action-selection logic | Current proposal |

## 0. Decision summary

The current model draws an offensive phase's duration from one unconditional A1
law (transition 15 % 2–7 s, early 30 % 5–11 s, half-court 55 % 10–22 s) for every
live phase, including phases after an offensive rebound (shot clock 14) or a
retained-possession defensive foul (floor `max(remaining, 14)`). A reset therefore
shortens the *clock* without changing the *plan*. Measured: 92.1 % of the 16,409
shot-clock violations occur with exactly 14 seconds on the clock.

**Revised hypothesis.** Changing the *elapsed-time distributions* for continuation
offence can improve shot-clock behaviour while leaving the baseline
action-profile selection mechanism unchanged. The experiment isolates one
variable: the duration law by context.

**The candidate changes exactly three things:** the upper bound of the OREB
transition bracket, the OREB early and half-court brackets, and the retained-foul
early and half-court brackets. It changes no weight, no action-selection
function, no modifier, no reset value, no clock rule, no event and no accounting
path. Fresh-possession A1 is preserved byte-for-byte.

**Isolation guarantee.** The `PhaseKind` draw stays first, unconditional and
identically distributed at 1500/3000/5500 in every context, and that same
`PhaseKind` is passed to `selectAction`. The per-phase action profile is
therefore *identical by construction*. Aggregate action frequencies are still not
guaranteed: fewer expiries, different durations and different continuation paths
change which actions are reached (§5.2).

## 1. Problem and causal hypothesis

### 1.1 Observation (verified, not a claim)

From the frozen T015 corpus, reproduced read-only (§Appendix A): 280,447 sampled
phases; 15,944 strict overshoots; 465 exact expiries; 16,409 shot-clock
turnovers; 0 overshoots on fresh 24-second phases.

| Reset state | Entries | Entries/game | Violations | Violations per entry | Share |
|---|---|---|---|---|---|
| Fresh possession (24 s) | 229,780 | 205.2 | 0 | 0.00 % | 0.0 % |
| Offensive rebound (14 s) | 29,705 | 26.5 | 10,124 | 34.08 % | 61.7 % |
| Retained foul, floor 14 | 14,411 | 12.9 | 4,987 | 34.61 % | 30.4 % |
| Retained foul, floor 15–22 | 6,951 | 6.2 | 1,298 | 18.67 % | 7.9 % |

15,111 of 16,409 violations (92.1 %) occur on phases that start with exactly
14 seconds. The analytic `P(D > 14)` for the approved law is
`0.55 × 8/13 = 33.85 %`; the observed **eligible** 14-second overshoot rate is
`14,697 / 43,333 = 33.92 %`. The 34.08 % above is violations per OREB **entry**,
which includes 414 exact expiries; the two are not interchangeable.

### 1.2 Causal hypothesis

A reset creates a clock state the duration law does not know about. The offence
re-enters the same set bracket (10–22 s), so on a 14-second clock the half-court
slot alone plans more time than exists with probability `8/13`. The violation is
then mechanical: no legal release was planned before expiry
(`design-decisions.md` A1 clock-expiry table; `game_simulator.dart:505–529`).

Basketball-wise the missing ingredient is **possession context**: after an
offensive rebound the ball is already in the frontcourt and the defence is not
set; after a retained-possession foul the defence is set and play restarts from a
dead ball. Neither state justifies re-running a 24-second possession's timing.

The hypothesis is deliberately narrow: it concerns *elapsed time*, not *what the
offence runs*. That is why Draft A's weight change is withdrawn — it would
confound timing with action-profile frequency.

### 1.3 Four separate questions

| Question | Status |
|---|---|
| **Correctness under the current contract** | The implementation obeys the approved clock-blind A1 contract. No reducer, accounting or precedence defect has been demonstrated. |
| **Basketball-model plausibility** | Weak: the plan ignores the reset. Continuation offence in a real game is organised around remaining time. |
| **Statistical calibration** | Not established. No bound in this proposal is calibrated; the repository holds no target for shot-clock violations. |
| **Owner realism acceptance** | Open. AC10 is READY FOR OWNER REVIEW, not passed. Nothing here changes that. |

### 1.4 Why timing-only is the smallest defensible candidate

- One variable: the duration bracket selected after the `PhaseKind` draw.
- No new event, state, clock rule, precedence branch or accounting path.
- Fresh A1 untouched, so the canonical 24-second possession keeps its semantics.
- Still two integer draws per phase, so the PRNG and its identifier are unchanged.
- Action selection is untouched *by construction*, which makes any observed
  turnover-composition or shot-mix movement attributable to survival and
  phase counts rather than to a changed action law.

**Strongest limitation.** Timing remains clock-blind *within* each context. One
retained-foul bracket set must serve floors from 14 to 22 seconds. The candidate
therefore cannot make violation probability non-zero at every reachable clock,
and it cannot represent the offence speeding up as the clock drains. Clock
awareness (Option A) or an explicit attempt/failure model (Option D) would be
required for that; neither is proposed here. Pairing two trajectories — a
“timing-only” variant and a later clock-aware variant — would be the clean
experimental order if the owner wants both.

### 1.5 Conceptual reference (not empirical validation)

A source review of Basketball GM at pinned revision
`282848cc365a1e3020637b0e41a7425db1911daf`
(`src/worker/core/GameSim.basketball/index.ts`) was checked while drafting:

| Claim | Status |
|---|---|
| Possessions starting in the frontcourt are distinguished from possessions that must advance the ball; the flag is set from `orb` or `nonShootingFoul` (lines 1505–1520) | **Verified** by reading the pinned file |
| Frontcourt continuations skip ball-advancement time (lines 1655–1680) | **Verified** |
| Shot timing is bounded by available time; putbacks use their own short interval; frontcourt possessions carry their own turnover check (lines 1960–2039) | **Verified** |
| The inspected file does not expose an explicit 14-second reset state or a separate shot-clock-violation branch; it uses a `SHOT_CLOCK` constant and per-iteration `possessionLength` | **Verified** within the inspected ranges; no claim is made about the rest of the file |
| The implementation does not justify treating faster OREB continuations as transition offence | **Supported by absence**: the continuation flag changes timing and turnover handling, not the action profile |

Use is conceptual only. Its mechanism differs from ours: it *clamps* shot timing
into `[lowerLimit, upperLimit]` so that a shot generally fits the clock. This
proposal explicitly does **not** copy that approach, because our approved
contract defines a plan that exceeds the clock as a violation rather than
silently fitting it (`design-decisions.md` A1). No constant, function or
structure is imported.

## 2. Exact context semantics

Three contexts: `fresh`, `oreb`, `retainedFoul`. The context selects the duration
bracket set for the next sampled phase. It changes nothing else.

**Rule (single, explicit).** At the start of every sampled phase, the context is
determined by the **immediately preceding qualifying possession-entry event**
from the table below. It persists unchanged across subsequent phases of the same
possession until another qualifying entry event fires. Context is never inferred
from the clock, from elapsed time, or from the last event of *any* kind: a shot,
rebound or free throw alone does not change it.

| Qualifying entry event | Context for following phases | Shot clock | Notes |
|---|---|---|---|
| `PossessionStarted` (period start, after any possession end, overtime) | `fresh` | 24 | Cleared at every possession boundary |
| Offensive rebound of a live missed FG | `oreb` | 14 | Possession continues; no `PossessionStarted` |
| Offensive rebound of a live missed final FT | `oreb` | 14 | Includes the final FT of shooting, bonus and and-one groups |
| Non-bonus non-shooting defensive foul (`freeThrowsAwarded == 0`) | `retainedFoul` | `max(remaining, 14)`, capped 24 | Overrides `oreb` if it follows one |
| Bonus non-shooting defensive foul (2 FTs) | unchanged | unchanged | FT group runs; the possession then ends, or a missed final FT → `oreb` |
| Made FG, made final FT, defensive rebound, live turnover, offensive foul | cleared | — | Next start is `fresh` |
| Period end / overtime start | cleared | 24 | |
| Non-bonus foul landing exactly on the horn | cleared | — | Period ends; **no following phase exists** (denominator caveat in §7.3) |

Reachable continuation paths, all present in the current engine:

| Path | Resulting context |
|---|---|
| OREB → OREB → … (repeated offensive rebounds) | `oreb` each time; each rebound re-enters and the next phase draws afresh |
| OREB → non-bonus foul | `retainedFoul` |
| Retained foul → OREB | `oreb` |
| Retained foul → retained foul | `retainedFoul` (floor recomputed from the remaining clock) |
| Retained foul → bonus foul | `retainedFoul` preserved until the possession ends or an OREB occurs |
| Missed final FT (bonus/shooting/and-one) → OREB | `oreb` |
| Any end event → next start | `fresh` |

Boundary notes:

- A continuation context never survives a possession end or a period boundary.
- An offensive rebound at zero game time does not exist: a zero-clock miss is a
  `DeadBallMiss` with no rebound (`spec.md` §5), so `oreb` is always entered with
  live time.
- The context does not alter reset values, bonus thresholds, possession
  ownership, event order or clock precedence.

## 3. Sampling contract and candidate

### 3.1 One contract: unchanged `PhaseKind` draw, context-specific duration

Per sampled live phase, exactly two draws, in this order:

1. **`kindDraw = rng.nextInt(10000)`** selects `PhaseKind` using the **baseline,
   unchanged, unconditional** cumulative bands: `0–1499` transition, `1500–4499`
   early, `4500–9999` half-court (`game_rules.dart:20`,
   `probability_model.dart:158–189`).
2. **`offsetDraw = rng.nextInt(count(context, kind))`** selects the duration from
   the context-and-kind bracket: `duration = lower + offsetDraw`, inclusive at
   both ends, never clamped.

The selected `PhaseKind` is then passed to the **unchanged**
`selectAction(phase: phase.kind, …)`, and the existing ordering — clock checks,
then category, actor and outcome draws — is untouched.

**Compatibility with the implementation.** The current `drawPhaseDuration(rng)`
reads `rules.phaseWeights` and `rules.phaseDurations`. The contract needs one
input it does not have today: the context. That is an additive rule-object change
(three bracket sets instead of one) plus a context parameter on the draw. It is
compatible with the existing structure: no new event, no new state machine and no
change to `selectAction`. Two follow-on obligations are recorded, not designed
here: `GameRules.validate` must validate all three bracket sets, and
`GameSimulator._requireCompatibleA1` (`game_simulator.dart:99–140`) must compare
all three sets as well as the unchanged weights.

**Why not an independent timing-archetype draw?** Because that variant (Draft A)
couples timing with action-profile frequency by construction. Keeping the
existing draw as draw 1 is what makes the isolation guarantee hold.

### 3.2 Draws per path

| Path | A1 draws | Action draws | Note |
|---|---|---|---|
| Legal phase (`D <= Rg && D <= Rs`) | 2 (kind, offset) | full action sequence | unchanged |
| Strict overshoot (`D > Rs && Rs < Rg`) | 2 | **none** | action never selected |
| Exact expiry (`D == Rs`, no qualifying action) | 2 | full action sequence, then violation | unchanged |
| Game clock first (`D > Rg && Rg <= Rs`) | 2 | none | period ends |
| `D == Rg` with a shot | 2 | full sequence | legal release at 0 |
| `D == Rg` with live turnover / offensive foul | 2 | full sequence, then discarded | period ends |
| Final tick (`Rg == 1`) | 0 | full sequence | no phase record |

The context changes only the **distribution** of draw 2. It does not change which
draws occur on any path.

### 3.3 Candidate distributions

Weights are basis points and are **unchanged in every context**. Brackets are
inclusive integer bounds; each phase still costs exactly two draws.

| Context | `PhaseKind` | Weight | Duration bracket | Count | Mean |
|---|---|---|---|---|---|
| `fresh` (unchanged) | transition | 1500 | 2–7 | 6 | 4.50 |
| | early | 3000 | 5–11 | 7 | 8.00 |
| | half-court | 5500 | 10–22 | 13 | 16.00 |
| | **context mean** | | | | **11.875** |
| `oreb` | transition | 1500 | **2–6** | 5 | 4.00 |
| | early | 3000 | **4–9** | 6 | 6.50 |
| | half-court | 5500 | **7–15** | 9 | 11.00 |
| | **context mean** | | | | **8.600** |
| `retainedFoul` | transition | 1500 | 2–7 | 6 | 4.50 |
| | early | 3000 | **4–10** | 7 | 7.00 |
| | half-court | 5500 | **8–16** | 9 | 12.00 |
| | **context mean** | | | | **9.375** |

Diff against baseline: five brackets change, no weight changes. Mean continuation
duration falls by 3.275 s after an OREB and 2.50 s after a retained foul.

### 3.4 Terminology and what the weights mean

`PhaseKind` labels are retained for compatibility with the existing contract,
the event-free internal API and the frozen tests. They are **action-profile
slots**, not descriptions of play:

- The `transition` slot denotes the transition *modifier set* (`inside +700`,
  `midrange −300`, `three −400`, turnover hazard `+250` bp), not a fast break.
- The `early` slot denotes the early modifier set (neutral zones, `+100` bp hazard).
- The `halfCourt` slot denotes the half-court modifier set (`inside −300`,
  `midrange +100`, `three +200`, `+0` bp hazard).

Using the `transition` slot 15 % of the time in a continuation context is a
statement about *action-profile frequency*, not a claim that 15 % of post-rebound
phases are fast breaks. This is exactly the Draft A error that is now removed:
Draft A raised that share to 45 % and thereby changed the action law in
continuation contexts.

### 3.5 Parameter rationale and evidence status

Every bound below is a **provisional design assumption**. None is calibrated, and
none was chosen to move the turnover rate below 24; the 24 band is unchanged and
is not a design input. The question asked for each bound was "how long does this
kind of attack take when the available clock is this short", and the resulting
violation probability is an output (§4.3).

| Parameter | Intended mechanism | Evidence status | What would justify revision or rejection |
|---|---|---|---|
| `fresh` weights and brackets | Existing approved A1 | Owner-approved, uncalibrated | Not changed here |
| `oreb` transition 2–6 | A putback or immediate kick-out shot; the ball is already in the frontcourt, so no advance is needed | **Provisional assumption** | Time-to-shot after offensive rebounds from public play-by-play; or evidence that post-OREB quick attacks need more than six seconds |
| `oreb` early 4–9 | A secondary action while the defence is still recovering | **Provisional assumption** | Same |
| `oreb` half-court 7–15 | The organised option is entered earlier because only 14 s exist, and one second of tail expresses "the possession used the whole reset and never got a shot" | **Provisional assumption**; the tail is deliberate (§4.5) | Evidence that post-rebound sets essentially always finish, or owner direction to remove the tail |
| `retainedFoul` transition 2–7 | A quick restart after a dead ball against a set defence; unchanged from baseline | **Provisional assumption** (kept unchanged to avoid unnecessary movement) | Evidence that dead-ball restarts are slower or faster |
| `retainedFoul` early 4–10 | Restart action inside the compressed clock; one second shorter at each end than baseline early | **Provisional assumption** | Measured restart durations |
| `retainedFoul` half-court 8–16 | Organised set compressed because the available clock is 14–22 s, not 24 s; two seconds of tail above 14 | **Provisional assumption** | Measured restart durations, or owner direction |
| Preserved weights | Isolation: the action-profile draw is not part of the experiment | Not a new parameter | Owner direction to run a separate action-profile experiment later |

If the owner prefers different bounds, §3.3 is the unit of decision: five integers
and their bracket sizes.

## 4. Clock and action behaviour

### 4.1 Unchanged machinery

Only the bracket selected at draw 2 changes. Everything after the draw is the
current contract:

| Condition (phase start) | Behaviour |
|---|---|
| `Rg == 1` | Final-tick attempt; no A1 draw; shot consumes the last second |
| `D <= Rg && D <= Rs` | Phase completes; action selected; a release at `Rg - D == 0` or `Rs - D == 0` is legal |
| `D > Rs && Rs < Rg` | Shot-clock violation at `Rg - Rs`; the action is never selected |
| `D > Rg && Rg <= Rs` | Period expires; no terminal action, turnover or rebound |
| `D == Rs` with a shot | Legal release at shot-clock zero |
| `D == Rs` with a live turnover, offensive foul, or non-bonus non-shooting foul | No qualifying release or award; shot-clock violation |
| `D == Rg` with a live turnover or offensive foul | Action discarded; period ends (live turnovers require game clock > 0) |

### 4.2 Reachable clocks

Verified in the frozen corpus: **no sampled phase starts with a shot clock below
14 or at 23** (buckets 10–13 and 23 were empty; every reset is ≥ 14). A fresh
phase always starts at 24, because the only ways a possession continues are an
offensive rebound or a retained foul. Clocks below 14 are therefore not tabulated.

### 4.3 Exact probabilities from the proposed duration law (A)

`P(D > S)` is strict overshoot; `P(D == S)` is exact equality. Both are **exact
calculations** from the brackets in §3.3 and carry no action or game-state
assumption.

| S | fresh `P(D>S)` | fresh `P(D==S)` | oreb `P(D>S)` | oreb `P(D==S)` | retainedFoul `P(D>S)` | retainedFoul `P(D==S)` |
|---|---|---|---|---|---|---|
| 24 | 0 | 0 | 0 | 0 | 0 | 0 |
| 22 | 0 | 0.04231 | 0 | 0 | 0 | 0 |
| 18 | 0.16923 | 0.04231 | 0 | 0 | 0 | 0 |
| 17 | 0.21154 | 0.04231 | 0 | 0 | 0 | 0 |
| 16 | 0.25385 | 0.04231 | 0 | 0 | 0 | 0.06111 |
| 15 | 0.29615 | 0.04231 | 0 | 0.06111 | 0.06111 | 0.06111 |
| 14 | 0.33846 | 0.04231 | **0.06111** | **0.06111** | **0.12222** | **0.06111** |

Fresh rows are reference only: a fresh phase only ever starts at 24, where both
probabilities are zero. Every equality in this table comes from the half-court
slot, because only that bracket contains 14, 15 or 16 in the candidate and only
`10–22` contains 14 or 15 in the baseline.

### 4.4 Expiry requires an action, so violation probability is an estimate (B)

Equality is legal when the terminal action is a shot release, a qualifying
shooting foul, or a bonus-awarding foul. It is a violation when the action is a
live turnover, an offensive foul, or a non-bonus non-shooting foul. That
conditional probability is **not** a universal constant: it depends on the
turnover hazards and foul probabilities (which depend on lineup ratings), on the
phase profile, and on the team-foul count (a bonus foul is qualifying). The
frozen corpus gives one aggregate estimate at 14 s:

`414 / 1,833 ≈ 0.226`, where 1,833 is the analytical expected number of
half-court equality draws at 14 s under the baseline law. This is an empirical
estimate, not an exact result.

Applying it to the candidate gives per-phase violation estimates — **B, not A**:

| Context | S = 14 | S = 15 | S = 16 | S = 17–22 |
|---|---|---|---|---|
| `oreb` | ≈ 0.0749 | ≈ 0.0138 | 0 | 0 |
| `retainedFoul` | ≈ 0.1360 | ≈ 0.0749 | ≈ 0.0138 | 0 |

For reference, the baseline law at 14 s gives `0.3385 + 0.226 × 0.0423 ≈ 0.348`,
which reproduces the measured 33.92 % overshoot plus 0.96 % exact expiry. The
0.226 factor is attested only at 14 s in the baseline; the future evaluation must
measure it per context and per clock rather than assume it.

### 4.5 How legitimate violations remain possible

No clamping, no resampling, no forced last-second shot, no artificial failure
probability. Two channels, both already in the approved contract:

1. **Tail overshoot.** `oreb` half-court reaches 15 s against a 14 s reset; the
   `retainedFoul` half-court reaches 16 s against floors of 14 and 15. Those
   plans produce no release and the approved violation applies.
2. **Equality without a qualifying action.** A phase that consumes exactly the
   remaining clock still violates when its terminal action is not qualifying
   (§4.4).

### 4.6 States where violation becomes impossible by construction

| State | Why | Owner-relevant assessment |
|---|---|---|
| Fresh phase at 24 s | max plan 22 s | Accepted today; unchanged |
| `oreb` at 15 s | max plan 15 s, equality only at 0.0611 | Violation requires a non-qualifying action at equality |
| `oreb` at 16 s and above | max plan 15 s | **0 % — construction limit** |
| `retainedFoul` at 16 s | equality only at 0.0611 | ≈ 1.4 % including the expiry estimate |
| `retainedFoul` at 17–22 s | max plan 16 s, no equality possible | **0 % — construction limit** |

The last row covers 5,195 entries (4.6 per game). These zeros are a limitation of
a clock-blind context model, not evidence of improved realism. If the owner
requires non-zero violation probability at every reachable clock, one bracket set
cannot deliver it: the obstacle is structural, and the fix is clock awareness (A)
or an explicit attempt/failure model (D) — a scope change, not a parameter choice.

### 4.7 Period-end behaviour

Unchanged: game-clock-first phases end the period with no terminal action; a
turnover or offensive foul landing exactly on the horn is discarded; a shot or
qualifying foul on the horn resolves before `PeriodEnded`; context is cleared at
the boundary. The 3,741 game-clock-first, 18 simultaneous-expiry and 50
discarded-action records keep their semantics. Shorter phases will change how
often those paths occur; the direction is unmeasured.

## 5. Expected effects and risks

No candidate has been run. Directions are reasoned from the model structure.
Section labels: **A** = exact from the duration law, **B** = estimate from
observed baseline shares, **C** = unmeasured.

### 5.1 What is preserved

| Preserved | Why it matters |
|---|---|
| `PhaseKind` weights 1500/3000/5500 in every context (§3.1) | The per-phase action profile is identical by construction |
| `selectAction`, category draw, actor selection | No action-law change |
| Turnover-security hazard and its `+250/+100/0` phase bonuses | Turnover probability per phase unchanged |
| Shot-zone modifiers `inside +700/−300`, `three −400/+200` | Zone selection per phase unchanged |
| Make, foul, and-one, assist, block, rebound and free-throw probabilities | Unchanged formulas |
| Reset values, bonus thresholds, clock precedence, event schema, accounting | Contract untouched |
| M001 generation, PRNG identifier, historical evidence | Untouched |

### 5.2 What may still change in aggregate

Unchanged selection functions do **not** guarantee unchanged aggregate action
frequencies. Four channels remain:

1. **Survival.** Fewer phases end in a violation of the type removed, so more
   phases reach action selection and a terminal event.
2. **Phase counts and clocks.** Shorter phases change how many phases occur per
   game and at which game clocks; the final-tick path, period-end truncation and
   game-clock-first paths all shift frequency.
3. **Continuations.** Repeated OREBs and retained fouls now consume less clock,
   so more continuations may fit per possession and per game.
4. **Conditional mix.** Because the clock at action time changes, the mix of
   phases that *survive* to an action can differ even though the per-phase law is
   identical.

| Quantity | Direction | Basis |
|---|---|---|
| OREB shot-clock violations | Decrease | A: per-phase at 14 s falls from 0.338 (overshoot alone) to 0.061 overshoot + 0.061 equality |
| Retained-foul violations | Decrease, unevenly; zero at floors 17–22 | A/B |
| Total shot-clock violations | Decrease | B sketch (§5.3) |
| Steal / non-steal / offensive-foul turnovers per phase | **Unchanged per phase**; per game may rise if more actions survive | A/C |
| Shot attempts | Likely rise with more surviving actions | C |
| Shot-zone mix | **Unchanged per phase**; aggregate may shift only through survival and clock state | A/C |
| Offensive rebounds, repeated continuations | Unmeasured; more second-chance attempts plausible | C |
| Pace, possessions, scoring | Likely rise; magnitude unmeasured | C |
| Free throws, bonus timing | Unchanged probabilities; different phase counts and clocks | C |
| Regulation vs overtime | Overtime games may shift; unmeasured | C |

### 5.3 Scenario arithmetic (C — unmeasured, assumptions stated)

Duration deltas from §3.3: `oreb` mean 11.875 → 8.600 (−3.275 s);
`retainedFoul` 11.875 → 9.375 (−2.50 s). Using baseline entry counts
(26.5 and 19.1 per game): `26.5 × 3.275 + 19.1 × 2.50 ≈ 134.5 s` of game clock
released per game, i.e. roughly +4.7 % possessions at the baseline 14.04 s per
possession. A first-order violation sketch with the §4.4 estimates and baseline
entry counts:

`29,705 × 0.0749 = 2,226`; `14,411 × 0.1360 = 1,960`; `911 × 0.0749 = 68`;
`845 × 0.0138 = 12`; floors 17–22 = 0 → **≈ 4,266 violations, ≈ 3.8 per game**.

These are arithmetic on assumptions that are mutually inconsistent: entry counts
and possessions will rise precisely because durations fall, so neither number is
a prediction and neither is used in the recommendation. No scoring figure is
claimed.

### 5.4 Superseded Draft A claims

| Draft A claim | Disposition |
|---|---|
| OREB action-profile weights 4500/4000/1500 | **Withdrawn.** Would change inherited hazards and zone modifiers |
| “This is not a timing-only change… 45 % of post-OREB phases inherit the transition action profile” | **Withdrawn.** No longer true under preserved weights |
| “Zone mix shifts toward the rim (inside +700, three −400)” | **Withdrawn.** Per-phase zone selection is unchanged |
| Per-phase violation 0.0263 (`oreb`) / 0.1530 (`retainedFoul` at 14) | **Superseded** by §4.3/§4.4 (0.0749 / 0.1360 including the equality estimate) |
| “≈ 3,080 violations, ≈ 2.75 per game” | **Superseded** by §5.3 (≈ 4,266 / ≈ 3.8 per game under different assumptions) |
| “≈ –13× violations” | **Withdrawn.** No ratio is claimed |
| “≈ +6 % pace, +11 combined points” | **Withdrawn.** Replaced by the first-order +4.7 % pace arithmetic in §5.3, and no points claim |
| Archetype→`PhaseKind` mapping as a design decision (§3.3 of Draft A) | **Removed.** The mapping is now the identity: the `PhaseKind` drawn by draw 1 is passed through unchanged |

### 5.5 Symptom-suppression risk

The candidate reduces violation probability by construction in two contexts and
to zero at retained-foul floors 17–22. A reader can reasonably ask whether bounds
were chosen to move a number. Mitigations are procedural: bounds are set from
attack-length reasoning, the 24 band is frozen and not a design input, the
evaluation is joint and prespecified, the holdout is not inspected before
freezing, and the zeros are reported as limitations rather than as success.

## 6. Determinism, compatibility, versioning

### 6.1 Draw contract

| Aspect | Statement |
|---|---|
| RNG API calls per phase | 2 in every context: `nextInt(10000)` then `nextInt(count)` |
| Underlying PRNG words | Normally 1 per call. `nextInt(10000)` rejects with probability `7296/2³² ≈ 1.7 × 10⁻⁶`; `nextInt(5/6/7/9)` reject with probability ≤ `4/2³²`. Because `count` differs by context, the rejection probability differs slightly by context |
| Downstream divergence | Different durations change clocks, which changes which branches are taken next; later paths consume different numbers of draws |
| Canonical consequence | **Equal nominal draw counts do not preserve canonical output.** Ledgers change |
| PRNG | `xorshift32-v1` unchanged; integer-only; VM and Chrome unaffected |

### 6.2 Timing/action correlations

- **Preserved:** the `PhaseKind` draw is unconditional and first, so
  `P(kind)` is 1500/3000/5500 in every context and `P(action | kind)` is
  untouched. Equality at 14–16 s still comes only from the half-court slot, as
  in the baseline, so the §4.4 estimate is structurally transferable even though
  it remains empirical.
- **Changed:** `P(duration | kind)` and therefore `P(clock at action | kind)` and
  `P(survival | kind)`. The joint distribution of kind and duration is new.

### 6.3 Proposed versions (documented only; no constant is changed)

| Constant | Now | Proposed | Rationale |
|---|---|---|---|
| `gameActionDurationModelVersion` | 1 | **2** | The A1 duration law changes (`design-decisions.md:243` requires a rules-version bump for a bracket change) |
| `gameRulesVersion` | 1 | **2** | The rules object gains context bracket sets |
| `gameSimulationVersion` | 2 | **3** | Canonical gameplay changes; Amendment 002 §9 precedent |
| `gameFingerprintVersion` | 1 | **2** | **Changed from Draft A's recommendation.** The fingerprint payload embeds `rules.toJson()` (`game_fingerprint.dart:19`); the rules map gains keys, which is a layout change, so v1 must not silently cover it |
| `gameEventSchemaVersion` | 2 | **2** (unchanged) | No event shape, ordering or field change; no incompatibility identified |
| `coreEngineVersion`, `snapshotSchemaVersion`, `prngImplementationId` | — | unchanged | M001 generation, snapshot and PRNG vectors must not move |

Weights are unchanged, but the rules object still changes (three bracket sets), so
the rules and simulation bumps stand. If the owner prefers to keep
`gameFingerprintVersion = 1` and treat the added keys as an additive extension,
that is a policy decision to take explicitly; the draft does not encode a silent
choice.

### 6.4 Compatibility

- **Historical replay.** v1/v2 ledgers remain valid artefacts under their own
  version identifiers; they are replayable and auditable as data.
- **Regeneration.** The shipped simulator will **not** reproduce v1/v2 games after
  the bump. Old games are reproducible only at their historical commit. That
  distinction must be stated wherever old goldens are cited.
- **Canonical golden.** Add a new v3 fixture alongside `t012_canonical_ledger_fixture.dart`
  (v1) and `..._fixture_v2.dart` (v2), with its own pinned digest, event count,
  score and fingerprint. The v2 equality test is retargeted to v3; the v2 file is
  archived, not deleted.
- **Calibration outputs.** `t015-*`, `t014-*` and all M001 evidence stay untouched
  and remain labelled with the version they were produced under.
- **Event schema and accounting.** Unchanged.

## 7. Prespecified future evaluation (only after owner approval)

### 7.1 Design

Two arms on identical inputs: baseline `v2` (current code) and candidate `v3`.
Same league (`LeagueGenerator` seed 20261028, 8 teams, default lineups), same
schedule (28 pairs × 2 orientations × 20 seeds = 1,120 games per arm, 2,240
total). 1,120 keeps every published comparison like-for-like with T015. Same
league and rosters across arms: conclusions apply to these eight rosters and this
seed schedule, not to basketball generally.

### 7.2 Seed manifests and the provenance prerequisite

- **Development arm**: exactly the frozen T015 manifest,
  `seed(m, s) = 1 + ((97·m + 17·s) mod 200)`, m = 0…55, s = 0…19 → 200 distinct
  seeds, all previously explored.
- **Held-out arm**: seeds untouched by any prior experiment. Provenance is
  **incomplete in the repository**: T012–T015 corpora are documented; the recent
  read-only diagnostic corpora are not. Reconstructed union, to be verified:
  seeds `1 + ((97·m + 17·s) mod 200) + base` for `base ∈ {0,100,…,1100}` →
  **seeds 1–1300**; earlier T013/T014 corpora must be added to the manifest.
- **Prerequisite.** Produce one machine-readable seed-provenance manifest (seed
  value, experiment, date) and verify that (a) every held-out raw seed is absent
  from it, (b) the **actual** `GameInput.normalizedSeed` values are checked, not
  range labels, (c) seeds are distinct within each directed matchup and every
  matchup is covered, (d) the generator is committed with the manifest. If the
  manifest cannot be completed, the held-out arm is **BLOCKED**.
- Proposed rule (verified clean): `i = 20·m + s`, `seed(i) = 2001 + ((137·i + 23) mod 600)`,
  giving exactly 600 distinct seeds across 1,120 slots (520 seeds used 2×, 80 used 1×,
  20 distinct seeds per directed matchup; range 2001..2600).
  Replaces superseded Draft B formula `2001 + ((89·m + 23·s) mod 600)` which yielded
  only 189 distinct seeds. See `amendment-003-seed-provenance-manifest.md`.
- No inspection of held-out outcomes before the candidate is frozen. No tuning on
  held-out results. A failed holdout is reported as failed.

### 7.3 Metrics, denominators, analysis

| Metric | Numerator | Denominator | Unit |
|---|---|---|---|
| Shot-clock violations by context | `Turnover(shotClock)` by reset state | game; and per **sampled phase** in that state (trace), never per census entry | /game, % |
| Overshoot vs exact expiry | `shotClockOvershoot`, `shotClockExpiryNoAttempt` | eligible phases (`gameClockBefore > shotClockBefore`) | count, % |
| Turnover composition | steal, nonSteal, offensiveFoul, shotClock | completed possessions | /100 completed |
| Action distribution | category by `PhaseKind` and context | sampled phases reaching action selection | share |
| Zone mix | inside / midrange / three attempts, by context and overall | FGA | % of FGA |
| Pace | `PossessionStarted`; completed; period-end | game | /game |
| Scoring | team points, combined points, points/100 completed | game, team-game | points |
| Shooting | FGA/FGM/3PA/FTA/FTM | team-game, aggregate | count, % |
| Rebounds | OREB, DREB, OREB% = OREB/(OREB + opponent DREB) | live rebound opportunities | % |
| Continuation duration | trace `plannedSeconds` by context and kind | sampled phases in that context | mean, distribution |
| Repeated continuations | phases per possession segment, OREB chains | possession | count |

**Census vs phases.** Reset-event census counts (`t015_metrics.dart:163–173`) are
entry counts, not sampled-phase counts; they differ (a non-bonus foul on the horn
is a census entry with no following phase, and final-tick iterations draw no
phase). Every rate names its denominator.

**Zone and turnover diagnostics stay**, even though their per-phase formulas are
unchanged: changed survival through clock checks can alter observed outcomes, and
that is precisely what the isolation experiment must detect.

**Clustering & Paired Inference.** Observations are not independent: seeds recur across matchups ($4\dots 8\times$ in Dev, $1\dots 2\times$ in Held-Out) and matchups recur across seeds ($20\times$). This is a crossed non-nested structure, not a hierarchical hierarchy. Primary analysis uses paired differences by slot $i \in [0, 1119]$ and two-way crossed-cluster variance estimation (Cameron-Gelbach-Miller) across `seed` and `matchup` dimensions. Nominal binomial intervals overstate precision by roughly a factor of two or more and must not be used for inferential conclusions. Same-seed pairing breaks once paths diverge, so pairing is by input tuple, not by event-stream position.

**Joint review.** Violations by context and clock, strict overshoots versus exact
expiries, turnover composition, action and zone distributions, pace, scoring,
shooting, free throws, rebounds, continuation durations, repeated continuations,
regulation versus overtime, and representative event sequences for owner review.

### 7.4 Gates

| Layer | Content |
|---|---|
| Existing mandatory gates (unchanged) | AC01–AC13 as written; frozen bands; determinism; VM/Chrome parity; M001 regression |
| Proposed experimental guardrails (owner approval required) | 1) no candidate is judged on the total turnover rate alone; 2) pace change reported with a cluster interval and owned explicitly; 3) every zero-violation-by-construction state listed in the report; 4) representative sequences reviewed before any verdict; 5) a decline in violations with a decline in FGA/pace or a rise in offensive-foul share is a rejection trigger; 6) any material movement in action or zone mix must be explained by survival, not by the sampling law |
| Descriptive only | Distributions, percentiles, per-team splits, continuation duration summaries |
| Human realism review | Owner only; this document does not pre-judge it |

**Rejection conditions** (any one rejects the candidate even if the turnover rate
improves): a frozen band leaves its range, or pace/scoring moves outside an
owner-set envelope; shot attempts, zone mix or 3PA/FGA shift materially without an
owned rationale; offensive-foul share rises; OREB% or second-chance behaviour
changes implausibly; a context sits at zero violations by construction and the
owner does not accept that as a limitation; representative sequences show
non-basketball behaviour; determinism, VM/Chrome parity or M001 regression fails.

## 8. Future verification plan (if implementation is later approved)

1. **Context transitions**: fresh→oreb, fresh→retainedFoul, oreb→retainedFoul,
   retainedFoul→oreb, repeated OREB, retained→bonus foul, missed final FT→oreb,
   possession end→fresh, period boundary→fresh.
2. **Bounds**: every context-and-kind bracket hits both endpoints; weights still
   sum to 10000; validation rejects a malformed context table; the injected-model
   compatibility check covers all context tables.
3. **Clock boundaries**: `D < Rs`, `D == Rs`, `D > Rs` at 14, 15, 16 and floors
   17–22; `D == Rg`; simultaneous expiry; final tick; discarded-at-horn.
4. **Replay/accounting**: reducer validation and `EventAccounting` reconciliation
   over the 1,120-game arm; turnover categories unchanged in kind.
5. **VM/Chrome**: identical canonical bytes and digests for the new golden.
6. **Historical compatibility**: v1/v2 goldens archived and readable; M001 PRNG
   vectors, snapshot and generator tests unchanged.
7. **Attribute sensitivity**: rerun the T014 paired-seed experiments, because
   changed continuation frequency can move effect sizes even with unchanged
   action formulas.
8. **Joint calibration and owner review**: rerun the T015 protocol under the new
   version identifiers with corrected phase-versus-census denominators.

## 9. Unresolved items and owner decision

| Item | Status |
|---|---|
| 18-second discrepancy (279/1,330 vs 0.1692) | **Unresolved diagnostic observation.** Nominal binomial p ≈ 1.2e-4 reflects overdispersion under independent trials; phase trials within repeated seeds are clustered. Not a proven engine defect or seed-clustering artifact without per-seed trace analysis. Kept as diagnostic limitation |
| Test-count documentation | Conflicting records: `t015-calibration-report.md:246–247` says 345 Dart / 344 Chrome; `tasks.md:47` says 350. Neither re-run |
| Offensive-foul realism (10.06/game) | Separate open calibration concern; untouched |
| Candidate duration bounds | Uncalibrated provisional assumptions; no external target verified for this league |
| B's clock-awareness limitation | Structural: zero violation probability at retained-foul floors 17–22 |
| Seed provenance for the holdout | Manifest incomplete; verification is a prerequisite (§7.2) |
| Realism of the preserved baseline action profiles | **Unproven and out of scope.** Preserving them isolates the experiment; it is not a claim that they are realistic |

**Owner decision requested.** Approve or reject this *experimental implementation
scope*:

> Authorize, as a separate task, the implementation of Amendment 003 Draft B:
> three context bracket sets — fresh unchanged; `oreb` 2–6 / 4–9 / 7–15;
> `retainedFoul` 2–7 / 4–10 / 8–16 — with the baseline weights 1500/3000/5500 and
> the `PhaseKind`→`selectAction` path unchanged; `gameActionDurationModelVersion`
> 1→2, `gameRulesVersion` 1→2, `gameSimulationVersion` 2→3,
> `gameFingerprintVersion` 1→2 (or an explicitly owned decision to keep 1), no
> event-schema change; a new v3 canonical golden alongside the archived v1/v2
> fixtures; and the §7 evaluation executed only after the seed-provenance
> manifest is verified clean — with the frozen bands, AC10 status and any realism
> verdict untouched.

Approval to draft is not approval of the candidate, of implementation, of any
duration bound, or of AC10.

## Appendix A — Verified evidence and source checks

Verified read-only in this drafting session (reproduced corpus in `E:/bm002-diag`;
no repository writes; frozen artefact hashes match the report):

- 280,447 sampled phases; 15,944 overshoots; 465 exact expiries; 16,409 total.
- 43,333 eligible phases at 14 s with 14,697 overshoots (33.92 %); 1,330 at 18 s
  with 279 (20.98 %).
- Census entries: 229,780 starts, 29,705 OREB, 21,362 retained-foul entries;
  violations 10,124 / 4,987 / 1,298 → 92.1 % at exactly 14 s.
- No sampled phase starts below 14 or at 23; fresh phases only at 24.
- 35 phases whose terminal action landed exactly on the horn while tracing
  `legalFoul`; the census overcount is the non-bonus subset `H ≤ 35`.
  `H + N_ft = 400` with `N_ft` final-tick iterations, so
  `N_ft = 400 − H ∈ [365, 400]`; 365 holds only if none of the 35 was a bonus
  foul. No re-run was performed to split them.
- Census entries and sampled phases are not interchangeable denominators.

Local code paths cited above were re-read at the baseline commit:
`game_rules.dart:9–30` (defaults), `game_rules.dart:176–200` (`toJson`),
`probability_model.dart:158–189` (draw order), `probability_model.dart:127–131`
(phase modifier arrays), `probability_model.dart:492/499/506/586` (modifier use),
`game_simulator.dart:375–541` (clock precedence), `game_simulator.dart:99–140`
(injected-model compatibility), `game_fingerprint.dart:19` (rules in payload),
`t015_metrics.dart:163–173` (census).

External source verified at pinned revision
`282848cc365a1e3020637b0e41a7425db1911daf`, file
`src/worker/core/GameSim.basketball/index.ts`: lines 1505–1520 (frontcourt
continuation flag), 1655–1680 (advance skipped for frontcourt continuations),
1960–2039 (bounded shot timing, putback interval, frontcourt-only turnover
check). Claims about other parts of that file are **not** verified and are not
relied on.

Supplied but not independently verified here: the 350/349 test counts; the
full-corpus band table; AC09 status wording.

## Appendix B — JEV advisory record (advisory only)

This record was produced for **Draft A**, the superseded coupled candidate. It is
retained for provenance and is **not** a judgment on Draft B; no new JEV call was
made for this revision.

| Question | Result | Confidence |
|---|---|---|
| B_context_specific | 66 % | 59 % |
| B adequate for proposal | 80 % | 73 % |
| Largest risks: symptom suppression / secondary outcomes / confidence | 52 % / 37 % / 36 % | — |
| Draft with unresolved 18-second limitation | 92 % | 88 % |
| Next step: targeted diagnostic / draft | 54 % / 43 % | 31 % |

Mixed. The strongest signals — low confidence on the next-step split and the
symptom-suppression risk — are why §5.5 and §7.4 exist. JEV provides advisory
judgment, not empirical validation or authorization.

## Appendix C — Checks performed for this revision

- Arithmetic recomputed from the §3.3 brackets: means, `P(D>S)`, `P(D==S)` at
  14/15/16/17/18/22/24, and the §4.4 estimate — all reproduced independently.
- Weights re-read from `game_rules.dart:20` and unchanged in every context.
- Stale Draft A references removed or explicitly marked (§5.4); no cross-reference
  to the withdrawn mapping remains as a live requirement.
- Internal table column counts and `§` cross-references checked.
- Whitespace checked in the untracked file; `git status` compared before and
  after.
