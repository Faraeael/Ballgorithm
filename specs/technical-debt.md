# Technical Debt Register

Project-level register. Entries keep the audited P2 findings from Milestone 001
so they are not lost when the milestone closes. P1 findings were fixed before
the M001 gate and are recorded in
`specs/001-league-player-foundation/acceptance-report.md`.

Status: all items open unless marked otherwise. None block M001.

| ID | Area | Finding | Impact | Trigger to fix | Proposed minimal fix |
|----|------|---------|--------|----------------|----------------------|
| TD-01 | Simulation realism | Generated ratings and positional offsets are uncalibrated design guesses; no realism claim has been made or tested. | Users may find ratings implausible on inspection. | Before any balancing, scouting or match-simulation work. | Calibrate offsets/distribution against an explicit target distribution and record it as a spec decision. |
| TD-02 | Persistence | `snapshotSchemaVersion` is compared for exact equality only; there are no migration fixtures or dispatcher. | Adding any snapshot field breaks old saves unless migrated. | Before the first persistent save milestone. | Add `switch (schemaVersion)` migration functions, a checked-in v1 fixture and migration tests. |
| TD-03 | Persistence metadata | `League.toJson` writes the current `coreEngineVersion` at the top level while preserving `generation.engineVersion`; re-encoding an old snapshot relabels it. | Snapshot metadata can contradict itself; reproducibility audits become unreliable. | Same milestone as TD-02. | Write `config.engineVersion` at the top level, or remove the duplicate field. |
| TD-04 | Domain extensibility | Adding a player attribute touches ~6 string-keyed places (`attributeNames`, `asMap`, constructor, `fromJson`, generator offsets per position); a missing offset throws on `!`. | One attribute addition is error-prone and can fail at runtime. | Before the second attribute set or player-skill expansion. | Introduce a single `Attribute` enum plus one validated offsets map, or generate the tables. |
| TD-05 | Test infrastructure | `packages/simulation_core/test/domain_isolation_test.dart` resolves `Directory('lib')` from the working directory and scans raw source text (comments included) rather than imports. | False pass/fail depending on invocation directory; brittle to doc comments. | Next time domain isolation is audited in CI. | Resolve package root from `Platform.script`, assert the expected file count, scan import lines, and check runtime deps in `pubspec.yaml`. |
| TD-06 | Determinism tests | No golden league snapshot; determinism tests compare two runs of the same code, and only PRNG vectors are pinned. | Generated output can change for a seed without failing tests if offsets, names or draw order change. | When snapshots become user-visible or long-lived. | Store a hash/JSON fixture of the default league and update it only with an engine-version bump. |
| TD-07 | UI testing | Widget tests cover all teams, rosters and 96 profiles at three phone widths, but there are no golden/screenshot tests or large-font accessibility checks. | Visual regressions and accessibility scaling issues can slip through. | Before a visual polish pass or accessibility review. | Add golden tests for the three screens and a text-scale factor (e.g. 1.3) test. |
| TD-08 | Android packaging | Package id is the scaffold default `com.example.basketball_manager`; applicationId, signing config and store metadata are unconfigured. | Cannot ship to Play Store or upgrade safely without changing the id. | Before any release/distribution build. | Set the final applicationId, signing config and version strategy. |
| TD-09 | Android release | Only a debug APK has been built; release AAB/APK, shrinking and performance packaging are untested. | Release build issues and size/performance regressions are unknown. | Before a closed test or release build. | Add a release build check to the verification routine and record size/start-up timings. |

## Out-of-scope notes (accepted, not debt)

- The 32-bit seed space and `0..2^32` `nextInt` bound are documented limits of `xorshift32-v1`, not defects.
- The domain package intentionally has no runtime dependencies.
- Android licenses are not accepted on the review machine; the debug build succeeded, and this affects only local tooling.
