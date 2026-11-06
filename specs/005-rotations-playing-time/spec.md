# Specification 005 — Rotations and Playing-Time Management

> **Status:** **FROZEN — OWNER APPROVED 2026-11-06.** Implementation is **NOT STARTED** and **NOT
> AUTHORIZED**. T01–T06 each require a separate owner authorization.
>
> **Freeze record — owner approval 2026-11-06.** M005 — Rotations and Playing-Time Management,
> Approach C-lite, approved. The owner approved **Option 2** for Decision 5 (remainder distribution):
> *"Remainder seconds are assigned to starters in canonical court-slot order first, then selected
> reserves in canonical roster order."* This is the authoritative, owner-approved, deterministic
> priority rule and it **replaces** the earlier ambiguous phrase "canonical roster-order rounding".
> The starters-first rule is intentional: the selected starting lineup is part of the canonical game
> input and the input fingerprint, so the order is reproducible. Preset weights, allocation vectors
> and worked examples are preserved unchanged because no mathematical error was found.
>
> **Baseline:** `develop/m002` at `f53201314e9cfdcc8734eb523e41f313f3c644c2` (M004 accepted and closed).
> **Predecessors:** M002 possession contracts (frozen), M003 Mobile Game Day (accepted and closed),
> M004 Foundational Player Participation (accepted and closed), `M005-DRAFT.md` (historical design input).

## 1. Purpose

M004 made participation a replayed fact: a team's five can change at legal windows, a sixth personal
foul disqualifies, and minutes are derived from the ledger. But the bench still only plays when a
starter fouls out; in games without disqualification the five never changes.

M005 adds **playing-time management** for one user-managed team:

- the user chooses the starting five in five canonical court slots;
- the user chooses a rotation preset or explicit per-player second targets;
- the simulator applies a deterministic, best-effort substitution policy at existing legal windows;
- the opponent runs a deterministic generated default plan, with no user input;
- results show actual minutes and statistics for every player who participated.

M005 does **not** change probability coefficients, draw structure, action selection, event ordering
semantics, clock rules, or the PRNG implementation.

## 2. What must be true

1. One managed team per matchup; the opponent is always automatic.
2. The managed starting five is selected by the user and is part of the canonical game input and the
   input fingerprint.
3. A rotation plan is optional. `null` means legacy no-rotation gameplay; a non-null plan carries both
   teams' plans and is fully validated.
4. Playing-time targets are integer player-seconds, conserve the team total exactly, and never exceed
   the regulation per-player cap.
5. Preset expansion is exact integer arithmetic: no randomness, no optimizer, no clamping loop, no
   floating-point rounding.
6. Remainder distribution follows the owner-approved priority: starters in canonical court-slot order
   first, then selected reserves in canonical roster order.
7. The rotation policy is deterministic and consumes **no PRNG draws**.
8. Tactical substitutions are emitted only at legal windows W1, W2, W4 and W5, only after any
   mandatory foul-out replacement for that event has completed, and at most once per team per window.
9. Mandatory foul-out replacement always precedes a tactical swap; a team with a pending or due
   mandatory replacement emits no tactical swap in that window.
10. Overtime uses a fresh, deterministic per-period allocation derived from the original regulation
    plan and the then-eligible roster. Regulation targets and completed regulation minutes are never
    recomputed or rewritten.
11. Minutes and participation remain ledger-derived; the simulator keeps no competing minutes
    scoreboard.
12. Semantically equal plans serialize to one canonical form and produce one fingerprint.
13. Historical no-plan gameplay remains behaviorally identical to v5: the canonical event array for
    the same input and seed is unchanged apart from ledger header/version metadata.
14. Rematch preserves the managed lineup, both team plans and the matchup, and advances only the seed
    along the existing M003 `deriveGameSeed` cycle.
15. Every M004 limitation and non-acceptance remains in force.
16. Same input, seed and approved version identifiers produce identical ledgers and identical derived
    results, on Dart VM and Chrome.

## 3. Rotation plan contract

Core owns the plan. No UI-only state participates in simulation.

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
- `GameInput` gains a single nullable field: `RotationPlan? rotationPlan`.
  - `null` = legacy no-rotation behavior for both teams (v5 gameplay path).
  - non-null = both `home` and `away` `TeamRotationPlan` values must be present; a partially populated
    plan is a typed validation error.
- Canonical JSON: team order **home then away**; each `TeamRotationPlan` serializes `preset` and
  `targets` as a list of `{playerId, seconds}` entries in **canonical roster order**. No
  insertion-ordered map is serialized, so semantically equal plans fingerprint identically.
- Presets are expanded to explicit `targetSeconds` **before** validation; a plan whose `preset` and
  explicit targets disagree is rejected rather than silently re-expanded.
- `Home` and `away` association is structural: the home plan's target set must equal the home roster's
  player-id set, and the away plan's target set must equal the away roster's player-id set. Ownership
  is validated; no separate team-id field is serialized.

### 3.1 Plan validation (typed errors)

- Every roster player of each team appears exactly once as a target key; unknown ids, missing ids and
  duplicate entries are rejected.
- `0 ≤ target ≤ C` for every player, where `C` is the regulation per-player cap (§5.1).
- `Σ target == T` exactly, where `T` is the regulation team total (§5.1).
- All five selected starters have `target > 0`.
- `preset` is a known value. `custom` requires explicit targets; `balanced` and `starterHeavy` require
  targets equal to their deterministic expansion.
- Validation failures are typed `GameValidationException` issues with stable codes and paths. Message
  wording is not part of the contract.

## 4. Starting lineup transport

Starting lineups travel separately from playing-time targets.

- `GameRequest` (app transport) gains optional immutable `homeLineup` / `awayLineup` (`CourtLineup?`)
  and the optional `RotationPlan?` alongside `league`, `homeTeamId`, `awayTeamId` and `seed`.
- The worker uses the supplied lineup when present and `CourtLineup.defaultFor(team)` otherwise.
- `GameInput.create` re-canonicalizes and validates slot order, roster ownership, uniqueness and size.
- Lineups are immutable across the isolate boundary; the object graph must not hold isolate-local
  state.
- Rematch copies both lineups, both team plans and the matchup, and changes only the seed.
- A lineup is **not** a plan: plans only add targets. Selecting a starter who is not in the starting
  lineup is impossible by construction.

## 5. Preset allocation

Weighted integer allocation. Presets are expanded into explicit targets before validation. No
randomness. No optimizer.

### 5.1 Definitions

- `L(p) = rules.periodLength(p)`.
- Regulation team total `T = 5 × Σ_{p=1..periods} L(p)` (`= 5 × periods × periodSeconds`; periods
  currently fixed at 4).
- Individual regulation cap `C = Σ_{p=1..periods} L(p)` (`= periods × periodSeconds`).
- Standard rules: `periods = 4`, `periodSeconds = 720`, so `C = 2880` and `T = 14400`.

### 5.2 Participant selection

`r = min(n, preferred) − 5` reserves, where `n` is roster size.

- The five participants that are not reserves are the **selected starters**, in canonical court-slot
  order.
- Selected reserves are the first `r` non-starters in **canonical roster order**.
- Balanced: `preferred = 9`, starter weight `wS = 3`, reserve weight `wR = 2`.
- Starter-heavy: `preferred = 8`, `wS = 5`, `wR = 2`.
- Custom: user-supplied targets; no expansion.

**Small-roster branch.** If `n == 5`, every player receives `C` (sum `5C = T`). `n < 5` is rejected
by input validation. `r == 0` occurs only at `n == 5`; no division by `r` is performed.

### 5.3 Allocation mathematics

For `n > 5`:

1. `W = 5·wS + r·wR`.
2. `target_i = floor(T · w_i / W)` for each participant, where `w_i = wS` for starters and `w_i = wR`
   for selected reserves.
3. `rem = T − Σ target_i`. Because `rem` is strictly smaller than the participant count, grant `+1`
   second to the first `rem` participants in the owner-approved order of §5.4.
4. Non-participants receive `0`.
5. Assert every target in `[0, C]`, all five starters `> 0`, participant count `= 5 + r`, and
   `Σ targets = T`; violations are typed allocation errors. No clamping loop is used: floors plus a
   remainder smaller than the participant count cannot exceed `C`, and the `n == 5` branch is exact.

### 5.4 Remainder distribution (owner decision, 2026-11-06)

> **Remainder seconds are assigned to starters in canonical court-slot order first, then selected
> reserves in canonical roster order.**

This is the **owner-approved deterministic priority rule**. It is a deliberate priority assignment,
not a fractional-remainder tie-break, and it is **not** global roster-order rounding. It is
reproducible because the selected starting lineup is part of the canonical game input and the input
fingerprint. The earlier phrase "canonical roster-order rounding" is withdrawn and must not appear as
an operative rule.

### 5.5 Standard-rules vectors

`periods = 4`, `periodSeconds = 720`, `C = 2880`, `T = 14400`. Values in seconds; `S1…S5` are starters
in canonical court-slot order, `R1…Rk` selected reserves in canonical roster order.

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
37:54 and reserves 25:15; Starter-heavy gives 41:23 and 16:33. Presets are convenience heuristics, not
NBA-calibrated plans.

### 5.6 Short-period example

`periodSeconds = 100`, `periods = 4`, `C = 400`, `T = 2000`, `n = 6`:

- Balanced: `[353,353,353,353,353, 235]`, sum `2000`.
- Starter-heavy: `[371,371,370,370,370, 148]`, sum `2000`.

These are exact integer targets even though the total is not minute-aligned.

## 6. Deterministic rotation policy

Evaluated after every event that opens W1/W2/W4/W5, per team, before the next live event. Integer
seconds only; **no PRNG draws**.

### 6.1 State

- `actualSeconds[playerId]` is derived by the simulator from its own emitted events and must be
  cross-checked in tests against `EventAccounting`.
- `targetSeconds[playerId]` comes from the validated plan.
- The active five is the simulator's mutable on-court lineup, matching the reducer's replayed five.

### 6.2 Horizons and expected values

During regulation:

```text
horizonGameSeconds = Σ regulation period lengths only
elapsedGameSeconds = game seconds elapsed so far
expected(p) = targetSeconds[p] × elapsedGameSeconds ÷ horizonGameSeconds
deficit(p)  = expected(p) − actualSeconds[p]
```

Regulation targets and this formula apply only until the regulation horn. Overtime switches to the
separate per-period allocation in §8; no regulation target or completed minute is recomputed.

### 6.3 Thresholds (phase-aware)

Thresholds scale with the **active** period length using integer division and a strictly positive
floor:

- regulation: `h = max(1, periodSeconds ~/ 8)`, `cooldown = max(1, periodSeconds ~/ 6)`
  (90 s and 120 s at 720);
- overtime: `h_ot = max(1, overtimeSeconds ~/ 8)`, `cooldown_ot = max(1, overtimeSeconds ~/ 6)`
  (37 s and 50 s at 300).

Using regulation values inside a 300-second overtime would delay a meaningful swap until roughly
260 s; the overtime-scaled values are required. Very short periods still floor at `1`, so at most one
swap per team per window applies.

These are **simulation policy constants** versioned by `gameSimulationVersion`. They are not rule
fields and are not part of the input fingerprint.

### 6.4 Decision order

Per team, at a tactical hook:

1. If a mandatory foul-out replacement is pending or due, perform it first; do not emit a tactical
   swap for that team in this window.
2. If the team swapped tactically within `cooldown` game-seconds, or the proposed pair is the exact
   reverse of the previous window's swap, skip.
3. Eligible bench = roster players not active, not disqualified, with `target > 0`.
4. Choose the swap only if some active player has `deficit ≤ −h` and some eligible bench player has
   `deficit ≥ +h`.
5. Outgoing: minimum `deficit` (most over target); tie-break lower canonical roster index, then id.
6. Incoming: maximum `deficit`; tie-break same primary position as the vacated slot, then lower
   canonical roster index, then id.
7. Emit **at most one** tactical `Substitution(reason: tactical)` per team per window, at the same
   game clock and shot clock. The reducer's per-window single-appearance rule is never approached.

Disqualified players are never outgoing or incoming candidates for tactical swaps.

## 7. Legal windows and mandatory precedence

Each tactical hook fires only after the entire mandatory sequence for that event has completed, and
only if a tactical swap is still legal for the team under the reducer's window, clock and shot-clock
rules. A tactical substitution must never be emitted before a mandatory foul-out replacement.

| Window | Actual simulator order | Tactical hook placement |
|---|---|---|
| W1 | `PersonalFoul` (non-shooting, non-bonus, 0 FTs) → record foul → shot-clock reset / `retainedFoul` context → `_emitFoulOutReplacement` | After the replacement call returns; same game clock and reset shot clock; before the next live action |
| W2 | final made `FreeThrowAttempt` → `_endPossession(madeFinalFreeThrow)` (possession state cleared) | Immediately after `_endPossession`, before the next `PossessionStarted`, only when clock > 0 |
| W4 | offensive `PersonalFoul` → `Turnover(offensiveFoul)` → `_endPossession(turnover)` → `_emitFoulOutReplacement` for the offending team | After the replacement call; possession already closed; only when clock > 0 |
| W5 | `PeriodStarted` → mandatory replacements for both teams → pending set cleared → first possession | After the replacement loop and before the first possession; `shotClock` is null and clock is the period length |
| W0 | foul → `_emitFoulOutReplacement` → free throws | **No tactical hook**; mandatory only |
| — | `PossessionEnded(madeFieldGoal)`, `PossessionEnded(defensiveRebound)`, `PeriodEnded`, `GameEnded`, live turnovers | **No tactical hook**; these do not open a reducer window |

M005 adds no new windows, no timeouts and no synthetic stoppages.

## 8. Overtime handling

Regulation targets, regulation minutes and regulation expectations are immutable. Overtime uses a
**fresh participation allocation per overtime period**, derived from the original plan, the currently
eligible roster, the actual `overtimeSeconds`, and the current active lineup.

### 8.1 Per-period allocation

For an overtime period of length `L = rules.overtimeSeconds` (`L > 0` by rules validation), let
`O = 5 × L` team player-seconds. Eligible set `E` = players not disqualified who are either currently
active or have a positive regulation target. Order `E` as current active slots first, then eligible
bench in canonical roster order.

1. `base_i = floor(regulationTarget[i] × L ÷ C)` for each `i` in `E` (`C` = regulation player cap).
   A player with a full regulation target therefore receives exactly `L`.
2. Clamp `base_i` to `L`.
3. `leftover = O − Σ base_i`. Grant `+1` second round-robin over `E` in the order above, skipping
   players already at `L`, until `leftover` is zero or every eligible player is capped. If `E` has
   fewer than five players (depleted continuation), any unallocated seconds are forced onto
   disqualified continuers; no error and no tactical swap is possible.
4. If every regulation target in `E` is zero (possible only after unusual substitution chains), fall
   back to an equal split of `O` over `E`, capped at `L`, with the same round-robin remainder.
5. This allocation is fixed for that overtime period. It is recomputed identically at the start of
   each later overtime period from the original plan and the then-eligible roster; no overtime actuals
   are carried across periods.

### 8.2 Policy inside overtime

`horizon = L`, `elapsed` = seconds elapsed in that overtime period, `expected_i = otTarget_i × elapsed
÷ L`, `actual_i` = seconds played in that overtime period only. The same deficit rule,
one-swap-per-window rule, tie-breaks and overtime-scaled thresholds (`h_ot`, `cooldown_ot`) apply.
Regulation-phase accumulated seconds never enter these deficits, so an overtime period cannot inherit
a negative total-deficit state.

### 8.3 Foul-outs in overtime

Mandatory replacement always runs first at the window that follows the sixth foul; no tactical swap is
emitted for that team in that window. The disqualified player is removed from `E` for later windows,
but the current period's `otTarget` vector is not retroactively rewritten. If an eligible bench player
remains, the mandatory replacement enters and later tactical swaps continue against the existing
`otTarget`. If no eligible bench remains, depleted continuation applies: no tactical swaps,
disqualified players stay on court, and conservation still comes from the ledger. The next overtime
period recomputes allocations without the disqualified player.

### 8.4 Worked example

`overtimeSeconds = 300`, `L = 300`, `C = 2880`, `O = 1500`; Balanced nine-player plan
`[1879,1879,1878,1878,1878,1252,1252,1252,1252]`.

- **Regulation tie → first overtime:** floors are `floor(1879×300/2880)=195`,
  `floor(1878×300/2880)=195`, `floor(1252×300/2880)=130`; sum `5×195 + 4×130 = 1495`;
  `leftover = 5`; active-first round-robin gives one second to each starter →
  `otTarget = [196,196,196,196,196,130,130,130,130]`, sum `1500`. The active five begin overtime; no
  swap occurs at elapsed 0; later windows may swap if an active player is `h_ot` over and a reserve
  `h_ot` under.
- **Second overtime:** recomputed from the same regulation plan and the roster then eligible. If one
  reserve fouled out in the first overtime, `E` has eight players: floors `5×195 + 3×130 = 1365`,
  `leftover = 135`. Round-robin covers **all eight eligible players**, not only the starters:
  `135 = 16×8 + 7`, so 16 full passes give `+16` to everyone, then the first seven in order (five
  starters, then the first two reserves) receive one more:
  `otTarget = [212,212,212,212,212,147,147,146]`, sum `1500`.
- **Foul-out during overtime:** the sixth foul at a live window triggers mandatory replacement before
  any tactical decision; that team skips a tactical swap in that window. If a reserve remains, it
  enters; if not, depleted continuation ends tactical rotations. Regulation minutes and prior overtime
  periods are untouched; the next overtime period recomputes without the disqualified player.

No new windows, no extra PRNG draws, and no overtime allocation changes regulation targets.

## 9. Versioning (proposed, not applied)

| Identifier | Current | Target | Reason |
|---|---|---|---|
| `gameSimulationVersion` | 5 | **6** | New behavior: tactical substitutions |
| `gameFingerprintVersion` | 3 | **4** | Canonical input gains the rotation plan |
| `gameRulesVersion` | 3 | 3 | No rule or clock change; the plan is input and the policy is engine behavior |
| `gameEventSchemaVersion` | 3 | 3 | Existing `Substitution` only |
| `gameActionDurationModelVersion` | 2 | 2 | Unchanged |
| PRNG | `xorshift32-v1` | unchanged | Rotation consumes no draws |
| `coreEngineVersion` / `snapshotSchemaVersion` | unchanged | unchanged | M001 contracts untouched |

- The version bump, the `GameInput.rotationPlan` field and the fingerprint payload change land in one
  atomic public-contract commit (T01). No commit may expose the new payload under an old version.
- `GameRequest` gains the plan and optional immutable lineups. The worker supplies `defaultFor` only
  when a lineup is absent.

### 9.1 Historical compatibility

- **No-plan mode:** `null` plans produce historical v5 gameplay. Under v6 the ledger header/version
  differs; the canonical event array must equal the pinned v5 array for the same input and seed.
  Header and version differences are explicit and must not be treated as behavioral drift.
- New v6 canonical fixtures are added. Every M004 v5 fixture is preserved and never rebaselined.
- M001 league-generation vectors, snapshots and public contracts are unchanged.
- Historical M002–M004 evidence keeps its own pinned verification.
- Version identifiers are compared for exact equality on read, so a v6 build rejects v5 ledgers with
  the existing typed `unsupportedEventSchemaVersion` behavior. M005 does not promise transparent
  historical parsing.

## 10. UI

- Matchup setup adds: managed-team choice, starting-five selection in five canonical slots, rotation
  preset (Balanced, Starter-heavy, Custom).
- Preset UI is the default. Custom exposes per-player integer steppers with an exact total indicator
  for `T` and inline typed validation; invalid plans block confirmation.
- The shipped Flutter editor may present standard-rules minutes, while the core accepts arbitrary
  validated integer-second targets for nonstandard rules.
- At 360 dp the plan is a compact list, not a twelve-row free-form editor on the first screen.
- Results show actual minutes and statistics for everyone who started or entered, retaining M004
  starter/substitute tagging and disqualification indicators.
- Mandatory disclosure: *"Targets are best-effort. Foul-outs, disqualification rules and the limited
  dead-ball windows can change minutes."*
- M004 disclosures remain: technical fouls are not modelled; a disqualified player may continue when
  no eligible bench player remains; rotations here are participation control, not fatigue management.
- No in-game manual substitution UI.

## 11. Non-goals

Fatigue/stamina, injuries/ejections, coaching AI, in-game manual substitutions, technical fouls,
contracts, trades, seasons, persistence, player development, NBA realism or calibration,
probability/coefficient changes, timeouts, new dead-ball events, foul-rate investigation. Regular
tactical rotations beyond the deterministic playing-time policy are excluded; the policy is not a
coaching AI.

## 12. Traceability

Acceptance criteria: `acceptance-matrix.md`. Design rationale: `design-decisions.md`. Verification:
`verification-plan.md`. Task breakdown: `tasks.md`. Historical design input: `M005-DRAFT.md`
(superseded).
