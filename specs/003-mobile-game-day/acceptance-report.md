# M003 — Acceptance Report (provisional)

> **Status:** **TECHNICAL VERIFICATION COMPLETE — OWNER ACCEPTANCE PENDING.**
> M003 is **not accepted** by this document. Automated tests passing is not owner sign-off, realism
> approval, release readiness or an Android performance claim.
> **Date:** 2026-11-02
> **Baseline:** `develop/m002`, starting commit `415040bd037453cfdafbc70e152d795e508874ea`.
> **Authorization:** `BALLGORITHM — M003 T025 MOBILE UX VERIFICATION`.
> **Predecessors:** `spec.md` (frozen), `amendment-001-scroll-clarification.md`, `t021-isolate-gate.md`.

## 1. What M003 delivered

League → Play Game → team selection → matchup/seed confirmation → off-isolate simulation → results with
scoreboard, period scoring, team statistics, player box scores, disclosures → rematch or return.

No simulation behavior, coefficient, rule, clock, event schema, PRNG draw order, version identifier,
canonical fixture or M002 evidence was changed. `gameSimulationVersion` remains 4.

## 2. Environment

| Item | Value |
|---|---|
| OS | Microsoft Windows 11 Pro, 10.0.26100, x86-64 |
| Flutter / Dart | 3.44.2 stable (`c9a6c48423`) / Dart 3.12.2 |
| Widget-test platform | Dart VM (JIT), not AOT, not a device |
| League fixture | `LeagueGenerator(GenerationConfig(seed: 20261028))`, 8 teams × 12 players |
| Android device | Infinix X6882, Android 14 (API 34), arm64, wireless ADB |
| Android performance | **NOT MEASURED** |

## 3. Acceptance matrix

| AC | Requirement | Evidence | Result |
|---|---|---|---|
| AC-MGD-01 | League → Play Game → setup → results → return works | `game_setup_test` (Play Game opens setup), `game_flow_test` (confirm opens `GameScreen`), `game_results_test` (Return pops to root) | **PASS (test-level)**. One end-to-end test with the real worker completing to success is not asserted, because widget tests run under fake async while `compute` needs a real event loop; the real worker is proven separately in `game_runner_parity_test` and `game_flow_test`'s real-runner test. |
| AC-MGD-02 | Home and away must differ | Duplicate team is removed from the other role's options; `game_setup_test` asserts absence and option counts | **PASS** |
| AC-MGD-03 | Worker and caller produce identical fingerprint and ledger digest | `game_runner_parity_test` (6 tests) | **PASS** |
| AC-MGD-04 | Rematch advances the seed inside the bounded cycle; reproducible; no outcome guarantee | `game_results_test`: advance, reproducibility, wrap disclosure | **PASS** |
| AC-MGD-05 | Rendered values equal `GameResult` values | `game_results_test`: scores, winner, period cells, team stats, player stats | **PASS** |
| AC-MGD-06 | Period scoring and overtime | `game_results_test` regulation + deterministic overtime fixture | **PASS** |
| AC-MGD-07 | Typed error state, retry, no stuck spinner | `game_flow_test` (validation/unexpected errors, retry, duplicate guard, disposal) | **PASS** |
| AC-MGD-08 | No overflow at 360×640, 393×852, 430×932 | `game_mobile_layout_test` (13 tests across all widths, every state); device captures at 360 dp and at ~393/~430 dp via display density | **PASS (test-level + device observation)**. No overflow or page-level horizontal scroll observed on the device; heights at non-360 widths differ, see §7. |
| AC-MGD-09 | Disclosure text present | `game_results_test` disclosure test | **PASS** |
| AC-MGD-10 | Analyze clean, tests green, core suite unchanged | Commands in §4 | **PASS** |

## 4. Technical verification commands

| Command | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **71/71 passed** |
| `dart format --set-exit-if-changed lib test` | 19 files, 0 changed |
| `cd packages/simulation_core && dart analyze` | No issues found |
| `cd packages/simulation_core && dart test` | **351/351 passed** (M002 baseline) |
| `git diff --name-only -- packages/simulation_core` | empty |

## 5. Three-width layout findings

`test/game_mobile_layout_test.dart` exercises, at 360×640, 393×852 and 430×932:

1. league entry and Play Game;
2. team selection;
3. matchup summary and derived seed;
4. loading state;
5. validation error and retry;
6. regulation result;
7. overtime result;
8. team statistics;
9. away and home player tables;
10. rematch and return actions.

Assertions: no framework overflow exception at any step; the results page scrolls vertically only; the
only horizontal scroll views are the player tables (asserted per table as an ancestor relationship);
both player tables and the action buttons are reachable by vertical scrolling; the score, seed, tables
and controls build at every width.

Actions are exercised, not just located: at each width the suite taps **Rematch** (verifying a new
request, a new seed, the loading state, then a completed result) and taps **Return to League**
(verifying the root route and no remaining `GameScreen`).

Player identity is verified per width and per team, not once: for both teams at each of the three
widths, the statistics pane is scrolled to its right edge and the suite asserts the pane's offset
increased, all ten statistic cells exist for all five players, `PF` is on screen for every player, and
all five names and positions remain visible at unchanged screen positions. The long-name test adds the
truncation check (full text, `Text.overflow` null, no overflow, identity unmoved).

**Limits:** widget-test layout is not a device render. Font metrics, system text scaling, gesture
physics and real clipping are not measured by these tests.

## 6. Long-name usability

A JSON-round-trip league renames a player to `Bartholomew Maximilian Fitzgerald-Washington III`.
At 360×640 the tests assert: full name retained, `Text.overflow` null, the table's horizontal scroll
extent is greater than zero, dragging the table does not move the page's vertical position, and all five
rows remain configured in canonical order.

**Known awkwardness:** long names widen the player table and increase horizontal travel. No truncation
is reintroduced. Whether this is acceptable is a visual/owner judgement, not a technical result.

## 7. Visual review

Captured from the connected Android device; see `t025-visual-review.md` for the file list, findings and
incident disclosure. Path: `E:\ballgorithm-m003-review\screenshots\`.

| Artifact | Status |
|---|---|
| Setup, loading, regulation result, player tables, horizontally scrolled table, rematch result, overtime result at 360 dp | **CAPTURED** — loading was captured on a rematch attempt (seed `20327846`); two earlier rapid captures returned the result screen and were discarded rather than mislabelled |
| Representative ~393 dp and ~430 dp result layouts | **CAPTURED** (via display density; heights differ from 852/932 dp) |
| Error state on device | **NOT CAPTURED** — not reachable through the shipped UI |
| Long-name fixture on device | **NOT CAPTURED** — app generates corpus names only; covered by widget test |
| Readability, spacing, hierarchy judgement | **PENDING OWNER REVIEW** |

Four defects found during review were fixed: duplicated winner, team-statistics column order
inconsistent with the scoreboard, no affordance for the horizontally clipped player tables, and player
names scrolling out of view while statistics were read. The last fix rebuilt the player tables as a
two-pane layout with a frozen identity column (see `tasks.md` T025 UX correction); captures 20–24 show
the result at 360, ~393 and ~430 dp. Widget tests are not screenshots and no capture is presented as a
performance measurement.

## 8. Android validation

| Item | Status |
|---|---|
| Compatible device present | Infinix X6882, Android 14 (API 34), arm64, wireless ADB |
| Interactive smoke check | **PERFORMED** — debug APK installed; league → setup → game → result → sideways table scroll → rematch → overtime result, all by real touch on the device |
| On-device determinism cross-check | **MATCHED** — seed `20327844` produced 103–97 in 4 periods on device, identical to the widget fixture; rematch `20327845` produced 110–102 with 1 OT |
| Frame timing, memory, battery | **NOT MEASURED** |
| Release build, signing, store readiness | Not attempted (TD-08/TD-09 remain open) |

No Android performance claim is made, and desktop benchmark results are not extrapolated.

## 9. Status taxonomy

| Category | Items |
|---|---|
| Technical PASS | AC-MGD-01…AC-MGD-10 (with the AC-MGD-01 and AC-MGD-08 qualifiers above) |
| Visual review | Pending owner judgement |
| Device validation | Smoke check recorded separately; performance NOT MEASURED |
| Owner acceptance | **PENDING** |
| Historical/out of scope | M002 evidence, simulation v4 contracts, M004 work |

## 10. Remaining limitations

1. No end-to-end widget test drives the real worker from setup to a rendered result; the worker is
   proven by direct tests and the screens by injected runners.
2. Player statistics require horizontal scrolling, but the player identity pane (name + position) is fixed and always visible; the team statistics table is dense at 360 dp.
3. Rematch gives no explicit cycle-position counter; wrap is disclosed only when it happens.
4. No persistence: results vanish on return to the league (DD-MGD-07).
5. Android performance and release packaging unmeasured.
6. The player tables still cut the rightmost visible column mid-cell at 360 dp; the swipe hint was added, but an owner may prefer a stronger affordance (for example a fade or a partial-column design). Section headings scroll away; there are no sticky headers.

## 11. Owner decision requested

Accept M003 as **ACCEPTED WITH CONDITIONS**, request visual/layout corrections, or reject. This report
does not accept the milestone on its own.
