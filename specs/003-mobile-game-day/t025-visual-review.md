# T025 — Visual review (Android device)

> **Status:** captures recorded for owner review. This is **not** owner acceptance and **not** a
> performance measurement.
> **Date:** 2026-11-02
> **Build:** debug APK from `develop/m002` at the T025 working tree (after the two layout fixes below),
> `applicationId com.example.basketball_manager` (still the scaffold id — TD-08 open).
> **Screenshots:** `E:\ballgorithm-m003-review\screenshots\` (outside the repository).

## 1. Device

| Item | Value |
|---|---|
| Model | Infinix X6882 |
| OS | Android 14 (API 34), arm64 |
| Connection | wireless ADB |
| Physical panel | 1080 × 2460 px, density 480 → **360 × 820 dp** |
| Alternate widths | density 440 → ~393 dp wide (1080 ÷ 2.75); density 402 → ~430 dp wide (1080 ÷ 2.512) |
| Performance | **NOT MEASURED** (no frame timing, memory or thermal data) |

Widths other than 360 dp were produced by changing display density, so their heights (894 dp and
917 dp) differ from the nominal 852/932 dp test sizes.

## 2. Captures

| File | State | Width | Build |
|---|---|---|---|
| `01-league-360x820.png` | League list, Play Game tile | 360 dp | pre-fix (screen unchanged by the fixes) |
| `02-setup-empty-360x820.png` | Setup, nothing chosen, seed unset, Confirm disabled | 360 dp | pre-fix (unchanged) |
| `03-setup-ready-360x820.png` | Setup, RSC home / SLK away, "Silverlake Kestrels at Redstone Coyotes", seed `20327844`, Confirm enabled | 360 dp | pre-fix (unchanged) |
| `04-loading-360x820.png` | **Loading state** — spinner, matchup, "Simulating game · seed 20327846" (captured during a rematch) | 360 dp | post-fix |
| `07-result-top-360x820.png` | Regulation result: SLK 103 – RSC 97, winner, seed `20327844`, 4 periods, period table, team statistics | 360 dp | post-fix |
| `09-player-tables-360x820.png` | Player tables with per-table swipe hint; columns cut at FT | 360 dp | post-fix |
| `10-player-table-scrolled-360x820.png` | Table scrolled sideways; FT/REB/AST/STL/BLK/TOV/PF visible, page position unchanged | 360 dp | post-fix |
| `11-rematch-result-360x820.png` | Rematch result: seed `20327845`, SLK 110 – RSC 102, **1 OT**, 5 periods | 360 dp | post-fix |
| `17-ot-scoreboard-periods-360x820.png` | Overtime scoreboard and period table with OT1 | 360 dp | post-fix |
| `12-ot-periods-stats-360x820.png` | Team statistics tail and both player tables, overtime game | 360 dp | post-fix |
| `13-ot-player-table-360x820.png` | Player table, disclosures and both actions | 360 dp | post-fix |
| `14-result-393dp.png`, `18-result-top-393dp.png` | Result at ~393 dp | ~393 dp | post-fix |
| `15-result-430dp.png`, `19-result-top-430dp.png` | Result at ~430 dp | ~430 dp | post-fix |

Every file in this table was opened and checked before being listed. Nothing in the directory is
presented as a state it does not show.

## 3. Determinism cross-check on device

The device reproduced the widget-test fixture exactly:

| Fixture | Seed | Score | Periods |
|---|---|---|---|
| Widget test (home index 3 = RSC, away index 5 = SLK, rematch 0) | `20327844` | 103 – 97 | 4 |
| Device, same matchup | `20327844` | 103 – 97 | 4 |
| Widget test rematch 1 | `20327845` | fixture-dependent | — |
| Device rematch | `20327845` | 110 – 102 | 5 (1 OT) |

## 4. Findings and fixes

Reviewing the captures produced three defects, all fixed before the final captures:

| # | Finding | Fix |
|---|---|---|
| V1 | Winner appeared twice (row badge and `Winner:` line) | Removed the row badge; the explicit summary line remains |
| V2 | Team statistics ordered home-then-away while the scoreboard and period table are away-first | Team statistics now away-first, same as every other section |
| V3 | Player tables cut columns mid-cell with no affordance | Each table now carries "Swipe sideways for FT, REB, AST, STL, BLK, TOV and PF." |

Verified after the fixes: `flutter analyze` clean; `flutter test` 71/71; the captures above are from the
rebuilt APK.

## 5. Observations

1. No page-level horizontal scrolling and no paint/overflow artifacts were observed at any of the three
   widths.
2. Player tables scroll sideways independently; the page position is unchanged during the drag.
3. Full player names render (e.g. `Dante Lindqvist`, `Caleb Fairweather`, `Jonas Rasmussen`); no ellipsis.
4. The cut column at the right edge remains visible mid-cell even with the hint. It reads as
   "more columns to the right" only after the first swipe; an owner may still consider it awkward.
5. Section titles scroll away with the page; there are no sticky headers.
6. The loading state is real but lasts well under a second on this device. It was captured on a
   rematch attempt (seed `20327846`); earlier rapid captures returned the result screen instead, and
   those attempts were discarded rather than mislabelled.
7. Rematch produced an overtime game, which supplied the overtime captures without any seed input.

## 6. Not captured

| Item | Reason |
|---|---|
| Error state on device | Not triggerable through the shipped UI: the picker prevents invalid requests, and no fault-injection hook exists in the app. Covered by widget tests only. |
| Long-player-name fixture on device | The app generates names from the M001 corpus; the long-name fixture exists only in tests. Covered by widget tests only. |
| Android performance (frame timing, memory, thermals) | Not measured. No claim is made. |
| Release build / signed APK | Not attempted; TD-08/TD-09 remain open. |

## 7. Incident disclosure

While clearing a picture-in-picture video call that obscured early captures, `adb shell am force-stop
com.facebook.orca` was issued. That is not an acceptable way to clear a user's overlay and may have
ended an active call on the device. The overlay was subsequently left alone. The captures in §2 are
clean, but the incident is recorded here rather than hidden.

## 8. Owner decision

Accept the visual result, request further layout changes, or reject. The remaining judgement calls are
the mid-cell column cut (item 4) and the absence of sticky section headers (item 5).
