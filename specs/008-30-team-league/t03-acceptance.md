# M008-T03 Acceptance Criteria — Team Selection & Situation-Driven League Generation

| ID | Category | Criterion Description | Verification Method |
|---|---|---|---|
| **AC-008-22** | Franchise Selectability | All 30 fictional franchises can be selected as the starting career team | Automated test querying catalog and verifying selection of teams 1..30 |
| **AC-008-23** | Situation Flexibility | Any selected franchise supports all four competitive situations | Generate same team under Tanking, Play-In, Playoff, and Contender |
| **AC-008-24** | Situation Guarantee | Selected franchise is strictly assigned the user-chosen situation in the generated league | Assert `result.selectedTeam.situation == request.selectedSituation` |
| **AC-008-25** | Macro Tier Invariant | 30-team competitive distribution strictly maintains 7 Tanking, 9 Play-In, 9 Playoff, 5 Contender | Count tier occurrences across all 30 generated teams |
| **AC-008-26** | Attribute Impact | Selecting Contender yields higher team attributes than selecting Tanking for the same team | Assert mean overall rating: Contender > Tanking on same team and seed |
| **AC-008-27** | Career Profile Impact | Selecting Tanking yields younger mean age and higher potential upside than Contender on the same team | Assert mean age and upside margin differences on same team and seed |
| **AC-008-28** | Opening Pick Entitlement | User franchise receives opening pick (#1 for Tanking, #12 for Play-In, #20 for Playoff, #30 for Contender) | Assert `result.userOpeningDraftPick == request.selectedSituation.userOpeningDraftPick` |
| **AC-008-29** | Determinism | Same `(teamId, situation, seed)` reproduces byte-identical league and profiles | Assert `jsonEncode(r1.league.toJson()) == jsonEncode(r2.league.toJson())` |
| **AC-008-30** | Isolation from Default | Calling `LeagueGenerator.generate(config)` without career request yields unchanged M008-T01 output | Assert M008-T01 test assertions pass unchanged |
| **AC-008-31** | Legacy M001 Snapshot | 8-team legacy generation produces exact byte-identical golden snapshot (`29,263` bytes) | `m001_regression_test.dart` passes unchanged |
| **AC-008-32** | UI Flow & Preview | UI preview flow allows selecting team, situation, generating preview, and inspecting roster without saving | Flutter widget test covering all 3 screens |
