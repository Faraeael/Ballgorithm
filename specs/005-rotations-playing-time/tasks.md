# Tasks 005 — Rotations and Playing-Time Management

> **Status:** **FROZEN — OWNER APPROVED 2026-11-06.** No task below is authorized by appearing here;
> each needs its own owner authorization. **Implementation is NOT STARTED.**
> **Baseline:** `develop/m002` at `f53201314e9cfdcc8734eb523e41f313f3c644c2`.
> The M005 specification was frozen by explicit owner approval on 2026-11-06 (see `spec.md` freeze
> record). T01 is the first task and remains gated on a separate authorization.

## Standing constraints (every task)

- Do not change M001 generation, snapshots, league vectors or PRNG behavior.
- Do not change M002 historical evidence, frozen thresholds, calibration records or v1–v5 fixtures.
- Do not change M003 accepted navigation or M004 accepted participation behavior beyond M005 scope.
- No coefficient, clock-rule, action-selection, event-ordering or PRNG-implementation change.
- Rotation policy constants are engine behavior versioned by `gameSimulationVersion`; they are not
  rule fields and do not enter the input fingerprint.
- Report PASS / FAIL / NOT RUN / BLOCKED with exact commands and environment.
- Stop and report rather than widening scope.

---

## T01 — Rotation plan contract, validation and atomic version transition

**Purpose:** make the plan a validated, canonically serialized, fingerprinted part of `GameInput`
without yet emitting tactical substitutions.

**Prerequisites:** M005 frozen; T01 authorized by the owner.

**Authorized scope (single commit):** new `RotationPlan` / `TeamRotationPlan` / `RotationPreset` with
canonical roster-order JSON; preset expansion for Balanced and Starter-heavy; Custom validation;
nullable `GameInput.rotationPlan`; fingerprint payload change; `gameSimulationVersion` 6 and
`gameFingerprintVersion` 4 together. `gameRulesVersion`, `gameEventSchemaVersion`,
`gameActionDurationModelVersion` and the PRNG stay unchanged. The plan is exported through the
package barrel.

**Acceptance evidence:** contract tests for canonical JSON, insertion-order independence, exact-sum,
cap, roster-completeness, starter-positivity and typed errors; preset vectors from `spec.md` §5.5 and
§5.6 asserted, including the starter-first remainder order; `n < 5` rejected; one commit contains the
field, the payload change and both bumps; package and Flutter consumer compile; no tactical
substitution is emitted yet.

**Stop condition:** any need to split the public field, the fingerprint payload and the version bumps
across commits, or any historical fixture edit — stop.

---

## T02 — Deterministic rotation policy component

**Purpose:** implement the deficit, threshold and tie-break logic as a pure component.

**Prerequisites:** T01 green.

**Authorized scope:** new policy component; regulation horizons and expected values; phase-aware
thresholds; outgoing/incoming selection; cooldown and reverse-swap suppression; at most one swap per
team per window. No simulator wiring. No PRNG use.

**Acceptance evidence:** unit tests for deficit selection and both tie-break chains; `h` and `cooldown`
values at 720/300 and at very short periods (floor at 1); cooldown and reverse-swap rejection; zero
eligible bench; disqualified players never selected; **zero PRNG draws** (draw-count assertion); the
component returns "no swap" when no candidate satisfies both deficits.

**Stop condition:** any need for randomness, or any need to change `GameRules` to hold a policy
constant — stop.

---

## T03 — Simulator hooks and mandatory precedence

**Purpose:** emit lawful tactical substitutions in real games.

**Prerequisites:** T02 green.

**Authorized scope:** simulator hooks after W5 first, then W1/W2/W4; mandatory foul-out replacement
always first; no hook at W0 or on non-window possession ends; overtime hooks with period-local
actuals and the fresh per-period allocation from `spec.md` §8.

**Acceptance evidence:** reducer accepts every emitted tactical substitution; a plan changes player
minutes relative to no plan on the same seed; no tactical swap precedes a mandatory replacement in a
constructed collision; no tactical swap is emitted at clock 0 or on a non-window end; overtime
allocations match §8.4; OT foul-out path keeps mandatory-first ordering; conservation holds; no
simulator minutes scoreboard.

**Stop condition:** reducer rejects an emitted ledger, or a mandatory replacement is skipped — stop.

---

## T04 — v6 canonical fixtures, replay and no-plan equivalence

**Purpose:** pin v6 and prove compatibility and determinism.

**Prerequisites:** T03 green.

**Authorized scope:** new v6 canonical fixture(s) with a pinned plan and lineup; repeat-run identity;
worker/caller parity; no-plan v5 event-array equivalence fixture; mutation tests for illegal plans.

**Acceptance evidence:** fixture digest pinned; repeated runs identical on Dart VM and in Chrome-
compatible tests (excluding the IO-dependent isolation test with the exclusion recorded); worker and
caller produce identical results; no-plan event array equals the pinned v5 array with header/version
excluded; v1–v5 fixtures unchanged and verified by their pinned tests; a v6 build rejects a v5 ledger
with the typed schema-version error.

**Stop condition:** nondeterminism, a parity difference, or any unexplained no-plan event diff — stop.

---

## T05 — Flutter setup, transport and validation feedback

**Purpose:** let the user choose the managed team, starting five and rotation plan.

**Prerequisites:** T01–T04 green.

**Authorized scope:** setup UI for managed team, five starter slots, Balanced / Starter-heavy /
Custom; integer-second steppers for Custom with the exact total indicator; inline typed validation
that blocks confirmation; `GameRequest` carries optional lineups and plan; worker uses `defaultFor`
when a lineup is absent; rematch preserves lineups and plan and advances only the seed.

**Acceptance evidence:** widget tests at 360/393/430 with no overflow; invalid plans cannot be
confirmed; a valid plan reaches `GameInput`; a supplied lineup is the actual starting five; opponent
uses the generated default; rematch keeps lineup/plan and changes only the seed; existing M003/M004
tests green.

**Stop condition:** any need to redesign navigation, theme, or M004 result behavior beyond M005 — stop.

---

## T06 — Walkthrough, evidence and owner acceptance

**Purpose:** assemble acceptance evidence for the owner.

**Prerequisites:** T01–T05 complete.

**Authorized scope:** physical-device walkthrough on a 360 dp Android device or the owner-approved
substitute; acceptance report; evidence index; limitations; explicit non-claims.

**Acceptance evidence:** AC-M005 matrix filled with PASS / FAIL / NOT RUN / NOT MEASURED, commands and
counts, exact seeds and fixture digests; walkthrough recording milestones (setup, simulation, results,
rematch, determinism repeat, preset difference); disclosure text present; no realism, Android
performance, memory or battery claim.

**Stop condition:** any approved scope, window, acceptance or version change discovered late → report
and stop; do not fold it into an acceptance report silently.
