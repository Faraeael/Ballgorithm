# Plan 006 — Role-Aware Shot Selection v1 (DRAFT, rev 4)

> **Status: DRAFT — NOT FROZEN.** No task is authorized. Baseline `develop/m002`
> `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`.

## 1. Delivery sequence (revised)

The rev-2 plan bumped versions in T01. That is corrected: intermediate commits must keep the
existing v6 behaviour and the existing v6 suite green. Dormant policy code is added and unit-tested
without being called from production paths; one activation commit switches the call sites, bumps
versions and migrates historical tests together.

| Task | Purpose | Behaviour visible? | Version bump? | Key deliverable |
|---|---|---|---|---|
| T01 | Dormant role helper | No | No | Pure, position-free creation ranking and role assignment functions plus unit tests; production call sites untouched |
| T02 | Dormant opportunity weights | No | No | Pure role-adjusted usage weights plus unit tests; `selectAction` still calls the v6 weights |
| T03 | Dormant derived shot preferences | No | No | Pure piecewise three-point weight plus unit tests; production zone function and make coefficients unchanged |
| T04 | Activation, version boundary, fixtures and migration | Yes (v7) | Yes, atomic 7/5 | Switch the three call sites; bump simulation 7 / fingerprint 5; land the v7 fixture; migrate historical tests per `verification-plan.md` §2 |
| T05 | Instrumentation and metrics | No | No | Optional debug shot observer; ledger metrics; shot-time role classification |
| T06 | Pilot, protocol freeze, held-out evaluation and owner review | No | No | Three-stage evidence process (see §3) |

### Dormancy isolation without a second engine

- T01–T03 add **pure functions** beside the existing v6 functions in `probability_model.dart`
  (or a small adjacent library); they are reached only by unit tests.
- Production paths (`selectAction`, `_selectShot`, `shotUsageWeights`) keep calling the v6 functions.
- A dormancy test asserts the production weights equal the v6 reference vectors at fixed inputs
  until T04, and a source-scan test asserts no production call site invokes the new functions before
  activation.
- T04 changes only the call sites, bumps the constants and pins fixtures in the same commit; no
  alternate engine class, flag-switched simulator or duplicate event pipeline exists at any point.
- Intermediate commits therefore keep the v6 integration suite green; historical migration happens
  exactly once, in the activation commit.

If a safer sequence is later required (for example separating the fixture commit from the call-site
commit), the owner must approve it; the default above is the minimum-risk order because behaviour
and version identifiers change atomically.

## 2. Gates

- **G0 design:** owner answers DD-M006-01…08; rev-3 reviewed.
- **G1 dormant code:** T01–T03 merged with v6 behaviour unchanged and the full existing suite green.
- **G2 activation:** T04 atomic — versions 7/5, call sites switched, v7 fixture pinned, historical
  migration applied, v1–v6 files untouched, typed rejection both directions.
- **G3 evidence:** T05 metrics reproducible; T06 stages A→B→C executed in order.
- **G4 acceptance:** owner decision only.

## 3. Evidence stages

A. **Development pilot** — development seeds only; estimate per-game variance, pooled-metric
   behaviour, eligible-player/attempt counts and sample size. Held-out seeds are never touched.
B. **Frozen confirmatory protocol** — owner-approved file fixing metrics, denominators, eligibility,
   margins, sample size, CI method, multiplicity and decision rules. Committed before any held-out
   run.
C. **One held-out evaluation** — single run on the frozen protocol; results reported without moving
   thresholds. A failed or null result returns to design review, not to tuning.

No cohort runs in this design task.

## 4. Version and fixture impact

simulation 7 / fingerprint 5 land with activation (T04), not earlier. rules 3, schema 3, duration 2
and PRNG unchanged. Historical v1–v6 fixture files and digests stay byte-identical; historical v6
generation is verified once at `68018db` in a detached worktree. New v7 fixtures are additive. No
dual simulation engine ships.

## 5. JEV advisory (non-binding)

Piecewise structure preferred 0.71 (confidence 0.56); “per-branch draw order without v6/v7
draw-count equality” returned 0.62. Advisory input only.

## 6. Rollback

Before T04, reverting the dormant commits changes no production behaviour. After T04, rollback is a
version reversal plus test selection; historical fixtures were never modified, so no data migration
is needed.
