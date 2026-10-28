# Tasks 002 — FROZEN SPECIFICATION, NOT AUTHORIZED TO EXECUTE

Specification frozen: 2026-10-28 at baseline `a431aeb5a652b134ce40cf442c7d9ffee874fe79`.
OD-01…OD-14 are adopted; A1 (duration distribution) and A2 (`package:crypto`)
are owner-approved. Implementation authorization is still outstanding.

OD-01…OD-14 and A1/A2 are recorded in `design-decisions.md` and
`review-findings.md`. The specification is frozen; no implementation task may
start before T003 receives separate authorization.

## Design/review gate

- [ ] T001 Review M001 source at pinned commit; document unchanged API/versions and risks.
- [ ] T002 Approve typed event model, clock/foul/bonus rules, lineup limitations and calibration review bands.
- [ ] T002a Confirm the live-action duration distribution and the `package:crypto` SHA-256 dependency as part of specification approval.
- [ ] T003 Record owner approval of this specification and **separate authorization to implement M002**. No coding before approval.

## Pure Dart design and implementation (only after T003)

- [ ] T004 Add versioned `GameRules`, `GameInput`, `ActiveLineup` with typed validation failures and tests.
- [ ] T005 Implement typed immutable `GameEvent` hierarchy and canonical event serialization.
- [ ] T006 Implement replayable `GameState`/reducer with legal transitions, possession/period/clock guards and illegal-event fixtures.
- [ ] T007 Implement derived-only team/player/period box-score accounting; test every equation and event attribution.
- [ ] T008 Implement pure ratings-based shooter, shot-type, outcome, turnover, foul, rebound, assist/steal/block models; document coefficients.
- [ ] T009 Implement game orchestrator: full regulation, transitions, shot clock, simple bonus, and bounded overtime.
- [ ] T010 Implement shooting-foul/and-one/FT/rebound edge cases and dead-ball period handling.
- [ ] T011 Validate complete games on deterministic seeds; prevent endless loops and invalid transitions.
- [ ] T012 Pin canonical ledger fixture, verify VM/Chrome compatibility, preserve M001 vectors/output.
- [ ] T013 Run adversarial/property tests across >=100 seeds and all acceptance matrix cases.
- [ ] T014 Run paired-seed skill-sensitivity experiments and document effects/uncertainty.
- [ ] T015 Run >=1,000-game calibration sample; publish summary, diagnostic cases and limitations.
- [ ] T016 Measure bounded runtime/memory under named environments; document Android suitability constraints without fabricated measurements.
- [ ] T017 Run full Dart/Flutter regressions, format/analyze and independence/scope audit.
- [ ] T018 Prepare exact acceptance-report.md for AC01–AC13 and list remaining debt.
- [ ] T019 Obtain human statistical/gameplay review (AC09/AC10) and sign-off before M002 closure.

No task is completed by merely drafting this document. Owner authorization remains outstanding.
