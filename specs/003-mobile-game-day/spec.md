# Specification 003 — Mobile Game Day

> **Status:** **FROZEN — OWNER-APPROVED 2026-11-02** (`BALLGORITHM — M003 T020 SPECIFICATION FREEZE`).
> Implementation is not authorized by this freeze: T021–T025 each require separate owner authorization.
> **Frozen at:** `develop/m002`, baseline `6ca43b632e9229216a49966b35bb660c6651c2e8` (M002 ACCEPTED WITH CONDITIONS).
> **Predecessor contracts:** `specs/002-possession-simulation/` (frozen), `M002-OWNER-ACCEPTANCE.md`, `M003-BACKLOG.md`. None is amended by this document.

## 1. Purpose

Expose the accepted M002 possession engine to the player for the first time. Today the Flutter
application (`lib/`) contains three read-only screens — league list, roster, player profile — and
never references `GameSimulator`. A user can inspect a generated league but cannot play a game.

Mobile Game Day delivers one complete, honest, deterministic game loop on a phone:

```
League Screen → Play Game → Select Home and Away Teams → Confirm Matchup and Seed
              → Run Game → View Results → Return / Rematch
```

The milestone adds **presentation and orchestration only**. It does not change basketball behavior,
probability coefficients, draw order, event vocabulary, rules, version identifiers or frozen
fixtures.

## 2. What must be true for a user

1. Any two distinct teams in the generated league can be matched against each other.
2. The game outcome is reproducible: the same league, teams, lineups, seed and versions produce an
   identical ledger, fingerprint and box score.
3. A rematch advances the seed within its documented bounded cycle and stays equally reproducible.
4. The result screen reports final score, winner, per-period scoring, overtime count, team totals and
   per-player box scores — all derived from one validated `GameResult`.
5. The UI is usable at 360×640 logical pixels without horizontal scrolling or overflow.
6. The UI never presents unmodelled quantities as if they were measured.

## 3. Functional requirements

| ID | Requirement |
|---|---|
| R-01 | The League screen exposes a **Play Game** entry point that does not replace existing roster navigation. |
| R-02 | The setup screen allows choosing a home team and a distinct away team from `league.teams`. Selecting the same team for both roles is prevented in the UI; the core's `GameValidationCode.teamsNotDistinct` remains the authoritative guard. |
| R-03 | The active lineups are supplied by `ActiveLineup.defaultFor(team)` — no user lineup editing in this milestone. |
| R-04 | The setup screen displays the deterministic game seed that will be used for the current selection, and updates it when the selection changes. The rematch action that advances the seed lives on the result screen (R-11). |
| R-05 | `GameInput` is built with `GameInput.create(...)`, `GameRules.standard`, and a non-empty deterministic `gameId`. No hand-rolled validation substitutes for it. |
| R-06 | The game runs off the UI isolate on supported native platforms (Android, iOS, desktop). On web — a development target only — `compute()` runs inline on the current event loop, so no web frame-blocking claim is made. The game screen shows a loading state while the run is pending, and back navigation remains available throughout. |
| R-07 | Validation or runtime failures surface a typed, human-readable error with a retry path. No failure may leave a permanent spinner. |
| R-08 | The result screen shows: home and away team names and abbreviations, both totals, the winner, points per period, and the overtime count when `periodsPlayed > 4`. |
| R-09 | The result screen shows team statistics (FGM/FGA, 3PM/3PA, FTM/FTA, REB, AST, STL, BLK, TOV, PF, points) and per-player box scores for both teams. |
| R-10 | The result screen states the fixed-lineup and unmodelled-minutes disclosure (see §6). |
| R-11 | The result screen exposes **Return** (back to league) and **Rematch** (same teams, next seed) actions. |
| R-12 | All values shown come from the single returned `GameResult`; no widget recomputes or re-derives basketball quantities. |
| R-13 | The seed actually used is displayed with the result so a run can be reproduced. A derived seed of `0` is shown together with the core-normalized value `0x9E3779B9` that the PRNG actually consumed. |
| R-14 | Existing navigation, `ValueKey` contracts (`team-<id>`, `player-<id>`, `attribute-<name>`) and responsive behaviour are preserved. |

## 4. Non-goals (explicit)

- Season scheduling, standings, results history, save/load, persistence, database.
- Tactics, play-calling, substitutions, rotations, minutes, fatigue, foul-outs, injuries.
- Shot-selection tuning, role models, coefficient changes, new attributes.
- Any change to `packages/simulation_core/lib/**` simulation behavior, versions, fixtures or
  historical evidence.
- Play-by-play rendering, animations, sound.
- Any realism claim, any statistical calibration claim, any Android performance claim.
- Localization, theming redesign, accessibility overhaul beyond not regressing current behaviour.

## 5. Contracts used unchanged

| Contract | Value used |
|---|---|
| `gameSimulationVersion` | 4 |
| `gameRulesVersion` | 2 |
| `gameEventSchemaVersion` | 2 |
| `gameFingerprintVersion` | 2 |
| `gameActionDurationModelVersion` | 2 |
| PRNG | `xorshift32-v1` |
| `coreEngineVersion` / `snapshotSchemaVersion` | `1.0.0` / 1 (untouched) |

No version identifier changes in this milestone. The M002 acceptance evidence therefore continues to
describe the code that ships in M003, because the simulation code is unchanged.

### 5.1 Deterministic seed contract (frozen)

```text
teamIndex  = index of the team in league.teams          (0..7 for the generated eight-team league)
gameSeed   = (league.config.seed
              ^ (homeIndex << 16)
              ^ (awayIndex << 8)
              ^ (rematchIndex & 0xFF))
             & 0x7FFFFFFF
```

| Property | Value |
|---|---|
| Derived domain | `0 .. 0x7FFFFFFF` (31-bit) |
| Ordered matchups | 8 × 8, home and away not interchangeable |
| Rematch index | masked to the low 8 bits, advanced modulo 256 |
| Seeds per ordered matchup | exactly 256 |
| Rematch cycle | exactly 256 games, then repeats from rematch 0 |
| Reserved value | no derived seed can equal `0x9E3779B9` (`2654435769`), because it exceeds the 31-bit domain |
| Core zero normalization | `GameInput.normalizedSeed` maps raw `0` to `0x9E3779B9`; all other derived seeds normalize to themselves, so normalized seeds stay distinct across the bounded input domain |
| Fingerprint | `GameFingerprint.canonicalPayload` includes the raw `gameSeed` and `normalizedSeed`; different seeds therefore give different fingerprints, not necessarily different scoreboards |
| Core change | none — `game_input.dart` normalization is untouched |

Verified numerically over all 16,384 `(homeIndex, awayIndex, rematchIndex)` combinations for league
seeds `20261028`, `0`, `1`, `0x7FFFFFFF`, `0xFFFFFFFF`, `0x9E3779B9`, `0xDEADBEEF` and `12345`: 16,384
distinct derived seeds, 16,384 distinct normalized seeds, none equal to `0x9E3779B9`, minimal rematch
period 256, and swapped home/away always differ (`design-decisions.md` DD-MGD-04).

**UI disclosure required:** the result screen states that the rematch seed cycle repeats after 256
games, and a derived seed of `0` is displayed with its core-normalized value `0x9E3779B9`.

## 6. Mandatory disclosure wording

Shown on the result screen, verbatim or equivalent in meaning:

> Each team fields one fixed five-player lineup for the whole game. Minutes, substitutions, fatigue
> and foul-outs are not modelled, so per-player totals are whole-game totals, not per-minute rates.
> These results are a deterministic simulation, not a realism claim.

The result screen also states:

> Rematch seeds repeat after 256 games for the same matchup.

and, when the derived seed is `0`:

> Seed 0 is normalised to 0x9E3779B9 by the simulation engine.

## 7. Acceptance criteria

Each criterion is verified by the listed method. Counts and timings must be reported, not assumed.

| ID | Criterion | Verification |
|---|---|---|
| AC-MGD-01 | League → Play Game → setup → results → return works on the generated league | widget test with `BasketballManagerApp` |
| AC-MGD-02 | Home and away must differ; the UI blocks the duplicate choice | widget test; core guard cited |
| AC-MGD-03 | Same `GameInput` produces identical `inputFingerprint` and identical canonical ledger digest on the UI isolate and in the worker | parity test; digest via `GameEventLedger.toJson()` + SHA-256 |
| AC-MGD-04 | Rematch advances to a different derived seed inside the bounded 0–255 cycle, and the new result is reproducible from that seed. No outcome difference is asserted: a new seed changes the PRNG stream, it does not guarantee a different scoreboard. | seed unit tests (determinism, domain, swap and rematch distinctness, no normalization aliasing) plus one widget test asserting the displayed seed changes and the new `inputFingerprint` differs |
| AC-MGD-05 | Result screen values equal the values in the `GameResult` produced for that input | widget test asserting exact score, period rows and selected player/team cells |
| AC-MGD-06 | Period scoring covers regulation plus overtime and the overtime indicator appears only when `periodsPlayed > 4` | widget test on a fixture game with overtime |
| AC-MGD-07 | A thrown `GameValidationException` renders an error state with retry; the loading indicator is gone | widget test with an injected failing runner |
| AC-MGD-08 | No overflow or clipped critical text at 360×640, 393×852 and 430×932 portrait | widget test following `test/mobile_layout_test.dart` conventions |
| AC-MGD-09 | Disclosure text renders on the result screen | widget test |
| AC-MGD-10 | `flutter analyze` clean, full `flutter test` suite green, `packages/simulation_core` suite unchanged and green | command evidence in the acceptance report |

No new statistical cohort, calibration protocol or held-out evidence is required: no simulation
behavior changes. Existing core regression tests remain mandatory.

## 8. Open items resolved elsewhere

- Milestone naming and roadmap re-sequencing: `design-decisions.md` DD-MGD-01.
- Result transport and isolate mechanism: `design-decisions.md` DD-MGD-02/03, `plan.md` §3.
- Seed derivation: `design-decisions.md` DD-MGD-04, §5.1 above.
- Task sequence and per-task acceptance: `tasks.md`.
- Applied operational-status corrections: `documentation-debt.md`.

## 9. Traceability

| Decision | Implemented / verified by |
|---|---|
| DD-MGD-01 naming and re-sequencing | T020 (this freeze); `AGENTS.md` §3 status pointer |
| DD-MGD-02 direct `GameResult` transport | T021 (gate), T023 (runner) |
| DD-MGD-03 `compute()` worker | T021, T023 |
| DD-MGD-04 seed derivation and limits | T021 (seed tests), T022 (display), T024 (rematch + disclosure) |
| DD-MGD-05 no core change or version bump | every task's standing constraints; T025 report |
| DD-MGD-06 fixed-lineup disclosure | T024, T025 |
| DD-MGD-07 ephemeral results | T024 (no history), T025 (acceptance scope) |

| Acceptance criterion | Task |
|---|---|
| AC-MGD-01 | T022, T023 |
| AC-MGD-02 | T022 |
| AC-MGD-03 | T021 |
| AC-MGD-04 | T021, T022, T024 |
| AC-MGD-05 | T024 |
| AC-MGD-06 | T024 |
| AC-MGD-07 | T023 |
| AC-MGD-08 | T025 |
| AC-MGD-09 | T024 |
| AC-MGD-10 | T025 |
