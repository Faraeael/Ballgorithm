# Verification Plan 006 — Role-Aware Shot Selection v1 (FROZEN — OWNER APPROVED 2026-11-07)

> **Status: FROZEN — OWNER APPROVED 2026-11-07.** Approved decisions DD-M006-01 through DD-M006-10 apply.
> Implementation is **NOT STARTED and NOT AUTHORIZED**; every acceptance row remains NOT RUN. Rev 3 corrects the implementation sequence,
> the role acceptance rules and the evaluation protocol. Baseline `develop/m002`
> `d642e7880f38dac0b14f2a55a35bd1282d9f9bd3`.

## 1. Test layers

| Layer | Purpose | Examples |
|---|---|---|
| Contract | Role ranking, version boundary | Position-free ranking, tie-break, atomic 7/5 bump in T04 only |
| Dormancy | No behaviour change before activation | Production weights equal v6 reference vectors; no production call site uses the new functions |
| Weight unit | Opportunity and preference policy | Multipliers, normalisation, piecewise curve, floors, shuffled input equality |
| Layer separation | Ability vs preference vs opportunity | Make vectors unchanged; actor-weight change leaves make probability fixed; zone-weight change leaves accuracy fixed; actors separate; no new draws; no schema |
| Determinism | Repeatability and parity | Repeat-run identity, Dart VM/Chrome equality, per-branch draw-order audit |
| Simulator | Ledger integrity | Reducer acceptance, accounting conservation, no new event types |
| Fixtures | Versioned evidence | New v7 digest; v1–v6 archived bytes preserved |
| Metrics | Decision evidence | FGA, per-36 attempts, pooled 3PA shares, role shares at shot time |
| Comparison | Policy attribution | Usage-only, zone-only and both-policy paired runs |
| Owner review | Directional judgment | Weak shooter, creator, stretch-big box scores |

## 2. Historical fixture compatibility

Historical **fixture files** and their digests are never modified. Historical **generation**
assertions are not re-run against the current engine; they are executed once in a detached read-only
worktree at the accepted M005 implementation `68018db98cd033b3008513ff7e6d174eaa81f09f` and recorded,
exactly as the M004 v5 replay was verified at `36bc3597` during T04. The current suite keeps
archive-integrity and typed-rejection coverage and gains a v7 fixture. No second engine is
maintained in the product.

| Test (file) | Current behaviour | Proposed treatment |
|---|---|---|
| `t04` “pinned bytes, digest and header” | Asserts v6 fixture digest and header | Keep archive digest/header assertions as history; current constants move to the v7 fixture test |
| `t04` “the pinned plan reproduces the fixture and repeats exactly” | Re-runs the simulator and compares v6 bytes | Archive integrity stays; v6 reproduction verified once at the M005 checkpoint; v7 generation/repeat in a new fixture test |
| `t04` “replay validates, completes and reconciles minutes” | Decodes/replays v6 ledger | Replay coverage moves to the v7 fixture; v6 replay verified at the checkpoint |
| `t04` “decoded v6 ledger preserves … links” | Link integrity on v6 | Same migration to the v7 fixture; v6 verified at the checkpoint |
| `t04` mutation matrix (8 tests) | Mutates decoded v6 events | Apply the matrix to the v7 ledger |
| `t04` “null-plan event array equals the pinned v5 array” | Current v6 output equals v5 events | Historical only (checkpoint); current suite asserts v7 no-plan determinism and records the v6→v7 difference |
| `t04` “null plans consume no rotation decisions” | No tactical subs without a plan | Still valid; update version references |
| `t04` “v6 build rejects the v5 fixture …” | Typed rejection | Extend to v5 **and** v6 fixtures, `unsupportedSimulationVersion` only |
| `t04` version identifiers | 6/4/3/3/2 | 7/5/3/3/2 |
| `t04` historical fixture parse/digest | v1–v5 archive | Add v6 to the archive list |
| `t012` seed-42 golden test | Current prefix vs v5 fixture; v6 fingerprint | Archive digest stays; prefix comparison retired to checkpoint; v7 fixture covers current output; fingerprint re-pinned at implementation |
| `t012` v5 rejection | Typed rejection | Rename to current reader; expectation unchanged |
| `t012` published seed digests | v6 digests | Retired to checkpoint; v7 repeat runs and v7 digests after implementation |
| `t012` fingerprint identity | `05e56d…`, payload version 4 | Re-pin v7 fingerprint and payload version 5 |
| `t012` v1–v3 archive parse, raw seed alias | No historical bytes | Unchanged |
| `t03` version identifiers | 6/4 | 7/5 |
| `t03` v4 header rejection | Schema mutation | Rename to current reader; same typed expectation |
| `t03` no-disqualification baseline | v6 fingerprint and event hash pins | Historical at checkpoint; v7 pins in the current suite |
| `t03` v5 vs v4 fixture array | Fixture-to-fixture | Unchanged |
| `t07` current constants | 6/4 | 7/5; archive markers untouched |
| `m001_regression_test` version cross-check | Simulation 6 | Update cross-check to 7; M001 identifiers stay pinned |
| `game_input_test`, `turnover_nonsteal_test` fingerprints | `05e56d…` | Re-pin the v7 fingerprint |
| `t01_rotation_plan_test` version test | 6/4 | 7/5; null-plan behaviour unchanged |
| App widget tests | No historical fingerprints pinned | Unchanged |

Rules: no historical fixture file changes; no silent rebaseline labelled as a fix; archive tests
stay in-tree; checkpoint results recorded in M006 evidence; current tests use only v7 artifacts.

## 3. Metrics and denominators

| Metric | Definition | Denominator |
|---|---|---|
| FGA per 36 | `FGA × 2160 / secondsPlayed`; rate metrics require `secondsPlayed ≥ 240` | Actual ledger minutes |
| Weak-shooter 3PA share | `Σ 3PA / Σ FGA` over players with `threePoint < 40`, pooled within each game | Field-goal attempts |
| Stretch-big 3PA share | Same for `threePoint ≥ 70` at PF/C slots | Field-goal attempts |
| Primary/secondary role share | Pooled FGA by role classification at the moment of each shot (substitutions replayed) | Team FGA |
| Team 3PA distribution | Team 3PA/FGA; share of team 3PA by `threePoint < 40` players | Team FGA |
| Guardrails | Points/game, eFG, TOV/100, FTA/game, possessions/game, exact conservation | Per game and per 100 possessions |

## 4. Controlled, formula-level acceptance (no cohort)

Exact normalized expectations (half-court):

- Weak PG three share ≤ 40.0% (design 39.3%); weak SG ≤ 41.0% (40.1%).
- Non-shooting C ≤ 15.0% (12.3%); high-three C ≥ 36.0% (38.5%); high-three F ≥ 39.0% (40.3%).
- Median shooter within ±1.0 pp of v6 (0.0 pp).

Role acceptance (corrected):

1. **Incremental usage change.** For identical attribute vectors, changing only the role rank changes
   the raw weight by exactly the multiplier ratio and the normalised share monotonically.
2. **Assignment correctness.** The position-free creation score picks the correct player as primary,
   including ties (canonical slot order) and roster-insertion-order independence.
3. **Pre-normalisation ordering.** Raw weight × multiplier is ordered by rank before normalisation;
   the neutral multiplier is exactly 1.0.
4. **Substitution recomputation.** Replacing the creator recomputes the ranking and moves the
   primary multiplier to the highest-creation player on court.
5. **No forced suppression of elite scorers.** No player ever receives a multiplier below 1.0. A
   high-usage scorer ranked neutral keeps the identical raw weight; any normalised-share dilution is
   reported, not asserted as an ordering requirement. There is no rule that the primary-creation
   player must out-shoot every secondary or neutral player.

6. **Same player, different teammates.** A player's classification changes when the on-court five
   changes, with no persisted role.
7. **Actor separation.** Turnover, offensive-foul and non-shooting-foul actors keep their separate
   draw and are unchanged in kind.
8. **No new randomness or schema.** No new draw stage; `Player` and snapshot schema unchanged.
9. **Layer isolation.** For a fixed shooter/defender/zone, `shotMakeBasisPoints` is identical before
   and after any opportunity or preference change; all conversion coefficients equal the v6
   reference vectors.

Role remains a classification; turnover and foul actors keep their separate draw.

## 5. Evaluation protocol (three stages, no execution here)

### A. Pre-registered development pilot

- Development seeds only (proposal: 1–200); held-out seeds are never inspected.
- Estimate per-game variance of the pooled metrics, eligible-player/attempt counts, paired-difference
  SD and the sample size needed for the proposed margins.
- Publish the pilot record (seeds, metrics, variance). It may not test held-out hypotheses.

### B. Frozen confirmatory protocol

Owner-approved before any held-out run; fixes metrics, denominators, eligibility, margins, sample
size, CI method, multiplicity and failure rules. Threshold values remain OPEN until the pilot and
this freeze; they are never chosen from held-out results.

### C. One held-out evaluation

Single run on the frozen protocol (proposal: seeds 10001–10500). Report paired effects, CIs and
decisions. A fail/null returns to design, not to tuning.

### Statistics

- Per-game metric: the pooled proportion within one game (e.g. weak-shooter `Σ3PA/ΣFGA`).
- Pooled attempt-weighted proportion across games: `Σ 3PA / Σ FGA`; it is not the mean of per-game
  shares and not a simple binomial estimate.
- Paired game differences: `d_g = metric_v7(g) − metric_v6(g)` on identical seed `g`.
- Uncertainty: bootstrap over **games** (the resampling unit), e.g. 10,000 resamples of paired `d_g`
  with percentile 95% CI; report the bootstrap SE. Attempts inside one game are correlated, so an
  independent-attempt binomial interval is invalid and must not be used.
- Multiplicity: four primary metrics, Holm-adjusted; guardrails reported descriptively with CIs.

### Predetermined paired case selection (safeguard)

- The evaluation case set is fixed before any run: exact league seed, home/away lineups, rotation
  plans, rules and game seed, evaluated identically under v6 and v7.
- Cases are never selected, excluded or replaced based on post-simulation outcomes. Observed attempt
  counts are used only to judge evidence sufficiency, never to choose a more favourable comparison
  sample.
- Denominator-zero handling: a game whose eligible bucket records zero attempts yields an undefined
  per-game proportion. That game is excluded from that metric only, its count is reported, and no
  replacement game is drawn. Pooled attempt-weighted proportions remain defined when the cohort total
  is non-zero.
- Cohort insufficiency: if the predetermined eligible-game count falls below the frozen minimum
  (proposal: 400 of 500; final value OPEN until Stage B), the result is reported as
  **INSUFFICIENT** and the evaluation stops. A separate owner decision is required before any new
  evidence run; the cohort is not topped up with extra or substituted cases.

### Eligibility, minimum counts and insufficiency

- Weak-shooter game eligible only if combined eligible FGA ≥ 20.
- Stretch-big game eligible only if at least one PF/C with `threePoint ≥ 70` records ≥ 10 FGA.
- Report eligible game counts, player counts and attempt totals per arm.
- Controlled archetype evidence is mandatory because the generated league may lack a genuine
  stretch-five; synthetic rosters are constructed deterministically and documented.
- If eligible games fall below the frozen minimum (proposal: 400 of 500), do not run confirmatory
  statistics; report insufficiency and require an owner decision or constructed-league evidence.

## 6. Commands (when authorized)

```powershell
cd packages/simulation_core
dart pub get
dart analyze
dart format --set-exit-if-changed lib test
dart test
dart test -p chrome test/deterministic_random_test.dart test/generator_test.dart `
  test/validation_test.dart test/simulation

cd ..\..
flutter analyze
flutter test
```

## 7. Failure conditions

- Production behaviour or version change before T04.
- Any new random draw, altered per-branch draw order, or schema change outside the design.
- Any v1–v6 fixture file modified, or a historical assertion silently rebaselined.
- Stretch-big collapse; weak-shooter controlled bounds missed.
- Repeat-run or VM/Chrome divergence.
- Held-out seeds inspected before the Stage B freeze; a binomial interval used for a pooled
  per-game metric.
