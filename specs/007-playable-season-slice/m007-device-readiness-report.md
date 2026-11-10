# M007-T01/T02 Playable Season Stabilization & Device Readiness Report

- **Repository:** `Faraeael/Ballgorithm`
- **Worktree:** `E:\ballgorithm-dev`
- **Branch:** `fix/m007-final-save-safety`
- **Baseline Commit:** `89a33c474ba5a02393f69e31546bdc83c147f8e4`
- **Status:** **STABILIZED & WINDOWS PLAYTEST READY**

---

## 1. Defects Discovered and Exact Fixes

| # | Defect Identified | Root Cause | Exact Technical Fix |
|---|---|---|---|
| 1 | Unsafe relative save path | `main.dart` used relative path `ballgorithm_save.json`, which resolves to an arbitrary, non-persistent, or permission-denied directory on mobile/desktop. | Added `path_provider: ^2.1.6`. Updated `main.dart` to use `getApplicationDocumentsDirectory()`, creating a verified, persistent, application-owned documents directory save path (`$docsDir/ballgorithm_save.json`). |
| 2 | Save read swallowing all I/O errors | `FileSeasonStorage.read()` caught all exceptions and returned `null`. This treated permission errors, file lock errors, and read failures as an empty save, risking silent overwrite of existing player saves. | `FileSeasonStorage.read()` now explicitly checks file existence. Genuinely missing saves return `null`. Permission, path, or read errors throw typed `SeasonStorageException` to surface recoverable notices. |
| 3 | Non-atomic write and crash vulnerability | `FileSeasonStorage.write()` wrote directly to the active save file. A crash, power loss, or app termination during write destroyed the save file. | Implemented crash-resistant 3-stage atomic save protocol: (1) write and flush complete payload to `$path.tmp`; (2) move active file to `$path.bak`; (3) atomically promote `$path.tmp` to `$path`, deleting backup on success. `read()` automatically recovers from `.bak` or `.tmp` if promotion was interrupted. |
| 4 | Permissive loaded state deserialization | `SeasonCodec.decode()` lacked structural and progression validation, allowing corrupted files with missing fixtures, future completed games, or contradictory standings to load. | Added comprehensive validation in `SeasonCodec.decode()`: verifies league seed, validates exactly 14 rounds and 56 distinct fixtures, verifies past rounds are 100% completed and current/future rounds have zero completed fixtures, validates standings match archived fixture results ($W, L, PF, PA, STRK$), and verifies player totals reconcile with archived box scores. Throws `FormatException` on contradiction. |
| 5 | Permissive round commit matching | `SeasonController.commitRoundWithUserResult` accepted legacy matchup-derived IDs as substitutes for exact scheduled fixture IDs. | Strictly enforced exact fixture ID match (`result.input.gameId == fixture.id`). Legacy matchup IDs and exhibition games are rejected with `ArgumentError`. |
| 6 | UI thread freezing during background games | Controller synchronously simulated the other 3 round fixtures via `GameSimulator()` on the UI isolate, causing frame freezes on mobile devices. | Injected asynchronous `GameRunner` into `SeasonController`. Background fixtures simulate concurrently across worker isolates via `compute(_simulateGame, request)`, keeping the UI thread responsive during round advancement. |
| 7 | Unhandled commit failure and lost games | If storage write failed, user had to re-play the entire game. | Added `_pendingUserResult` and `retryPendingCommit()` in `SeasonController`. If persistence fails, state does not partially advance; the completed game is retained in memory, and the dashboard renders a "Retry Saving Round" banner allowing immediate retry without re-simulating. |
| 8 | File deletion swallowing exceptions | `FileSeasonStorage.clear()` caught all errors and concealed deletion failures. | Reports any `FileSystemException` as `SeasonStorageException` so storage deletion failures are not concealed. |
| 9 | Zero-byte or whitespace active save treated as missing save | `SeasonController.loadSeason()` checked `raw == null || raw.trim().isEmpty` and set `_state = null` without an error message, treating an existing empty file as a fresh first-launch. | `loadSeason()` now checks `raw == null` for a genuinely absent save. If `raw.trim().isEmpty`, it throws `FormatException('Save file exists but is empty or contains only whitespace.')`, surfacing a recoverable notice and preserving the file without deletion or silent overwrite. |
| 10 | Promotion failure leaving partial destination blocking backup restoration | If fallback copy-and-delete failed mid-stream, a truncated active save lingered, blocking automatic recovery from `.bak`. | Hardened `_replaceFile()`: deletes partial target upon copy failure. Hardened `FileSeasonStorage.recoverBackup()`: automatically recovers from `.bak` if the active file is corrupted, truncated, or unparseable. |

---

## 2. Supported Platform Matrix

| Platform | Persistence Mechanism | Status | Notes |
|---|---|---|---|
| **Android** | `path_provider` (`getApplicationDocumentsDirectory`) + `FileSeasonStorage` | **SUPPORTED** | Tested via headless VM/file persistence tests; release target. |
| **Windows Desktop** | `path_provider` (`getApplicationDocumentsDirectory`) + `FileSeasonStorage` | **VERIFIED RELEASE BUILD** | Built native release executable `build/windows/x64/runner/Release/basketball_manager.exe`. |
| **Linux / macOS / iOS** | `path_provider` + `FileSeasonStorage` | **SUPPORTED** | Clean pure Dart file I/O abstraction. |
| **Flutter Web** | `InMemorySeasonStorage` | **DOCUMENTED LIMITATION** | Web has no native `dart:io` `File`. In-memory storage is used for browser demonstrations. |

---

## 3. Save Recovery Guarantees and Limitations

### Guarantees:
1. **Never Silently Overwrite on Read Failure:** If the save file exists on disk but cannot be read due to OS permissions, locks, or corrupt bytes, `read()` throws `SeasonStorageException` or `FormatException`. The UI renders the error screen and preserves the file without deletion.
2. **Crash-Resistant Promotion & Intact Backup Preservation:**
   - Active file is never overwritten directly. Payload is written to `.tmp` and flushed.
   - Active file is backed up to `.bak` prior to promotion.
   - If an app crash occurs mid-promotion, the next `read()` detects the missing or corrupted active file, recovers `.bak` (or `.tmp`), restores it to active, and resumes without progress loss.
   - Partial target files created during failed replacement are cleaned up immediately so valid backups remain recoverable.
3. **No Partial Round Commits:** If background simulation or storage write fails, `_state` is retained at the current round. Standings and player totals do not partially advance.
4. **Retry Without Replay:** A finished user game is preserved in memory as `_pendingUserResult` upon save failure, enabling the user to retry persistence directly.

### Limitations:
- Single active save slot (`ballgorithm_save.json`).
- If underlying physical disk media is completely destroyed or has zero bytes free, OS write calls fail until disk space is freed.

---

## 4. Verification Evidence

### 4.1 Test Suites

| Suite | Scope | Executed | Passed | Status |
|---|---|---|---|---|
| `test/real_filesystem_persistence_test.dart` | Temporary filesystem persistence (atomic writes, crash recovery, 8-step lifecycle, strict fixture ID enforcement, corrupted active file recovery from backup, zero-byte file rejection, failure retry) | 12 | 12 | **PASS** |
| `flutter test` | Full Flutter test suite (navigation, flow, layouts, strategies, participation, real persistence) | 128 | 128 | **PASS** |
| `dart test` | Simulation Core pure Dart VM tests | 643 | 643 | **PASS** |
| `dart test -p chrome test/season/` | Core season tests on Chrome platform | 15 | 15 | **PASS** |
| `flutter analyze` | App static analysis | 0 issues | 0 | **PASS** |
| `dart analyze` (simulation_core) | Package static analysis | 0 issues | 0 | **PASS** |
| `dart format --set-exit-if-changed` | All Dart sources | 0 unformatted | 0 | **PASS** |

### 4.2 Native Windows Release Build Evidence

- Build command: `flutter build windows --release`
- Output: `√ Built build\windows\x64\runner\Release\basketball_manager.exe` (56.0s build time).
- Full executable directory:
  `E:\ballgorithm-dev\build\windows\x64\runner\Release\`
  Contents:
  - `basketball_manager.exe` (Application executable)
  - `flutter_windows.dll` (Flutter engine runtime)
  - `dartjni.dll` (Dart JNI runtime library)
  - `native_assets.json`
  - `data/`
    - `app.so` (Compiled Ahead-Of-Time application bundle)
    - `icudtl.dat` (ICU internationalization dataset)
    - `flutter_assets/` (Fonts, shaders, manifests, licenses)

---

## 5. Windows Playtest Handoff

### Exact Launch Command (Windows CMD or PowerShell):
```cmd
cd /d E:\ballgorithm-dev\build\windows\x64\runner\Release && basketball_manager.exe
```

### Save-File Location for Inspection and Backup:
```
%USERPROFILE%\Documents\ballgorithm_save.json
```
(Typically: `C:\Users\<username>\Documents\ballgorithm_save.json`)

### Manual Playtest Checklist:
1. **Launch application:** Execute `basketball_manager.exe`.
2. **Choose a franchise:** Select one of the 8 teams from the Franchise Selection screen and tap **Start Season**.
3. **Save starting five:** Navigate to the **Team** tab, change a starter or rotation preset/minutes, tap **Save Strategy**, and verify the success notice.
4. **Play Round 1:** Return to **Home**, tap **PLAY NEXT GAME**, watch the game load and render, verify box scores, and tap **Continue Season**.
5. **Verify score and standings:** Navigate to **Standings**, verify 1 game played for each team (4 wins and 4 losses across the league), and verify your franchise's record and streak.
6. **Exit application completely:** Close the window (Alt+F4 or window close button).
7. **Reopen and verify Round 2:** Relaunch `basketball_manager.exe`. Confirm dashboard loads directly into **ROUND 2 OF 14** with saved record and starting five preserved.
8. **Play Round 2:** Tap **PLAY NEXT GAME**, finish the game, tap **Continue Season**, and confirm dashboard advances to **ROUND 3 OF 14**.
9. **Confirm no duplicate results:** Check the **Schedule** tab: verify Rounds 1 and 2 are marked `COMPLETED` with distinct scores and no duplicate games.
10. **Report UX:** Note any visual anomalies, unexpected delays, or confusing labels.

---

## 6. Playtest Readiness Verdict

**VERDICT: PLAYTEST READY**
