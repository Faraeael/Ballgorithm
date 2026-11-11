# M008-T06B — Interactive Rookie Draft Experience

## Authorization and scope

Owner-authorized UI/application integration. Baseline `feat/m008-t06a-draft-execution`, `48837e3a5b6a1bc59d0cfb42d3dfbd8b4015e8c5`. Implementation branch `feat/m008-t06b-interactive-draft`. This specification records implementation contracts, not milestone acceptance.

Preserve T06A execution, schema v4, public-only scouting, immutable roster ownership, existing storage and M007 isolation. No T07, contracts, signing, roster intake, trading, timers, new AI, or new persistence layer.

## Audit and design

The old board accepted a career snapshot and rendered two read-only tabs. All entry paths must instead pass the same live `GmCareerController`. Offseason and draft surfaces rebuild from controller notifications. No widget copies career state back into storage.

T06A persists every selection before notifying listeners. Its start/human commands advance AI until the next human pick. Render committed history and current status directly; do not replay existing selections or add delays. Keep navigation enabled during progression. Controller serialization remains responsible for command integrity.

The app's home loading guard must not replace an active career subtree while draft commands run. Standalone setup/resume paths must establish a live controller rather than launch snapshot-only screens.

Prospect presentation accepts `PublicProspectScoutingView`, including visible attributes, overall, age, rank and estimated grade/range. It cannot receive hidden potential or development trajectory.

A read-only controller recovery-required getter exposes the existing uncertain-write latch. After write failure disable drafting, offer Reload Saved Career, and only allow subsequent progression after successful reconciliation. Never offer automatic retry of a failed selection.

Confirmed human choices close the detail sheet and reveal live committed order updates during AI progression. Successful completion opens Results; reopening an already-completed career also opens Results. No success is displayed before a committed controller state.

The two controller additions are read-only: `draftRecoveryRequired` exposes the existing failed-write latch, and `commandsSettled` lets standalone route owners defer disposal until queued saves finish. Neither changes execution or persistence semantics.

## Acceptance criteria

| ID | Contract |
|---|---|
| B01 | Opening Offseason opens the board through the live controller; entry labels reflect not-started, in-progress or completed state. |
| B02 | Before starting show franchise, both owned round picks, 90 available prospects and 60 selections. Explicit confirmation required; cancellation performs no writes. |
| B03 | Start only appears for unstarted drafts. In-progress drafts offer Resume Draft; completed drafts offer View Draft Results. |
| B04 | Header shows round, overall pick, selecting team and abbreviation, and committed progress out of 60. |
| B05 | Order shows all 60 selections, completed prospect identity, remaining picks, current-pick and human-ownership markers. |
| B06 | Prospect board retains name search and five position filters; all 90 prospects show public evaluation and availability. |
| B07 | Details use public scouting only. Draft Player is enabled only for an available prospect on a human turn while idle and reconciled. |
| B08 | Human confirmation shows name, age, position, overall, rank, estimated grade/range, round, overall selection and franchise. Cancel performs no write. |
| B09 | Confirm submits at most once, waits for controller persistence, then reflects committed state. No optimistic success or automatic human choice. |
| B10 | AI Drafting status and latest committed pick show team, pick, prospect, position and overall. No second decision engine or artificial delay. |
| B11 | Repeated taps and stale confirmations cannot execute duplicate picks or consume a later human turn. |
| B12 | Exit/re-enter and app restart preserve exact history, availability and current pick; no automatic replay of old selections. |
| B13 | Uncertain save failure offers explicit reload reconciliation, blocks blind retries, retains committed picks, and never resets/regenerates the career. |
| B14 | Completed results show 60 selections, 30 undrafted prospects, user drafted prospects, owned unsigned rights, round/pick metadata and complete history. |
| B15 | Unsigned draft rights are explicitly distinct from Active Roster Players; no signing controls or roster mutations. |
| B16 | All four starting situations stop at their human-owned first/second picks and support completing both rounds. |
| B17 | 360x640 and a larger mobile viewport support readable scrolling, accessible dialogs and touch targets without horizontal or RenderFlex overflow. |
| B18 | Focused interaction tests cover B01–B17; core/Flutter regressions and analyses pass. Existing M007 isolation remains exercised. |
| B19 | Practical Android walkthrough runs if a device/emulator is usable. Report actual environment and screenshots; widget tests are not device evidence. |

## Implementation plan

1. Convert board and offseason routes to controller ownership and keep the incumbent visual conventions.
2. Add explicit start/human confirmations, live status/order/prospect views, and completed results.
3. Connect existing recovery latch and reload behavior without changing storage or domain mechanics.
4. Add interaction tests for all starting situations, save failure, restart, duplicate taps, completion and public-data isolation.
5. Run existing regressions, inspect real mobile/runtime surfaces, record evidence, commit and push only the implementation branch.

## Verification protocol

Use deterministic seed `20261028` for representative interactions. Human choices are explicit test/user inputs. Compare complete roster snapshots before/after drafts. Exercise failed writes before/after possible commitment using existing controller/storage seams. Use widget tests at 360x640 and 393x852, plus actual runtime inspection. No simulation calibration cohort or Android performance claim.

## Rollback and compatibility

No schema or simulation version changes. Existing v4 and legacy decoding remain T06A-owned. UI rollback does not alter career data. Controller remains the sole mutation path. Preserve existing ValueKey contracts where behavior remains applicable; change obsolete snapshot-only test setup rather than adding compatibility shims.

## Implementation evidence

### Architecture and interactions

Both offseason entries and all setup/resume routes pass a live controller. The main app retains its career surface during draft writes. Standalone routes load their own controller and dispose it only after already-queued commands settle.

The board offers Order, Prospects, and Results tabs. Order and prospect lists build lazily; the results history is also lazy. Current and human-owned picks carry explicit text markers. Search, all five position filters, and available/selected filters remain usable throughout the draft.

Start and human selection require scrollable confirmations. Cancellation does not write. Confirmation captures the immutable career and rejects changes before submission. Repeated taps cannot resubmit the command. Human-turn Resume opens the prospect board; AI-turn Resume uses the existing controller progression.

Human confirmation reveals the live order while persistence and AI progression run. Every displayed selection comes from a committed controller state. Completed drafts open Results automatically, including after restarting. Details resolve the current public prospect by stable ID after reload.

Save failures expose Reload Saved Career and block drafting. Reload reconciles the persisted history without retrying the prior choice. Failed reloads remain visibly blocked.

### Acceptance and regression evidence

Environment: Windows x64; Dart 3.12.2; Flutter 3.44.2.

| Gate | Result |
|---|---|
| Core `dart.bat test` | PASS — 760 tests |
| Core `dart.bat analyze` | PASS — no issues |
| Core `dart.bat format --output=none --set-exit-if-changed lib test` | PASS — 136 files, zero changes |
| Root `flutter.bat test --machine` | PASS — 175 successful tests, zero errors; final runner event `success: true` |
| Root `flutter.bat analyze` | PASS — no issues |
| Root `dart.bat format --output=none --set-exit-if-changed lib test` | PASS — 46 files, zero changes |
| Android `flutter.bat build apk --debug --target-platform android-x64` | PASS |
| Impeccable detector on draft/overview sources | No findings |

Twelve new interactive tests cover the four complete drafts, both explicit human decisions, confirmation cancellation, committed AI updates, navigation during gated writes, duplicate and stale submissions, failed writes before/after commitment, reload failures, availability, public scouting, search/position/round filters, and both viewports. An additional route-lifecycle regression verifies pending saves finish after leaving an owned controller route.

Existing M007 filesystem/sentinel tests remain part of the passing regression suites. Complete serialized rosters remain unchanged across draft commits.

Initial verification exposed an existing contender-label overflow, ambiguous nested-scroll test finders, and obsolete exact-copy assertions. The label now wraps within available width; test gestures target the intended list/tab text. Obsolete wording assertions were deleted, not re-pinned. The superseded read-only board test was replaced by interactive coverage. A redundant real-I/O widget harness was removed; actual Android file-backed execution and existing filesystem/controller tests provide that evidence.

No production source changed during the complete 175-test run. A subsequent tab-padding-only adjustment addresses clipped labels at 360px; its focused layout check is recorded below.

### Practical Android walkthrough

Device: owned Android emulator, Android 13 / API 33, x86_64. Viewport overrides: 360x640 and 393x852, density 160. A physical Infinix device was detected but was not modified or used as verification.

1. Installed the debug APK into an emulator with no prior Ballgorithm installation.
2. Created Aurora Comets, Play-In Contender, career seed `1604126146`.
3. Opened Rookie Draft through the offseason entitlement entry.
4. Cancelled Start Draft and compared saved bytes: unchanged.
5. Confirmed Start Draft; the file contained 11 committed selections and the UI stopped at human pick #12.
6. Inspected Kai Rasmussen: SG, age 20, overall 64, public rank #4, estimated grade A-, estimated range 78–84.
7. Cancelled the human confirmation and compared saved bytes: unchanged.
8. Confirmed Kai at #12; AI advanced to 41 committed selections, next human pick #42.
9. Terminated and relaunched the Android process. The offseason entry displayed Resume Draft at #42; saved bytes and previous selections remained unchanged.
10. Filtered Available prospects and explicitly selected Andrei Calloway at #42: SG, age 19, overall 51, public rank #31, estimated grade C+, estimated range 57–63.
11. Results opened with 60 selections, 30 undrafted prospects, and two owned unsigned rights. Parsed the real save: 60 unique selected IDs, 60 rights, completed status, and exact original league/profile snapshots.
12. Terminated the process again, confirmed no process remained, and relaunched. Completed save bytes stayed identical; View Draft Results reopened the unsigned rights summary.
13. Installed the final application build without clearing data and rechecked completed results at both viewport sizes.

Screenshot captures were inspected under ignored build output `build/t06b-walkthrough/`, including the human confirmation and both completed-results layouts. This documented walkthrough is the durable repository evidence; build captures are not versioned assets.

An unrelated emulator Bluetooth crash dialog interrupted initial setup. Bluetooth was disabled only in the owned emulator for the walkthrough; this is not a Ballgorithm crash or physical-device result.

### Independent judgment and limits

JEV integration review: proceed, confidence 0.88. Final evidence review: publish, confidence 0.98, conditional on the final narrow tab-layout check. Neither verdict constitutes milestone owner acceptance.

No schema, simulation version, draft policy, roster category, or storage implementation changed. No signing, contracts, trades, timers, or T07 functionality was added.

Not measured: physical-device performance, frame-rate benchmarks, battery, memory, or full screen-reader/large-text certification. Existing single-process storage and copy-fallback limitations remain unchanged.

Next gate: owner review of T06B. Recommended subsequent work is a separately authorized T07 specification for unsigned rookie signing and validated roster intake; no implementation is authorized by this recommendation.

### Final narrow-screen confirmation

- `flutter.bat test test/interactive_draft_test.dart --plain-name "public scouting, all position filters" --reporter expanded`: **PASS — 2 tests**, 360x640 and 393x852.
- Rebuilt and installed the final APK after reducing tab-label padding. The final 360x640 capture shows all three labels without clipping; the completed career remained byte-identical.
- Restored emulator size/density and Bluetooth settings, then stopped the emulator launched for this task. The physical device was untouched.

### Changed files

```text
lib/app.dart
lib/features/career/career_controller.dart
lib/features/career/career_setup_screens.dart
lib/features/career/draft_board_screen.dart
lib/features/career/offseason_overview_screen.dart
lib/features/season/franchise_select_screen.dart
test/dynamic_roster_ui_test.dart
test/interactive_draft_test.dart
test/persistent_career_flow_test.dart
test/rookie_draft_flow_test.dart
specs/008-30-team-league/t06b-interactive-draft-spec.md
```
