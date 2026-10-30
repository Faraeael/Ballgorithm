# T013 — Acceptance-matrix coverage map

Baseline: `d1759a09bfa7cdb5630d5aff59bb2867bdd99c16` (`develop/m002`, T012).
Scope: T013 adversarial/property validation only. The frozen
`acceptance-matrix.md` is unchanged; this document maps its cases to evidence
without rewriting it.

Statuses: `COVERED_EXISTING` (already proven by T004–T012 tests),
`COVERED_T013` (added or strengthened by this task),
`PARTIALLY_COVERED` (some subcases proven, others recorded as gaps),
`GAP_FOUND` (no test yet), `DEFERRED_TO_OWNER_TASK` (separately authorized
future milestone). No row here is final acceptance; AC01–AC13 closure and owner
sign-off remain T017–T019.

| Matrix case | Status | Evidence |
|---|---|---|
| AC01 headless game | COVERED_EXISTING + T013 | `smoke_test.dart`, `game_simulator_test.dart` complete games, `domain_isolation_test.dart` import audit; T013 runs 200 headless games with no IO |
| AC02 validation | COVERED_EXISTING + T013 | `game_input_test.dart` (same team, foreign/cross-lineup player, invalid/unsupported rules), `ActiveLineup` tests; T013 adds unknown team (`teamNotFound`), empty game id, lineup size/order/duplicate, malformed ledger headers |
| AC02b seed identity | COVERED_EXISTING + T013 | `game_input_test.dart` seed 0 and alias fingerprint; T013 adds even/odd starters, negative and >32-bit raw seeds, alias gameplay equality, seed-0 simulation |
| AC03 determinism | COVERED_EXISTING + T013 | T012 golden fixture (VM/Chrome), `probability_model_test.dart` draw order and final-tick no-draw tests; T013 adds 20 identical simulations of the pinned input, pinned seed digests 1/99/20261029/42, 25 distinct-seed digests. The "opening possession consumes no PRNG draw" subcase is NOT directly counted: there is no public draw counter, so only canonical-output evidence attests it |
| AC04 clocks and overtime | COVERED_EXISTING | `t010_event_hardening_test.dart` (buzzer, dead-ball, bonus at horn, expiry precedence, ORB 14), `game_reducer_test.dart` (period bounds, ten-OT bound), `game_simulator_test.dart` (OT start/end, no post-horn possession), `t011_game_reliability_test.dart` (OT limit inclusive/exceeded) |
| AC04b A1 durations | COVERED_EXISTING + T013 | `probability_model_test.dart` (weights/brackets, draw order, final tick consumes no draw), `game_reducer_test.dart` live-phase-vs-shot-clock rejection, `t010` final-tick and shot-clock-zero releases; T013 adds exact type-draw boundaries 0/1499/1500/4499/4500/9999 mapped to the approved phases |
| AC05 causality | COVERED_EXISTING + T013 | `t010` rebound/and-one/FT continuity, `game_reducer_test.dart` possession transitions; T013 audits 200 generated games: one resolution per miss, no duplicate rebounds, possession continuity, no post-`GameEnded` events |
| AC06 accounting | COVERED_EXISTING + T013 | `game_accounting_test.dart` hand-authored ledgers, `game_simulator_test.dart` 20-game reconciliation; T013 checks every equation (player, team, period) on all 200 corpus games plus bench exclusion |
| AC07 event vocabulary | COVERED_EXISTING | Legal fixture per outcome in `t010_event_hardening_test.dart` and `game_reducer_test.dart`; T013 corpus exercises every event type (event mix recorded in `t013-adversarial-validation.md`) |
| AC07b ledger boundary | COVERED_EXISTING + T013 | `game_event_test.dart` schema/no-float/round-trip, `t012` canonical header; T013 mutation matrix rejects sequence, lifecycle, clock, possession, FT, rebound and turnover corruption with typed codes |
| AC07c attribution | COVERED_EXISTING + T013 | Accounting attribution tests; T013 causality audit enforces PG shot-clock attribution, offender attribution, assist/steal/block links and active-player ownership |
| AC08 boundedness | PARTIALLY_COVERED | Proven: configured exact/over event, zero-time and overtime limits (`t011`), reducer ten-OT bound, default cap values pinned, reducer rejects an over-cap ledger (`t013`). GAP_FOUND: the literal 50,001st event and the 65th consecutive unchanged-timestamp event are not exercised. Those subcases are recorded as gaps for T017/T018, not as passed |
| AC09 directional skills | DEFERRED_TO_OWNER_TASK | T014 paired-seed experiments; not started |
| AC10 calibration | DEFERRED_TO_OWNER_TASK | T015 ≥1,000-game calibration and human review; not started. T013's 200 games are correctness evidence only |
| AC11 M001 preservation | COVERED_EXISTING | `m001_regression_test.dart`, `deterministic_random_test.dart`, `generator_test.dart`, `validation_test.dart`; no `lib/` change in T013. The AC11 test counts (44/43/8) are the M001-era baseline and have been exceeded by later milestones, not weakened |
| AC11b fingerprint | COVERED_EXISTING + T013 | `game_input_test.dart` and `t012_canonical_ledger_test.dart`; T013 adds wide/negative raw seeds producing distinct fingerprints with identical normalized behaviour |
| AC12 performance | DEFERRED_TO_OWNER_TASK | T016 formal runtime/memory acceptance; T013 records only observed corpus wall time, which is not a T016 claim |
| AC13 scope | COVERED_EXISTING | `git status` shows only test and documentation changes; no Flutter UI, networking, persistence, season, AI GM or tactics code |

## AC08 subcase audit

| AC08 subcase | Status | Evidence / gap |
|---|---|---|
| 50,001st event fails | GAP_FOUND | configured-cap equivalent proven in `t011`; no 50,001-event fixture exists |
| 65th consecutive zero-time event fails | GAP_FOUND | configured-cap exact/over proven in `t011`; no 65-event same-timestamp fixture exists |
| 11th overtime fails | COVERED_EXISTING | `game_reducer_test.dart` ten-overtime bound; `t011` simulator limit tests |
| Invalid probability inputs fail | COVERED_EXISTING | `probability_model_test.dart`, `game_input_test.dart` |
| No NaN/Infinity | COVERED_EXISTING | integer basis points; canonical JSON float scan in `t012` |

## Matrix items with honest gaps

| Item | Status | Note |
|---|---|---|
| Invalid seed range policy | N/A — no policy exists | `GameValidationCode.invalidSeed` is declared but never emitted; `GameInput` accepts any integer seed and masks to 32 bits. T013 documents the actual contract instead of inventing a rule |
| `duplicatePlayerAcrossLineups` constructibility | COVERED_EXISTING, construction-limited | League validation forbids a player on two teams, so the code path is only reachable through foreign-team lineup reuse, which `game_input_test.dart` exercises |
| Declared-but-unused codes `wrongOffenseTeam`, `gameAlreadyStarted` | P3 | Reducer reports `wrongTeam` for the equivalent conditions; no consumer depends on the unused names |
| Literal default caps (50,000 events, 64 zero-time events) | GAP_FOUND (AC08) | The guard compares against `input.rules` with no separate constant, so configured-cap tests exercise the same code path, but the literal default boundary is not exercised. Deliberately recorded as a gap rather than fabricating a 50,001-event game for the appearance of complete coverage |
| Opening possession PRNG draw count | NOT DIRECTLY TESTED | No public draw counter exists; only canonical-output evidence (identical repeats, pinned digests) attests the property. Recorded as an unproven subcase of AC03 |
