# Design Decisions 006 — Role-Aware Shot Selection v1 (DRAFT)

> **Status: DRAFT — decisions below are proposals requiring owner approval.** None is frozen.

## DD-M006-01 — Derived role signal, never persisted

**Proposal.** Rank the active five by
`creation = slotBase[slot] + 3·ballHandling + passing + basketballIQ`; ties break on canonical
court-slot order. The top rank is the primary-creation slot; the rest are secondary.

**Why.** Existing attributes already encode creation ability; the same score already drives foul
actor selection, so the concept exists in the code without a name. A persisted role would need an
M001 `Player` schema change, snapshot version bump and league-generator change — a large blast
radius with no proven benefit.

**Trade-offs.** A derived rank cannot represent a coach-chosen role, a position switch within a
game, or a lineup where two creators alternate. It classifies, it does not simulate a ballhandler.

## DD-M006-02 — Usage multipliers by role rank

**Proposal.** Multiply raw usage weights by `[13500, 11500, 10000, 10000, 10000]` basis points before
normalisation. Coefficients are provisional.

**Why.** The owner direction requires a measurable usage effect independent of zone effects. A
multiplicative factor keeps ordering and floors intact and touches no draw.

**Trade-offs.** Multipliers larger than ~1.5 risk a one-man offence; smaller than ~1.15 may be
statistically invisible. Alternative: add a `creation` term instead of a multiplier — harder to
isolate from the existing rating terms.

## DD-M006-03 — Piecewise three-point ability curve

**Proposal.** `ability(p) = 50·(p−50)` below 50 and `30·(p−50)` at or above 50, replacing the linear
`24·(p−50)` term; position, phase and floor unchanged.

**Why.** The defect is insufficient differentiation, not missing ability dependence. A steeper
below-median penalty suppresses routine threes for non-shooters; a positive above-median slope keeps
stretch-bigs because the centre position penalty is unchanged and no position gate exists.

**Trade-offs.** The breakpoint at 50 and both slopes are design choices that need owner review. The
JEV advisory preferred this structure (0.71) over a role gate (0.16) and a multiplicative factor
(0.13) at confidence 0.56 — advisory only.

## DD-M006-04 — Keep event schema 3

**Proposal.** No new event type and no persisted zone field. Ledgers expose shooter and 2/3 value
only; inside-versus-midrange remains unmeasured.

**Why.** A schema change forces new serialisation, fixtures and rejection tests for a capability the
v1 acceptance does not need. The owner direction explicitly permits keeping schema 3.

**Trade-offs.** Cannot measure or claim inside/midrange differentiation from canonical artifacts.
If the owner later wants it, that is a separate decision with schema 4.

## DD-M006-05 — Non-persistent shot-decision observer

**Proposal.** Add a debug-only callback (mirroring `onPhaseTrace`) that reports the drawn zone and
weights during simulation. It never enters the ledger or the fingerprint.

**Why.** Test instrumentation can validate inside/midrange choices without changing canonical
serialisation.

**Trade-offs.** Adds public API surface. Alternative: keep evidence to ledger-derived metrics only
and drop inside/midrange claims entirely.

## DD-M006-06 — Pre-registered evaluation

**Proposal.** Freeze metrics, development seeds, held-out seeds, thresholds and failure conditions
before any cohort; run once; report directional effects, not NBA realism.

**Why.** M002 acceptance conditions and the backlog require pre-registration and separate
development/held-out data.

**Trade-offs.** Prevents iterative tuning, so thresholds must be chosen conservatively.

## DD-M006-07 — Version boundary

**Proposal.** simulation 7 and fingerprint 5; rules 3, schema 3, duration 2 and `xorshift32-v1`
unchanged. No v6/v7 ledger equality. Draw order per branch fixed; repeat-run determinism and
VM/Chrome parity required.

**Why.** Weights change behaviour; the version identifiers must move atomically. Whole-game draw
counts legitimately diverge because different weighted choices change game paths.

**Trade-offs.** v6 fixtures stop describing current output; they remain historical evidence only.
