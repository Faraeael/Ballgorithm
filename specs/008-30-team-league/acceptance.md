# M008-T01 Acceptance Criteria — 30-Team League & Situation-Based Generation

| ID | Category | Criterion Description | Verification Method |
|---|---|---|---|
| **AC-008-01** | Team Count | Generator produces exactly 30 unique teams when `teamCount == 30` | Unit test checking `league.teams.length == 30` and distinct team IDs |
| **AC-008-02** | Roster Size | Each of the 30 teams has exactly 12 players covering all 5 positions | `LeagueValidator.validate(league)` passes with zero issues |
| **AC-008-03** | Player Uniqueness | All 360 player IDs and full names are unique across the 30-team league | Set assertion on player IDs and name pairs |
| **AC-008-04** | Competitive Situations | All 4 situations (`tanking`, `playIn`, `playoff`, `contender`) are represented | Assert count of each tier in generated league (7 tanking, 9 play-in, 9 playoff, 5 contender) |
| **AC-008-05** | Tier Stratification | Average team ratings follow strict hierarchy: Contender > Playoff > Play-In > Tanking | Mean rating comparison across all 30 teams |
| **AC-008-06** | Non-Uniformity | Teams within the same tier exhibit attribute variance and style variation | Variance assertion across same-tier team attribute profiles |
| **AC-008-07** | Determinism | Same configuration seed produces byte-identical serialized JSON | `jsonEncode(leagueA.toJson()) == jsonEncode(leagueB.toJson())` |
| **AC-008-08** | Legacy Compatibility | `GenerationConfig(seed: 20261028, teamCount: 8)` produces exact golden snapshot (`29,263` bytes) | Assertion in `m001_regression_test.dart` passes unchanged |
| **AC-008-09** | Validation Range | `GenerationConfig(teamCount: 30).validate()` passes; out-of-range counts (`0`, `9`, `31`) are rejected | `ValidationCode.teamCountOutOfRange` test coverage |
| **AC-008-10** | Metadata Contracts | Each franchise situation declares correct future draft pick (#1, #12, #20, #30) | Assertion on `FranchiseSituation.targetDraftPick` |
