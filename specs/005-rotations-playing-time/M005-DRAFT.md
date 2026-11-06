# M005 — Rotations and Playing-Time Management

> **SUPERSEDED — HISTORICAL DESIGN INPUT ONLY.** The frozen M005 specification in this directory
> (`spec.md`, `plan.md`, `tasks.md`, `acceptance-matrix.md`, `design-decisions.md`,
> `verification-plan.md`) is authoritative and replaces this draft.
> **Original status: DRAFT — NOT FROZEN — NOT IMPLEMENTATION-AUTHORIZED**
> Authoring date: 2026-11-03. Baseline: `f53201314e9cfdcc8734eb523e41f313f3c644c2`.
> This document proposed scope for owner review. It does not authorize implementation, version
> bumps, fixture changes or calibration.
> **2026-11-06 correction:** the owner approved Option 2 for Decision 5. The allocation step below now
> states the authoritative remainder order; the earlier ambiguous phrase "canonical roster-order
> rounding" is withdrawn. No other design content was intentionally changed.

---

## 1. Scope and explicit exclusions

**In scope (proposed):** Approach C-lite — one user-managed team per matchup, a five-slot starting
lineup, a rotation preset (Balanced, Starter-heavy, Custom), best-effort playing-time targets enforced
by a deterministic tactical-substitution policy at existing legal windows, an opponent driven by a
deterministic default plan, results showing actual participation.

**Excluded:** fatigue/stamina, injuries/ejections, coaching AI, in-game manual substitutions, technical
fouls, contracts, trades, seasons, persistence, player development, NBA realism or calibration,
probability/coefficient changes, timeouts or new dead-ball events. Foul-rate investigation is separate.

## 2. User experience

For the current matchup only (no franchise ownership):

1. Choose the managed team on the matchup setup screen.
2. Pick five starters from that team's roster in the five canonical slots.
3. Pick a rotation preset: **Balanced**, **Starter-heavy**, or **Custom**.
4. See the team playing-time total (`T`) and inline typed validation; invalid plans block confirmation.
5. Start the game. The opponent uses its generated default plan.
6. Results show actual minutes and statistics for everyone who started or entered.

Preset UI is the default; Custom exposes per-player integer steppers with an exact total indicator.
The shipped Flutter editor may present standard-rule minutes, while the core accepts arbitrary
validated integer-second targets for nonstandard rules.
At 360 dp the plan is a compact list, not a 12-row free-form editor on the first screen.

Disclosure: "Targets are best-effort. Foul-outs, ejection-free disqualification rules and the limited
dead-ball windows can change minutes."

## 3. RotationPlan data contract

Core owns the plan; no UI-only state participates in simulation.

```text
RotationPlan {
  TeamRotationPlan home;
  TeamRotationPlan away;
}
TeamRotationPlan {
  Preset preset;                    // balanced | starterHeavy | custom
  Map<PlayerId, int> targetSeconds; // canonical roster order
}
```

- Canonical unit: **integer player-seconds**.
- Single nullable plan on `GameInput`: `RotationPlan? rotationPlan`.
  - `null` = legacy no-rotation behavior for both teams (v5 gameplay).
  - non-null = validated `home` and `away` `TeamRotationPlan` values; both must be present.
- Canonical JSON: team order **home then away**; each `TeamRotationPlan` serializes `preset` and
  `targets` as a list of `{playerId, seconds}` entries in **canonical roster order**. No map with
  insertion-dependent order is serialized. Semantically equal plans therefore fingerprint identically.
- Starting lineups travel separately from the plan: `GameRequest` carries optional immutable
  `homeLineup` / `awayLineup` (`CourtLineup?`). The worker uses the supplied lineup when present and
  `CourtLineup.defaultFor(team)` otherwise. `GameInput.create` re-canonicalizes and validates roster
  ownership, slot order, uniqueness and size. Lineups are immutable across the isolate boundary.
- Rematch copies both lineups, both team plans and the matchup, and changes only the seed.
- `L(p) = rules.periodLength(p)`; regulation team total `T = 5 × Σ_{p=1..periods} L(p)`
  (`= 5 × periods × periodSeconds`, periods currently fixed at 4).
- Individual regulation cap `C = Σ_{p=1..periods} L(p)` (`= periods × periodSeconds`).
- Validation (typed errors): every roster player exactly once; `0 ≤ target ≤ C`; sum exactly `T`;
  all five selected starters have `target > 0`; plan team ids match the input teams; `preset` and
  explicit targets must agree (presets are expanded before validation).
- `null` plan = explicit legacy no-rotation mode.
- Starting five remain `GameInput.homeLineup/awayLineup`; plans only add targets.
- Canonical JSON includes the plan only when present; M004 inputs remain representable.

## 4. Preset allocation algorithms

Weighted integer allocation. Presets are expanded into explicit targets before validation; no
randomness; no optimizer.

**Participant selection.** `r = min(n, preferred) − 5` reserves, chosen in canonical roster order.
- Balanced: `preferred = 9`, starter weight `wS = 3`, reserve weight `wR = 2`.
- Starter-heavy: `preferred = 8`, `wS = 5`, `wR = 2`.
- Custom: user-supplied targets, no expansion.

**Small-roster branch.** If `n == 5`, every player receives `C` (sum `5C = T`). `n < 5` is rejected by
input validation. `r == 0` only occurs at `n == 5`; no division by `r` is performed.

**Allocation.**
1. `W = 5·wS + r·wR`.
2. `target_i = floor(T · w_i / W)` for each participant.
3. `rem = T − Σ target_i`. Since `rem < participants`, grant `+1` second to the first `rem`
   participants in a fixed order: **remainder seconds are assigned to starters in canonical
   court-slot order first, then selected reserves in canonical roster order.** This is the
   owner-approved deterministic priority rule, not a fractional-remainder tie-break.
4. Non-participants receive `0`.
5. Assert every target in `[0, C]`, all five starters > 0, participants = `5 + r`, and `Σ = T`;
   violations are typed allocation errors. No clamping loop is used; floors plus a remainder smaller
   than the participant count cannot exceed `C` (the `n = 5` branch is exact).

**Standard-rules vectors** (`periods = 4`, `periodSeconds = 720`, `C = 2880`, `T = 14400`). Values in
seconds; `S1…S5` are starters in slot order, `R1…Rk` selected reserves in roster order.

| n | Balanced | Starter-heavy |
|---|---|---|
| 5 | `[2880,2880,2880,2880,2880]` | `[2880,2880,2880,2880,2880]` |
| 6 | `[2542,2541,2541,2541,2541, 1694]` | `[2667,2667,2667,2667,2666, 1066]` |
| 7 | `[2274,2274,2274,2274,2274, 1515,1515]` | `[2483,2483,2483,2483,2482, 993,993]` |
| 8 | `[2058,2058,2057,2057,2057, 1371,1371,1371]` | `[2323,2323,2323,2322,2322, 929,929,929]` |
| 9 | `[1879,1879,1878,1878,1878, 1252,1252,1252,1252]` | `[2323,2323,2323,2322,2322, 929,929,929, 0]` |
| 12 | `[1879,1879,1878,1878,1878, 1252,1252,1252,1252, 0,0,0]` | `[2323,2323,2323,2322,2322, 929,929,929, 0,0,0,0]` |

Six- and seven-player presets are meaningfully distinct: Balanced six gives starters ≈42:21 and the
lone reserve 28:14; Starter-heavy six gives ≈44:27 and 17:46. Seven-player Balanced gives starters
37:54 and reserves 25:15; Starter-heavy gives 41:23 and 16:33.

**Short-period example** (`periodSeconds = 100`, `periods = 4`, `C = 400`, `T = 2000`, `n = 6`):
- Balanced: `[353,353,353,353,353, 235]`, sum `2000`.
- Starter-heavy: `[371,371,370,370,370, 148]`, sum `2000`.
These are exact integer targets even though the total is not minute-aligned.

Presets are convenience heuristics, not NBA-calibrated plans.

## 5. Deterministic rotation policy

Evaluated after every event that opens W1/W2/W4/W5, per team, before the next live event. Integer
seconds only; **no PRNG draws**.

State: `actualSeconds[playerId]` accumulated by the simulator from emitted events; cross-checked in
tests against `EventAccounting`.

During regulation:

```
horizonGameSeconds = Σ regulation period lengths only
elapsedGameSeconds = game seconds elapsed so far
expected(p) = targetSeconds[p] × elapsedGameSeconds ÷ horizonGameSeconds
deficit(p)  = expected(p) − actualSeconds[p]
```

Regulation targets and this formula apply only until the regulation horn. Overtime switches to the
separate per-period allocation in §7; no regulation target or completed minute is recomputed.

Thresholds are phase-specific and scale with the active period length using integer division and a
strictly positive floor:
- regulation: `h = max(1, periodSeconds ~/ 8)`, `cooldown = max(1, periodSeconds ~/ 6)` (90 s / 120 s
  at 720);
- overtime: `h_ot = max(1, overtimeSeconds ~/ 8)`, `cooldown_ot = max(1, overtimeSeconds ~/ 6)`
  (37 s / 50 s at 300).

Using the regulation values inside a 300-second OT would delay a meaningful swap until roughly 260 s;
the OT-scaled values are required. Very short periods still floor at `1`, so at most one swap per team
per window applies. These are **simulation policy constants** versioned by `gameSimulationVersion`;
they are not rule fields and not part of the input fingerprint.

Decision, per team:
1. If a mandatory foul-out replacement is pending/due, do it first; do not emit a tactical swap for
   that team in this window.
2. If the team swapped tactically within `cooldown` game-seconds, or the proposed pair is the exact
   reverse of the previous window's swap, skip.
3. Eligible bench = roster players not active, not disqualified, `target > 0`.
4. Choose the swap only if some active player has `deficit ≤ −h` and some eligible bench player has
   `deficit ≥ +h`.
5. Outgoing: minimum `deficit` (most over target); tie-break lower canonical roster index, then id.
6. Incoming: maximum `deficit`; tie-break same primary position as the vacated slot, then lower
   canonical roster index, then id.
7. Emit **at most one** tactical `Substitution(reason: tactical)` per team per window, at the same
   clock and shot clock. The reducer’s per-window single-appearance rule is never approached.

Disqualified players are never outgoing candidates for tactical swaps and never incoming candidates.

## 6. Legal-window integration map

Each tactical hook fires only after the entire mandatory sequence for that event has completed, and
only if a tactical swap is still legal for the team under the reducer’s window, clock and shot-clock
rules. Never emit a tactical substitution before a mandatory foul-out replacement.

| Window | Actual simulator order | Tactical hook placement |
|---|---|---|
| W1 | `PersonalFoul` (non-shooting, non-bonus, 0 FTs) → record foul → shot-clock reset/`retainedFoul` context → `_emitFoulOutReplacement` | After the replacement call returns; same game clock and reset shot clock; before the next live action |
| W2 | final made `FreeThrowAttempt` → `_endPossession(madeFinalFreeThrow)` (possession state cleared) | Immediately after `_endPossession`, before the next `PossessionStarted`, only when clock > 0 |
| W4 | `PersonalFoul` (offensive) → `Turnover(offensiveFoul)` → `_endPossession(turnover)` → `_emitFoulOutReplacement` for the offending team | After the replacement call; possession already closed; only when clock > 0 |
| W5 | `PeriodStarted` → mandatory replacements for both teams → pending set cleared → first possession | After the replacement loop and before the first possession; `shotClock` is null and clock is the period length |
| W0 | foul → `_emitFoulOutReplacement` → free throws | **No tactical hook**; mandatory-only |

No tactical hook is attached to made-field-goal, defensive-rebound or period-end possession ends
because those do not open a reducer window. No timeouts or synthetic stoppages are added.

## 7. Overtime handling

Regulation targets, regulation minutes and regulation expectations are immutable. Overtime uses a
**fresh participation allocation per overtime period**, derived from the original plan, the currently
eligible roster, the actual `overtimeSeconds`, and the current active lineup.

**Per-period allocation.** For an overtime period of length `L = rules.overtimeSeconds` (`L > 0` by
rules validation), let `O = 5 × L` team player-seconds. Eligible set `E` = players not disqualified who
are either currently active or have a positive regulation target. Order `E` as current active slots
first, then eligible bench in canonical roster order.

1. `base_i = floor(regulationTarget[i] × L ÷ C)` for each `i` in `E` (`C` = regulation player cap).
   A player with a full regulation target therefore receives exactly `L`.
2. Clamp `base_i` to `L`.
3. `leftover = O − Σ base_i`. Grant `+1` second round-robin over `E` in the order above, skipping
   players already at `L`, until `leftover` is zero or every eligible player is capped. If `E` has
   fewer than five players (depleted continuation), any unallocated seconds are forced onto
   disqualified continuers; no error and no tactical swap is possible.
4. If every regulation target in `E` is zero (possible only after unusual substitution chains),
   fall back to an equal split of `O` over `E`, capped at `L`, with the same round-robin remainder.
5. This allocation is fixed for that overtime period. It is recomputed identically at the start of
   each later overtime period from the original plan and the then-eligible roster; no OT actuals are
   carried across periods.

**Policy inside overtime.** `horizon = L`, `elapsed` = seconds elapsed in that OT period,
`expected_i = otTarget_i × elapsed ÷ L`, `actual_i` = seconds played in that OT period only. The same
deficit rule, one-swap-per-window, tie-breaks and OT-scaled thresholds (`h_ot`, `cooldown_ot`) apply. Regulation-phase
accumulated seconds never enter these deficits, so an OT period cannot inherit a negative
total-deficit state.

**Foul-outs in overtime.** Mandatory replacement always runs first at the window that follows the
sixth foul; no tactical swap is emitted for that team in that window. The disqualified player is
removed from `E` for later windows, but the current period’s `otTarget` vector is not retroactively
rewritten. If an eligible bench player remains, the mandatory replacement enters and later tactical
swaps continue against the existing `otTarget`. If no eligible bench remains, depleted continuation
applies: no tactical swaps, disqualified players stay on court, and conservation still comes from the
ledger. The next overtime period recomputes allocations without the disqualified player.

**Worked example** (`overtimeSeconds = 300`, `L = 300`, `C = 2880`, `O = 1500`; Balanced nine-player
plan `[1879,1879,1878,1878,1878,1252,1252,1252,1252]`):

- **Regulation tie → first OT:** floors are `floor(1879×300/2880)=195`, `floor(1878×300/2880)=195`,
  `floor(1252×300/2880)=130`; sum `5×195 + 4×130 = 1495`; `leftover = 5`; active-first round-robin
  gives one second to each starter → `otTarget = [196,196,196,196,196,130,130,130,130]`, sum `1500`.
  The active five begin OT; no swap occurs at elapsed 0; later windows may swap if an active player is
  `h` over and a reserve `h` under.
- **Second OT:** recomputed from the same regulation plan and the roster then eligible. If one reserve
  fouled out in OT1, `E` has eight players: floors `5×195 + 3×130 = 1365`, `leftover = 135`.
  Round-robin covers **all eight eligible players**, not only the starters: `135 = 16×8 + 7`, so 16
  full passes give `+16` to everyone, then the first seven in order (five starters, then the first two
  reserves) receive one more:
  `otTarget = [212,212,212,212,212,147,147,146]`, sum `1500`.
- **Foul-out during OT:** the sixth foul at a live window triggers mandatory replacement before any
  tactical decision; that team skips a tactical swap in that window. If a reserve remains, it enters;
  if not, depleted continuation ends tactical rotations. Regulation minutes and prior OT periods are
  untouched; the next OT period recomputes without the disqualified player.

No new windows, no extra PRNG draws, and no OT allocation changes regulation targets.

## 8. Compatibility and version proposal

Proposed, not applied:

| Identifier | Current | Proposed | Reason |
|---|---|---|---|
| `gameSimulationVersion` | 5 | **6** | New behavior: tactical substitutions |
| `gameFingerprintVersion` | 3 | **4** | Canonical input gains the rotation plan |
| `gameRulesVersion` | 3 | 3 | No rule/clock change; plan is input, policy is engine behavior |
| `gameEventSchemaVersion` | 3 | 3 | Existing `Substitution` only |
| `gameActionDurationModelVersion` | 2 | 2 | Unchanged |
| PRNG | `xorshift32-v1` | unchanged | Rotation consumes no draws |

- `GameInput` gains `RotationPlan? rotationPlan`; `GameRequest` gains the same plan plus optional
  immutable `homeLineup` / `awayLineup`. The worker supplies defaults only when a lineup is absent and
  passes the immutable object graph through the isolate boundary. Rematch preserves lineups and plans.
- **No-plan mode:** `null` plans produce historical v5 gameplay. Under v6 the ledger header/version
  differs; the canonical event array must equal the pinned v5 array for the same input and seed.
  Header/version differences are explicit and must not be treated as behavioral drift.
- New v6 canonical fixture(s) are added; every M004 v5 fixture is preserved, never rebaselined.
- Rematch preserves the configured plan and advances the seed per the existing M003
  `deriveGameSeed` cycle; repeating the same complete rematch request remains deterministic.

## 9. Acceptance criteria

**Contract/unit evidence**
1. Plan validation: exact-sum, cap, roster-completeness, starter-positive and typed-error cases.
2. Preset expansion sums exactly to `T` for rosters 5…12 and for non-standard `periodSeconds`.
3. The draft vectors above are asserted, including: five-player rosters assign `C` to all five;
   six- and seven-player Balanced and Starter-heavy differ; no reserve exceeds any starter target in
   the standard vectors; short-period rules yield exact integer targets.
4. Policy unit tests: deficit selection, tie-breaks, cooldown, one-swap-per-window, zero draws, and
   mandatory foul-out precedence (a rotation is never emitted before/deferred past a required
   replacement).
5. Overtime determinism: identical plan and seed reproduce the same OT allocations, substitutions and
   ledger; each OT period recomputes its own `otTarget`; regulation targets/minutes are never rewritten;
   a tie, one or multiple OTs, and an OT foul-out all follow the §7 rules.
   OT thresholds use `overtimeSeconds`, not `periodSeconds`.
   Tactical substitutions never precede a mandatory foul-out replacement.
6. Simulator integration: every tactical substitution is reducer-valid and occurs only in W1/W2/W4/W5.
7. Foul-out precedence and depleted continuation unchanged.
8. No-plan mode reproduces the v5 canonical event array (header excluded) for the pinned game.
9. Two different plans produce different player minutes; team seconds equal `5 × Σ L(p)`.

**Startup and transport**
10. A user-selected slot-ordered starting five survives setup → `GameRequest` → worker → `GameInput`
    and is the actual on-court five; the opponent uses `defaultFor` unless explicitly configured.
11. Rematch preserves the managed lineup, both team plans and the matchup, advancing only the seed.
12. Semantically equal plans serialize to one canonical form and produce one fingerprint, independent
    of map insertion order.

**Player-visible walkthrough**
13. On a 360 dp device: choose a team, starting five and preset; simulate; see legal tactical
   substitutions, real bench minutes and statistics; repeat the same request and get the same ledger;
   rematch keeps the plan and changes only the seed; a different preset shows a visibly different
   participation pattern.

Unit/contract evidence is not a substitute for the walkthrough, and the walkthrough is not a
substitute for the determinism and legality tests.

## 10. Minimal task sequence

1. T01 — `RotationPlan` contract, validation, preset expansion, canonical serialization and
   fingerprint/version decision evidence.
2. T02 — deterministic policy component with unit tests and zero-draw assertions.
3. T03 — simulator hooks (W5 first, then W1/W2/W4), foul-out precedence and legality tests.
4. T04 — v6 canonical fixtures, replay/worker parity, no-plan v5 event-array equivalence.
5. T05 — Flutter plan editor, starting-five transport, request/worker plumbing and validation feedback.
6. T06 — physical-device walkthrough and owner acceptance evidence.

## 11. Open owner decisions and technical risks

**Decisions**
1. Approve C-lite scope and the proposed version bumps (simulation 6, fingerprint 4).
2. Approve preset definitions (Balanced 9 participants / Starter-heavy 8 / Custom), the weights
   (3/2 and 5/2) and the starter-first remainder rule.
3. Approve policy constants `h = periodSeconds/8`, `cooldown = periodSeconds/6`.
4. Approve no-plan mode as the official compatibility path and the single nullable
   `RotationPlan? rotationPlan` contract.
5. Approve optional immutable lineup transport in `GameRequest` with `defaultFor` fallback.
6. Approve the opponent default as Balanced generated per roster.
7. Confirm foul-rate investigation is outside M005.

**Technical risks**
- Windows are event-driven; targets can be structurally unattainable. Disclosure is mandatory.
- Small-roster presets compress toward full-game minutes by construction (six-player Balanced gives
  starters 42:21 and the reserve 28:14). This is intentional, legal and clearly distinct from
  Starter-heavy, but it is not an NBA-like rotation.
- Fingerprint v4 invalidates v5 inputs by design; migration and fixtures must move atomically.
- In-game clock accounting inside the simulator must exactly match `EventAccounting`; drift would make
  rotation decisions and displayed minutes disagree.
- Without fatigue, targets are participation control, not performance management.
- Rotation may reduce individual foul concentration but will not necessarily normalize disqualification
  frequency; no coefficient tuning is in scope.

## 12. Historical foul-out context (method and limits)

T08 retained raw v5 rows (`E:\ballgorithm-t08-artifacts\t08-raw-v5.jsonl`, SHA-256 `58ea4969…`) show
189/200 games with at least one disqualification, 464 total, and 40.2 combined personal fouls per game.

For the starter split, OMP regenerated the league fixture (`GenerationConfig(seed: 20261028)`) and
identified actual starters with `CourtLineup.defaultFor`, then joined those ids to the retained T08
player rows: 2,000 starter player-games with mean 3.76 fouls versus 2,800 bench player-games with mean
0.18; starters account for **93.6%** of fouls and **94.4%** of minutes (mean 2,721 s vs 116 s).

This is descriptive evidence from one league fixture. It does not prove a coefficient defect, does not
establish an NBA comparison, and does not promise that rotations will normalize foul-out frequency.
