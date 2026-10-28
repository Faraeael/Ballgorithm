# Implementation Plan 001

1. Bootstrap Flutter project with /packages/simulation_core pure Dart package.
2. Define immutable models and typed IDs; document serialization conventions.
3. Define generator config, PRNG and deterministic name/attribute generation.
4. Implement validation and explicit failure reporting.
5. Build minimal read-only Flutter navigation and screens.
6. Add unit, property-style, snapshot and widget tests.
7. Produce acceptance evidence and an unresolved-questions report.

## Proposed boundaries
- `packages/simulation_core/lib/src/models/`
- `packages/simulation_core/lib/src/generation/`
- `packages/simulation_core/lib/src/validation/`
- `lib/features/league/` and `lib/features/roster/`
- `packages/simulation_core/test/` and `test/`

## Gate
Do not start Milestone 002 until AC1–AC8 pass and a human reviews the generated league and roster UX.
