# Amendment 004 — Evidence Recovery Addendum

> **Date:** 2026-10-31
> **Status:** EVIDENCE-RECOVERY TASK COMPLETE — NOT a new calibration experiment
> **Baseline:** `9f8458ab345ea7c075f3b910b60d7ee964f1c5fe` (v3)
> **Candidate:** `c359c3577f14d7e903c9e8836912f7045dba0b52` (v4, `develop/m002`)
> **Authorization:** owner Option A — deterministic re-execution of the DEVELOPMENT pilot to repair incomplete evidence

This addendum does not modify the frozen experimental protocol
(`amendment-004-turnover-calibration-spec.md`), any coefficient, any clamp, any
duration bracket, or any acceptance threshold. It repairs the *evidence record*
for an experiment whose gates were already defined before execution.

---

## 1. Why the earlier evidence was insufficient

The original Amendment 004 pilot commit (`c359c35`) claimed a full recovery of the
280-game pilot and the T014 E1–E6 sensitivity gate. Independent audit found four
defects.

### 1.1 One pre-registered gate had no persisted evidence

The frozen gate table (specification §3.2) has nine gates. The eighth is
**"Attribute Sensitivity (T014 E1–E6): all maintain expected sign, $p<0.05$"**.
The committed `amendment-004-statistical-summary.json` contains no
attribute-sensitivity entry, and the runner artifact that produced those numbers
(`v4_t014_summary.json`) had been deleted after aggregation. Gate G9 therefore
existed only as terminal output in a chat transcript, which is not reproducible
evidence.

### 1.2 The recorded checksums did not describe the committed bytes

| Artifact | Recorded SHA-256 (working tree) | Committed blob SHA-256 |
|---|---|---|
| `amendment-004-pilot-sample.csv` | `16e6256a…58b3` | `d12a0a5d…3f03` |
| `amendment-004-statistical-summary.json` | `23d98cd3…cd34` | `674e7283…3759` |

Cause: `core.autocrlf` normalized CRLF to LF on commit. The recorded hashes
described untracked working-tree bytes, so checking out the commit could never
reproduce them. Reporting them as repository checksums was incorrect.

### 1.3 Two gates were not independently recomputable

G7 (3PA/FGA) and G8 (eFG%) were recorded only as pre-aggregated values in the
summary JSON. The committed per-game CSV carried no `threePa`, `fgm` or `threePm`
columns, so a reviewer could not recompute them from per-game evidence.

### 1.4 A fabricated and a non-existent commit identifier were reported

Two SHAs appeared in earlier agent reporting that do not correspond to this
repository: an ending HEAD of `c359c3558836511a2f1ef32551ec94d80eb5c557` (actual
`c359c3577f14d7e903c9e8836912f7045dba0b52`) and a candidate commit
`83edd5288d8db9bc5397f259fe7b79bebc04a9e5` in the summary JSON (actual
`83edd52c54baccfedfd7801c2a08db07377de3c6`). Both are corrected here.

---

## 2. A withdrawn non-gate: "live steals did not decline"

Earlier reporting listed "Live Steals: No decline → PASS". That line is
**withdrawn**. It was not a pre-registered criterion:

- The frozen §3.2 gate table has nine metrics; live-steal volume is not among them.
- `grep -ri "no decline" specs/002-possession-simulation/*.md` returns no hits in
  any committed document.
- Amendment 003's manifest §5.3 does define *per-phase* steal bands
  `[4.5%, 5.5%]` and non-steal bands `[4.8%, 5.8%]`, but those governed the
  Amendment 003 experiment and were deliberately omitted from the Amendment 004
  frozen gate set.

The observed difference (v3 13.154 → v4 13.061 steals per game, i.e. −0.093 per
game, or 6.39 → 6.36 per 100 completed possessions) is therefore reported as a
**diagnostic**, with no PASS or FAIL verdict attached. It is neither a pass that
was earned nor a failure that was suppressed.

No tenth gate is added retrospectively.

---

## 3. Corrected methodology

Two tracked, reviewable runners replace the deleted ad-hoc scripts. Both are
version-agnostic: they compile against whichever `simulation_core` package they
are placed in, so the same code produces the baseline and candidate evidence.

### 3.1 Pilot runner

`packages/simulation_core/tool/amendment_004_pilot_runner.dart`

- Frozen cohort only: 56 directed matchups (28 lexicographic pairs × 2
  orientations), first 5 development slots each, seed
  `1 + ((97·m + 17·s) mod 200)`, league seed `20261028`.
- 280 paired inputs; no held-out seeds; no parameter selection.
- Validates every game through the reducer and reconciles `EventAccounting`
  against the reported score before a row is accepted.
- Emits per-game `fga`, `fgm`, `threePa`, `threePm`, `fta`, `ftm`, turnover
  subtypes, fouls by kind, completed possessions, and phase denominators
  (`sampledPhases`, `actionPhases`, `freshPhases`, `orebPhases`,
  `orebViolations`, `retFoul14Phases`, `retFoul14Violations`), so gates G1–G8 are
  recomputable by a third party.

```bash
# candidate (v4)
cd packages/simulation_core
dart run tool/amendment_004_pilot_runner.dart /tmp/v4_recovery.json

# baseline (v3) from an isolated checkout of the pinned commit
git archive 9f8458ab345ea7c075f3b910b60d7ee964f1c5fe packages/simulation_core \
  | tar -x -C <dir> --strip-components=2
cp packages/simulation_core/tool/amendment_004_pilot_runner.dart <dir>/tool/
cd <dir> && dart pub get && dart run tool/amendment_004_pilot_runner.dart /tmp/v3_recovery.json
```

### 3.2 T014 sensitivity runner

`packages/simulation_core/tool/amendment_004_t014_runner.dart`

Re-executes the frozen T014 protocol unmodified (seeds 1–200, six
pre-registered interventions, +20 rating delta, frozen bootstrap and permutation
seeds) and persists the complete summary plus per-seed rows, so gate G9 is
auditable from an artifact instead of a transcript.

```bash
cd packages/simulation_core
dart run tool/amendment_004_t014_runner.dart /tmp/v4_t014.json
```

---

## 4. Original versus recovered results

Every recovered metric reproduces the original pilot **exactly**, with zero
tolerance (identical rational values, not rounded agreement).

| Metric (v4 arm) | Original | Recovered |
|---|---|---|
| Offensive fouls / team-game | 5.542857 (v3) / 2.312500 (v4) | 5.542857 / 2.312500 |
| TOV / 100 completed possessions | 20.507619 / 17.463936 | 20.507619 / 17.463936 |
| Completed possessions / team-game | 103.001786 / 102.619643 | 103.001786 / 102.619643 |
| Shot-clock violations / game | 4.164286 / 4.242857 | 4.164286 / 4.242857 |
| Live steals / game | 13.153571 / 13.060714 | 13.153571 / 13.060714 |

The first recovery attempt did **not** reproduce. Diagnosis: the new runner
incremented the pair index inside the orientation loop, selecting directed
matchups 0, 3, 4, 7, 8, … instead of 0, 1, 2, 3, …. Both arms drifted together
by the same amount, which identified the cause as cohort selection rather than a
behavioural change. The increment was moved outside the orientation loop and both
arms then reproduced exactly. The defect is recorded here rather than quietly
fixed, because the first recovered numbers were wrong and were not adopted.

---

## 5. Nine frozen gate verdicts (recomputed from recovered evidence)

Source artifacts: `pilot-v4-raw.json` (G1–G8), `t014-v4-raw.json` (G9).

| Gate | Metric | Frozen threshold | Computed | Method | Verdict |
|---|---|---|---|---|---|
| G1 | Offensive fouls / team-game | `[1.80, 2.60]` | 2.312500 | `sum(offensiveFoulTov)/280/2` | **PASS** |
| G2 | Offensive-foul share of turnovers | `[0.100, 0.160]` | 0.129035 | `sum(offensiveFoulTov)/sum(tov)` | **PASS** |
| G3 | Turnovers / 100 completed possessions | `[15.0, 19.5]` | 17.463936 | `sum(tov)/sum(completed)*100` | **PASS** |
| G4 | Shot-clock violations / game | `[3.0, 5.5]` | 4.242857 | `mean(shotClockTov)` | **PASS** |
| G5 | Completed possessions / team-game | `[100.0, 106.0]` | 102.619643 | `mean(completed)/2` | **PASS** |
| G6 | Team median FGA | `[88.0, 95.0]` | 92.0 | `median(homeFga ∪ awayFga)` | **PASS** |
| G7 | 3PA / FGA | `[0.380, 0.450]` | 0.415205 | `sum(threePa)/sum(fga)` | **PASS** |
| G8 | eFG% | `[0.510, 0.540]` | 0.528598 | `(sum(fgm)+0.5·sum(threePm))/sum(fga)` | **PASS** |
| G9 | T014 E1–E6 attribute sensitivity | all expected sign, `p<0.05` Holm | all six PASSED | frozen T014 protocol | **PASS** |

### 5.1 T014 E1–E6 detail (v4)

| ID | Expected | Mean difference | Raw p | Holm p | Verdict |
|---|---|---|---|---|---|
| E1 | increase | +0.088505 | 0.0001 | 0.000600 | PASSED |
| E2 | increase | +0.125257 | 0.0001 | 0.000600 | PASSED |
| E3 | increase | +0.012464 | 0.0001 | 0.000600 | PASSED |
| E4 | decrease | −0.830135 | 0.0001 | 0.000600 | PASSED |
| E5 | decrease | −0.068626 | 0.0001 | 0.000600 | PASSED |
| E6 | increase | +29.208988 | 0.0001 | 0.000600 | PASSED |

`ac09` recorded by the runner is the T014 protocol's own six-experiment verdict
under v4. It is **not** a milestone AC09 sign-off; historical AC09 remains
inconclusive on Amendment 002 evidence and AC10 remains owner-review-pending.

### 5.2 Diagnostic, explicitly not a gate

Per-action-phase steal rate under v4 is 5.22% and non-steal 5.56%. Under the
inherited Amendment 003 per-phase bands (`[4.5%, 5.5%]` and `[4.8%, 5.8%]`) these
would sit at the upper edge of the steal band. Those bands are **not** applicable
to Amendment 004, where no per-phase turnover-rate gate was frozen. Reported for
completeness only.

---

## 6. Reproducibility and checksum policy

- All artifacts in this directory are marked `-text` by a local `.gitattributes`,
  so Git performs no newline conversion and the committed blob is byte-identical
  to the working-tree file.
- Recorded SHA-256 values are computed over **LF-normalized bytes** and are
  therefore valid both for the working tree and for `git show <commit>:<path>`.
- Git object IDs (SHA-1/SHA-256 of the git object) are a different namespace and
  are not used as content checksums anywhere in this record.

| Artifact | Canonical SHA-256 (LF bytes) |
|---|---|
| `pilot-v3-raw.json` | `002838b3a48a0f29199c55f38d3aa973bd25d2a84296cc7724fab829df8b33f3` |
| `pilot-v4-raw.json` | `97729132a563809a46e072c9e55325012c73f9c4bb50215d04390bcf10cdb316` |
| `pilot-paired-recovered.csv` | `a6b527b91b274b7e83b399305883c24c9ae8e58cee6a4ee820a165a2487202d3` |
| `t014-v4-raw.json` | `62371e05ad820e804bf10b45529302041b9b85c12233d7bbe9efffbdec987cb4` |
| `gate-audit-recovered.json` | `e15f002859f8bc903747114641a641c253c25d64546e0ed39a9603625a674f91` |

### 6.1 Verification step

```bash
python specs/002-possession-simulation/amendment-004-recovery/verify_evidence.py
```

The verifier fails with a non-zero exit when any required artifact is missing or
empty, when any recorded checksum does not match the LF-normalized bytes, when a
required artifact is not covered by `CHECKSUMS.sha256`, when any gate recomputes
outside its frozen bound, when a recorded verdict disagrees with the recomputed
verdict, when any T014 experiment is not `PASSED`, or when the pilot dataset
contains a seed outside 1–200, a duplicate `(matchupIndex, seed)` pair, or a
matchup index outside 0–55. It re-derives gates from raw rows and does not trust
`gate-audit-recovered.json`.

Observed output:

```
EVIDENCE VERIFICATION PASSED
  artifacts checked: 5
  gates recomputed:  G1-G8 from pilot-v4-raw.json, G9 from t014-v4-raw.json
  provenance:        development seeds 1..200, matchups 0..55, 280 unique slots
```

---

## 7. Original artifacts preserved

The defective original artifacts are **not** overwritten or deleted:

- `specs/002-possession-simulation/amendment-004-pilot-sample.csv`
- `specs/002-possession-simulation/amendment-004-statistical-summary.json`
- `specs/002-possession-simulation/amendment-004-turnover-calibration-spec.md`

They remain the historical record of what was originally claimed, including their
incorrect checksum values, which this addendum documents rather than erases. The
recovered artifacts live alongside them in `amendment-004-recovery/`.

---

## 8. Outstanding limitations

1. **Development seeds only.** The cohort reuses seeds 1–200, already explored by
   T013/T014/T015. This is reproduction of a development pilot, not independent
   validation.
2. **One league, eight rosters.** All conclusions are scoped to the M001 fixture
   generated with seed `20261028`.
3. **Clamp floor not probed.** With a 170 bp base, high-IQ low-opposition-IQ
   lineups compress against the retained `[100, 1000]` bp floor. The pilot does
   not quantify how often the floor binds. Changing the clamp remains
   unauthorized and would require a separate proposal.
4. **Amendment 003 gate failures stand.** The v3 pace delta (+2.21% development,
   +2.05% held-out, against a `+2.5%` minimum) and the v3 offensive-foul turnover
   share (26.02% / 25.67% against a `24.0%` maximum) remain formal failures.
   Nothing here retroactively corrects them; v4 changes a different coefficient
   and is a separate model version.
5. **No held-out execution.** The fresh held-out cohort authorized in principle
   was not run and is not started by this addendum.
6. **AC09 and AC10 unchanged.** Neither is marked passed.
