# M004 Acceptance Report — Foundational Player Participation

> **Date:** 2026-11-03. **Baseline:** `3db63c7102a0c69befd8953a549600d3996ea615`
> (`develop/m002`, after AC-12 integration). **Scope:** documentation-only acceptance
> audit; no simulation, calibration, fixture, UI or specification change.
> **Decision:** ACCEPTANCE BLOCKED — 27 of 29 criteria have PASS evidence.
> AC-M004-15 (mutated-totals typed failure) and AC-M004-24 (zero-second entrant at
> 360/393/430) are NOT MEASURED. Final milestone acceptance cannot be claimed. See
> `limitations.md` for the required corrections and non-claims.

## Status legend

- **PASS** — supported by identified, successfully verified evidence.
- **FAIL** — contradicted by observed evidence.
- **NOT MEASURED** — evidence missing/incomplete or check not performed.

Command results are recorded separately from criterion status. Historical evidence is
cited as recorded at its own gate; later functionality is not used as proof of what an
earlier gate claimed.

## Criterion results

| ID | Criterion (abridged) | Status | Evidence |
|---|---|---|---|
| AC-M004-01 | Five canonical slots; unique roster players; any slot may hold any eligible player; `defaultFor` maps own positions | PASS | `court_lineup_test.dart`: "maps the five players to canonical PG..C slots", "accepts a player whose primary position differs from the slot", "rejects a wrong slot count", "rejects a duplicate player", "rejects a player outside the roster"; `t03_contract_test.dart`: "fingerprint uses ordered slot/player-id pairs". Commit `8618550`. |
| AC-M004-02 | `CourtLineup` replaces `ActiveLineup`; app runner and tests migrated | PASS | `grep -rn "ActiveLineup" lib test packages` → no matches on baseline; `8618550` deletes `active_lineup.dart` and migrates `game_runner.dart`; full suites green (see §Verification). |
| AC-M004-03 | Default-lineup outcomes unchanged from v4 before substitutions; prefix identity for substitution games | PASS | Seed 15 no-disqualification: `t03_contract_test.dart` "a no-disqualification game equals the pre-participation baseline" (839 events, digest `7a82d20e…`). Seed 42 prefix: `t07_canonical_participation_test.dart` "seed-42 prefix matches the historical v4 event array" against v4 build `c7f1d7a`, digest `0fa93f89…` (first 392 events). T08 Category A 11/11 full equality, Category B 189/189 prefix equality. |
| AC-M004-04 | `Substitution` round-trips; malformed forms rejected with typed codes | PASS | `t03_contract_test.dart` group "Substitution event contract": canonical JSON round-trip, tactical reason accepted, unknown reason typed rejection, missing player id rejection, "reducer rejects a Substitution with no open window". |
| AC-M004-05 | Legal W0/W1/W2/W4/W5 accepted; all non-windows rejected | PASS | `t04_participation_test.dart`: W5 acceptance tests, W1 acceptance, W0 acceptance, W2 acceptance, W4 acceptance, plus the 29-case rejection checklist mapping (see `verification-plan.md` §3 and the T04 test groups). |
| AC-M004-06 | No substitution at `gameClock == 0`; horn disqualification defers to W5 | PASS | `t04_participation_test.dart` "W0 cannot occur at clock zero", "P1 made final free throw resolves and replaces at W5", "P1 missed final free throw resolves and replaces at W5", "P2 retained foul resolves and replaces at W5". |
| AC-M004-07 | W0 requires disqualified defender's team, precedes first FT, preserves group fields | PASS | `t04_participation_test.dart` "wrong-team substitution is rejected on a disqualifying W0 foul", "W0 preserves the awarded free-throw group", "rejects a W0 substitution that alters the free-throw group". |
| AC-M004-08 | W1 preserves pending shot-clock ceiling and rejects later increase | PASS | `t04_participation_test.dart` "accepts a substitution and preserves the shot-clock ceiling", "does not consume the pending ceiling", "rejects a possession start above the pending ceiling". |
| AC-M004-09 | Sixth foul disqualifies immediately; mandatory replacement enforced when bench exists | PASS | `t04_participation_test.dart` "sixth foul awarding free throws opens W0", "mandatory foul-out replacement is accepted at W0", "rejects a missing mandatory replacement", "rejects replay while a disqualified player remains active"; `t05_emission_test.dart` "substitutions are foul-out only, lawful and positional". |
| AC-M004-10 | Continuation only with no eligible inactive roster player; five-player rosters continue on first disqualification | PASS | `t05_emission_test.dart` "a depleted roster continues without substitutions"; `t04_participation_test.dart` "allows depleted continuation with no eligible bench"; `t06_minutes_test.dart` "a depleted five-player roster plays every interval"; T09 "depleted continuation is distinguished from a foul-out". |
| AC-M004-11 | Continuing disqualified players accumulate fouls with no technical foul; disclosure present | PASS | Reducer has no technical-foul event or penalty (`grep -rni "technicalFoul" packages/simulation_core/lib` → none); depleted ledgers validate with further play in `t04`; disclosure asserts "Technical-foul penalties … are not modelled" — `game_results_test.dart` disclosure test and `game_mobile_layout_test.dart`. |
| AC-M004-12 | Replacement ranking deterministic: same-slot preference, roster-order tiebreak, no PRNG draw | PASS | `t05_emission_test.dart` "replacement selection consumes zero PRNG draws": real `GameSimulator` path with `ReplacementDrawTrace`; 4 seed-42 substitutions, 8 selections, every delta `0`; independent event-based oracle asserts the first same-position candidate in roster order (two cases with two same-slot candidates); sensitivity mutation (extra draw) failed with `Expected 0 / Actual 1`. "roster-order fallback selects the first eligible candidate": pinned 7-player-roster fixture (league seed 20261028, game seed 3, `ac12-fallback-3`), vacated SF, eligible bench `player-2-6`, `player-2-7`, no same-slot candidate, selected `player-2-6` (first roster order), observer matched, draw delta 0; sensitivity mutation (last candidate) failed as expected. Commits `f8371a805f9a3a86663a40897292d8540bc5dd6e`, `3db63c7102a0c69befd8953a549600d3996ea615`. Instrumentation is passive: one integer increment per PRNG draw; pinned ledgers, digests, version constants and PRNG identity unchanged. Not performance-benchmarked. |
| AC-M004-13 | Tactical substitutions ledger-valid but never emitted | PASS | `t03_contract_test.dart` "accepts the tactical reason" and "simulator emits only foul-out substitutions and they validate"; `t05_emission_test.dart` reason scan. |
| AC-M004-14 | Administrative loop bound per window | PASS | `t04_participation_test.dart` "rejects a second appearance by the same player in one window". |
| AC-M004-15 | Minutes conservation exact for regulation, overtime, W1 splits, continuation, 5-player rosters | NOT MEASURED | Positive conservation evidence passes: `t06_minutes_test.dart` (regulation, W1 split, same-clock, overtime, horn, depleted), `t07_canonical_participation_test.dart` replay seconds/team totals. The frozen evidence requirement also demands a "typed failure on mutated totals"; no committed test provides it. Feasibility analysis finds this unreachable through the public validated-ledger API: `GameStarted` fixes period 1 at `periodSeconds`; `PeriodStarted` requires the full `periodLength`, no open possession and resets the accounting anchor; clocks are monotonic and bounded; `PeriodEnded` requires clock 0; substitutions cannot move the clock and preserve five active players; `GameEnded` requires a closed final period. Accounting accrues each interval delta to exactly five active players, so the team total telescopes to `5 × Σ periodLengths` for every validated completed ledger. `EventAccounting` contains the `periodEndInvalid` `secondsPlayed` guard, but it is defence-in-depth and unreachable from the validated public entrypoint. No honest negative test can be written, and the frozen evidence requirement cannot be silently reinterpreted. |
| AC-M004-16 | Per-input determinism and worker parity in v5 | PASS | `t07_canonical_participation_test.dart` "20 repeated simulations reproduce the committed fixture" (full player/team projections, bytes and digest); `test/game_runner_parity_test.dart` 6/6 including fingerprint, ledger bytes, substitution identity, `secondsPlayed`, team stats, period points, conservation. |
| AC-M004-17 | Matched-seed primary analysis over all games, no post-treatment filtering, descriptive divergence | PASS | T08 pre-registration and execution: 200 pairs, seeds 20001–20200, four matchups; `specs/004-player-participation/t08/t08-summary.json`; independent review of the 4,312,412-byte archive. Descriptive only; see limitations. |
| AC-M004-18 | Versions: sim 5, rules 3, schema 3, fingerprint 3; duration 2 and PRNG unchanged | PASS | `t03_contract_test.dart` "version identifiers are the frozen T03 values"; `t07_canonical_participation_test.dart` header assertions; `game_versions.dart` constants; `prngImplementationId = xorshift32-v1`. |
| AC-M004-19 | Historical M001–M003 contracts and fixtures unchanged | PASS | `git diff --name-only d29d1ff..HEAD -- '*fixture*'` lists only the new T07 fixture; T012 v1–v4 and v5 provisional fixtures unchanged; historical fixture tests and `m001_regression_test.dart` pass in the recorded suites. "Core suite count unchanged" is not provable from this snapshot; historical fixture/content preservation is. |
| AC-M004-20 | Results UI shows minutes and disqualification/continuation without regressions at 360/393/430 | PASS | `test/game_mobile_layout_test.dart` 13/13 at the three widths (no overflow, disclosure, MIN, participant rows, frozen identity); `test/game_participation_test.dart` statuses and minutes. |
| AC-M004-21 | Scope compliance: no rotations, fatigue, technical fouls, user lineups, persistence | PASS | Source/API review on baseline: `grep -rniE "fatigue|rotation|technicalFoul|persistence|userLineup" packages/simulation_core/lib lib/features` returns only the disclosure sentence; simulator emits no tactical substitutions; no persistence dependency. |
| AC-M004-22 | Bench production attributed to the substitute; no credit to replaced player | PASS | `t06_minutes_test.dart` "a substitute keeps the points, rebounds and fouls they record" (points 2, rebounds 1, fouls 1; departed starter 0). |
| AC-M004-23 | Every roster player has a box row; non-participants zero; team totals reconcile | PASS | `t06_minutes_test.dart` all-roster rows, unused-bench zero assertions, per-team conservation; `t07` replay all 24 rows. |
| AC-M004-24 | Results list starters then entrants, tagged, with minutes; zero-second entrant visible; non-participants hidden and disclosed | NOT MEASURED | Committed evidence covers parts: `game_results_test.dart` "participants list starters then entrants, without duplicates"; `game_participation_test.dart` "zero-second entrant with production stays visible" (tall 430×4000 test surface); `game_mobile_layout_test.dart` at 360×640, 393×852, 430×932 using the ordinary simulated participation fixture. The frozen evidence requires the same zero-second entrant at all three mobile widths; no committed test combines them. The earlier combined check was transient and deleted, so it cannot count. Required permanent regression: pump the validated zero-second ledger at each of the three viewports and assert the row, `MIN 0:00`, the substitute label and no overflow. |
| AC-M004-25 | v5 rejects v4 ledgers with `unsupportedEventSchemaVersion`; pinned v1–v4 evidence; comparison via two pinned builds | PASS | `t03_contract_test.dart` "a v4 ledger header is rejected by the v5 reader"; historical fixture tests; T07 comparison against build `c7f1d7a` with normalized league/team/seed/rules (event arrays only; fingerprints never compared across versions); T08 same normalization. |
| AC-M004-26 | Atomic public-contract transition: adoption, payload, four version bumps in one commit; no old-version capability | PASS | Commit `8618550`: `ActiveLineup` deleted, `CourtLineup` payload adopted, `GameInput`/runner migrated, `gameSimulationVersion 4→5`, `gameRulesVersion 2→3`, `gameEventSchemaVersion 2→3`, `gameFingerprintVersion 2→3` in the same commit; v4 header rejected by v5 reader. |
| AC-M004-27 | `GameInput` holds starting lineups only; eligibility follows the reconstructed current five | PASS | `game_input.dart` exposes starting lineups; reducer maintains current five from events (`t04` "rejects an event crediting a departed starter after substitution", "accepts a live event by the entering substitute"); `isActive` has starting-lineup semantics only (grep). |
| AC-M004-28 | Horn obligation survives `PeriodEnded`, satisfies only at W5, voids after `GameEnded`; phase-aware P1/P2/P3 only | PASS | `t04_participation_test.dart` horn group: made final FT, missed final FT, retained foul, negatives (live event before W5, substitution outside W5, mismatched possession end); `test/game_participation_test.dart` made/missed FT horn fixtures and re-entry regression. |
| AC-M004-29 | T03 gate: compiles, no-substitution determinism, event JSON contract, no feature claim, unsupported paths fail | PASS (historical gate, T03-era evidence only) | At `8618550` (T03): build and targeted tests green; `t013_adversarial_game_test.dart` already contained "20 identical simulations of the pinned input are byte-identical" (no-substitution era); `t012_canonical_ledger_test.dart` "seed 42 reproduces the committed golden bytes and digest" reproduced the pinned v5 ledger; `t03_contract_test.dart` covered the substitution JSON contract, version constants, v4 rejection and unsupported paths; T03 evidence described a limited contract gate. The seed-15 full-equality test was added later in `ee50aca` (T04–T06 period) and is **not** used as T03-era evidence. |

## Totals

- **PASS: 27**
- **FAIL: 0**
- **NOT MEASURED: 2** (AC-M004-15, AC-M004-24)

## Gap history

- Resolved: AC-M004-12. The earlier blocked audit (`b389b9d6333dd97253dc6c4d2d44d724e5829962`)
  recorded it NOT MEASURED because the old test compared two identical runs. The integrated
  AC-12 branch adds the passive draw observer, the same-slot first-candidate tie-break and the
  seven-player roster-order fallback fixture. AC-12 is PASS.
- Open: AC-M004-15. The required typed failure on mutated minute totals is unreachable through
  the validated public API; the derivation is recorded above and in `limitations.md`. The
  frozen contract would need owner-approved amendment to accept an impossibility proof.
- Open: AC-M004-24. The combined zero-second-entrant-at-three-widths test is missing; the
  proposed permanent test is recorded above and in `limitations.md`.

Caveats recorded rather than hidden:

- AC-M004-19: frozen fixtures are unchanged (v1–v4 archives and M001 vectors); all 23 pre-M004 core test files still exist. The literal "core suite count unchanged" proxy does not hold because M004 adds tests: pre-M004 baseline `d833dd5` ran 351 VM tests, current snapshot runs 454 (Chrome 453). The increase is additive, not a historical test loss; the count comparison is recorded explicitly rather than treated as a regression.
- AC-M004-24's zero-second entrant at all three widths was verified by a transient, deleted local test.
- AC-M004-29 cites only T03-era evidence; the seed-15 regression (`ee50aca`) postdates T03 and is not used there.
- AC-M004-12's passive draw counter adds one integer increment per PRNG draw; no performance benchmark of that overhead exists.

## Verification executed for this report (2026-11-03)

| Command | Result |
|---|---|
| `flutter analyze` | PASS — no issues |
| `flutter test` | PASS — 78/78 |
| `dart format --set-exit-if-changed lib test` (app) | PASS — 0 changed |
| `dart pub get` (core) | PASS |
| `dart analyze` (core) | PASS — no issues |
| `dart test` (core VM) | PASS — 454/454 (final AC-12 verification; the earlier T10 pass was 453/453 before AC-12) |
| `dart format --set-exit-if-changed lib test` (core) | PASS — 0 changed |
| Chrome suite (excludes IO-only `domain_isolation_test.dart`) | PASS — 453/453 (final AC-12 verification; the earlier T10 pass was 452/452 before AC-12) |

Environment: Flutter 3.44.2 stable, Dart 3.12.2, Windows 11 (10.0.26100), Chrome 156, Infinix X6882 Android 14/API 34 for the device review.
