# Tasks 004 — Foundational Player Participation

> **Status:** **DRAFT — NOT FROZEN.** No task below is authorized by appearing here.
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

## T01 — Specification package drafting — **DRAFT COMPLETE (2026-11-02); AWAITING OWNER REVIEW**

**Purpose:** produce a reviewable M004 contract package.

**Prerequisites:** M003 closed at `125e1e6`.

**Authorized scope:** documentation only — `specs/004-player-participation/{spec,plan,tasks,design-decisions,acceptance-matrix,verification-plan}.md`.

**Acceptance evidence:** six DRAFT documents; no source, test, fixture or version-constant change; no
push; internal contradiction review recorded.

**Stop condition:** owner review. Freezing requires a separate authorization.

---

## T02 — `CourtLineup` and slot semantics

**Purpose:** replace the fixed-five type and make positional bonuses slot-aware without changing
default-lineup behaviour.

**Prerequisites:** T01 frozen; owner decisions DD-M004-01/02 confirmed.

**Authorized scope:** new `CourtLineup`/`CourtSlot`; migrate `GameInput`, `GameResult`, `TeamOnCourt`,
probability-model positional lookups, app runner, test fixtures; remove `ActiveLineup`.

**Acceptance evidence:** contract tests for size, canonical order, uniqueness, roster ownership,
slot ≠ position legality; default-lineup event lists identical to v4 for representative seeds before
any substitution support exists; full core and Flutter suites green; no coefficient change.

**Stop condition:** any outcome difference for default lineups — stop and report.

---

## T03 — Event and version contract

**Purpose:** add `Substitution` and the pose of v5 identifiers.

**Prerequisites:** T02 green.

**Authorized scope:** `Substitution` event + `SubstitutionReason`; schema dispatcher; `GameRules`
`foulOutLimit` and `substitutionPolicyVersion`; version constants per `spec.md` §9; serialization
round-trip tests; ledger rejection of unknown types unchanged.

**Acceptance evidence:** round-trip and malformed-JSON tests; rules validation ranges; version values
asserted; v1–v4 fixtures still parse under their own versions (no silent migration).

**Stop condition:** any historical fixture requiring edit — stop.

---

## T04 — Reducer participation state

**Purpose:** make the five replay-derived and validate every window.

**Prerequisites:** T03 green; DD-M004-06/07/08/09 confirmed.

**Authorized scope:** current-five state; window flag; W0/W1/W2/W4/W5 validation; eligibility and
continuation checks; ceiling exemption; administrative loop bound.

**Acceptance evidence:** the negative-test list in `verification-plan.md` §3 all rejected with typed
codes; legal windows accepted in hand-built ledgers; shot-clock ceiling survives W1 and still rejects a
later illegal increase; no substitution at clock 0.

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
simulator-side minutes state.

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

**Authorized scope:** minutes column, disqualification/continuation indicators, disclosure text;
existing navigation unchanged.

**Acceptance evidence:** widget tests at 360/393/430; no overflow; existing M003 tests green; disclosure
asserts the technical-foul departure.

**Stop condition:** any need to redesign navigation or theme.

---

## T10 — Acceptance report and owner review

**Purpose:** assemble evidence for the owner.

**Prerequisites:** T02–T09 complete.

**Authorized scope:** acceptance report; evidence index; limitations.

**Acceptance evidence:** AC-M004 matrix filled with PASS/FAIL/NOT MEASURED; commands and counts;
explicit non-claims.

**Stop condition:** unanswered owner decisions remain → report, do not freeze.
