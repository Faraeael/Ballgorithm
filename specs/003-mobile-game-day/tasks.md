# Tasks 003 — Mobile Game Day

> **Status:** **FROZEN — OWNER-APPROVED 2026-11-02.** T020 is complete. T021–T025 are pending; each
> requires separate owner authorization. The sequence is locked: T021 must pass before T022–T024
> proceed.
> **Frozen at:** `develop/m002`, baseline `6ca43b632e9229216a49966b35bb660c6651c2e8`.
> **Authorization model:** each task requires its own owner GO. T020 is the design and freeze
> deliverable; T021–T025 require separate authorization.

## Standing constraints (every task)

- Do not modify `packages/simulation_core/lib/**` behavior, coefficients, rules, events, versions or
  fixtures. A change there invalidates this milestone's premise and requires a new specification.
- Do not run new calibration cohorts, do not create a simulation version, do not re-baseline any
  historical evidence.
- Preserve M001 generation and existing widget `ValueKey` contracts.
- Stop and report if a task would need a core change; do not widen scope silently.
- Record PASS / FAIL / NOT RUN / BLOCKED with the exact command and environment for every check.

---

## T020 — Specification and owner design review — **COMPLETE (2026-11-02)**

**Deliverables:** `specs/003-mobile-game-day/{spec,plan,tasks,design-decisions,documentation-debt}.md`.

**Status:** specification frozen and owner-approved 2026-11-02. No implementation code was written in
this task.

**Acceptance evidence:**

- The specification defines the full workflow, R-01…R-14, explicit non-goals and AC-MGD-01…AC-MGD-10
  with a verification method for each (`spec.md`).
- Milestone naming is recorded as re-sequencing, with the reason frozen M002 text stays untouched
  (`design-decisions.md` DD-MGD-01).
- Isolate feasibility covers options A/B/C, selects `compute()`, and records object-graph sendability
  as a static hypothesis pending T021 (`plan.md` §3, DD-MGD-02/03).
- Seed contract frozen with exhaustive 16,384-combination verification across eight league seeds
  (`spec.md` §5.1, DD-MGD-04).
- No file outside the milestone's own directory plus the authorized operational-status corrections was
  modified; no implementation file, test, fixture or historical evidence changed.
- No claim of proven isolate transport, Android performance or realism appears anywhere in the frozen
  set.

**Exit gate:** satisfied. T021 is the next task and still requires its own authorization.

---

## T021 — Isolate feasibility and deterministic parity gate — **COMPLETE (2026-11-02) — PASS**

**Evidence:** `t021-isolate-gate.md`. Verdict `ISOLATE TRANSPORT — PASS`: direct `GameResult`
transport works on the native Dart VM, typed `teamsNotDistinct` crosses from inside the worker, seed
domain verified over 16,384 bounded inputs × 6 league seeds. Added `lib/features/game/game_runner.dart`,
`lib/features/game/game_seed.dart`, `test/game_runner_parity_test.dart`, `test/game_seed_test.dart`.
Core untouched. T022–T025 remain pending and unauthorized.

**Scope:** `lib/features/game/game_seed.dart`, `lib/features/game/game_runner.dart`,
`test/game_seed_test.dart`, `test/game_runner_parity_test.dart` (names indicative).

**Acceptance (observable):**

1. A direct `GameSimulator().simulate(input)` and a run through the runner produce equal
   `inputFingerprint`, `homeScore`, `awayScore`, `periodsPlayed`, `possessions` and event count.
2. SHA-256 of `utf8(jsonEncode(ledger.toJson()))` is identical for both paths.
3. Both box scores are field-by-field equal, and each team's totals equal the sum of its player rows.
4. The second run of the same input through the runner is identical to the first (no cross-run state).
5. Worker-executed validation failure: calling the runner directly with identical home and away team
   ids completes with a typed `GameValidationException` containing
   `GameValidationCode.teamsNotDistinct`, raised inside the worker — not an opaque `RemoteError` or a
   generic exception. The runner builds the `GameInput` in the worker, so `GameInput.create` failures
   cross the boundary as well.
6. Seed derivation tests pass: determinism; equal inputs give equal seeds; swapped roles differ;
   consecutive rematches `0..255` are pairwise distinct; every value is within `0..0x7FFFFFFF` and
   never `0x9E3779B9`; normalized seeds are pairwise distinct over the bounded domain sample, proving
   no alias through the core's `0 → 0x9E3779B9` rule.
7. Recorded copy/execution overhead for the offloaded path on the test machine (informational; no
   mobile claim).

Setup-level duplicate-selection validation is verified in T022, not here. T021 must not depend on the
picker existing; its worker-side failure test calls the runner directly with the invalid request.

**Verdict required:** `ISOLATE TRANSPORT — PASS` or
`ISOLATE TRANSPORT — FAIL → DTO FALLBACK REQUIRED`. A FAIL stops T022–T024 until the owner decides
between Option B and Option C.

**Evidence:** `specs/003-mobile-game-day/t021-isolate-gate.md`.

---

## T022 — Team picker and game setup

**Scope:** `lib/features/game/game_setup_screen.dart`, entry point in
`lib/features/league/league_screen.dart`, `test/game_setup_test.dart`.

**Acceptance (observable):**

1. From the league screen, **Play Game** opens the setup screen; roster navigation is unchanged and
   still reachable.
2. All `league.teams` are selectable as home and away; selecting the same team for both is prevented
   and the confirm action is unavailable in that state.
3. The derived seed for the current selection is displayed and updates when either team changes; when
   the derived seed is `0`, the display states the core-normalized value `0x9E3779B9`.
4. Confirm navigates to the game screen with the chosen teams and rematch index; back navigation
   returns to setup without running anything.
5. Existing widget `ValueKey`s remain unique and unchanged; new keys follow the same pattern.
6. `flutter analyze` clean; the pre-existing widget tests still pass unmodified.

**Evidence:** new test names and counts recorded in the T025 report.

---

## T023 — Game runner, loading and error handling

**Scope:** `lib/features/game/game_screen.dart`, `lib/features/game/game_runner.dart`,
`test/game_flow_test.dart`.

**Acceptance (observable):**

1. Opening the game screen suggests a run is happening: a progress indicator is visible before the
   result resolves, and it is gone afterwards.
2. A successful run replaces the loading state with the result; no spinner and no error text remain.
3. An injected failing runner produces an error state showing a readable message and a retry action;
   after the failure frame no `CircularProgressIndicator` exists in the tree.
4. Retry re-enters loading and can succeed; repeated taps during a run do not start a second run.
5. Returning to the league from an error state works; no exception escapes to `FlutterError.onError`.
6. The screen renders exactly one of loading / error / result at any time.
7. Widget test with the real runner on the generated league completes within the test timeout.

**Evidence:** test names recorded; failure-injection path cited.

---

## T024 — Results, team statistics and player box scores

**Scope:** `lib/features/game/*_widgets.dart`, `lib/features/game/game_screen.dart`,
`test/game_result_test.dart`.

**Acceptance (observable):**

1. Final score, winner name/abbreviation and both team names render from the `GameResult`.
2. One period row per played period, including overtime periods; the overtime indicator appears only
   when `periodsPlayed > 4`. Verified on a fixture game with at least one overtime and on one without.
3. Team totals row set matches `TeamBoxScore` fields: points, FGM/FGA, 3PM/3PA, FTM/FTA, REB, AST,
   STL, BLK, TOV, PF.
4. Player rows exist for all five active players per team, in canonical PG→C order, and a spot-checked
   player's PTS/FGA/REB/AST equal the `PlayerBoxScore` values.
5. The disclosure text from `spec.md` §6 is present on the result screen, including the rematch cycle
   statement and, when applicable, the zero-seed normalization note.
6. Rematch from the result screen advances `rematchIndex` modulo 256, reruns, and shows the new
   displayed seed; the new `inputFingerprint` differs from the previous run. No assertion is made that
   the scoreboard differs — a different seed only guarantees a different PRNG stream. When the counter
   wraps, the result screen states that the seed cycle has repeated.
7. No widget computes a basketball total locally; values are read from `GameResult` (verified by
   inspection during review).
8. Tests assert exact numbers against a `GameResult` produced in the test, not against re-derived
   arithmetic.

**Evidence:** test names recorded; fixture game identity (league seed, teams, game seed) documented.

---

## T025 — Mobile layout verification and milestone acceptance

**Scope:** `test/game_mobile_layout_test.dart`, acceptance report
`specs/003-mobile-game-day/acceptance-report.md`, no production code except layout fixes found here.

**Acceptance (observable):**

1. Setup, loading, error and result states render at 360×640, 393×852 and 430×932 portrait with no
   overflow (`RenderFlex` / paint overflow) and no clipped critical text.
2. Player box-score table remains readable; if it scrolls horizontally this is stated explicitly and
   the score and period tables still do not.
3. `flutter analyze` clean; `flutter test` green with existing tests preserved; recorded counts.
4. `cd packages/simulation_core && dart analyze && dart test` green, count compared against the
   recorded M002 baseline, with any difference explained.
5. `dart format --set-exit-if-changed lib test` reports no changes.
6. Acceptance report maps AC-MGD-01…AC-MGD-10 to evidence and states `Android NOT MEASURED`.
7. Report states explicitly: no simulation behavior change, no version bump, no new calibration
   cohort, M002 acceptance unaffected.

**Exit gate:** owner acceptance of M003. No GO is implied by tests passing.

---

## Sequence and dependencies

```text
T020 (design) --owner approval--> T021 (isolate gate) --PASS--> T022 --> T023 --> T024 --> T025
                                                            \--FAIL--> stop, owner decision
```

T022 and T023 touch different screens and could run in parallel only after T021 passes; T024 depends
on T023's result state; T025 depends on all screens.

## Explicitly excluded from every task

Season scheduling, standings, results history, save/load, tactics, substitutions, rotations, minutes,
fatigue, foul-outs, injuries, shot-selection tuning, coefficient changes, new simulation versions,
new calibration cohorts, animations, play-by-play, localization, theming redesign.
