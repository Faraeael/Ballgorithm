# Acceptance Report 001

Closed 2026-10-28 after the project owner recorded the T012 human UX sign-off.
Commands were run from the repository root unless noted.

## Task status

| Task | Status | Evidence |
|------|--------|----------|
| T001 Flutter app + pure Dart package | Done | `pubspec.yaml`, `packages/simulation_core/pubspec.yaml`, web/windows scaffolding |
| T002 ids + immutable entities | Done | `lib/src/models/{ids,league,team,player,roster}` |
| T003 attributes 0–100 | Done | `player_attributes.dart`; bounds tests |
| T004 seeded PRNG + ordering | Done | `deterministic_random.dart`, pinned vectors, `design-decisions.md` D1 |
| T005 8 teams × 12 players | Done | `generator_test.dart` shape tests |
| T006 position coverage | Done | generator cycle; `LeagueValidator`; coverage tests |
| T007 validation + error codes | Done | `ValidationCode`, `LeagueValidator`, regression tests below |
| T008 deterministic/multi-seed tests | Done | `generator_test.dart` determinism group, 10-seed signature test |
| T009 Flutter screens | Done | `lib/features/league`, `lib/features/roster` |
| T010 navigation/widget tests | Done | `test/app_navigation_test.dart` |
| T011 analyzer/formatter/tests | Done | Results below |
| T012 human review | Done — PASS | Mobile readiness verified on a physical Android device (see below); project owner recorded the human UX sign-off on 2026-10-28 |

## Acceptance criteria

| AC | Result | Evidence |
|----|--------|----------|
| AC1 same seed/config/version → identical snapshot | Pass | determinism tests; snapshot equality after JSON round trip |
| AC2 different seeds → distinct attributes | Pass | 10 seeds → 10 distinct content signatures; 32-bit seed collision is documented, not a failure of the tested range |
| AC3 8 teams, 96 distinct players, 12/team | Pass | shape tests |
| AC4 attributes 0–100 int, unique ids, one team per player | Pass | range test; id uniqueness and ownership count tests |
| AC5 invalid configs/rosters fail explicitly | Pass after P1 fixes | Originally overstated: accepted oversized configs crashed with `RangeError`; decoded snapshots accepted invalid config and coerced null/numeric team fields. Corrected and covered by the regression tests below. |
| AC6 headless Dart tests + widget navigation | Pass | `dart test` 44 passed; `dart test -p chrome` 43 passed; `flutter test` 8 passed (3 navigation + 5 mobile layout) |
| AC7 no Flutter/Flame/DB imports in domain | Pass | `domain_isolation_test.dart` scans `lib/`; manual import/dependency scan also clean |
| AC8 no gameplay/contracts/drafts/trades/online/Flame | Pass | no such modules; no runtime dependencies in the domain package |

## P1 hardening — original failure vs corrected behavior

| ID | Original failure (audit evidence) | Corrected behavior | Regression test |
|----|-----------------------------------|--------------------|-----------------|
| P1-1 | `playersPerTeam: 300` (8 teams) threw `RangeError: Invalid value: Not in inclusive range 0..1599` after config validation passed | `LeagueGenerator.generate` rejects `teamCount * playersPerTeam > namePairCapacity` with `ValidationCode.nameCapacityExceeded`; capacity is `firstNames.length * lastNames.length` | `validation_test.dart` “enforces unique-name capacity derived from the corpus” (last supported 200/team succeeds, 201/team rejected) |
| P1-2 | Snapshot with `team.id = null, name = null` decoded as id/name `"null"`; numeric id `12345` became `"12345"` | `League.fromJson` requires string id/name/abbreviation and throws `malformedJson` otherwise | `validation_test.dart` “rejects null, numeric and boolean team fields” |
| P1-3 | Zero-team snapshot with `teamCount: 0` and engine `9.9.9` decoded successfully | `League.create` runs `GenerationConfig.validateForEngine()`; `League` constructor is private, so create/fromJson are the only construction paths | “rejects invalid configuration decoded from a snapshot”, “rejects snapshots from an unsupported engine version” |
| P1-4 | `nextInt(0x100000001)` looped forever (`limit = 0`, probe produced no result within 3 s and left a live process) | `nextInt` rejects `max > 0x100000000` and `max <= 0` with `ArgumentError`; rejection sampling and output sequence below the bound are unchanged | `deterministic_random_test.dart` “supports the full 32-bit range and rejects larger bounds” (max 0, 1, 2^32, 2^32+1) |

Compatibility: the first player of the default seed (20261028) is still
`Aurora Comets / Jonas Cortez / SG` with the identical attribute map recorded
before the patch, and its full snapshot still serialises to 29263 bytes.
Pinned xorshift32-v1 vectors are unchanged.

## Exact command results

```
dart analyze                     (packages/simulation_core)  No issues found!
dart format --set-exit-if-changed lib test (package)         0 changed
dart test                        (packages/simulation_core)  00:00 +44: All tests passed!
dart test -p chrome test/deterministic_random_test.dart test/generator_test.dart test/validation_test.dart
                                                             00:00 +43: All tests passed!
flutter analyze                  (root)                      No issues found!
flutter test                     (root)                      00:12 +8: All tests passed!
flutter build apk --debug        (root)                      √ Built build\app\outputs\flutter-apk\app-debug.apk
adb install -r app-debug.apk     (Infinix X6882)             Success
```

`flutter build web` was verified before the hardening pass; it was not rerun
here. Its only warning was a cosmetic missing CupertinoIcons font (the app uses
Material icons).


## Mobile readiness (T012)

Target: Android phones first, portrait primary.

- Android project scaffolded in `android/` (applicationId `com.example.basketball_manager`, label "Basketball Manager").
- `android/app/src/main/AndroidManifest.xml:10` locks the activity to `portrait`; forcing the device to landscape rotation left the app at 1080x2460 (no landscape layout).
- `flutter build apk --debug` produced `build/app/outputs/flutter-apk/app-debug.apk` (140 MB) and installed on a physical Infinix X6882 (Android 14/API 34, 1080x2460 at 480 dpi = 360x820 logical, arm64, wireless adb).
- Device session: league screen listed all 8 teams including Cinder Bay Embers; taps opened the Aurora Comets and Cinder Bay Embers rosters (12 players each); the player profile showed all 12 attributes with readable labels and values; back navigation returned roster then league. `adb logcat` showed no `RenderFlex overflow`, `EXCEPTION CAUGHT` or `E/flutter` entries.
- Layout tests cover 360x640, 393x852 and 430x932 logical pixels: scroll to the last team, player and attribute, touch navigation and back at each size. An exhaustive 360x640 test opens all 8 rosters, taps all 96 player tiles, verifies each profile title, team header and scrolled attributes (through Basketball IQ), and returns to the roster. No overflow was recorded.
- Screenshots were captured from the device for each screen. A floating third-party video-call overlay covered part of the app bar in the captures; it belongs to another app and does not affect layout.
- Toolchain note: `flutter doctor` reports "Some Android licenses not accepted"; the debug build and install still succeeded.

Not verified: release APK/AAB build, Play Store packaging, emulator run (a real device was used instead), small-screen font-scale accessibility settings.

## Human sign-off (T012)

Recorded 2026-10-28 by the project owner. Result: PASS.

- Readable league, roster and player screens on Android.
- Understandable player attributes.
- Comfortable touch targets.
- Natural navigation.
- No blocking visual issues.

This sign-off covers UX judgement only; the automated and device evidence above
was rerun on 2026-10-28 and has not changed.

## Remaining technical debt

The audited P2 findings are preserved in `specs/technical-debt.md`
(TD-01 through TD-09). None of them block M001; TD-02/TD-03 should be closed
before persistent saves, and TD-08/TD-09 before any release build.

## Final verdict

**Milestone 001: GO.** All tasks T001–T012 are complete, AC1–AC8 pass, the P1
audit findings are fixed with regression tests, and the T012 human UX sign-off
is recorded. Remaining findings are tracked as technical debt.

**Milestone 002: not started and not authorized.** This close approves M001
only; starting M002 requires a separate explicit request from the project
owner.
