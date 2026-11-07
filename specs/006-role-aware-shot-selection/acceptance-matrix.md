# Acceptance Matrix 006 — Role-Aware Shot Selection v1 (DRAFT, rev 2)

> **Status: DRAFT — every row is NOT RUN.** No criterion may be marked PASS before the
> pre-registered evaluation and the owner decisions.

| ID | Task | Requirement | Evidence required | Status |
|---|---|---|---|---|
| AC-M006-01 | T01 | The role signal is derived from existing attributes with **no position base**; no `Player` field, snapshot or generator change | Unit tests; diff review | NOT RUN |
| AC-M006-02 | T01 | Ranking is deterministic, tie-broken by canonical court-slot order, and recomputed from the five players on court at each shot | Repeat-run and substitution tests | NOT RUN |
| AC-M006-03 | T01 | The role is documented and tested as a weight-shaping classification, not a simulated ballhandler; turnover/foul actors keep their independent draw | Spec review; separation tests | NOT RUN |
| AC-M006-04 | T01 | `gameSimulationVersion` 7 and `gameFingerprintVersion` 5 land atomically; rules 3, schema 3, duration 2 and `xorshift32-v1` unchanged | Constant assertions; fingerprint payload | NOT RUN |
| AC-M006-05 | T01 | v5 and v6 ledgers are rejected by the v7 reader with `unsupportedSimulationVersion`, never as schema errors | Typed rejection tests | NOT RUN |
| AC-M006-06 | T02 | Role multipliers change shooter usage as specified after normalisation, without changing the actor draw | Controlled usage-share table reproduced | NOT RUN |
| AC-M006-07 | T02 | Identical attributes produce identical weights regardless of roster insertion order | Shuffled-roster equality | NOT RUN |
| AC-M006-08 | T03 | The three weight uses the piecewise 70/30 ability curve; inside and midrange terms are unchanged | Weight vectors at the audit archetypes | NOT RUN |
| AC-M006-09 | T03 | Controlled normalized three shares meet: weak PG ≤ 40.0%, weak SG ≤ 41.0%, non-shooting C ≤ 15.0%, median within ±1.0 pp of v6 | Exact normalized table test | NOT RUN |
| AC-M006-10 | T03 | High-three forwards and centres retain ≥ 36.0% / ≥ 39.0% normalized three share; no position ban or role gate exists | Stretch-big vectors; source scan | NOT RUN |
| AC-M006-11 | T03 | No new random draws; documented per-branch draw order unchanged | Draw-order audit | NOT RUN |
| AC-M006-12 | T04 | Same input and seed produce identical v7 ledgers on repeat runs | Repeat-run byte identity | NOT RUN |
| AC-M006-13 | T04 | Dart VM and Chrome produce identical v7 results | Chrome suite with the IO test excluded and recorded | NOT RUN |
| AC-M006-14 | T04 | Emitted ledgers remain reducer-valid and accounting-conserving | Reducer acceptance; conservation | NOT RUN |
| AC-M006-15 | T04 | A v7 canonical fixture is pinned by digest with seed, lineups and plans | Fixture digest and header review | NOT RUN |
| AC-M006-16 | T04 | Every v1–v6 fixture file is byte-identical and never rebaselined; the v6 fixture joins the archive-parse list | File digests; git diff | NOT RUN |
| AC-M006-17 | T04 | Historical v6 generation is verified once at `68018db` in a detached worktree and recorded; the current suite does not re-run it | Checkpoint evidence record | NOT RUN |
| AC-M006-18 | T04 | v7 no-plan mode is deterministic and its intentional difference from v6 is documented; no v6/v7 byte or draw-count equality is claimed | Repeat test; difference record | NOT RUN |
| AC-M006-19 | T05 | Metrics expose FGA per player and per 36 actual minutes (minimum 240 s exposure for rate metrics) | Metric tests on a pinned fixture | NOT RUN |
| AC-M006-20 | T05 | Three-point share is reported by bucket (`<40`, `40–69`, `≥70`), separating weak-shooter volume from stretch-big volume | Controlled and generated-league reports | NOT RUN |
| AC-M006-21 | T05 | Role shares are attributed at shot time from replayed lineups, and usage-policy effects are separated from zone-policy effects | Paired policy-on/off comparisons | NOT RUN |
| AC-M006-22 | T05 | Deterministic synthetic archetypes supply a genuine stretch-five when the generated league lacks one, without changing M001 generation | Fixture construction tests | NOT RUN |
| AC-M006-23 | T06 | Metrics, development and held-out seeds, thresholds, CIs and multiple-comparison handling are frozen before any cohort | Protocol commit preceding the run | NOT RUN |
| AC-M006-24 | T06 | Weak-shooter pooled 3PA share decreases by the frozen margin and stretch-big pooled share is non-inferior, both with 95% CIs | Held-out evaluation report | NOT RUN |
| AC-M006-25 | T06 | Guardrails hold: eFG, points/game, TOV/100 and FTA/game within frozen margins; accounting exact; reducer valid | Guardrail report | NOT RUN |
| AC-M006-26 | T06 | Owner review can observe the weak shooter, primary creator and stretch-big behaving differently in box scores, stated as directional only | Owner review record | NOT RUN |
| AC-M006-27 | T06 | Scope compliance: no fatigue, injuries, coaching AI, defensive schemes, trades, contracts, seasons, persistence, ball movement, turnover/assist redistribution, new PRNG or real-player data | File and API diff review | NOT RUN |

## Explicit non-claims

- No NBA realism, calibration or win-rate claim.
- No inside-versus-midrange claim while event schema stays 3.
- No Android or device-performance claim.
- No claim that any generated league contains a genuine stretch-five without constructed fixtures.

## Preserved historical records

M001–M005 acceptance records, frozen specifications and every v1–v6 fixture remain unchanged. This
draft supersedes nothing.
