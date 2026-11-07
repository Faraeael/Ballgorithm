# M006 — Owner Design-Freeze Decision Record

> **Decision:** M006 **Role-Aware Shot Selection v1** is **FROZEN — OWNER APPROVED** on 2026-11-07.
> **Frozen source:** `design/m006-role-aware-shot-selection` at
> `33fc148b6b5db25c360b4585e0fc95767c3c0f13` (Revision 4 of the six-document draft).
> **Freeze commit:** the documentation commit on this branch that first adds this record; locate it
> with `git log --diff-filter=A -- specs/006-role-aware-shot-selection/M006-OWNER-DESIGN-FREEZE.md`.
> **Baseline protected branches:** `develop/m002` `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`;
> `main` `a431aeb5a652b134ce40cf442c7d9ffee874fe79`. Neither was modified by this freeze.
> **Implementation status:** NOT STARTED. Every acceptance criterion remains NOT RUN. No cohort was
> executed. No simulation, coefficient, version constant or fixture changed.

## 1. Approved design decisions (DD-M006-01…10)

| ID | Approved decision |
|---|---|
| DD-M006-01 | Position-free creation ranking: `3·ballHandling + passing + basketballIQ`, ties broken by canonical court-slot order, recomputed from the five players on court at each shot. No persisted role; no `Player` or snapshot change. |
| DD-M006-02 | Opportunity multipliers: primary 1.35, secondary 1.15, other three players 1.00, applied before normalisation. No multiplier below 1.0. |
| DD-M006-03 | Three-point willingness curve: `70·(threePoint−50)` below 50, `30·(threePoint−50)` at or above 50, with existing slot/phase bonuses and floor 200; inside and midrange terms unchanged. |
| DD-M006-04 | Preserve event schema 3. No new event type and no persisted shot-zone field. |
| DD-M006-05 | Permit a passive, non-persistent shot-decision instrumentation callback for tests; never in the ledger or fingerprint. |
| DD-M006-06 | Three-stage evidence: pre-registered development pilot, separately owner-approved frozen confirmatory protocol, then exactly one held-out evaluation. |
| DD-M006-07 | Simulation version 7 / fingerprint version 5, with every historical v1–v6 fixture preserved byte-for-byte and historical generation verified at the M005 checkpoint rather than re-run. |
| DD-M006-08 | Dormant T01–T03 policy code followed by atomic T04 activation, version bump, v7 fixture and historical-test migration. No second engine or feature flag. |
| DD-M006-09 | Separate ability, derived shot preference and offensive opportunity. Shooting-success coefficients remain unchanged. |
| DD-M006-10 | Coaching strategy is a future architectural boundary, not M006 implementation scope. |

These are approved design contracts. They are not a claim of calibrated basketball realism.

## 2. Required correction A — decision coverage

Every frozen document now references DD-M006-01 through DD-M006-10 consistently: `spec.md` §8 and
the layer sections, `plan.md` G0 and gates, `tasks.md` header and task bodies, `design-decisions.md`
per-decision approval lines, `acceptance-matrix.md` status header, and `verification-plan.md`
evidence rules.

## 3. Required correction B — statistical selection safeguards

- The paired roster-and-seed case list is fixed before any run: identical league seed, lineups,
  rotation plans, rules and game seed under v6 and v7.
- Cases are never selected, excluded or replaced based on post-simulation outcomes. Observed attempt
  counts judge evidence sufficiency, never which games are compared.
- Denominator-zero handling: a game with zero eligible-bucket attempts yields an undefined per-game
  proportion; it is excluded from that metric only, counted and reported, and never replaced.
- Cohort insufficiency: if the predetermined eligible-game count is below the frozen minimum
  (proposal 400 of 500; value OPEN until Stage B), the report says **INSUFFICIENT** and stops for a
  separate owner decision; the cohort is not topped up or swapped.
- Empirical thresholds, confirmatory sample size and final margins remain **OPEN** until the
  development pilot and the owner-approved Stage B protocol. This freeze does not claim that the
  confirmatory protocol is already frozen.

## 4. Frozen documents

- `spec.md`
- `plan.md`
- `tasks.md`
- `design-decisions.md`
- `acceptance-matrix.md`
- `verification-plan.md`
- this decision record

All six specification documents carry the FROZEN banner; all 37 acceptance criteria remain NOT RUN.

## 5. Version boundary (approved, not applied)

| Identifier | Frozen target | Applied? |
|---|---|---|
| `gameSimulationVersion` | 7 | No — lands with T04 activation |
| `gameFingerprintVersion` | 5 | No — lands with T04 activation |
| `gameRulesVersion` | 3 | Unchanged |
| `gameEventSchemaVersion` | 3 | Unchanged |
| `gameActionDurationModelVersion` | 2 | Unchanged |
| PRNG | `xorshift32-v1` | Unchanged |
| `coreEngineVersion` / `snapshotSchemaVersion` | 1.0.0 / 1 | Unchanged |

## 6. Scope exclusions

Fatigue, injuries, manual play calling, coaching AI or team-strategy configuration, defensive
schemes, trades, contracts, seasons, persistence, possession-level ball movement, turnover or assist
redistribution, new PRNG algorithms, editable persisted tendencies, real-world player data, Flutter
gameplay UI and unrelated probability tuning.

## 7. Historical-fixture policy

Every v1–v6 fixture file and digest stays byte-identical. Historical generation tests are not re-run
against v7; they are verified once in a detached worktree at the accepted M005 implementation
`68018db98cd033b3008513ff7e6d174eaa81f09f` and recorded. The current suite keeps archive-integrity
and typed cross-version rejection, and adds v7 fixtures only. No dual engine ships.

## 8. Open empirical parameters

- Development seeds: proposal 1–200.
- Held-out seeds: proposal 10001–10500.
- Confirmatory sample size and eligible-game minimum: OPEN (proposal 500 paired games / 400 eligible).
- Empirical thresholds and margins: OPEN until pilot and Stage B.
- Bootstrap repetitions: proposal 10,000 over paired games.
- Multiple-comparison method: Holm over four primary metrics.

## 9. Authorization limitations

This freeze authorizes documentation only. It does **not** authorize T01–T06 implementation, any
version-constant change, fixture creation or modification, any statistical cohort, any Flutter or
core code change, any merge into `develop/m002`, any merge into `main`, or any release. Each task
requires its own explicit owner authorization, and Stage B requires a further explicit approval
before any held-out run.

## 10. Non-claims

No NBA realism, calibration or win-rate claim. No inside-versus-midrange claim while event schema
stays 3. No Android or device-performance claim. No claim that derived preferences are editable,
ability-independent tendencies. No claim of reproducing NBA 2K's proprietary formulas or coaching
systems.
