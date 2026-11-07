# Addendum 005-A1 — T04/T05 dependency and version-rejection clarification

> **Status:** OWNER APPROVED — 2026-11-07.
> **Scope:** task sequencing and evidence accounting only.
> **Not an amendment:** this addendum changes no gameplay requirement, acceptance criterion, version
> constant, fixture, coefficient or contract. The frozen files `spec.md`, `plan.md`, `tasks.md`,
> `acceptance-matrix.md`, `design-decisions.md` and `verification-plan.md` remain unchanged and
> authoritative for requirements.

## A. What T04 owns

T04 owns core v6 canonical fixtures, direct simulator replay, legacy no-plan event-array equivalence
and current-version verification. Its needed evidence is core-side and needs no Flutter transport.

## B. No-plan worker/caller parity

T04 can verify the existing no-plan worker/caller parity, because `GameRequest` already carries the
league, team ids, seed and rules, and the worker builds `CourtLineup.defaultFor` for both teams. The
current v6 simulation is used for that parity check.

## C. Planned worker/caller parity is deferred

`GameRequest` does not transport a starting lineup or a `RotationPlan`. Planned worker/caller parity
is therefore deferred to T05, which adds that transport. T04 must not claim it.

## D. Plan-preserving rematch is deferred

AC-M005-29 (a rematch keeps the managed lineup, both plans and the matchup, and advances only the
seed) needs the same T05 transport. It is deferred to T05 for the same reason. T04 must not claim it.

## E. T05 may start after the T04 core gate

T05 may begin once the T04 core-verification gate passes, even though the transport-specific
evidence in C and D is still outstanding. The deferral is explicit, not a silent gap.

## F. Deferred items stay mandatory

C and D remain mandatory before M005 final acceptance. Deferral moves the task, not the requirement.

## G. Typed rejection of a v5 ledger

`spec.md` §9.1 and `verification-plan.md` item 16 describe a v5 ledger read by a v6 build as a
schema-version rejection. The implemented and correct behaviour is different, and this addendum
records it:

- The event schema is unchanged at version 3, so a simulation-version mismatch is **not** an event
  schema mismatch.
- A v5 ledger read by a v6 build is rejected with the typed code
  `GameValidationCode.unsupportedSimulationVersion` at path `gameSimulationVersion`.
- `GameValidationCode.unsupportedEventSchemaVersion` remains reserved for a real event-schema
  mismatch.

No other rejection contract changes. The reading code, the validation codes and the ledger format are
untouched by this clarification.
