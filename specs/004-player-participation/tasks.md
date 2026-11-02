# Tasks 004 — Foundational Player Participation

> **Status:** **FROZEN — OWNER APPROVED 2026-11-02.** No task below is authorized by appearing here;
each needs its own owner authorization, starting with T02.
> **Baseline:** `develop/m002` at `125e1e652baa41db17f3684242bbd73683f9602b`.
> Each task needs its own owner authorization after the specification is frozen.

## Standing constraints (every task)

- Do not change M001 generation, snapshots or PRNG vectors.
- Do not change M002 historical evidence, frozen thresholds, calibration records or v1–v4 fixtures.
- Do not change M003 accepted UI behaviour beyond the participation additions in scope.
- No coefficient, clock-rule, event-ordering or PRNG-implementation change.
- Report PASS / FAIL / NOT RUN / BLOCKED with exact commands and environment.
- Stop and report rather than widening scope.

---

## T01 — Specification package drafting — **COMPLETE — FROZEN 2026-11-02; T02 AWAITING AUTHORIZATION**

**Purpose:** produce a reviewable M004 contract package.

**Prerequisites:** M003 closed at `125e1e6`.

**Authorized scope:** documentation only — `specs/004-player-participation/{spec,plan,tasks,design-decisions,acceptance-matrix,verification-plan}.md`.

**Acceptance evidence:** six DRAFT documents; no source, test, fixture or version-constant change; no
push; internal contradiction review recorded.

**Stop condition:** completed. The specification was frozen by explicit owner approval on 2026-11-02
(see `spec.md` freeze record). T02 requires its own authorization.

---

## T02 — Slot semantics, genuinely internal

**Purpose:** make the model slot-aware behind the existing public API, with no contract change.

**Prerequisites:** T01 frozen; owner decisions DD-M004-01 and DD-M004-02 confirmed.

**Authorized scope:** a **non-exported** `CourtLineup`/`CourtSlot` used only inside the package;
`TeamOnCourt` and the nine positional-bonus lookups read slots; an internal converter builds a
slot-identical five from the existing `ActiveLineup`. **`GameInput`, `GameResult`, the package barrel,
`ActiveLineup`, public constructors and serialization are untouched.** No mismatched-slot lineup is
reachable from outside the package; no version constant changes.

**Acceptance evidence:** internal tests for size, canonical order, uniqueness and roster ownership;
`GameFingerprint.of` digest and event list identical to pinned v4 values for representative inputs;
full core and Flutter suites green; package barrel diff empty; a diff check showing no edits to
`GameInput`, `GameResult`, `simulation_core.dart` or version constants.

**Stop condition:** any public API, barrel, serialization or version-constant change, or any reachable
mismatched-slot lineup — stop and report.

---

## T03 — Atomic public-contract transition

**Purpose:** land the new event, rules fields, fingerprint payload and all four version bumps in one
commit so no intermediate build mislabels its contract.

**Prerequisites:** T02 green.

**Authorized scope (single commit):** `Substitution` + `SubstitutionReason`; **public adoption** of
`CourtLineup` — export it, migrate `GameInput`/`GameResult`/app runner/tests, remove `ActiveLineup`,
rename or remove `GameInput.isActive` to starting-lineup semantics, permit mismatched slot/position
lineups; schema dispatcher; `GameRules.foulOutLimit` and `substitutionPolicyVersion`; fingerprint
payload changed to slot-player pairs;
`gameSimulationVersion` 5, `gameRulesVersion` 3, `gameEventSchemaVersion` 3,
`gameFingerprintVersion` 3 together; serialization tests; typed rejection of a v4 ledger by the v5
reader.

**Acceptance evidence (contract gate, not feature gate):** one commit contains public adoption, the
payload change **and** all four bumps; no commit exists where the new payload or mismatched-slot
capability is reachable under an old version; the package and Flutter consumer compile;
no-substitution games remain executable and deterministic; `Substitution` round-trips and malformed
JSON is rejected; rules validation ranges hold; `unsupportedEventSchemaVersion` is asserted for a v4
ledger; v1–v4 fixtures unchanged and verified by their pinned tests. T03 must **not** claim the v5
participation feature is operational: reducer acceptance is T04, simulator emission is T05, and any
unsupported path fails explicitly.

**Stop condition:** any need to split public adoption, the payload change or the version bumps across
commits, or any historical fixture edit — stop.

---

## T04 — Reducer participation state

**Purpose:** make the five replay-derived and validate every window.

**Prerequisites:** T03 green; DD-M004-06/07/08/09 confirmed.

**Authorized scope:** current-five state; window flag; W0/W1/W2/W4/W5 validation; eligibility and
continuation checks; pending horn-replacement obligation across `PeriodEnded`; ceiling exemption;
administrative loop bound.

**Acceptance evidence:** the negative-test list in `verification-plan.md` §3 all rejected with typed
codes; legal windows accepted in hand-built ledgers; shot-clock ceiling survives W1 and still rejects a
later illegal increase; no substitution at clock 0; eligibility after a substitution follows the
current five; the horn obligation follows the phase-aware P1/P2/P3 sequence, with `PossessionEnded`
restricted to the matching reason and possession and `periodEnd` allowed only after `DeadBallMiss` or a
retained foul; satisfied only by W5 (void after `GameEnded`); a live event before the W5 replacement and
any arbitrary `PossessionEnded` are rejected.

**Stop condition:** any need to alter generic clock or possession rules beyond the documented
exemption — stop.

---

## T05 — Simulator disqualification and emission

**Purpose:** detect disqualification and emit lawful replacements.

**Prerequisites:** T04 green.

**Authorized scope:** mutable on-court five; foul counting consistency with the reducer; W0/W1/W4/W5
emission; deterministic ranking; depleted continuation; horn deferral.

**Acceptance evidence:** games complete with substitutions; foul-outs per game > 0 on a search cohort;
five-player-roster fixture produces continuation and zero substitutions; no substitution at clock 0;
reducer accepts every emitted ledger; no PRNG draw added (draw-count assertion on a controlled phase).

**Stop condition:** emitted ledger rejected by the reducer, or duplicates/leaks of the on-court five.

---

## T06 — Minutes accounting

**Purpose:** derive `secondsPlayed` and enforce conservation.

**Prerequisites:** T05 green.

**Authorized scope:** `PlayerBoxScore.secondsPlayed`; interval derivation; conservation failure mode.

**Acceptance evidence:** exact conservation for regulation, overtime, W1 split possessions,
continuation games and five-player rosters; typed failure when a fixture is mutated to break totals; no
simulator-side minutes state. Hand-built fixtures must assert **exact seconds for every player**:
outgoing interval closes at the substitution clock, incoming interval opens at the same clock, unused
bench players stay at zero, two substitutions at one clock are handled, period and overtime boundaries
anchor correctly, and no interval is negative or overlapping. A fixture where a substitute records
points, rebounds and fouls is required.

**Stop condition:** conservation failure on a legal ledger.

---

## T07 — Canonical v5 fixture, determinism, equivalence

**Purpose:** pin v5 and prove replay.

**Prerequisites:** T06 green.

**Authorized scope:** new canonical ledger fixture; repeat-run identity; worker/caller parity;
v4-equivalence assertion for a no-disqualification seed; mutation suite.

**Acceptance evidence:** fixture digest pinned; 20-repeat identity; parity equality; equivalence diff
empty apart from version metadata.

**Stop condition:** any nondeterminism or unexplained equivalence diff.

---

## T08 — Fresh matched-seed cohort

**Purpose:** describe v5 outcomes without claiming realism.

**Prerequisites:** T07 green; owner approves cohort design.

**Authorized scope:** pre-registered seeds and matchups; per-seed paired differences against v4;
descriptive tables for disqualifications, substitutions, minutes; no post-treatment filtering.

**Acceptance evidence:** pre-registration recorded before running; paired mean and uncertainty;
first-divergence and substitution counts reported descriptively; no AC09/AC10 acceptance claimed.

**Stop condition:** any need to change the registered analysis after seeing results — stop.

---

## T09 — Results UI update

**Purpose:** show minutes and disqualification honestly.

**Prerequisites:** T08 evidence available; not a blocking dependency for coding, but acceptance needs
it.

**Authorized scope:** participants-only table (starters in slot order, tagged; substitutes in entry
order, tagged), minutes column, disqualification/continuation indicators, disclosure text including
that non-participants are not listed; existing navigation unchanged.

**Acceptance evidence:** widget tests at 360/393/430; no overflow; existing M003 tests green; a
substitute's row and production appear; starter/substitute distinction asserted; non-participant
disclosure asserted; disclosure also states the technical-foul departure.

**Stop condition:** any need to redesign navigation or theme.

---

## T10 — Acceptance report and owner review

**Purpose:** assemble evidence for the owner.

**Prerequisites:** T02–T09 complete.

**Authorized scope:** acceptance report; evidence index; limitations.

**Acceptance evidence:** AC-M004 matrix filled with PASS/FAIL/NOT MEASURED; commands and counts;
explicit non-claims.

**Stop condition:** unanswered owner decisions remain → report, do not freeze.
