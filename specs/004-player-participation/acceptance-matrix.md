# Acceptance Matrix 004 — Foundational Player Participation

> **Status:** **DRAFT — NOT FROZEN.** All rows are **NOT RUN**; this matrix defines what evidence will
> be required, not what has been achieved.

| ID | Requirement | Evidence required | Status |
|---|---|---|---|
| AC-M004-01 | Five canonical slots, unique roster players, any slot may hold any eligible player; `defaultFor` maps players to their own positions | Contract tests for size, order, uniqueness, ownership, slot/position mismatch legality | NOT RUN |
| AC-M004-02 | `CourtLineup` replaces `ActiveLineup`; app runner and tests migrated | Build + full suites green; no `ActiveLineup` references remain | NOT RUN |
| AC-M004-03 | Default-lineup outcomes unchanged from v4 before substitutions | Event-list identity against v4 on representative seeds; digest equality apart from version metadata | NOT RUN |
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

## Explicit non-claims

- No NBA-level realism claim.
- No AC09/AC10 re-certification in M004.
- No Android performance, memory or battery measurement.
- No production or release authorization.
