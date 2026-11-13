# T08H-P2 hardship feasibility and clearance evidence

Status: **T08H-P2 technically ACCEPTED; offseason confirmation NO-GO**. No regular-season simulation started.

## Authorization and policy

Owner authorization is explicit in the current T08H-P2 instruction. The earlier report's `approve_exact` claim was unverified and is not relied upon. Baseline `32a8cef9b49e337d86711f4d5af7a1308296937a`; implementation branch `feat/m008-t08h-p2-hardship-contracts`.

Ordinary cap remains 41,000 CU; `FinancialRules.maximumReliefOverage` remains 800 CU. Separate hardship authority covers only exact sealed offers. Existing relief plus hardship relief cannot exceed 1,000 CU per franchise and season. Offers use the public T08E acceptance evaluator, standard contract schedules, current cash, mandatory vacancy count, and existing competitive ranking. No new round, salary discount, cash loan, created player, forced acceptance, or season advancement.

## Reproduction

From `packages/simulation_core`:

```text
dart run tool/t08h_p2_hardship_diagnostics.dart
```

The passive tool runs the complete opening-offseason sequence for six seeds and four human situations. A separate active-human widget diagnostic runs the same 24 cohorts through real controller market/clearance offers and the screen's hardship confirmation/AI-preparation/resolution actions: `flutter test test/t08h_p2_active_human_diagnostics_test.dart --reporter expanded`. Active automation submits explicit legal human choices; it does not bypass consent or inspect sealed AI offers.

Seeds `20261028`, `1604126146`, and `987654321` are required cohorts. Held-out seeds `314159265`, `271828182`, and `8675309` were pre-registered in the owner-approved amendment before evaluation. No policy tuning followed these runs.

## Cohort results

Each cell records `ready/30; vacancies (human/AI); hardship acquisitions; financially/competition/player-rejection blocked teams; total exception used CU; maximum combined overage required CU; human offers; all-30-ready`. Passive mode records zero human offers. Active human offer counts cover both regular market rounds, original clearance, and hardship settlement. Blocker categories may overlap; competition counts underfilled teams with a recorded outbid at any completed stage. Player-rejection counts formal T08E rejections, not financially illegal offers. Exception use is summed across 30 franchises within one cohort; the 1,000 CU ceiling remains per franchise.

| Seed | Situation | Passive | Active |
|---:|---|---|---|
| 20261028 | Tanking | 29/30; 2 (2/0); 1; 0/0/0; 600; 600; 0; no | 29/30; 1 (0/1); 1; 0/1/0; 160; 880; 2; no |
| 20261028 | Play-In | 29/30; 2 (2/0); 1; 0/0/0; 600; 600; 0; no | 30/30; 0 (0/0); 2; 0/0/0; 1,280; 880; 2; yes |
| 20261028 | Playoff | 29/30; 2 (2/0); 1; 0/0/0; 600; 600; 0; no | 30/30; 0 (0/0); 2; 0/0/0; 1,280; 880; 2; yes |
| 20261028 | Contender | 29/30; 2 (2/0); 1; 0/0/0; 600; 600; 0; no | 30/30; 0 (0/0); 1; 0/0/0; 880; 880; 4; yes |
| 1604126146 | Tanking | 27/30; 4 (2/2); 3; 0/2/0; 1,170; 800; 0; no | 28/30; 2 (0/2); 3; 0/2/0; 1,170; 800; 2; no |
| 1604126146 | Play-In | 27/30; 4 (2/2); 3; 0/2/0; 1,170; 800; 0; no | 28/30; 2 (0/2); 3; 0/2/0; 1,170; 800; 2; no |
| 1604126146 | Playoff | 27/30; 4 (2/2); 3; 0/2/0; 950; 800; 0; no | 28/30; 2 (0/2); 3; 0/2/0; 950; 800; 3; no |
| 1604126146 | Contender | 27/30; 4 (2/2); 2; 0/2/0; 810; 760; 0; no | 28/30; 2 (0/2); 2; 0/2/0; 810; 760; 4; no |
| 987654321 | Tanking | 29/30; 2 (2/0); 3; 0/0/0; 2,430; 910; 0; no | 30/30; 0 (0/0); 3; 0/0/0; 2,430; 910; 2; yes |
| 987654321 | Play-In | 29/30; 2 (2/0); 3; 0/0/0; 2,430; 910; 0; no | 30/30; 0 (0/0); 3; 0/0/0; 2,430; 910; 2; yes |
| 987654321 | Playoff | 29/30; 2 (2/0); 3; 0/0/0; 2,430; 910; 0; no | 30/30; 0 (0/0); 3; 0/0/0; 2,430; 910; 3; yes |
| 987654321 | Contender | 26/30; 5 (2/3); 1; 0/3/0; 300; 860; 0; no | 29/30; 1 (0/1); 3; 0/1/0; 2,590; 910; 4; no |
| 314159265 | Tanking | 27/30; 4 (2/2); 1; 0/2/0; 260; 630; 0; no | 28/30; 2 (0/2); 1; 0/2/0; 260; 630; 2; no |
| 314159265 | Play-In | 27/30; 4 (2/2); 1; 0/2/0; 260; 650; 0; no | 28/30; 2 (0/2); 1; 0/2/0; 260; 650; 2; no |
| 314159265 | Playoff | 27/30; 4 (2/2); 1; 0/2/0; 260; 650; 0; no | 28/30; 2 (0/2); 1; 0/2/0; 260; 650; 2; no |
| 314159265 | Contender | 28/30; 3 (2/1); 1; 0/1/0; 260; 630; 0; no | 29/30; 1 (0/1); 1; 0/1/0; 260; 630; 2; no |
| 271828182 | Tanking | 27/30; 5 (2/3); 1; 1/1/0; 330; 1,940; 0; no | 28/30; 3 (0/3); 1; 2/2/0; 680; 2,210; 2; no |
| 271828182 | Play-In | 27/30; 4 (2/2); 1; 0/2/0; 330; 850; 0; no | 28/30; 2 (0/2); 1; 1/2/0; 680; 1,090; 2; no |
| 271828182 | Playoff | 27/30; 4 (2/2); 1; 0/2/0; 330; 850; 0; no | 28/30; 2 (0/2); 1; 1/2/0; 430; 1,090; 5; no |
| 271828182 | Contender | 28/30; 3 (2/1); 1; 0/1/0; 330; 850; 0; no | 29/30; 1 (0/1); 1; 1/1/0; 430; 1,090; 4; no |
| 8675309 | Tanking | 28/30; 3 (2/1); 1; 0/1/0; 540; 850; 0; no | 28/30; 2 (0/2); 1; 0/2/0; 540; 850; 2; no |
| 8675309 | Play-In | 27/30; 4 (2/2); 1; 0/2/0; 160; 740; 0; no | 27/30; 3 (0/3); 1; 0/3/0; 160; 740; 3; no |
| 8675309 | Playoff | 28/30; 3 (2/1); 1; 0/1/0; 540; 950; 0; no | 29/30; 1 (0/1); 1; 0/1/0; 950; 950; 4; no |
| 8675309 | Contender | 28/30; 3 (2/1); 1; 1/1/0; 540; 1,600; 0; no | 28/30; 3 (2/1); 1; 1/1/0; 540; 1,600; 0; no |

Passive mode: 116 vacancies before hardship, 64 hardship offers, 37 acquisitions, 27 outbids, and zero player rejections. Final vacancies: 79; no cohort reaches 30/30. Across independent cohorts, ordinary relief used 4,390 CU and hardship relief used 13,840 CU, for 18,230 CU total exception use. Authorized hardship total was 20,830 CU.

Active mode: 62 explicit human offers across both market rounds, clearance, and hardship; 41 hardship acquisitions; 34 final vacancies (2 human, 32 AI); six cohorts reach 30/30. Active exception use totals 23,030 CU across independent cohorts. Human participation leaves two vacancies only in 8675309/Contender; all remaining active vacancies are AI. No offer bypassed T08E or human consent. The active diagnostic does not inspect sealed AI offers.

`Maximum required` is the greatest exact combined overage from authorized offers or residual acceptable contracts. A value above 1,000 CU is a measured economic blocker, not permission to raise the ceiling. Team-level exception use remains within the approved cap in every cohort.

## Exact over-ceiling blockers

| Mode | Seed / situation / team | Payroll | Room | Existing relief | Cheapest acceptable contracts | Total overage required | Additional relief required | Cash after | Competition | Future guaranteed |
|---|---|---:|---:|---:|---|---:|---:|---:|---|---:|
| Passive | 271828182 / Tanking / RSC | 40,900 | 100 | 700 | 900 × 1 year; 1,140 × 1 year | 1,940 | 1,240 | 20,760 | No hardship contest; ceiling blocks authorization | 0 |
| Active | 271828182 / Tanking / RSC | 40,900 | 100 | 700 | 1,140 × 1 year; 1,170 × 1 year | 2,210 | 1,510 | 20,490 | Prior outbid recorded; cap remains independently binding | 0 |
| Active | 271828182 / Play-In / SFS | 40,950 | 50 | 350 | 1,140 × 1 year | 1,090 | 740 | 21,610 | Prior outbid recorded; cap remains independently binding | 0 |
| Active | 271828182 / Playoff / SFS | 40,950 | 50 | 350 | 1,140 × 1 year | 1,090 | 740 | 21,610 | Prior outbid recorded; cap remains independently binding | 0 |
| Active | 271828182 / Contender / SFS | 40,950 | 50 | 350 | 1,140 × 1 year | 1,090 | 740 | 21,610 | Prior outbid recorded; cap remains independently binding | 0 |
| Passive and active | 8675309 / Contender / AUR | 40,700 | 300 | 500 | 900 × 1 year; 1,000 × 2 years (1,000 / 1,050) | 1,600 | 1,100 | 21,100 | No offer submitted; cap shortfall is decisive | 1,050 |

RSC retains the original passive 1,940 CU counterexample. Active human choices leave a different cheapest pair and raise RSC's measured requirement to 2,210 CU. SFS's active 1,090 CU cases are also cap-blocked; recorded prior outbids do not remove the independent ceiling shortfall of 90 CU. AUR's active case has no submitted offer; its two contracts require 1,600 CU, including 1,050 CU future guaranteed salary. These observations do not bound all seeds.

The passive diagnostic records all underfilled teams' payroll, room, exception, shortage, acceptable terms, projected cash, future commitment, and rookie-right outcome. Re-run the reproduction command for complete per-team records.

## Policy handoff

| Option | Benefit | Risk | Decision |
|---|---|---|---|
| A. Keep 1,000 CU combined ceiling | Predictable maximum exposure; preserves approved rule | Fails observed requirements of 1,600, 1,940, and 2,210 CU | Keep as current policy; offseason remains NO-GO |
| B. Raise fixed ceiling | A ceiling above 2,210 CU would cover current measured cases | Arbitrary seed-dependent threshold; still no guarantee; increases future liabilities | Do not recommend |
| C. League-supervised minimum-roster exception | Funds only cheapest T08E-acceptable legal contracts needed for 14, subject to cash solvency | Removes fixed cap bound; risks cap erosion and larger future obligations | Recommend for separate owner review |

Recommendation: C, with the ordinary cap unchanged, exact contract schedules and cash proof, shortage capped at two, auditable team/season/player authorizations, and no automatic renewal in later seasons. Any new authority needs separate owner approval. No new policy is implemented here.

## Transaction, persistence, UI, and recovery

The hardship aggregate is separate from completed clearance history. Each authorization is team/season/offer-bound, records exact ordinary and additional amounts, allowed ceiling, shortage, and consumed transaction IDs. Only `AcquisitionOrigin.hardship` with the exact active offer and next settlement state may use hardship relief. Generic and clearance acquisitions cannot provide hardship fields. Validation cross-checks offer/result/attempt/acquisition/contract/schedule identity, unique ownership, unique outcomes, and current-season cap authority. Ordinary relief stays minimum-only; a hardship contract must satisfy normal acceptance and standard salary rules.

Career schema is v14. v1–v13 decode into an empty hardship settlement; native v14 requires the field and validation rejects malformed records. Existing contract and finance records are retained. Root save-recovery test injects an error after the persisted promotion, reloads explicitly, resumes, and compares full serialized state against uninterrupted execution; no resolution or transaction duplicated or disappeared. The test also checks 360x640 and 393x852 screen layouts and excludes acceptance-threshold disclosure.

The full-seed diagnostic does not auto-confirm human participation. New widget tests exercise the eligible-human dialog: decline leaves settlement unchanged; confirm persists only displayed offers; AI preparation cannot confirm the human team; repeat confirmation and reusing an authorized offer for another player are rejected without mutation. Injected confirmation and acquisition-write failures require reload, then resume without duplicate offers, outcomes, authorizations, or acquisitions.

## Commands and results

| Command | Result |
|---|---|
| `dart analyze` (`packages/simulation_core`) | PASS — `No issues found!` |
| `dart test` (`packages/simulation_core`) | PASS — `All tests passed!`, 935 tests |
| `dart run tool/t08c_financial_audit.dart` | PASS — exit 0; 48 career validations; 0 cap-over teams; historical two-minimum infeasible count 8 |
| `dart run tool/t08e_market_calibration.dart` | PASS — exit 0; reports valuation and acceptance calibration; no policies tuned |
| `dart run tool/t08g_p1_allocation_diagnostics.dart` | PASS — exit 0; 24 rows; no player rejections; AI market outbids recorded |
| `dart run tool/t08h_clearance_diagnostics.dart` | PASS — exit 0; historical clearance evidence reproduced |
| `dart run tool/t08h_p2_hardship_diagnostics.dart` | PASS — exit 0; 24 seed/situation cohorts |
| `flutter test test/hardship_settlement_recovery_test.dart` | PASS — `All tests passed!`, 6 tests after consent additions |
| `flutter analyze test/hardship_settlement_recovery_test.dart` | PASS — `No issues found!` |
| `flutter analyze` (repository root) | PASS — `No issues found!` |
| `flutter test` (repository root) | PASS — `All tests passed!`, 228 tests in prior full run; not repeated after test-only diagnostics |
| `flutter test test/t08h_p2_active_human_diagnostics_test.dart --reporter expanded` | PASS — 24 active cohorts; final test-only edits; 1 test |
| `dart format --set-exit-if-changed lib test tool` (core) | PASS — 206 files, 0 changed |
| `dart format --set-exit-if-changed lib test` (root) | PASS — 63 files, 0 changed |

Windows host: `E:\ballgorithm-dev`. Final core `dart analyze` and 206-file format check passed. Final root `flutter analyze` and 63-file format check passed. Full suites remain the reported 935 core and 228 Flutter tests; no production code changed after those runs. The six-test consent/recovery suite passed after consent changes. The final active diagnostic test passed after the last test-only edits. No season started.

## Independent review and decision

Focused JEV review selected technical acceptance with offseason NO-GO (confidence 0.94; accept probability 0.96); critical-integrity concern probability was 0.11. JEV is an assessment, not proof. Independent reviewer flagged the denominator assertion and ordinary/hardship accounting; both were corrected, the diagnostic reran, and follow-up found no concrete issue. Prior read-only security review found no exploitable defect.

**Offseason confirmation: NO-GO.** Six active cohorts reach 30/30; 18 do not. The approved 1,000 CU combined ceiling fails observed 1,940 CU and 2,210 CU RSC requirements and the 1,600 CU AUR requirement. Human consent, transaction integrity, and recovery tests pass; readiness gate blocks confirmation for remaining vacancies. Keep the regular season unstarted. Any policy change requires new explicit owner approval and separately authorized work.
