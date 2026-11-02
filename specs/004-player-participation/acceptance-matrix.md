# Acceptance Matrix 004 — Foundational Player Participation

> **Status:** **DRAFT — NOT FROZEN.** All rows are **NOT RUN**; this matrix defines what evidence will
> be required, not what has been achieved.

| ID | Requirement | Evidence required | Status |
|---|---|---|---|
| AC-M004-01 | Five canonical slots, unique roster players, any slot may hold any eligible player; `defaultFor` maps players to their own positions | Contract tests for size, order, uniqueness, ownership, slot/position mismatch legality | NOT RUN |
| AC-M004-02 | `CourtLineup` replaces `ActiveLineup`; app runner and tests migrated | Build + full suites green; no `ActiveLineup` references remain | NOT RUN |
| AC-M004-03 | Default-lineup outcomes unchanged from v4 before substitutions | Full event-list identity for a no-disqualification game; **prefix** identity up to the first `Substitution` for games that contain one; digest equality apart from version metadata where paths are fully equivalent | NOT RUN |
| AC-M004-04 | `Substitution` round-trips and malformed forms are rejected with typed codes | Serialization tests; unknown type still rejected | NOT RUN |
| AC-M004-05 | Legal windows W0/W1/W2/W4/W5 accepted; all non-windows rejected | Hand-built ledger acceptance and rejection tests | NOT RUN |
| AC-M004-06 | No substitution at `gameClock == 0`; horn disqualification defers to W5 | Ledger tests, including made and missed final free throws at 0 | NOT RUN |
| AC-M004-07 | W0 requires the disqualified defender's team, precedes the first FT, and preserves group id, shooter, attempt count and total | Ledger tests asserting group fields unchanged | NOT RUN |
| AC-M004-08 | W1 preserves the pending shot-clock ceiling and still rejects a later illegal increase | Reducer tests; mutated ledger where next possession exceeds the ceiling | NOT RUN |
| AC-M004-09 | Sixth personal foul disqualifies immediately; mandatory replacement enforced when a bench player exists | Ledger tests for each window; rejection when replacement is missing | NOT RUN |
| AC-M004-10 | Continuation only when no eligible inactive roster player exists; five-player rosters continue on first disqualification | Ledger tests including a 5-player league fixture | NOT RUN |
| AC-M004-11 | Continuing disqualified players accumulate fouls with no technical foul; disclosure present | Ledger + UI disclosure test | NOT RUN |
| AC-M004-12 | Replacement ranking deterministic: same-slot preference, roster-order tiebreak, no PRNG draw | Unit tests; repeated runs identical; draw-count assertion | NOT RUN |
| AC-M004-13 | Tactical substitutions are ledger-valid but never emitted by the simulator | Reducer acceptance test; simulator output scan finds only `foulOut` | NOT RUN |
| AC-M004-14 | Administrative loop bound enforced per window | Ledger tests: repeated player in one window rejected | NOT RUN |
| AC-M004-15 | Minutes conservation exact for regulation, overtime, W1 splits, continuation and 5-player rosters | Accounting tests; typed failure on mutated totals | NOT RUN |
| AC-M004-16 | Per-input determinism and worker parity in v5 | Canonical fixture pinned; repeat identity; main-vs-worker equality | NOT RUN |
| AC-M004-17 | Matched-seed primary analysis over all games; no post-treatment filtering; descriptive divergence table | Pre-registered analysis record + results | NOT RUN |
| AC-M004-18 | Versions: sim 5, rules 3, schema 3, fingerprint 3; duration 2 and PRNG unchanged | Constant assertions; fixture version checks | NOT RUN |
| AC-M004-19 | Historical M001–M003 contracts and fixtures unchanged | Path diff empty for frozen artifacts; core suite count unchanged | NOT RUN |
| AC-M004-20 | Results UI shows minutes and disqualification/continuation without regressions at 360/393/430 | Widget tests; disclosure assertions | NOT RUN |
| AC-M004-21 | Scope compliance: no rotations, fatigue, technical fouls, user lineups, persistence | File/API diff review | NOT RUN |
| AC-M004-22 | Bench production is attributed: a substitute who scores, rebounds and fouls appears with those totals; no event is credited to the replaced player | Hand-built + simulated fixture; box assertions | NOT RUN |
| AC-M004-23 | Every roster player has a box row; non-participants are zero; team totals reconcile across starters and substitutes | Accounting tests over a substitute game | NOT RUN |
| AC-M004-24 | Results list starters and players who **entered** (by `Substitution`), tagged, with minutes; an entrant with zero seconds but recorded production is still shown; non-participants hidden and disclosed | Widget tests at 360/393/430 including a same-clock entrant | NOT RUN |
| AC-M004-25 | Historical compatibility is explicit: v5 rejects v4 ledgers with `unsupportedEventSchemaVersion`; v1–v4 evidence verified by pinned tests; v4/v5 comparison uses two pinned builds and normalized configuration | Typed-rejection test; pinned-fixture suites; comparison harness documentation | NOT RUN |
| AC-M004-26 | Public contract transition is atomic: public adoption, payload change and all four version bumps in one commit; no payload or mismatched-slot capability reachable under an old version | Commit inspection; barrel diff before/after T02; fingerprint digest assertions | NOT RUN |
| AC-M004-27 | `GameInput` holds starting lineups only; eligibility after a substitution follows the reconstructed current five; `isActive` is removed or renamed to starting-lineup semantics | Reducer tests: substituted player credited, departed starter rejected; API diff; call-site sweep | NOT RUN |
| AC-M004-28 | Horn disqualification records a pending obligation that survives `PeriodEnded`, is satisfied only at W5, is void after `GameEnded`, and does not become a general over-limit exemption; while pending, only the phase-aware P1/P2/P3 sequence is legal | Positive ledgers for all three paths (made last FT → `PossessionEnded(madeFinalFreeThrow)`; missed last FT → `DeadBallMiss` → `PossessionEnded(periodEnd)`; retained non-bonus foul → `PossessionEnded(periodEnd)`), each then `PeriodEnded` → `PeriodStarted` → W5; negatives for wrong `PossessionEnded` reason/possession, wrong order, live event before W5, and depleted continuation | NOT RUN |
| AC-M004-29 | T03 gate: compiles, no-substitution games deterministic, event JSON basic contract, no feature-operational claim, unsupported paths fail explicitly | Build + targeted tests; commit message and evidence wording review | NOT RUN |

## Explicit non-claims

- No NBA-level realism claim.
- No AC09/AC10 re-certification in M004.
- No Android performance, memory or battery measurement.
- No production or release authorization.
