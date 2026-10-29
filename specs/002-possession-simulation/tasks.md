# Tasks 002 — PHASE 1, T008, AMENDMENT 001, T009 AND T010 IMPLEMENTED; T011–T019 NOT AUTHORIZED

Specification frozen: 2026-10-28 at baseline `a431aeb5a652b134ce40cf442c7d9ffee874fe79`.
Phase 1 (T004–T007) is implemented on `feat/m002-phase1-simulation-foundation`.
T008 is implemented on `feat/m002-phase2a-probability-model`.
T009 is implemented on `feat/m002-phase2b-game-orchestrator`; see `t009-orchestrator.md`.
T010 is implemented on `feat/m002-phase2c-event-hardening`; see `t010-event-hardening.md`.
T011–T019 remain unauthorized and unchecked.

OD-01…OD-14 and A1/A2 are recorded in `design-decisions.md` and
`review-findings.md`. The specification is frozen; no implementation task may
start before T003 receives separate authorization.

## Design/review gate

- [x] T001 Review M001 source at pinned commit; document unchanged API/versions and risks. Evidence: M001 source inspected; versions verified unchanged.
- [x] T002 Approve typed event model, clock/foul/bonus rules, lineup limitations and calibration review bands. Evidence: frozen specification commit dd4234d.
- [x] T002a Confirm the live-action duration distribution and the `package:crypto` SHA-256 dependency as part of specification approval. Evidence: A1/A2 recorded as owner-approved in design-decisions.md and review-findings.md.
- [x] T003 Record owner approval of this specification and **separate authorization to implement M002**. Evidence: Phase 1 authorization covers T004–T007 only; T008–T019 remain unauthorized.

## Pure Dart design and implementation (only after T003)

- [x] T004 Add versioned `GameRules`, `GameInput`, `ActiveLineup` with typed validation failures and tests.
- [x] T005 Implement typed immutable `GameEvent` hierarchy and canonical event serialization.
- [x] T006 Implement replayable `GameState`/reducer with legal transitions, possession/period/clock guards and illegal-event fixtures.
- [x] T007 Implement derived-only team/player/period box-score accounting; test every equation and event attribution.
- [x] T008 Implement pure ratings-based shooter, shot-type, outcome, turnover, foul, rebound, assist/steal/block models; document coefficients. Evidence: `probability_model.dart` + `action_intent.dart` on `feat/m002-phase2a-probability-model`; coefficients and draw order in `probability-model.md`; 37 model tests + 11 paired-seed probes pass; uncalibrated, T014/T015 still open.
  Amendment 001 (`TurnoverReason.nonSteal`, event schema v2) is implemented on `feat/m002-nonsteal-turnover-contract`; see `amendment-001-nonsteal-turnover.md`. T011–T019 remain unauthorized.
- [x] T009 Implement game orchestrator: full regulation, transitions, shot clock, simple bonus, and bounded overtime. Evidence: `game_simulator.dart` + `game_result.dart` on `feat/m002-phase2b-game-orchestrator`; full games replay through the reducer, box scores derive from EventAccounting, 200 seeded games zero failures, 190 Dart / 189 Chrome / 8 Flutter tests; T010 edge-case hardening was implemented separately.
- [x] T010 Implement shooting-foul/and-one/FT/rebound edge cases and dead-ball period handling. Evidence: `t010-event-hardening.md`; 40 new legal/illegal fixtures, duplicate-miss typed-error and linked-clock validation fixes, 320 varied-configuration games audited, standard seeds replay and reconcile, 230 Dart / 229 Chrome / 8 Flutter tests; T011–T019 remain unauthorized.
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
