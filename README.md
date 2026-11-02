# Basketball Manager

Offline-first basketball manager prototype.

- Milestone 001 — deterministic fictional league generation and a read-only roster UI. Accepted.
- Milestone 002 — deterministic, event-sourced possession-simulation engine (simulation v4).
  Accepted with conditions; see `specs/002-possession-simulation/M002-OWNER-ACCEPTANCE.md`.
- Milestone 003 — Mobile Game Day. Accepted 2026-11-02 (functional foundation); see
  `specs/003-mobile-game-day/M003-OWNER-ACCEPTANCE.md`.
- Milestone 004 — Foundational Player Participation. Specification frozen 2026-11-02; implementation
  not started.

Current cross-milestone status is maintained in `AGENTS.md` §3. No NBA-level realism,
release-readiness or Android performance claim has been made or measured.

## Layout

- `packages/simulation_core/` — pure Dart domain (models, deterministic generator, validation). No Flutter, Flame, database or network imports.
- `lib/` — Flutter presentation: league list, roster, player profile, game day setup and results.
- `specs/001-league-player-foundation/` — spec, plan, tasks, design decisions, acceptance report.
- `specs/002-possession-simulation/` — frozen M002 specification, evidence, calibration records and the owner acceptance record.
- `specs/003-mobile-game-day/` — frozen Mobile Game Day specification, evidence and the owner acceptance record.

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
