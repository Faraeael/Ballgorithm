# M008-T02 Acceptance Criteria — Player Age, Potential & Development Profiles

| ID | Category | Criterion Description | Verification Method |
|---|---|---|---|
| **AC-008-11** | Profile Completeness | All 360 generated players receive a valid `PlayerCareerProfile` | Assert `profiles.length == 360` with zero missing player IDs |
| **AC-008-12** | Valid Age Bounds | All generated player ages fall strictly within `19..38` | Assert every player age $\ge 19$ and $\le 38$ |
| **AC-008-13** | Potential Bounds | Potential is strictly $\ge \text{currentOverall}$ and $\le 100$ | Assert every player's potential $\ge$ overall rating and $\le 100$ |
| **AC-008-14** | Trajectory Enum | All 4 development trajectories are represented | Verify occurrences of `earlyBloomer`, `steady`, `lateBloomer`, and `volatile` |
| **AC-008-15** | Situation Stratification | Mean age: Tanking < Play-In < Playoff < Contender; Mean potential margin: Tanking > Contender | Statistical mean comparison across situation tiers |
| **AC-008-16** | Individual Variation | Teams within the same tier exhibit varied age and potential distributions (veterans on tanking, young bench on contenders) | Range and standard deviation assertions per tier |
| **AC-008-17** | Determinism | Same seed reproduces byte-identical career profile JSON; different seeds yield distinct profiles | `jsonEncode(p1.toJson()) == jsonEncode(p2.toJson())` |
| **AC-008-18** | Simulation Isolation | Player attributes, names, IDs, and M001/M008-T01 golden outputs remain 100% byte-identical | `m001_regression_test.dart` and `league_generator_30_test.dart` pass without change |
| **AC-008-19** | Serialization & Validation | `LeagueCareerProfiles` round-trips cleanly through JSON; rejects missing/foreign player IDs and corrupt values | Deserialization and validation unit tests |
| **AC-008-20** | Draft Pick Clarity | `FranchiseSituation` draft pick metadata explicitly documents user-franchise guarantee | Code inspect and unit test |
| **AC-008-21** | Rookie ID Collision Prevention | Future rookie ID format `player-rookie-{year}-{pick}` has zero collisions with inaugural roster IDs | Disjoint ID set assertion |
