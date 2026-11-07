# M005 T06 — Proposed Acceptance Report and Evidence Index

> **Status:** **proposed — owner acceptance is pending.** This report does not accept M005, does not
> authorize T06 completion, merging, release or M006, and does not claim owner-observed evidence.
> **Prepared:** 2026-11-07 on `review/m005-t06-acceptance`, based on T05
> `730ede3f214fa2e5d8bb71f8596ae894d1f65777` (parent `fe85f7f`).
> **Baseline:** `develop/m002` `f1aa16ad…`, `main` `a431aeb5…` (unchanged).

## 1. Evidence classes

| Tag | Meaning |
|---|---|
| `[IMPL]` | Implementation test in this repository, re-executed in this session |
| `[T06-AUTO]` | Automated command run during T06 preparation |
| `[T06-WEB]` | Real Flutter app in a real Chromium browser, observed in this session — **provisional**, not an owner-approved device substitute |
| `[OWNER]` | Owner-observed walkthrough — **none recorded** |
| `[UNEXECUTED]` | Not run or not measured |

## 2. Runtime used

| Item | Value |
|---|---|
| Device target | Chrome 156.0.8078.81 (web, JavaScript) — no Android device or emulator was connected (`flutter devices` listed Windows desktop, Chrome, Edge only) |
| OS | Windows 10.0.26100.9711 x64 |
| Flutter | 3.44.2 stable, engine `04efd7c093d4e9281d5526ebcad6ecc60ba8badf` |
| Viewports | 393 × 852 CSS (walkthrough), 360 × 640 CSS (layout check) |
| Build | `flutter build web --release` (122.8 s) |
| Serve | `python -m http.server 8099 --bind 127.0.0.1` in `build/web` |
| Launch result | App rendered and was interactive. `flutter run -d web-server` (debug) did **not** boot on this Windows setup: the page stayed blank because the DDC module loader stalled. The release build was used instead; recorded as an environment observation, not an app defect. |

## 3. Walkthrough milestones `[T06-WEB]`

Screenshots are stored locally in `E:/ballgorithm-t06-evidence/` and are **not committed**.

| # | Milestone | Result | Evidence |
|---|---|---|---|
| 1 | Open Ballgorithm | PASS | `01-league.png` — generated “Fictional League 20261028”, 8 teams, seed 20261028 |
| 2 | Create/load generated league | PASS | League is generated at launch; no separate load step exists |
| 3 | Open Game Day | PASS | `02-matchup.png` |
| 4 | Select home and away | PASS | AUR (home) vs SLK (away), derived seed 20262308 |
| 5 | Select managed team | PASS | Home managed (`AUR`) exercised; away managed (`SLK`) exercised in `13-managed-away-setup.png` |
| 6 | Replace a default starter | PASS | PG Elias Vasquez → Teodor Halloran, `03-starters.png` |
| 7 | Balanced targets | PASS | `04-balanced.png` — starters 31:19, reserves 20:52 |
| 8 | Starter-heavy targets | PASS | `05-starter-heavy.png` — starters 38:43, reserves 15:29 (visibly different) |
| 9 | Custom preserves Starter-heavy | PASS | `06-custom-preserved.png` — custom opened at 38:43/15:29, not Balanced |
| 10 | Modify while keeping 14,400 | PASS | `08-custom-edited.png` — Teodor 37:43 (−1 m), Elias Vasquez 16:29 (+1 m), total 14400/14400 |
| 11 | Invalid total blocks confirmation | PASS | `07-invalid-total.png` — error `targets sum to 14460, expected 14400`, Confirm disabled |
| 12 | Restore valid plan and confirm | PASS | `18b-valid-confirm.png` (recovery path); game run from the valid 14,400 plan |
| 13 | Simulate complete game | PASS | `09-result-top.png`, `10-home-table.png` |
| 14 | Inspect result | PASS | AUR 117–103 SLK; MIN and TGT columns distinct; participation and disclosure visible |
| 15 | Rematch | PASS | `11-rematch-home.png` — seed 20262308 → 20262309, same lineup and target vector |

## 4. Gameplay evidence `[T06-WEB]`

- Game 1 (managed home, custom plan): AUR 117 – SLK 103, seed 20262308, 4 periods; period
  scores AUR 33/17/31/36, SLK 33/32/13/25.
- Substitution pattern: nine AUR players recorded minutes; starters 35:33–39:55, reserves
  10:31, 16:28, 17:22 and 4:17 entered. No AUR player reached the foul limit (max PF 6 on one
  reserve), so the visible bench minutes are rotation-driven, matching the automated tactical
  substitution evidence in AC-18/AC-20.
- Targets versus actuals are distinguishable and not equal, e.g. Teodor 37:43 target vs 37:29
  actual; Elias Vasquez 16:29 target vs 10:31 actual; the zero-target entrant shows `—`.
- Team conservation: the nine visible AUR minutes sum to exactly 14,400 seconds (5 × 48 min);
  the nine SLK minutes also sum to exactly 14,400.
- Managed-away flow: switching the managed side to SLK rebuilt the SLK five and plan; the run
  completed AUR 127 – SLK 109 at the same matchup seed (`14-managed-away-result.png`).
- Determinism, real app: returning to setup preserved the exact configuration; confirming it
  again produced an identical game (AUR 117–103, identical period scoring) at seed 20262308
  (`12-repeat-run.png`). This is repeat-run determinism, not a rematch.
- Rematch: seed advanced by exactly one step while matchup, starters and target vector stayed
  fixed; the result changed (AUR 98–77, `11-rematch.png`, `11-rematch-home.png`).
- Disclosure present verbatim: “Targets are best-effort. Foul-outs, disqualification rules and
  the limited dead-ball windows can change minutes.” plus the retained M004 limitations
  (`10-home-table.png`).

## 5. UX findings (do not redesign in T06)

1. **Minor defect — internal id in a user-facing error.** Reproduction: choose a valid matchup,
   Custom preset, replace a starter with a reserve whose target is 0:00. Expected: the message
   names the player. Actual: `starter player-6-10 must have a positive target`
   (`17b-zero-target-error.png`). Severity: low, confirmation correctly blocks. Affected: AC-30
   presentation only. Smallest correction: map player ids to names while rendering the message
   in `game_setup_screen.dart`; no core change.
2. **Recovery is manual, by design.** Fixing the zero-target starter requires +10 s on the new
   starter and −10 s on the removed starter to keep 14,400. Discoverable from the total
   indicator, but the error does not suggest the fix (`18-recovered-plan.png`,
   `18b-valid-confirm.png`).
3. **Name truncation at 360 dp.** Editor rows clip the position/role suffix, e.g.
   “Caleb Fairweather · …” and “Dante Lindqvist · PG…”. Full names remain readable
   (`15-setup-360.png`, `18-recovered-plan.png`).
4. **Large edits need repeated taps.** ±1 m and ±10 s meet the requirement; moving 10 minutes
   takes ten taps. Practical for small corrections, tedious for wholesale rewrites.
5. **Positive:** the playing-time section, total and confirm remain reachable without horizontal
   overflow at 360 × 640; returning from results preserves setup state.

## 6. Acceptance matrix — AC-M005-01 … 35

Statuses are limited to PASS / FAIL / NOT RUN / NOT MEASURED.

| ID | Status | Evidence |
|---|---|---|
| AC-M005-01 | PASS | `[IMPL]` `t01_rotation_plan_test.dart`: canonical home-then-away JSON, roster-order targets, insertion-order equality |
| AC-M005-02 | PASS | `[IMPL]` `t01_rotation_plan_test.dart` typed rejection matrix (unknown/duplicate/missing id, range, total, zero starter, preset mismatch) |
| AC-M005-03 | PASS | `[IMPL]` `t01` null-plan and both-team-plan tests; `t04_v6_fixture_test.dart` null-plan legacy |
| AC-M005-04 | PASS | `[IMPL]` `t01` preset vectors for n = 5…12 and the n < 5 rejection |
| AC-M005-05 | PASS | `[IMPL]` `t01` standard vectors, Balanced vs Starter-heavy |
| AC-M005-06 | PASS | `[IMPL]` `t01` short-period vector |
| AC-M005-07 | PASS | `[IMPL]` `t01` starter-first remainder test |
| AC-M005-08 | PASS | `[IMPL]` `t01`/`t012` fingerprint tests; plan present only when non-null |
| AC-M005-09 | PASS | `[IMPL]` `t01` fingerprint and lineup tests; `[T06-AUTO]` `game_runner_parity_test.dart` asserts a non-default five reaches `GameInput` and is not the default |
| AC-M005-10 | PASS | `[IMPL]` version constant assertions (simulation 6, fingerprint 4, rules 3, schema 3, duration 2, `xorshift32-v1`) |
| AC-M005-11 | PASS | `[IMPL]` T01 commit `5137d80` atomic payload + versions; `[T06-WEB]` build presents v6 behavior |
| AC-M005-12 | PASS | `[IMPL]` `t02` purity tests; `t03` zero-draw trace assertion |
| AC-M005-13 | PASS | `[IMPL]` `t02` integer expected/deficit tests |
| AC-M005-14 | PASS | `[IMPL]` `t02` thresholds at 720, 300 and floor-1 |
| AC-M005-15 | PASS | `[IMPL]` `t02` tie-break chains |
| AC-M005-16 | PASS | `[IMPL]` `t02` one-swap, cooldown and reverse suppression; `t03` caller-history test |
| AC-M005-17 | PASS | `[IMPL]` `t02` eligible-bench exclusions |
| AC-M005-18 | PASS | `[IMPL]` `t03` window scan (W1/W2/W4/W5 only, never W0) |
| AC-M005-19 | PASS | `[IMPL]` `t03` constructed foul-out collision at W1 with a due rotation |
| AC-M005-20 | PASS | `[IMPL]` `t03` reducer acceptance and clock-0/shot-clock negative fixtures |
| AC-M005-21 | PASS | `[IMPL]` `t03` conservation; `[T06-WEB]` both team minute sums equal 14,400 exactly |
| AC-M005-22 | PASS | `[IMPL]` `t03` paired preset test; `[T06-WEB]` Balanced 31:19 vs Starter-heavy 38:43 |
| AC-M005-23 | PASS | `[IMPL]` `t03` §8.4 vectors, fallback, depleted allocation |
| AC-M005-24 | PASS | `[IMPL]` `t03` overtime foul-out fixture seed 4329 and repeat runs |
| AC-M005-25 | PASS | `[IMPL]` `t03` five-player depletion test |
| AC-M005-26 | PASS | `[IMPL]` v6 fixture digest `7f0c3d2962f05a66ff54ad42b3a8d53059871ceca31ac1402cbc5c14e024aa12`; v1–v5 files unchanged |
| AC-M005-27 | PASS | `[IMPL]` `t04` null-plan event array equals the pinned v5 array (837 events, digest `c0332fb9…`) |
| AC-M005-28 | PASS | `[T06-AUTO]` planned worker/caller parity, repeat-run identity, Chrome core suite (see §7) |
| AC-M005-29 | PASS | `[IMPL]` `game_results_test.dart` rematch preservation; `[T06-WEB]` seed 20262308 → 20262309 with fixed lineup/targets |
| AC-M005-30 | PASS | `[T06-AUTO]` widget tests at 360/393/430, invalid plan blocks confirmation; `[T06-WEB]` invalid total and zero-target starter both disabled Confirm |
| AC-M005-31 | PASS | `[T06-AUTO]` `game_runner_parity_test.dart` transports lineups and plan into `GameInput`; absent lineup falls back to `defaultFor` |
| AC-M005-32 | PASS | `[T06-AUTO]` results/disclosure tests; `[T06-WEB]` MIN and TGT distinct, participation and disclosures visible |
| AC-M005-33 | **NOT RUN** | No physical Android device or emulator; no owner-approved substitute. The Chrome walkthrough is provisional evidence only (`[T06-WEB]`, §3–§4) |
| AC-M005-34 | PASS | `[IMPL]` M005 diff `f1aa16a..730ede3` touches only rotation plan/policy/window history, the simulator hooks, the app setup/results/runner and tests; no event type, rule, coefficient, PRNG, timeout or persistence change |
| AC-M005-35 | PASS | This report: statuses, commands, versions, seeds and digests; unexecuted claims are labelled |

### Totals

| Status | Count |
|---|---|
| PASS | 34 |
| FAIL | 0 |
| NOT RUN | 1 (AC-33) |
| NOT MEASURED | 0 rows; performance items below are not acceptance rows |

## 7. Automated verification `[T06-AUTO]`

| Command | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 100 passed, 0 failed |
| `dart analyze` (core) | No issues found |
| `dart format --set-exit-if-changed lib test` (core) | 78 files, 0 changed |
| `dart test` (core VM) | 547 passed, 0 failed |
| `dart test -p chrome …` (IO isolation test excluded) | 546 passed, 0 failed |

Fixtures: v6 ledger digest `7f0c3d2962f05a66ff54ad42b3a8d53059871ceca31ac1402cbc5c14e024aa12`;
v5 participation ledger `9b4244fbacd2f615a76724ce3e9885f04160e2fd9463ce13871bbde8685b4b8a`.
Seeds: league 20261028; walkthrough game 20262308; rematch 20262309.

## 8. Not measured / not claimed

- Android performance, memory, battery, large-text accessibility and physical-device behavior:
  **NOT MEASURED** — no device was available.
- NBA realism or calibrated foul rates: not claimed; AC09/AC10 are not re-certified.
- Owner-observed walkthrough: **none**; AC-33 stays NOT RUN until the owner performs it or
  approves a substitute.

## 9. Owner walkthrough steps

1. `cd E:\ballgorithm-dev` and `git checkout review/m005-t06-acceptance`.
2. `flutter pub get`.
3. Physical device: `flutter run -d <device>` (preferred for AC-33). Substitute path used here:
   `flutter build web --release`, then `python -m http.server 8099 --bind 127.0.0.1` inside
   `build/web`, and open `http://127.0.0.1:8099/` in Chrome at 360–393 dp width.
4. League → Play Game → home AUR, away SLK → keep AUR managed.
5. Replace the PG starter with Teodor Halloran.
6. Select Starter-heavy; read the targets; switch to Custom and confirm the same numbers persist.
7. Move one minute from a starter to a reserve and check the total stays 14400.
8. Add one extra minute to any row and confirm the total error and disabled Confirm; undo it.
9. Confirm, let the game finish, inspect MIN versus TGT, participation and the disclosure.
10. Rematch and check the seed advances while starters and targets stay fixed.
11. Record any deviation from §3–§5 in a new dated note; do not edit this report after acceptance.

## 10. Recommendation

**READY FOR OWNER REVIEW.** Automated verification is green at the reported counts. The real app
was exercised in Chromium and every workflow milestone behaved as designed, but the only remaining
acceptance gap is AC-M005-33: a physical-device or owner-approved substitute walkthrough, plus the
owner’s decision. M005 is not accepted by this document.
