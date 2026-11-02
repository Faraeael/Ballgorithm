# Design Decisions 004 — Foundational Player Participation

> **Status:** **DRAFT — NOT FROZEN.** Proposed decisions for owner review. Items marked **[owner]** need
> an explicit decision before freezing; the rest are implementation details inside the proposed scope.
> **Baseline:** `develop/m002` at `125e1e652baa41db17f3684242bbd73683f9602b`.

---

## DD-M004-01 — Slot-based `CourtLineup` replaces `ActiveLineup`

**Decision:** five canonical PG→C slots, each holding a unique roster player; a player's primary
position is independent of the slot. `ActiveLineup` is removed, not aliased.

**Rationale:** `ActiveLineup.create` rejects a player in a foreign slot, and the model indexes slots
positionally. Same-position-only substitution would permanently encode a non-basketball rule and force
a second migration when rotations arrive. One type now avoids maintaining two notions of "the five".

**Consequence:** app runner and every test/fixture constructor migrate; fingerprint payload changes.
**[owner]** confirms removal rather than a compatibility alias.

## DD-M004-02 — Positional bonuses read the slot; attributes read the player

**Decision:** nine positional-bonus lookups move from `player.position.index` to the occupied slot
index. Shooting, passing, defense, rebounding and all attribute terms keep reading the player.

**Rationale:** a slot is a role; the player is a skillset. Without this, a guard in the centre slot
would receive centre bonuses, contradicting the role model.

**Consequence:** no coefficient change, but a semantic change for lineups whose slot differs from the
player's primary position. For M004's `defaultFor` lineups there is no behavioural difference before a
substitution, which the equivalence test pins.

## DD-M004-03 — Six personal fouls disqualify; disqualification is derived

**Decision:** `foulOutLimit = 6`. A player is disqualified when their recorded foul count reaches the
limit. No stored flag, no separate disqualification event.

**Rationale:** the ledger already carries every foul; a derived predicate cannot drift from the
events. **[owner]** confirms the limit and whether it is configurable.

## DD-M004-04 — Depleted-roster continuation, without technical fouls

**Decision:** a disqualified player continues only when the team has **no eligible inactive roster
player at all**. Continuation is permanent. No technical foul is assessed for continuing play or for
subsequent fouls by the continuing player.

**Rationale:** guarantees exactly five players on court without a shorthanded model. NBA Rule 3,
Section I.1 instead assesses a technical foul and a team foul for each such foul; this engine has no
technical-foul event or technical free throws, so claiming equivalence would be false.

**Consequence:** deliberate, disclosed departure. **[owner]** confirms B (simplified) over A
(NBA-equivalent, requires technical-foul modelling).

## DD-M004-05 — Replacement ranking is deterministic and versioned

**Decision:** eligible candidates = inactive, non-disqualified roster players. Prefer the vacated
slot's primary position; then order by stable roster index. Chosen through
`substitutionPolicyVersion = 1`. No PRNG draw.

**Rationale:** reproducibility, no hidden evaluation, and the event records the outcome so replay never
re-derives it. Attribute-based ranking is deferred.

## DD-M004-06 — Substitution windows W0/W1/W2/W4/W5

**Decision:** legal windows are the five listed in `spec.md` §5. Not windows: post-made-field-goal,
post-defensive-rebound, live turnover, inside a free-throw group opened for another reason, at
`gameClock == 0`, after `PeriodEnded`, after `GameEnded`.

**Rationale:** the reducer has no timeout or inbound model. W3 is removed because NBA Rule 3.V.10
forbids substitution after a successful field goal; keeping it would be a FIBA-style convenience
presented as NBA alignment. W1 exists because a retained foul is a dead ball while the possession stays
open. W0 exists because a disqualified defender must not remain for awarded free throws.

**Consequence:** fewer substitution moments than a user might expect. **[owner]** confirms W3 removal.

## DD-M004-07 — Horn and game-end handling

**Decision:** no substitution at `gameClock == 0`, without exception. A disqualifying foul at the horn
defers replacement to W5 of the next period, or needs none if the game ends. Free throws are resolved
by the awarded shooter unchanged.

**Rationale:** the simulator resolves shooting/bonus fouls at 0 before `PeriodEnded`, and missed final
free throws at 0 become `DeadBallMiss`, not a live rebound, so the disqualified player performs no live
action. Deferral changes no interval and no statistic.

**Consequence:** the disqualified player remains in the active five through buzzer free throws in the
ledger; UI must not present them as active participants.

## DD-M004-08 — Shot-clock ceiling survives W1 substitutions

**Decision:** `Substitution` is exempt from the generic pending-shot-clock consumption rule but must
match the current `shotClock` exactly and change no state. The ceiling persists until the next live
event, where the existing "reset at most ceiling" validation still applies.

**Rationale:** the current rule consumes the ceiling on the next event of any type; without the
exemption, an administrative event would silently weaken the next-possession guarantee.

**Consequence:** a targeted exemption with dedicated negative tests; it must not generalise to other
administrative events.

## DD-M004-09 — Administrative loop bound

**Decision:** within one window per team, each player may appear at most once (as out or in). A player
who leaves may not re-enter in the same window.

**Rationale:** NBA permits re-entry during the same dead ball, but an unbounded cycle could inflate a
window indefinitely. One appearance per player makes the window finite and testable.

## DD-M004-10 — Tactical substitutions are ledger-valid but not simulated

**Decision:** `reason: tactical` is accepted by validation in v5; the M004 simulator emits only
`foulOut`.

**Rationale:** tactical substitutions are legal basketball; validating them now keeps validator
semantics stable when rotations arrive instead of widening them later. The simulator policy, not the
schema, decides when to use them.

**Consequence:** fixtures can exercise the windows without a rotation policy. **[owner]** confirms.

## DD-M004-11 — Minutes are derived, never tracked

**Decision:** `PlayerBoxScore.secondsPlayed` is derived from validated ledger timestamps only.
Conservation per team is exact: `Σ seconds == 5 × Σ periodLength(played)`.

**Rationale:** one source of truth. A simulator counter would be a second scoreboard.

**Consequence:** accounting walks the ledger; mismatch fails the box with a typed error.

## DD-M004-12 — Version bumps are independent and minimal

**Decision:** simulation 5, rules 3, event schema 3, fingerprint 3; duration model stays 2; PRNG stays
`xorshift32-v1`; M001 identifiers unchanged.

**Rationale:** each contract changed independently; the duration model and PRNG did not. Historical
v1–v4 fixtures remain valid under their own versions.

## DD-M004-13 — Statistical analysis is matched-seed and intention-to-treat

**Decision:** primary analysis uses all pre-registered matched seeds and matchups; per-seed paired
differences with paired uncertainty. No post-treatment filtering on disqualification occurrence.
First-divergence index and substitution counts are descriptive. The no-disqualification subset is a
mechanism check (expect identical event lists to v4), not a pooling condition.

**Rationale:** pairing is assigned before treatment; conditioning on disqualification would bias the
estimate. Divergence changes variance, not validity.

## DD-M004-14 — Scope: foul-out participation only

**Decision:** M004 implements Design 1 (disqualification-triggered substitution, minutes, display).
Regular rotations are deferred.

**Rationale:** rotations without fatigue or tactics multiply reducer window surface for cosmetic rest
patterns. A foul-out is a genuine rule-driven trigger that proves the participation architecture once.

**Consequence:** in games without disqualifications the bench still never plays. **[owner]** confirms
the deferral.

---

## DD-M004-15 — Bench accounting and results display

**Decision:** `EventAccounting.aggregate` initializes **every roster player** of both teams before
processing events. Substitute events credit the substituting player. Players who never enter keep zero
seconds and zero production. **Participation is defined by entry, not by minutes**: a player is shown
if they started or appear as `playerInId` in any `Substitution`, even when their interval is zero
seconds. The results table lists starters (slot order, tagged) followed by entrants (entry order,
tagged); non-participants are hidden and the screen states that they are not listed.

**Rationale:** the current implementation initializes only the starting five, so a substitute's event
would be rejected as uncredited and a substitute's production would be silently missing. Initializing
the whole roster keeps team totals reconcilable and makes the box lookup total. Hiding zero-minute
players is a presentation choice, not a data omission — their zero rows remain in the box model.

**Consequence:** a fixture where a substitute records points, rebounds and fouls is mandatory; the
results table grows only by players who actually played.

## DD-M004-16 — Historical ledgers are not transparently portable

**Decision:** `GameEventLedger.fromJson` keeps exact version equality, so a v5 build rejects v4 ledgers
with `unsupportedEventSchemaVersion`. Historical evidence remains verified by its own pinned fixtures
and builds. v4/v5 comparison runs both pinned builds and normalizes configuration (league, team ids,
seed, rules); fingerprints are never compared across versions.

**Rationale:** silently accepting an older schema under new semantics would allow a mislabelled
contract. An explicit typed rejection is auditable.

**Consequence:** no claim that v5 can read v1–v4 ledgers; a future migration would need its own spec.

## DD-M004-17 — Atomic public-contract transition

**Decision:** T02 introduces `CourtLineup` **not exported** and used only inside the package, built from
`ActiveLineup`, so public API, serialization, reachable capabilities and version identifiers are
unchanged. T03 is a single commit that performs public adoption (export, `GameInput`/`GameResult`
migration, `ActiveLineup` removal, mismatched slots allowed), changes the payload to slot-player pairs,
and bumps schema, rules, fingerprint and simulation versions together, adding the event and rules in the
same commit. The two tasks stay separately authorized.

**Rationale:** an intermediate commit that changed the payload under the old version would publish a
mislabelled contract. Splitting an internal type phase from the atomic public transition keeps review
scope small without ever misrepresenting a version.

**Consequence:** default-lineup equivalence is asserted against the pinned v4 baseline by comparing
event lists and digests independently of fingerprint metadata.

---

## DD-M004-18 — Starting lineups versus current five

**Decision:** `GameInput` carries only the immutable starting lineups. The reducer reconstructs the
current five from `GameStarted` and the `Substitution` stream. Eligibility is checked against the
current five. `GameInput.isActive` is removed or renamed to starting-lineup semantics in the atomic v5
transition so no caller can confuse the two. UI participation is derived from starting lineups plus
substitution events.

**Rationale:** a mutable "active" predicate on the input would be a second source of truth and would let
a stale starter remain eligible after leaving the floor.

**Consequence:** the reducer cannot reuse `GameInput.isActive`; accounting initializes from the roster,
not the starting five.

## DD-M004-19 — Pending replacement obligation at the horn

**Decision:** a disqualification at `gameClock == 0` records a per-team pending replacement obligation.
It survives `PeriodEnded`, is satisfied only by a lawful W5 `Substitution` at the next
`PeriodStarted`, and is void if `GameEnded` follows. While pending, the window-close check accepts the
over-limit active player only through that obligation. Depleted teams accrue no obligation.

**Rationale:** without an explicit obligation, either the over-limit player would be rejected at the
next event or the checker would need a broad exception that also permits illegal continuation. The
obligation keeps both invariants narrow and testable.

**Consequence:** the state machine gains one per-team flag and a **phase-aware ordered** allowlist while
it is pending: P1 free throws of the awarded group ending in `PossessionEnded(madeFinalFreeThrow)` or
`DeadBallMiss` + `PossessionEnded(periodEnd)`; P2 retained foul ending in
`PossessionEnded(periodEnd)`; P3 `PeriodEnded` then `GameEnded` or `PeriodStarted` + W5. Any live
event, or a `PossessionEnded` with the wrong reason/possession/order, is rejected. Fixtures must cover
all three horn paths positively, plus rejected wrong-reason, wrong-order, and live-before-replacement
cases, game-ended and depleted cases.

## DD-M004-20 — T03 is a contract gate, not a feature gate

**Decision:** T03's exit state is: package and consumer compile; no-substitution games executable and
deterministic; `Substitution` JSON round-trips and malformed forms are rejected; versions and payload
land atomically. It must not claim participation works. Reducer acceptance is T04; simulator emission is
T05. Unsupported behavior fails explicitly with typed errors.

**Rationale:** the atomic transition is large enough without also carrying a fully validated
participation feature; conflating them invites a mislabelled half-feature.

**Consequence:** the T03 acceptance evidence names its limits; reviewers should not read a green T03 as
a working participation feature.
