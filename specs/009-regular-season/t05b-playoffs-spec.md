# M009-T05B — 16-Team Playoffs and Championship

**Status:** Owner-authorized implementation specification (2026-11-15).  
**Scope:** Explicit Play-In-to-playoffs entry; fixed 16-team, 15-series bracket; deterministic best-of-seven games; atomic next-slate progression; persistence, recovery, migration, and Flutter bracket UI.  
**Non-goals:** Simulation-probability changes, coaching controls, conferences/divisions, offseason advancement, roster or financial changes, player development, and T05C.

## 1. Governing contract

The approved T05A Play-In and regular-season records remain authoritative and unchanged. T05B adds `CareerPhase.playoffs` and one career-local immutable `PlayoffState`. The playoff year equals the regular-season year. Completing the Finals does not begin another phase or process offseason activity.

Playoffs begin only after explicit human confirmation from a validated, completed T05A career. A complete bracket contains the 16 unique entries returned by `PlayInState.qualifiedTeams`, including each team's playoff seed and original regular-season rank. Seeds 1–14 remain direct qualifiers; Play-In winners retain playoff seeds 15 and 16. The Play-In results, regular-season results, contracts, finances, and year remain unchanged.

## 2. Audited architecture and boundaries

- `GmCareer` is the authoritative root, schema v19, and validates phase/state agreement plus full season and historical game evidence. Add `playoffState`; native playoffs careers require schema v20, completed regular season, completed Play-In, and a valid playoff state.
- `CareerPhase` currently has `openingOffseason`, `regularSeason`, and `playIn`. Add `playoffs`; do not add a later-season phase.
- `PlayInState.qualifiedTeams` derives the ordered `(playoffSeed, TeamId, originalRegularSeasonRank)` handoff. Validate and freeze that exact 16-team snapshot at playoff entry; do not reconstruct it from current roster state or re-rank it.
- `RegularSeasonGameAdapter` already selects standard-roster players, deterministic default lineups, `GameRules.standard`, and balanced rotations. Reuse `createGameInput` and `GameSimulator`; do not duplicate the engine or expose hidden profiles.
- `RegularSeasonGameInputEvidence` captures canonical game-time input and deduplicated league snapshots. Reuse it for playoff games; historical validation must use the saved snapshot, not today's roster.
- `RegularSeasonGameResult` validates fixture/game identity, versions, score, period totals, player ownership, minutes, and box-score reconciliation. Reuse this result contract without adding playoff games to `RegularSeasonState.gameResults`.
- `GmCareerCodec` currently writes v19 and preserves v1–v19 migration behavior. Upgrade native saves to v20; no migration auto-enters playoffs or generates games.
- `GmCareerController` serializes commands and publishes only after `GmCareerStorage.write` succeeds. Reuse this command and recovery boundary for entry and an entire slate.
- `FileGmCareerStorage` supplies temp-write, promotion, backup recovery, and explicit reload. Never blindly retry an uncertain slate.
- `app.dart` routes career phases; `PlayInTournamentScreen` is the existing postseason entry surface. Add a playoffs route and retain the T05A screen behavior.
- T05A normal and endurance test gates are independent. Keep complete-season and full-postseason workloads under the `endurance` tag; keep focused state/controller/UI tests under normal regression.
- `LeagueStandings.ranked`, M007 season state, storage, and serialization are outside scope and remain unchanged.

## 3. Entry and schema v20

`PlayoffEntryService.enter` accepts only a validated career in `playIn` phase. It rechecks: all three Play-In results; exactly 16 unique qualifiers; seeds 15 and 16 supplied by G1 and G3 winners; 82 completed regular-season rounds and 1,230 valid results; all 30 franchises at 82 games; no unresolved transactions; and native career validation. The controller also requires `confirmed == true` and no recovery-required state.

Entry creates one immutable `PlayoffState`, changes phase to `playoffs`, validates the complete next career, encodes and persists once, then publishes. Cancellation writes nothing. Duplicate or stale confirmation is rejected. No startup or decode path transitions a career.

Schema v20 requires a `playoffState` field. For v1–v19, absent or null means no playoff state; non-null pre-v20 playoff data is rejected. Preserve all prior v1–v19 migrations, including v17 historical evidence migration and v19 T05A state. A v19 completed Play-In career loads as `playIn` and remains eligible for explicit playoff entry. No prior game is regenerated.

Native phase invariants:

- `openingOffseason`: no regular-season, Play-In, or playoff state.
- `regularSeason`: regular-season state only.
- `playIn`: completed regular-season state plus valid Play-In state; no playoff state.
- `playoffs`: completed regular-season state, completed Play-In state, and valid playoff state for the same season/year; no year advancement.

## 4. Frozen qualification and bracket

Persist the ruleset ID `m009-fixed-playoff-bracket-v1`, the complete ordered 16-team qualification snapshot, and fixed series slot identities. Series indices are zero-based and permanently identify these slots:

| Series index | Round | Participants / dependencies |
|---:|---|---|
| 0 | Round of 16 | Seed 1 vs seed 16 |
| 1 | Round of 16 | Seed 8 vs seed 9 |
| 2 | Round of 16 | Seed 4 vs seed 13 |
| 3 | Round of 16 | Seed 5 vs seed 12 |
| 4 | Round of 16 | Seed 3 vs seed 14 |
| 5 | Round of 16 | Seed 6 vs seed 11 |
| 6 | Round of 16 | Seed 2 vs seed 15 |
| 7 | Round of 16 | Seed 7 vs seed 10 |
| 8 | Quarterfinals | Winner 0 vs winner 1 |
| 9 | Quarterfinals | Winner 2 vs winner 3 |
| 10 | Quarterfinals | Winner 4 vs winner 5 |
| 11 | Quarterfinals | Winner 6 vs winner 7 |
| 12 | Semifinals | Winner 8 vs winner 9 |
| 13 | Semifinals | Winner 10 vs winner 11 |
| 14 | Finals | Winner 12 vs winner 13 |

There is no reseeding. Series and game IDs derive from season identity and fixed indices. A downstream series has unresolved participants until its predecessor series are settled. Once materialized, its persisted participant identity must exactly match the result-derived bracket path. Do not persist a mutable winner, seed table, series-win ledger, or champion flag.

## 5. Series, game identity, and home court

A series is won by the first franchise to four validated game wins. Legal final scores are 4–0, 4–1, 4–2, or 4–3. A game requires every earlier game in that series to exist; it is invalid after a series reaches four wins. Game numbers are 1–7 only. Never create or simulate Game 8.

Home-court authority is the better original regular-season rank from the frozen qualification snapshot, not current playoff seed or bracket position. That franchise hosts Games 1, 2, 5, and 7; its opponent hosts Games 3, 4, and 6. Persist and validate each played game's actual home/away identity.

For series index `s` in `0..14` and game number `g` in `1..7`:

```text
rematchIndex = 86 + (s * 7) + (g - 1)
```

The reserved range is 86–190. Use canonical 0–29 team indices from the existing sorted franchise IDs and unchanged `deriveGameSeed`. Validate index/range boundaries, fixture IDs, stored seeds after reload, and normalized seed uniqueness against all 1,230 regular-season games, all three Play-In games, and every applicable playoff game slot. No regular-season seed changes.

## 6. Playoff state and historical results

`PlayoffState` stores season ID/year, bracket and home-court ruleset IDs, immutable qualification snapshot (including original rank), the 15 fixed series identities, resolved participant identities, seven immutable game identities for every resolved series, completed game results, and deduplicated historical input snapshots. Lists and maps are immutable. Each game identity fixes series index, game number, deterministic ID, rematch index, actual home/away teams, and seed. Unresolved future series have no participants or game identities until their preceding series settle.

Derive series wins, settled winners, eliminated teams, resolved downstream participants, current round, next eligible games, completion, and champion from validated game results. Results are append-only: reject unknown, duplicate, out-of-order, after-clinch, mismatched, or post-championship games. A completed result and its evidence cannot be replaced or regenerated.

Each game result retains fixture ID, season ID/year, home/away IDs, deterministic seed, fingerprint, simulation/rules/event/fingerprint/PRNG/core-engine/league-schema versions, game-time input evidence, period totals, final score, winner, and complete player box score. Validate evidence against its persisted snapshot. Validate winner, period sums, player ownership, standard-roster eligibility, minutes, and statistical reconciliation using existing contracts.

Playoff results exist only in `PlayoffState`; they never enter regular-season or Play-In result maps and never change regular-season standings, contracts, finances, or current year.

## 7. Single-game and slate progression

Provide a pure-Dart service that computes one eligible game's result and game-time snapshot without mutating the career. It validates the current career, phase, series, game number, participants, home court, and seed; builds the standard adapter input; runs `GameSimulator`; and captures historical evidence. The slate service appends all results to one immutable career update and validates the complete career before persistence.

`Simulate Next Playoff Slate` is one serialized controller command with explicit confirmation. Determine the earliest bracket round not fully settled. If that round is complete, the next round becomes eligible only on the next slate command. Process active series in ascending fixed series index. Simulate at most one next game for each active series in that round; never simulate a second game in a series during one slate. A clinched series receives no further game. If any game, validation, or serialization fails, publish none of the slate.

Build all slate results in memory, validate the complete resulting career, encode once, await one storage write, and publish once. Failure before or after storage promotion requires explicit reload; never replay stale in-memory work. The controller captures the immutable career identity before queueing and rejects execution if that submitted career is no longer current; this rejects repeated pending confirmations. Disable the primary action while the command is pending.

## 8. Championship and Flutter UI

The Finals champion is the result-derived winner once the Finals series reaches four wins. Completion disables further simulation. Preserve all 15 series, all played results, the original qualification snapshot, and the champion derivation. Keep career phase `playoffs` and the original year. Do not begin offseason, expire contracts, process revenue, or develop players.

The playoffs screen shows the Round of 16, quarterfinals, semifinals, Finals, matchups, series scores, advanced and eliminated teams, current round, and champion when complete. Provide one primary `Simulate Next Playoff Slate` action with confirmation, plus `View Game Results`, `View Box Score`, and `View Full Bracket`. Use vertically navigable/lazy round sections; avoid a phone-width-breaking horizontal bracket and fabricated dates. Preserve T05A screen and box-score behavior. Verify 360x640 and 393x852.

## 9. Acceptance and verification

Tests must cover:

1. Entry gates, explicit confirmation, cancellation, duplicate/stale entry, complete unique 16-team snapshot, original-rank retention, and unchanged T05A state.
2. All eight first-round matchups; every fixed advancement edge; no reseeding; unresolved dependencies remain blocked.
3. Home court for Games 1–7 using original rank; exact 2-2-1-1-1 pattern.
4. Series settlement at 4–0, 4–1, 4–2, and 4–3; no Game 8, no post-clinch game, no duplicate winner.
5. Deterministic IDs/seeds; indices 86–190; collision checks against regular season, Play-In, and all possible playoff slots; save/reload identity.
6. Single-game simulation uses standard rules/eligible lineups/balanced rotations and actual GameSimulator results; historical evidence, metadata, period totals, winner, player ownership, and box-score reconciliation validate.
7. Slate stable ordering, one game per active series, no next round before settlement, all-or-none publication, deterministic replay, and no automatic simulation.
8. Save/reload at entry, partial round, round boundary, semifinals, and Finals; pre-promotion and uncertain post-promotion failures; reload before continuation; duplicate command rejection.
9. v1–v19 migration, especially all v19 phases and partial/completed T05A Play-In; no auto-entry or regenerated game; M007 isolation.
10. One champion across the full bracket; regular-season and Play-In results, original standings, contracts, finances, and career year unchanged.
11. Playoff UI and box-score navigation at 360x640 and 393x852.
12. Core and Flutter analyzers/tests; dedicated `endurance` test completes an actual 82-round season, all Play-In games, playoff entry, all rounds, champion, checkpoint reloads, and identical final result fingerprints.

Keep routine tests independent from endurance workloads. Record commands, actual outcomes, seeds, fingerprints, game/result counts, elapsed time, save/decode stages, memory, and skipped checks. Tests establish consistency, not basketball realism or Android performance.

## 10. Review and delivery gate

Use focused JEV review for bracket correctness, original-rank home court, advancement, seed injectivity, historical evidence, atomic persistence, migration, and uncertain-write recovery. Resolve concrete defects; JEV does not replace deterministic tests.

Commit and push only after every required acceptance and normal/endurance verification gate passes. Otherwise preserve all work and report the exact blocker. Do not merge protected branches or start T05C.
