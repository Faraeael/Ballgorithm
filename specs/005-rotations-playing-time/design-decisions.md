# Design Decisions 005 — Rotations and Playing-Time Management

> **Status:** **FROZEN — OWNER APPROVED 2026-11-06.** All decisions below are part of the frozen
> specification. DD-M005-05 records the owner's rounding-order decision. Implementation is **NOT
> STARTED**; every task needs separate authorization.
> **Baseline:** `develop/m002` at `f53201314e9cfdcc8734eb523e41f313f3c644c2`.

---

## DD-M005-01 — Scope: Approach C-lite, one managed team

**Decision:** one user-managed team per matchup. The opponent is always automatic and runs a
deterministic generated default plan. In scope: five-slot starting lineup, a rotation preset or custom
targets, deterministic tactical substitutions at existing legal windows, results with actual
participation.

**Rationale:** the smallest feature that turns the accepted M004 participation architecture into
playing-time management without introducing fatigue, tactics or coaching AI. Two user-managed teams
would double the setup surface without proving anything new.

**Consequence:** no manual in-game substitutions, no fatigue, no coaching AI, no timeouts.

## DD-M005-02 — A single nullable plan is the rotation contract

**Decision:** `GameInput` carries `RotationPlan? rotationPlan`. `null` means legacy no-rotation
behavior for both teams; a non-null plan must contain both home and away `TeamRotationPlan` values.

**Rationale:** one contract and one nullability point. Two independent per-team plans would allow a
half-configured game and make fingerprint semantics ambiguous.

**Consequence:** partial plans are typed errors; the canonical payload is home-then-away.

## DD-M005-03 — Integer player-seconds are the canonical unit

**Decision:** targets are integer seconds, never minutes or floating point. The regulation team total
is `T = 5 × Σ L(p)`; the individual cap is `C = Σ L(p)`.

**Rationale:** integer arithmetic makes allocation exact, canonical, and testable across Dart VM and
Chrome. Minutes are a presentation concern.

**Consequence:** presets and custom targets share one validated representation; non-minute-aligned
totals are legal.

## DD-M005-04 — Preset participant selection and weights

**Decision:** `r = min(n, preferred) − 5` reserves, taken from non-starters in canonical roster order.
Balanced: `preferred = 9`, `wS = 3`, `wR = 2`. Starter-heavy: `preferred = 8`, `wS = 5`, `wR = 2`.
`n == 5` assigns `C` to all five; `n < 5` is rejected.

**Rationale:** the selected starters are known from the lineup, so reserve selection must be
deterministic and independent of which five the user chose. Weights produce visibly distinct
participation patterns across common roster sizes.

**Consequence:** presets are convenience heuristics, not calibrated rotations.

## DD-M005-05 — Remainder distribution order (owner decision, 2026-11-06)

**Decision:** **Remainder seconds are assigned to starters in canonical court-slot order first, then
selected reserves in canonical roster order.**

This is the authoritative, owner-approved deterministic priority rule. It replaces the earlier
ambiguous phrase "canonical roster-order rounding", which is withdrawn and must not appear as an
operative rule. The starters-first rule is intentional; it is **not** global roster-order rounding.

**Rationale:** the rule must be unambiguous, deterministic, and reproducible from the canonical input.
The selected starting lineup is part of the game input and the input fingerprint, so starters-first
ordering has a stable, auditable basis even when the lineup is not the first five in roster order.
Large-remainder examples (five starters receiving the extra second) made the earlier phrase
operationally ambiguous.

**Consequence:** the frozen vectors in `spec.md` §5.5 and §5.6 already reflect this order and are
unchanged. Preset weights, allocation vectors and worked examples are preserved because no
mathematical error was found. A contract test must pin the order, and a documentation scan must find
no conflicting statement.

## DD-M005-06 — Presets expand before validation; no optimizer

**Decision:** Balanced and Starter-heavy expand to explicit `targetSeconds` before validation. A plan
whose preset and explicit targets disagree is rejected. Custom targets use the same validation without
expansion.

**Rationale:** expansion is pure integer arithmetic; validation must see one representation. An
optimizer would add nondeterminism, tuning surface and unprovable claims.

**Consequence:** no clamping loop; `C` is asserted rather than enforced by mutation.

## DD-M005-07 — Deterministic deficit policy, zero PRNG draws

**Decision:** the rotation policy uses integer expected values and deficits, fixed tie-breaks and at
most one tactical swap per team per window. It consumes no PRNG draws.

**Rationale:** determinism is a non-negotiable contract; a scored approximation avoids re-deriving
actions while keeping the draw structure untouched.

**Consequence:** policy constants are engine behavior versioned by `gameSimulationVersion`, not rule
fields or fingerprint inputs.

## DD-M005-08 — Thresholds scale with the active period

**Decision:** regulation `h = max(1, periodSeconds ~/ 8)` and `cooldown = max(1, periodSeconds ~/ 6)`;
overtime `h_ot` and `cooldown_ot` use `overtimeSeconds`. Floors are strictly positive.

**Rationale:** using regulation thresholds in a 300-second overtime would delay a meaningful swap
until roughly 260 s. Scaling keeps the policy interpretable at both lengths and at very short periods.

**Consequence:** at most one swap per team per window remains true at any rules length.

## DD-M005-09 — One tactical swap per team per window

**Decision:** at most one tactical `Substitution` per team per window, at the same game clock and shot
clock; cooldown and exact-reverse suppression are enforced.

**Rationale:** avoids approaching the reducer's per-window player-appearance bound and avoids
oscillating swaps. The event stream stays small and auditable.

**Consequence:** repeated swaps require separate windows.

## DD-M005-10 — Mandatory foul-out replacement precedes every tactical swap

**Decision:** a pending or due mandatory replacement is performed first; that team emits no tactical
swap in the same window. Disqualified players are never tactical candidates.

**Rationale:** mandatory participation legality must never depend on rotation policy. The ordering is
an invariant, not a side effect of code order.

**Consequence:** a window can carry a foul-out replacement and still carry no tactical swap; tests
construct this collision.

## DD-M005-11 — Existing windows only; no new dead balls

**Decision:** tactical hooks attach to W1, W2, W4 and W5 only. W0 is mandatory-only. Made field goals,
defensive rebounds, live turnovers, `PeriodEnded` and `GameEnded` get no hook. No timeout or synthetic
stoppage is added.

**Rationale:** M004's window contract is frozen. Adding windows would reopen the reducer and
misrepresent the engine's dead-ball model.

**Consequence:** targets are structurally unattainable in some games; disclosure is mandatory.

## DD-M005-12 — Overtime uses a fresh per-period allocation

**Decision:** each overtime period computes `otTarget` from the original regulation target, the then-
eligible roster, `L = overtimeSeconds` and `C`: `base = floor(regTarget × L ÷ C)`, capped at `L`, then
a round-robin remainder over the eligible set ordered active-slots-then-roster. The allocation is
period-local and discarded at period end. Regulation targets and minutes are never recomputed.

**Rationale:** overtime has a different team total and a different duration; reusing regulation
targets would over-allocate. Carrying overtime actuals forward would let one period contaminate the
next.

**Consequence:** foul-outs change the eligible set for later periods but never rewrite the current
period's vector.

## DD-M005-13 — Lineups travel separately from the plan

**Decision:** `GameRequest` carries optional immutable `homeLineup` / `awayLineup` and the plan. The
worker uses a supplied lineup and `CourtLineup.defaultFor(team)` otherwise. `GameInput.create`
re-validates ownership, slot order, uniqueness and size.

**Rationale:** the lineup is M004's contract; the plan only adds targets. Keeping them separate avoids
a second definition of "the five" and preserves the accepted fingerprint semantics.

**Consequence:** no lineup can select a player outside the roster; the opponent default is generated.

## DD-M005-14 — Versioning: simulation 6, fingerprint 4

**Decision:** `gameSimulationVersion` 5 → 6 and `gameFingerprintVersion` 3 → 4 in one atomic commit.
`gameRulesVersion` stays 3, `gameEventSchemaVersion` stays 3, `gameActionDurationModelVersion` stays
2, PRNG stays `xorshift32-v1`, M001 identifiers unchanged.

**Rationale:** tactical substitution changes behavior; the plan changes the canonical input payload.
Rules, event schema and duration model genuinely do not change, and `Substitution` already exists.

**Consequence:** a v6 build rejects v5 ledgers under the existing exact-version check; v6 fixtures are
added, v5 fixtures are never rebaselined.

## DD-M005-15 — No-plan mode is the compatibility path

**Decision:** a `null` plan produces historical v5 gameplay. Under v6, the canonical event array for
the same input and seed must equal the pinned v5 array; only ledger header/version metadata differs.

**Rationale:** compatibility must be observable, not asserted. The event array is the behavioral
contract.

**Consequence:** the equality fixture excludes header/version fields explicitly; any other difference
is a defect.

## DD-M005-16 — Rematch continuity

**Decision:** rematch copies both lineups, both team plans and the matchup, and advances only the seed
along the existing M003 `deriveGameSeed` cycle. Repeating the same complete rematch request remains
deterministic.

**Rationale:** the user configured a plan; losing it on rematch would be a surprising reset. Seed
advancement is already frozen by M003.

**Consequence:** `GameRequest` must carry the plan and lineups, not the screen.

## DD-M005-17 — Best-effort targets and mandatory disclosure

**Decision:** targets are best-effort. Foul-outs, disqualification rules and limited dead-ball windows
can change actual minutes. The results surface states this.

**Rationale:** the engine has no timeout or inbound model; claiming exact minutes would be false.

**Consequence:** tests assert legality and conservation, never target achievement.

## DD-M005-18 — UI scope

**Decision:** setup adds managed-team choice, five starter slots and preset/custom targets. Preset UI
is default; Custom exposes integer steppers with an exact total indicator. At 360 dp the plan is a
compact list. Results keep M004 tagging and add minutes/statistics for starters and entrants.

**Rationale:** the editor must stay usable on the primary mobile target; the core accepts arbitrary
validated integer seconds for nonstandard rules.

**Consequence:** invalid plans block confirmation; no in-game manual substitution UI; no theme or
navigation redesign.

## DD-M005-19 — M004 limitations are retained

**Decision:** every M004 non-acceptance and preserved limitation remains in force. M005 amends no M004
acceptance record and does not claim that rotations fix foul-out frequency.

**Rationale:** milestone boundaries are contractual; silent re-certification would corrupt the
evidence record.

**Consequence:** the historical T08 foul evidence is descriptive context only, and foul-rate
investigation remains outside M005.
