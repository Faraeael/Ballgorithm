# M008-T01 Implementation Plan — 30-Team League & Situation-Based Generation

## 1. Domain Models
1. Create `FranchiseSituation` enum in `packages/simulation_core/lib/src/models/franchise_situation.dart`.
2. Expand `teamCatalog` in `name_corpus.dart` with 22 new unique fictional franchises (total 30).
3. Add optional `FranchiseSituation? situation` to `Team` model, preserving legacy 8-team JSON compatibility.
4. Update `GenerationConfig`:
   - Support `teamCount == 8` and `teamCount == 30`.
   - Maintain `teamCountOutOfRange` for invalid counts (e.g. `0`, `9`, `31`).

## 2. Generator Logic
1. In `LeagueGenerator`:
   - If `config.teamCount <= 8`: execute legacy uniform generation path, preserving 100% PRNG draw sequence and byte-identical output.
   - If `config.teamCount == 30`:
     - Distribute 30 situations: 5 Contender, 9 Playoff, 9 Play-In, 7 Tanking.
     - Apply situation-based rating baselines and role stratifications (starters vs rotation vs bench).
     - Apply team-specific style noise (perimeter, interior, athleticism) to prevent uniform rosters.
     - Generate valid 12-player rosters covering all 5 positions with unique names and IDs.

## 3. Verification & Acceptance
1. Add `packages/simulation_core/test/generation/league_generator_30_test.dart`:
   - Validate 30 teams, 360 players, unique names, position coverage.
   - Validate competitive situation distribution and attribute stratification.
   - Validate determinism and same-seed reproducibility across multiple seeds.
2. Run full regression battery:
   - `packages/simulation_core`: `dart analyze`, `dart test`, Chrome season tests.
   - App root: `flutter analyze`, `flutter test`.
