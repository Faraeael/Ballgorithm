# Basketball Manager Constitution v0.1

1. Determinism: same state, explicit commands, engine version and PRNG seed yield identical results.
2. Domain isolation: pure Dart domain has no Flutter, Flame, database or network imports.
3. One authoritative state: immutable IDs and explicit ownership; reject duplicate entities and invalid rosters.
4. Statistical integrity: derived aggregates reconcile with event sources once events are introduced.
5. True ability and scouting observations are separate, with no accidental UI leakage of hidden ability.
6. Persistence is versioned and migration-tested; incompatible versions fail explicitly.
7. Every feature has specification, plan, tasks, acceptance tests and evidence; agent must not self-certify realism.
8. No feature expansion beyond approved milestone without spec amendment.
9. Offline-first; no mandatory service or account.
10. No real league/player branding or data without rights review.
