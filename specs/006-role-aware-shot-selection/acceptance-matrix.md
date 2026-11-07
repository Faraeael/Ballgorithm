# Acceptance Matrix 006 — Role-Aware Shot Selection v1 (FROZEN — OWNER APPROVED 2026-11-07)

> **Status: FROZEN — OWNER APPROVED 2026-11-07.** Approved decisions DD-M006-01 through DD-M006-10 apply.
> Implementation is **NOT STARTED and NOT AUTHORIZED**; every acceptance row remains NOT RUN. No criterion may be marked PASS before the activation
> evidence, the pre-registered evaluation and the owner decisions.

| ID | Task | Requirement | Evidence required | Status |
|---|---|---|---|---|
| AC-M006-01 | T01 | The role signal is derived from existing attributes with **no position base**; no `Player` field, snapshot or generator change | Unit tests; diff review | NOT RUN |
| AC-M006-02 | T01 | Ranking is deterministic, tie-broken by canonical court-slot order, and recomputed from the five players on court at each shot | Repeat-run and substitution tests | NOT RUN |
| AC-M006-03 | T01 | The role is documented and tested as a weight-shaping classification, not a simulated ballhandler; turnover/foul actors keep their independent draw | Spec review; separation tests | NOT RUN |
| AC-M006-04 | T01–T03 | Dormant policy code changes no production behaviour: no version constant changes, production weights equal the v6 reference vectors, and no production call site invokes the new functions | Dormancy and source-scan tests; full existing suite green | NOT RUN |
| AC-M006-05 | T04 | Activation, `gameSimulationVersion` 7 and `gameFingerprintVersion` 5 land in one commit; rules 3, schema 3, duration 2 and `xorshift32-v1` unchanged | Constant assertions; commit inspection | NOT RUN |
| AC-M006-06 | T04 | v5 and v6 ledgers are rejected by the v7 reader with `unsupportedSimulationVersion`, never as schema errors | Typed rejection tests | NOT RUN |
| AC-M006-07 | T02 | For identical attribute vectors, a rank change alters raw usage by exactly the multiplier ratio and the neutral multiplier is exactly 1.0 | Controlled incremental-usage vectors | NOT RUN |
| AC-M006-08 | T02 | Identical attributes produce identical weights regardless of roster insertion order; raw weights stay ordered by rank before normalisation | Shuffled-roster and ordering tests | NOT RUN |
| AC-M006-09 | T02 | No player receives a multiplier below 1.0; an elite scorer ranked neutral keeps the same raw weight, with any normalised dilution reported rather than asserted as an ordering rule | Neutral-scorer test; report | NOT RUN |
| AC-M006-10 | T03 | The three weight uses the piecewise 70/30 ability curve; inside and midrange terms are unchanged | Weight vectors at the audit archetypes | NOT RUN |
| AC-M006-11 | T03 | Controlled normalized three shares meet: weak PG ≤ 40.0%, weak SG ≤ 41.0%, non-shooting C ≤ 15.0%, median within ±1.0 pp of v6 | Exact normalized table test | NOT RUN |
| AC-M006-12 | T03 | High-three forwards and centres retain ≥ 36.0% / ≥ 39.0% normalized three share; no position ban or role gate exists | Stretch-big vectors; source scan | NOT RUN |
| AC-M006-13 | T03 | No new random draws; documented per-branch draw order unchanged | Draw-order audit | NOT RUN |
| AC-M006-14 | T04 | Same input and seed produce identical v7 ledgers on repeat runs | Repeat-run byte identity | NOT RUN |
| AC-M006-15 | T04 | Dart VM and Chrome produce identical v7 results | Chrome suite with the IO test excluded and recorded | NOT RUN |
| AC-M006-16 | T04 | Emitted ledgers remain reducer-valid and accounting-conserving | Reducer acceptance; conservation | NOT RUN |
| AC-M006-17 | T04 | A v7 canonical fixture is pinned by digest with seed, lineups and plans | Fixture digest and header review | NOT RUN |
| AC-M006-18 | T04 | Every v1–v6 fixture file is byte-identical and never rebaselined; the v6 fixture joins the archive-parse list | File digests; git diff | NOT RUN |
| AC-M006-19 | T04 | Historical v6 generation is verified once at `68018db` in a detached worktree and recorded; the current suite does not re-run it | Checkpoint evidence record | NOT RUN |
| AC-M006-20 | T04 | v7 no-plan mode is deterministic and its intentional difference from v6 is documented; no v6/v7 byte or draw-count equality is claimed | Repeat test; difference record | NOT RUN |
| AC-M006-21 | T05 | Metrics expose FGA per player and per 36 actual minutes (minimum 240 s exposure for rate metrics) | Metric tests on a pinned fixture | NOT RUN |
| AC-M006-22 | T05 | Three-point share is reported by bucket (`<40`, `40–69`, `≥70`), using pooled attempt-weighted proportions within games | Controlled and generated-league reports | NOT RUN |
| AC-M006-23 | T05 | Role shares are attributed at shot time from replayed lineups; usage-policy effects are separated from zone-policy effects | Paired policy-on/off comparisons | NOT RUN |
| AC-M006-24 | T05 | Deterministic synthetic archetypes supply a genuine stretch-five when the generated league lacks one, without changing M001 generation | Fixture construction tests | NOT RUN |
| AC-M006-25 | T06 | Stage A pilot uses development seeds only and never inspects held-out seeds; it estimates variance, eligibility and sample size on predetermined roster-and-seed cases | Pilot record with fixed case list and variance | NOT RUN |
| AC-M006-26 | T06 | Stage B freezes the confirmatory protocol before any held-out run: metrics, denominators, eligibility, margins, sample size, bootstrap unit, multiplicity, failure rules | Owner-approved protocol committed first | NOT RUN |
| AC-M006-27 | T06 | Stage C runs the held-out evaluation once on the predetermined paired cases with 95% CIs from a bootstrap over paired games (not an independent-attempt formula); no case is selected, excluded or replaced after outcomes are seen | Held-out report; case-list diff | NOT RUN |
| AC-M006-28 | T06 | Eligibility minimums are enforced (weak-shooter combined FGA ≥ 20 per game; stretch-big PF/C with `threePoint ≥ 70` and ≥ 10 FGA); zero-attempt games are excluded per metric without replacement; cohort insufficiency reports INSUFFICIENT and stops for a separate owner decision | Eligibility report; INSUFFICIENT rule | NOT RUN |
| AC-M006-29 | T06 | Guardrails hold within frozen margins: eFG, points/game, TOV/100, FTA/game; accounting exact; reducer valid | Guardrail report | NOT RUN |
| AC-M006-30 | T06 | Owner review can observe the weak shooter, primary creator and stretch-big behaving differently in box scores, stated as directional only | Owner review record | NOT RUN |
| AC-M006-31 | T06 | Scope compliance: no fatigue, injuries, coaching AI, defensive schemes, trades, contracts, seasons, persistence, ball movement, turnover/assist redistribution, new PRNG or real-player data | File and API diff review | NOT RUN |

| AC-M006-32 | T04 | Shot-success coefficients are unchanged from v6: make, and-one, shooting-foul, free-throw, assist and block reference vectors are identical | Coefficient reference tests | NOT RUN |
| AC-M006-33 | T02 | Changing only the opportunity factor changes actor weights and never alters the zone-specific make probability for a fixed shooter, defender and zone | Layer-separation test | NOT RUN |
| AC-M006-34 | T03 | Changing only the derived preference weight changes zone selection and never alters shot accuracy or conversion coefficients | Layer-separation test | NOT RUN |
| AC-M006-35 | T01 | The same player is classified differently when his on-court teammates change; no persisted role follows him across lineups | Reclassification tests | NOT RUN |
| AC-M006-36 | T01 | Turnover, offensive-foul and non-shooting-foul actor selection remains separate from role/preference and unchanged in kind | Actor-path tests | NOT RUN |
| AC-M006-37 | T01–T04 | No new random draw stage is introduced and no `Player` schema or snapshot migration occurs | Draw audit; schema diff | NOT RUN |

## Explicit non-claims

- No NBA realism, calibration or win-rate claim.
- No inside-versus-midrange claim while event schema stays 3.
- No Android or device-performance claim.
- No claim that any generated league contains a genuine stretch-five without constructed fixtures.
- No claim that the primary-creation player must always out-shoot a secondary or neutral player.
- No claim that derived preferences are editable, ability-independent player tendencies.
- No claim of reproducing NBA 2K's proprietary probability formulas or coaching systems.

## Preserved historical records

M001–M005 acceptance records, frozen specifications and every v1–v6 fixture remain unchanged. This
draft supersedes nothing.
