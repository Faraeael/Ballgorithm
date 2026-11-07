# Acceptance Matrix 006 — Role-Aware Shot Selection v1 (DRAFT)

> **Status: DRAFT — every row is NOT RUN.** This matrix defines intended evidence only. No criterion
> may be marked PASS before the pre-registered evaluation and the owner decisions.

| ID | Task | Requirement | Evidence required | Status |
|---|---|---|---|---|
| AC-M006-01 | T01 | Offensive role is derived from existing attributes and canonical slots; no `Player` field, no M001 snapshot or generator change | Unit tests; schema and snapshot diff review | NOT RUN |
| AC-M006-02 | T01 | Role ranking is deterministic and tie-broken by canonical court-slot order | Repeat-run ranking tests | NOT RUN |
| AC-M006-03 | T01 | The role is documented as a weight-shaping classification, never as a simulated possession ballhandler or turnover/foul actor | Spec text review; separation tests showing foul/turnover actors unchanged in kind | NOT RUN |
| AC-M006-04 | T01 | `gameSimulationVersion` 7 and `gameFingerprintVersion` 5 land atomically; rules 3, schema 3, duration 2 and `xorshift32-v1` unchanged | Constant assertions; fingerprint payload test | NOT RUN |
| AC-M006-05 | T01 | A v6 ledger is rejected by the v7 reader with `unsupportedSimulationVersion`, never as a schema error | Typed rejection tests | NOT RUN |
| AC-M006-06 | T02 | Role multipliers change shooter usage as specified, after normalisation, without changing the actor draw | Unit vectors; weight-bound tests | NOT RUN |
| AC-M006-07 | T02 | Identical attributes produce identical weights regardless of roster insertion order | Shuffled-roster equality tests | NOT RUN |
| AC-M006-08 | T03 | The three-point weight uses the approved piecewise ability curve; inside and midrange terms are unchanged | Weight vectors at median and extreme ratings | NOT RUN |
| AC-M006-09 | T03 | Low-`threePoint` players take materially fewer threes than v6 for the same attributes | Controlled archetype comparison against v6 formulas | NOT RUN |
| AC-M006-10 | T03 | High-`threePoint` forwards and centres retain meaningful perimeter volume; no position ban or hard role gate exists | Stretch-big vectors; source scan | NOT RUN |
| AC-M006-11 | T03 | No new random draws; per-branch draw order is documented and unchanged | Draw-order audit; stall/step tests | NOT RUN |
| AC-M006-12 | T04 | Same input and seed produce identical v7 ledgers on repeat runs | Repeat-run byte identity | NOT RUN |
| AC-M006-13 | T04 | Dart VM and Chrome produce identical v7 results | Chrome-compatible suite with the IO test excluded and recorded | NOT RUN |
| AC-M006-14 | T04 | Emitted ledgers remain reducer-valid and accounting-conserving | Reducer acceptance; conservation checks | NOT RUN |
| AC-M006-15 | T04 | A v7 canonical fixture is pinned by digest with recorded seed, lineups and plans | Fixture digest and header review | NOT RUN |
| AC-M006-16 | T04 | Every v1–v6 fixture is preserved byte-for-byte and never rebaselined | File digests; git diff review | NOT RUN |
| AC-M006-17 | T04 | Intentional v6 differences are listed; no v6/v7 byte-equality or draw-count equality is claimed | Difference record; report review | NOT RUN |
| AC-M006-18 | T05 | Ledger-derived metrics expose FGA per player and attempts per 36 minutes of actual play | Metric tests on a pinned fixture | NOT RUN |
| AC-M006-19 | T05 | Three-point attempt share is reported by `threePoint` bucket, separating low-ability perimeter volume from stretch-big volume | Controlled archetype and generated-league reports | NOT RUN |
| AC-M006-20 | T05 | Primary versus secondary role shot shares are reported and attributable to the usage policy separately from the zone policy | Paired policy-on/policy-off comparisons | NOT RUN |
| AC-M006-21 | T05 | Deterministic synthetic archetypes can supply a genuine stretch-five when the generated league lacks one | Fixture construction tests | NOT RUN |
| AC-M006-22 | T06 | Metrics, development and held-out seeds, thresholds and failure conditions are frozen before any cohort runs | Protocol file with pre-run commit reference | NOT RUN |
| AC-M006-23 | T06 | Owner review can see a weak shooter, a primary creator and a stretch-big behave differently in box scores and controlled comparisons, stated as directional only | Owner review record | NOT RUN |
| AC-M006-24 | T06 | Scope compliance: no fatigue, injuries, coaching AI, defensive schemes, trades, contracts, seasons, persistence, ball movement, turnover/assist redistribution, new PRNG or real-player data | File and API diff review | NOT RUN |

## Explicit non-claims

- No NBA realism, calibration or win-rate claim.
- No inside-versus-midrange claim while event schema stays 3.
- No Android or device-performance claim.
- No claim that any generated league contains a genuine stretch-five without constructed fixtures.

## Preserved historical records

M001–M005 acceptance records, frozen M002/M003/M004/M005 specifications and every v1–v6 fixture
remain unchanged. This draft supersedes nothing.
