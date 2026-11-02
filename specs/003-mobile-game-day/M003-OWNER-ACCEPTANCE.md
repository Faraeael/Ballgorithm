# M003 — Owner Acceptance Record

> **Date of decision:** 2026-11-02
> **Milestone:** M003 — Mobile Game Day
> **Decision:** **ACCEPTED — FUNCTIONAL MOBILE GAME DAY FOUNDATION**
> **Decision maker:** project owner (human)
> **Evidence commit at decision time:** `e4247c4a8507deee50859ee02dba626725357732` (`develop/m002`)
> **Technical baseline:** simulation `gameSimulationVersion` 4, `gameRulesVersion` 2,
> `gameEventSchemaVersion` 2, `gameFingerprintVersion` 2, `gameActionDurationModelVersion` 2,
> PRNG `xorshift32-v1`, `coreEngineVersion` `1.0.0`
> **Review inputs:** T020 frozen specification (plus amendment 001), T021 isolate gate evidence, T022
> setup implementation and tests, T023 execution/error handling, T024 results/rematch, T025
> two-width-and-device verification, the correction commits `e2fd1c0`, `7de529b`, `e4247c4`, the
> Android captures in `t025-visual-review.md`, and human review of the original and corrected
> screenshots.

---

## 1. What is being accepted

The **functional Mobile Game Day foundation**: from the accepted M002 possession engine, a player can
select two distinct teams, confirm a deterministic seed, run the game off the UI isolate, read a
scoreboard, period scoring, team statistics and player box scores with a fixed identity column, see the
required limitations, and rematch or return to the league on a phone-sized screen.

Everything shown is derived from one validated `GameResult`. No statistic is recomputed in the UI, and
no simulation behavior changed in this milestone.

## 2. What is explicitly not accepted

1. This is **not** an Android performance, memory, thermal or battery certification.
2. This is **not** an accessibility certification; larger system text scales remain unverified.
3. This is **not** a persistence, season or long-term progression feature.
4. This is **not** approval of player minutes, substitutions, rotations, fatigue or foul-outs — none is
   modeled.
5. This is **not** a new approval of the simulation itself: simulation v4 keeps its M002 conditional
   acceptance and every historical qualification.
6. This does **not** imply NBA-level realism.
7. This does **not** authorize a production release, signing, store submission or deployment.

## 3. Acceptance-criteria disposition

| AC | Requirement | Basis | Disposition |
|---|---|---|---|
| AC-MGD-01 | League → Play Game → setup → results → return | `game_setup_test`, `game_flow_test`, `game_results_test`, device walkthrough | **ACCEPTED** |
| AC-MGD-02 | Home and away must differ | duplicate team removed from the other role's options; tests assert absence and option counts | **ACCEPTED** |
| AC-MGD-03 | Worker/console fingerprint and ledger parity | `game_runner_parity_test` (6 tests) | **ACCEPTED** |
| AC-MGD-04 | Bounded rematch seed cycle, reproducible, no outcome guarantee | `game_results_test` rematch, wrap, reproducibility tests | **ACCEPTED** |
| AC-MGD-05 | Rendered values equal `GameResult` values | `game_results_test` value assertions for all sections | **ACCEPTED** |
| AC-MGD-06 | Period scoring and overtime | regulation + deterministic overtime fixtures | **ACCEPTED** |
| AC-MGD-07 | Typed error state, retry, no stuck spinner | `game_flow_test` error/retry/duplicate/disposal tests | **ACCEPTED** |
| AC-MGD-08 | No overflow at 360×640, 393×852, 430×932 | `game_mobile_layout_test` (13 tests) + device observation at 360 dp and ~393/~430 dp via display density | **ACCEPTED** |
| AC-MGD-09 | Fixed-lineup disclosure | `game_results_test` disclosure test; visible in device captures | **ACCEPTED** |
| AC-MGD-10 | Analyze clean, tests green, core unchanged | 71/71 Flutter tests, 351/351 core tests, clean analyze and format, empty core diff | **ACCEPTED** |

Human visual acceptance covers the player-identity design: names and positions remain fixed while the
statistics pane scrolls, verified per team at every width and on the device.

## 4. Preserved limitations

1. Android performance, memory and battery characteristics are not certified.
2. Accessibility at larger system text scales remains unverified.
3. Results are ephemeral; persistence and seasons are deferred.
4. Player minutes, substitutions, rotations, fatigue and foul-outs are not modeled.
5. Simulation v4 retains its M002 conditional acceptance and historical qualifications.
6. No NBA-level realism certification is implied.
7. No production release authorization is granted.

Additional known limits, already recorded: player statistics still cut the right edge mid-cell while
scrolling; section headings scroll away with the page; the error state and the long-name fixture were
not captured on the device because they are not reachable through the shipped UI (widget-tested only);
`AGENT_PROMPT.md` remains a stale Milestone 001 onboarding prompt.

## 5. Scope integrity

- No basketball simulation behavior, coefficient, rule, clock, event vocabulary, PRNG draw order,
  version identifier or canonical fixture changed in M003.
- No file under `packages/simulation_core/` changed across the milestone's commits.
- No frozen M002 specification, acceptance matrix, calibration record or fixture was edited.
- M002's decision, conditions and historical failures are unchanged by this record.
- The closeout commit is documentation-only.

## 6. Consequences

- M003 task ledger: T020–T025 complete; technical verification PASS; human visual acceptance APPROVED;
  M003 **ACCEPTED** on 2026-11-02.
- `AGENTS.md` §3 records M003 as accepted and closed, and M004 as unstarted.
- M004 (Player Participation) requires a new frozen specification and its own owner authorization.
  `M003-BACKLOG.md` remains planning input and assigns nothing.
- Simulation realism beyond the M002 conditional acceptance still requires the deferred backlog work
  and a pre-registered evaluation; this acceptance does not shorten that path.
