# M009-T05A Regression Gates

## Test ownership

| Category | Coverage | Runner | Tag |
|---|---|---|---|
| A — Routine UI and career commands | `M009-T03 simulates ready careers and recovers game saves`; season entry, scheduling, round commands, screens, migrations, and save recovery | Flutter `testWidgets`; uses `WidgetTester` | Normal |
| B — Play-In lifecycle | `M009-T05A Play-In lifecycle from a completed regular season`; real completed season, v18 migration, entry confirmation, three games, recovery, reload, qualification, box score, and mobile sizes | Flutter `testWidgets`; uses `WidgetTester` and career storage | Normal |
| C — Full-season reliability | `M009-T04 endurance: completed-season reliability and starting situations`; reference/checkpoint equality, file persistence, recovery checkpoints, historical results, standings, and screen checks | Flutter `testWidgets`; file storage and UI assertions require `WidgetTester` | `endurance` |
| D — Historical persistence and recovery | T03/T05A migration, tamper rejection, pre/post-promotion write failures, reload, and result integrity assertions | Flutter integration tests plus core codec tests | Normal and endurance |
| E — Starting-situation evaluations | Same seed/situation inputs as T03; 82 rounds, 1,230 results, unchanged year and finances | Flutter test harness builds eligible careers; regular-season simulation uses pure-Dart core services | `endurance` |

The 24-cohort hardship diagnostic also uses `WidgetTester` for conditional hardship UI and runs under `endurance`. Core ranking, fixtures, seed namespace, outcome combinations, and state validation stay in `packages/simulation_core/test/career/play_in_state_test.dart` and run under `dart test`.

## Commands

Run from repository root unless noted:

```powershell
flutter test --exclude-tags endurance --concurrency=1 --reporter expanded
flutter test --tags endurance --concurrency=1 --reporter expanded
flutter analyze
```

Run core gates from `packages/simulation_core`:

```powershell
dart analyze
dart test
```

Normal and endurance runs are separate gates. Their union covers tagged and untagged tests; neither gate skips or comments out assertions. The endurance test prints progress by situation, pass, round, elapsed interval, simulation/save/validation stage, and process RSS.
