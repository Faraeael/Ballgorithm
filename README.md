# Basketball Manager

Offline-first basketball manager prototype. Milestone 001: deterministic
fictional league generation and a read-only roster UI.

## Layout

- `packages/simulation_core/` — pure Dart domain (models, deterministic generator, validation). No Flutter, Flame, database or network imports.
- `lib/` — Flutter presentation: league list, roster, player profile.
- `specs/001-league-player-foundation/` — spec, plan, tasks, design decisions, acceptance report.

## Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows        # or: flutter run -d chrome

cd packages/simulation_core
dart pub get
dart analyze
dart format --set-exit-if-changed lib test
dart test
```

The league is generated with a fixed seed (`20261028`) in `lib/main.dart`.
Generation rules and PRNG contract are documented in
`specs/001-league-player-foundation/design-decisions.md`.
