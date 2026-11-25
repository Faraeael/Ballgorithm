# M010 — Career Lineup & Rotation Integration Contract

**Status:** FROZEN — owner approved D1–D8 on 2026-11-25 (M010-T02 authorization). T02 and T03 implemented and approved for publication at M010 closeout (2026-11-25).
**Baseline:** `feat/m009-t05c-a-season-history` at `bceb8403b6a98c22fd43d5f96afaa0f6981bfe84`
**Scope:** bring the accepted M005 lineup and rotation contract into the persistent 30-team GM Career for the human franchise. No new rotation engine.

---

## 1. Existing reusable capabilities

| Capability | Location | Contract used by M010 |
|---|---|---|
| Starting five | `simulation/court_lineup.dart` | `CourtLineup.create(team, slotOrderedPlayers)` requires 5 unique roster players in PG..C slot order. **Slot ≠ primary position is allowed** (frozen M004 contract). `CourtLineup.defaultFor` picks the first player per primary position in roster order. |
| Playing-time plan | `simulation/rotation_plan.dart` | `RotationPreset {balanced, starterHeavy, custom}`; `TeamRotationPlan.create` stores integer seconds per player in canonical roster order. `RotationPlan.expandPreset` is pure integer arithmetic with no randomness. Team total is 14,400 s (240 min) and the per-player cap is 2,880 s. Remainder seconds go to starters in slot order, then to reserves in roster order. |
| Plan validation | `GameInput.validateLineupAndPlan` / `GameInput.create` | Typed codes: `invalidRosterSizeForRotation`, `foreignRotationPlayer`, `missingRotationPlayer`, `invalidRotationSeconds`, `invalidRotationTotal`, `starterTargetNotPositive`, `rotationPresetMismatch`, `foreignLineupPlayer`, `duplicateLineupPlayer`. |
| In-game policy | `simulation/rotation_policy.dart`, `game_simulator.dart` | Tactical swaps chase target deficits. Ties go to the same slot position first, then roster order. Foul-out replacement also uses slot position first, then roster order. Overtime allocation is derived from regulation targets. Mandatory substitutions take precedence. |
| Persisted strategy precedent | `season/franchise_strategy.dart` (M007) | JSON shape `{startingLineup, rotationPreset, rotationTargets}` and preset-inference rules for older saves. It binds to a `Team` at decode time and throws on a missing player, so it is **not** suitable as-is for career data that must survive roster changes. |
| Accepted slider behaviour | `lib/features/game/game_setup_screen.dart` (`_maximumAllowed`, `_setCustomTarget`, `_refreshBudgetMessage`) | Fixed 0–48 min scale, hard 240-min budget, drag clamping, fine-step rejection, only the edited player changes (M005 owner acceptance §3). The M007 `team_strategy_screen.dart` slider does **not** meet this standard: it has whole-minute steps and no budget enforcement. Do not reuse it. |
| Historical input evidence | `career/regular_season_game_input_evidence.dart` | Each native result stores its exact canonical input template (lineups and `rotationPlan` included), checked by SHA-256 against a league snapshot. History is **never re-derived** from current settings. The only re-derivation is the schema < 18 legacy path, which predates manual plans. |

## 2. Exact integration gap

Every career game input goes through **one** method, `RegularSeasonGameAdapter.createGameInput`. Its callers:

- `RegularSeasonRoundService` (single round and the batch loop);
- `PlayInGameService`;
- `PlayoffSlateService` and `PlayoffGameService` (playoff slates and single games);
- `GmCareerCodec._migrateV17` and `GmCareer.validate` for schema < 18 (legacy only).

That method always uses `CourtLineup.defaultFor(team)` and `RotationPreset.balanced` for **both** teams. `GmCareer` has no field for the human franchise's preferences, so no user choice can reach the simulator.

## 3. Proposed player experience

Entry point: a third sub-view in the Hardwood Command **TEAM** tab, **Lineup & Rotation**, next to *Roster & Depth* and *Cap & Contracts*. It applies only to the human franchise.

**Mode control (top of the view):** `AUTO` / `MANUAL`.

- AUTO shows the current computed default (read-only preview of the default starters and balanced minutes) and simulates exactly as today.
- MANUAL makes A and B editable.

**A. Starting Five.**
- Half-court graphic with five slot tokens, PG/SG/SF/PF/C.
- Tapping a slot opens a picker of **standard-roster** players.
- Players already starting are shown as "swap", so a swap never creates a duplicate.
- A player whose primary position differs from the slot gets an "out of position" badge; this is allowed by the engine contract (see open decision D1).

**B. Playing Time.**
- Preset selector: Balanced / Starter-heavy / Custom.
- Every standard player is listed with target minutes.
- Custom uses the accepted M005 slider behaviour: 0–48 min fixed scale, hard 240-min budget, independent sliders, ±10 s fine steps.
- Budget meter shows `used / 240:00`.
- Save is blocked while the total ≠ 14,400 s or any starter has 0 s; the validation code is shown in plain language.
- Switching Balanced → Custom keeps the expanded seconds (M005 preset-to-custom behaviour).
- Caption: "Targets guide substitutions; actual minutes vary with fouls, overtime and game flow."

**C. Depth Chart (display only in M010).**
- One column per position: the starter, then players whose primary position matches, ordered by target seconds descending, then roster order.
- Labelled: *"Preview of the rotation from your starters and minutes. The simulator uses starters and minute targets; ties go to roster order."*
- **What the engine uses today, with no engine change:** the 5 starters, per-player target seconds, and roster order for tie-breaks. Reordering reserves would change tie-breaks only by reordering the simulation roster, which changes the league snapshot. That is deferred (D3) and not offered as a cosmetic control.

Out of scope: live substitutions, play-calling, in-game coaching, separate playoff plans.

## 4. Control modes

| Mode | Human team input | AI teams |
|---|---|---|
| AUTO (default; existing saves) | `CourtLineup.defaultFor` + `balanced`, **identical to today**. | Unchanged: always the current default. |
| MANUAL | Saved starters + saved preset; custom targets used exactly. Preset expansion runs against the game-time standard roster. | Unchanged. |

A manual plan is pregame coaching. It applies to every game simulated after it is saved and never changes completed games.

## 5. Persistence & migration contract

**New core value type** in `career/career_rotation_settings.dart`: `CareerRotationSettings`.

```json
{ "mode": "auto" }
{ "mode": "manual",
  "starters": ["<pid PG>", "<pid SG>", "<pid SF>", "<pid PF>", "<pid C>"],
  "preset": "balanced" | "starterHeavy" | "custom",
  "customTargets": { "<pid>": <int seconds>, ... }  // only when preset == custom
}
```

- It stores stable `PlayerId` strings only; it is never bound to a `Team` at decode time.
- Keys and targets are sorted canonically.
- It validates structure on decode:
  - 5 unique starters;
  - `customTargets` present if and only if the preset is custom;
  - each value in `0..2880`.
- It does **not** validate roster membership on decode. That is a resolve-time check; see §6.

**Field:** `GmCareer.userRotation` (non-null, default `auto`), with `copyWith` and equality.

**Schema:** `GmCareerCodec.currentSchemaVersion` 25 → **26**.
- v1..v25 saves decode with `userRotation = auto`: lossless and deterministic.
- The `userRotation` key is rejected in saves below v26.

**Commands**, in `career_controller.dart` through the existing `_runCareerCommand` / `_saveCareerState` path:
- `updateUserRotation(settings)`
- `resetUserRotationToAuto()`
- `applyUserRotationRepair()`

Each command validates through the core resolver before writing. A failed save keeps the existing `draftRecoveryRequired` / reload behaviour, and the in-memory state is not advanced. Commands are rejected while a batch, playoff slate or season transition is running (`isLoading`).

**Season rollover:** `SeasonRolloverService` carries `userRotation` into Year N+1 unchanged. Validity is re-checked at the next regular-season entry (§6), because retirements and contract expiry happen at rollover.

**Archive / bundle:**
- `SeasonArchive` stores only season state, so archive digests are unaffected.
- Bundle export and import go through the codec, so the field travels with it.

## 6. Roster reconciliation rules

Eligibility stays **standard roster only**: the same filter `simulationLeagueFor` applies today. Two-way players, unsigned draft rights, free agents and retired players can never be starters or receive targets.

Roster changes happen only in `openingOffseason`: draft signing, free agency, clearance, hardship and rollover all require that phase. So the human roster is frozen while games are played.

**Resolver** (core, pure): `CareerRotationService.resolve(career, simulationTeam)` returns `(CourtLineup, TeamRotationPlan)` or a list of `RotationIssue`.

| Situation | Result |
|---|---|
| Starter left, retired, or became two-way | Issue `starterUnavailable(slot, playerId)`. |
| Custom target for a player no longer standard | Issue `targetPlayerUnavailable(playerId, seconds)`. The total then falls short of 14,400 s. |
| New standard player not in `customTargets` | Treated as 0 s. Valid, and flagged in the UI as "new, 0 min". |
| Preset plan (balanced or starterHeavy) | Re-expanded against the current roster every game. Only the starters can become invalid. |

**No silent repair, no silent loss:**

- The saved manual settings are kept unchanged until the user acts.
- The TEAM view and Home show a "Rotation needs attention" card listing the issues.
- **Repair proposal** (deterministic, shown before it is applied):
  - Each unavailable starter slot is filled by the first standard non-starter whose primary position matches the slot, in roster order. If none exists, the first standard non-starter in roster order.
  - Custom targets: the seconds of departed players are cleared. The user must rebalance to 14,400 s, or switch to a preset.
  - `applyUserRotationRepair` writes the proposal only after explicit confirmation.

**Gate:** `RegularSeasonEntryService.start` additionally requires that `userRotation` is `auto` or resolves without issues.
- Otherwise it throws `RegularSeasonEntryBlocked` with a rotation reason. The UI offers **Repair**, **Edit** or **Switch to Auto**.
- This is the only point where roster drift can happen before games, so in-season games never meet an invalid plan.

**Defensive invariant:**
- `GmCareer.validate` rejects `regularSeason`, `playIn` and `playoffs` phases whose manual `userRotation` does not resolve.
- The adapter **throws** rather than falling back to the default if resolution ever fails.

## 7. Simulator integration points

1. **The only authoritative path:** `RegularSeasonGameAdapter.createGameInput`.
   - If `homeTeamId` or `awayTeamId` is `career.userFranchiseId` and `career.userRotation.mode == manual`, the resolver builds that side's lineup and plan.
   - Every other side keeps exactly the current `defaultFor` + `balanced` code path.
2. Single round, batch (a loop over rounds), Play-In and playoff slates all call (1). Workers receive the `GmCareer`, so isolate paths need no extra plumbing.
3. **Determinism:**
   - No new randomness and no change to PRNG draw order.
   - AUTO produces byte-identical `GameInput` canonical JSON, and therefore identical fingerprints and results, compared with the baseline for the same career state.
   - `rotationPlan` is already part of the M005 canonical input, so **no simulation, rules, event-schema or fingerprint version change is required** (to be confirmed in T02).
4. **History:**
   - Completed regular-season, Play-In and playoff results keep their stored input templates and are validated by fingerprint. They are immutable regardless of later rotation edits.
   - The schema < 18 legacy re-derivation path stays default-only; such saves cannot contain manual settings.
5. **Unchanged rules:** foul-outs, overtime allocation, mandatory-first substitution precedence and tactical cooldowns. Targets are not a guarantee of exact minutes.

## 8. Fixture / version impact (requires owner approval in T02)

- The career JSON changes: `schemaVersion: 26` plus the `userRotation` key. Every **career-JSON SHA** golden changes, e.g. `t05c_d3c_t03a/t03b1` `baselineY2CareerSha` and `baselineY3CareerSha`.
- Archive digests and game input fingerprints are expected to stay unchanged in AUTO. T02 must prove this rather than rebaseline them.
- No M001 vectors, M002 goldens or simulation versions are touched.

## 9. Acceptance criteria (proposed)

| ID | Criterion |
|---|---|
| AC-M010-01 | v25 and older saves load with `userRotation = auto`. Encode → decode round-trips manual and auto settings losslessly at v26. |
| AC-M010-02 | AUTO: for the same career state, every regular-season, Play-In and playoff `GameInput` fingerprint equals the baseline adapter output. |
| AC-M010-03 | MANUAL: the human side's canonical input contains the saved starters and plan. AI sides are byte-identical to the AUTO output. |
| AC-M010-04 | MANUAL changes participation: a seeded game shows a different starters' box score and minute distribution from AUTO. A reserve with a 0 s target and no mandatory need records 0 s. |
| AC-M010-05 | Single round, batch, Play-In and playoff slate all use the saved plan. Verified per path through the input lineup. |
| AC-M010-06 | Invalid edits (duplicate starter, wrong total, starter at 0 s, ineligible player) are rejected with typed codes, and nothing is written. |
| AC-M010-07 | After an offseason departure, retirement or reclassification to two-way, the manual settings are kept, issues are reported, and regular-season entry is blocked until Repair, Edit or Auto. |
| AC-M010-08 | The repair proposal is deterministic, shown before it is applied, and written only on confirmation. |
| AC-M010-09 | Rollover carries `userRotation` into Year N+1. Validity is re-checked at the next season entry. |
| AC-M010-10 | Completed results, archives and history are unchanged by later rotation edits; stored-input fingerprint validation still passes. |
| AC-M010-11 | A save failure during a rotation command leaves the active save unchanged and surfaces the existing recovery flow. |
| AC-M010-12 | Editor: independent sliders, hard 240:00 budget and clamping match the M005 tests. No overflow at 360/393/430 dp. |
| AC-M010-13 | Determinism: a manual-plan round is identical on two runs and between the main thread and isolate workers. |
| AC-M010-14 | Android release: real gameplay with a manual plan; box-score minutes visibly follow the plan. No ANR or crash in logcat. |

## 10. Implementation plan and file scope

The architecture already funnels every game through one adapter, so **two tasks** are enough.

**T02 — Core contract, validation, simulator integration and controller commands (no UI).**
- New:
  - `packages/simulation_core/lib/src/career/career_rotation_settings.dart`
  - `packages/simulation_core/lib/src/career/career_rotation_service.dart`
- Modify:
  - `career/gm_career.dart` (field, copyWith, validate)
  - `career/gm_career_codec.dart` (v26)
  - `career/regular_season_game_adapter.dart`
  - `career/regular_season_entry_service.dart` (gate)
  - `career/season_rollover_service.dart` (carry)
  - `simulation_core.dart` (exports)
  - `lib/features/career/career_controller.dart` (3 commands)
- **No changes** to `src/simulation/*`, finance, market or draft services.
- Tests:
  - New: `packages/simulation_core/test/career/career_rotation_settings_test.dart`, `career_rotation_integration_test.dart` (AC-01..10, 13)
  - New: `test/m010_t02_rotation_controller_test.dart` (AC-11)
  - Approved rebaseline of the career-JSON SHA constants only.
- Gates:
  - core `dart analyze` / `dart format` / `dart test`;
  - Chrome core tests, because canonical serialization changes;
  - `flutter analyze`;
  - focused Flutter tests;
  - one full `flutter test --exclude-tags endurance`.

**T03 — Hardwood Command editor, focused UI tests and Android acceptance.**
- New:
  - `lib/features/career/career_rotation_view.dart`
  - `lib/features/game/rotation_budget.dart`: extract the pure M005 budget logic (`maximumAllowed`, clamped set, fine-step reject) and move `game_setup_screen.dart` onto it, so the two never drift apart. Existing M005 widget tests guard the move.
- Modify: `career_team_tab.dart` (third sub-view), `career_home_screen.dart` ("Rotation needs attention" card).
- Tests: `test/m010_t03_rotation_editor_test.dart` (AC-12), plus the existing M005 game-setup tests.
- Gates:
  - `flutter analyze`, format, full non-endurance suite;
  - release APK build;
  - Android manual-plan gameplay (AC-14). A few rounds plus one Play-In or playoff game is enough; no new full-season endurance run.

A separate T04 is unnecessary: the T03 Android acceptance covers it. Split T03 only if the extraction from `game_setup_screen.dart` meets resistance.

## 11. Extension points (not implemented)

- Coaching staff could later supply the AUTO default for AI teams (replacing `defaultFor` + `balanced`) through the same adapter branch.
- Morale, fatigue and injuries would feed resolver eligibility (`RotationIssue`).
- Trades would only add another roster-change source, which the existing issue/repair flow and season-entry gate already handle.
- Live coaching would need simulator changes and stays outside this contract.

## 12. Owner decisions (approved 2026-11-25)

| # | Decision | Approved outcome |
|---|---|---|
| D1 | Out-of-position starters | Allowed under the existing CourtLineup contract. No new positional penalty; the UI shows a badge only. |
| D2 | Invalid manual plan | Regular-season entry is blocked until Repair, Edit or Auto. No per-game fallback to AUTO. The adapter throws if a manual plan ever fails to resolve. |
| D3 | Depth ordering | Display-only in M010. Simulation roster order is unchanged. |
| D4 | Postseason plan | One plan for the regular season, Play-In and playoffs. |
| D5 | Mid-season edits | Allowed between rounds and slates for future games, only when no command, batch or transition is running. Concurrent edits are rejected, not queued. |
| D6 | Schema | Career schema v26 is authorized. Only career-JSON SHA goldens may be rebaselined, and only after AUTO equivalence is shown. Archive digests and game fingerprints are never rebaselined for the schema change. |
| D7 | New acquisitions in custom plans | 0 s until explicitly assigned. A player **absent** from `customTargets` is "unassigned"; an explicit `0` entry is an intentional zero. Edit commands must list every current standard player, so absence can only come from later roster changes. |
| D8 | Shared M005 slider helper | Approved for T03 (not T02). |

### T02 clarifications recorded at freeze

- **Malformed vs obsolete.** Malformed settings fail decoding with a `FormatException`: wrong types, unknown keys, not exactly 5 unique starters, `customTargets` present without `custom` (or missing with it), or values outside `0..2880`. A structurally valid manual plan whose player IDs no longer resolve against the standard roster is **obsolete**: it is kept unchanged and reported through `CareerRotationIssue`s.
- **Repair.** The repair proposal never redistributes custom seconds. Departed players' targets are dropped and unavailable starters are replaced (slot position first, then roster order). If issues remain (for example a budget shortfall, or a new starter with 0 s), the proposal reports them and `applyUserRotationRepair` refuses to write it; the user must edit or switch to AUTO.
- **Conflict check.** No conflict with existing invariants. Rosters change only in `openingOffseason`, so the season-entry gate plus the `GmCareer.validate` in-season invariant guarantee every simulated game resolves. Standard-only eligibility is unchanged.
