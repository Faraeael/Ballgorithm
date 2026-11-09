# M006-T06 Stage A — Reproducibility Audit

- **Date:** 2026-11-09
- **Status:** AUDITED REPRODUCIBILITY VERIFICATION — PASS.
- **Task:** M006-T06B — Stage A reproducibility hardening.
- **Historical v6 Checkpoint:** `68018db98cd033b3008513ff7e6d174eaa81f09f` (M005 accepted).
- **Current v7 Baseline:** `ac187b08db45e5a38c6031bc5c41d6bcc8cf1d08` (M006-T05 accepted evidence).
- **Reproducible Runner Tool:** `packages/simulation_core/tool/m006_pilot_runner.dart`.
- **Offline Analysis Tool:** `packages/simulation_core/tool/m006_analyze_paired.py`.
- **Runtime Environment:** Windows x64, Dart SDK 3.12.2 stable, Python 3.13.1.

---

## 1. Audit Summary & Artifact Checksums

The predetermined 200-game development pilot (seeds 2001–2200) was independently re-executed using the committed runner against both accepted engine checkpoints in isolated worktrees.

| Artifact | File Path | SHA-256 Checksum |
|---|---|---|
| Manifest | `specs/006-role-aware-shot-selection/t06a-development-pilot-manifest.csv` | `1595d322468f76a5d2a86c355248826832b226b1f4f01a9592e79c7c4d287ac6` |
| Paired Seeds CSV | `specs/006-role-aware-shot-selection/t06a-development-pilot-paired-seeds.csv` | `bfd244dada4d7ccfc1fe3699e1fc6e4c80b882d5ad117f0fdce27c4107d1eb26` |
| v6 Regenerated Export | `artifacts/t06a_v6_rerun.json` | `2fa04a1089b534ad958c0a83990e75c3734fb496ead9dbb213a1f658abc8d19d` |
| v7 Regenerated Export | `artifacts/t06a_v7_rerun.json` | `acf780f50e8aef7ba0d3ba1dc94fc64d5927f29995d5ace2efa7806195e32260` |

---

## 2. Execution Commands

To reproduce the pilot from clean checkouts:

```powershell
# 1. Run v7 baseline in main worktree:
cd packages/simulation_core
dart run tool/m006_pilot_runner.dart `
  --manifest=../../specs/006-role-aware-shot-selection/t06a-development-pilot-manifest.csv `
  --out=../../artifacts/t06a_v7_rerun.json `
  --label=v7

# 2. Run historical v6 checkpoint in detached worktree:
git worktree add --detach E:/ballgorithm-v6-checkpoint 68018db98cd033b3008513ff7e6d174eaa81f09f
Copy-Item tool/m006_pilot_runner.dart E:/ballgorithm-v6-checkpoint/packages/simulation_core/tool/m006_pilot_runner.dart
cd E:/ballgorithm-v6-checkpoint/packages/simulation_core
dart run tool/m006_pilot_runner.dart `
  --manifest=E:/ballgorithm-dev/specs/006-role-aware-shot-selection/t06a-development-pilot-manifest.csv `
  --out=E:/ballgorithm-dev/artifacts/t06a_v6_rerun.json `
  --label=v6
cd E:/ballgorithm-dev
git worktree remove --force E:/ballgorithm-v6-checkpoint

# 3. Execute version-neutral analysis and generate paired seeds CSV:
python packages/simulation_core/tool/m006_analyze_paired.py `
  --v6=artifacts/t06a_v6_rerun.json `
  --v7=artifacts/t06a_v7_rerun.json `
  --manifest=specs/006-role-aware-shot-selection/t06a-development-pilot-manifest.csv `
  --paired-csv=specs/006-role-aware-shot-selection/t06a-development-pilot-paired-seeds.csv
```

---

## 3. Reconciliation with Published Stage A Report

Every point estimate, mean difference, standard deviation, and median difference in the reproduced run matches the published `t06a-development-pilot-report.md` exactly to five decimal places:

| Metric | Published Diff ($d_g$) | Reproduced Diff ($d_g$) | Published SD ($s_d$) | Reproduced SD ($s_d$) | Reconciliation Status |
|---|---:|---:|---:|---:|---|
| **Primary creator share** | +0.04304 (+4.30 pp) | +0.04304 (+4.30 pp) | 0.03359 | 0.03359 | **EXACT MATCH** |
| **Secondary creator share** | +0.01024 (+1.02 pp) | +0.01024 (+1.02 pp) | 0.03041 | 0.03041 | **EXACT MATCH** |
| **Neutral player share** | -0.05328 (-5.33 pp) | -0.05328 (-5.33 pp) | 0.03756 | 0.03756 | **EXACT MATCH** |
| **Weak-shooter 3PA share (eligible $N=199$)** | -0.05173 (-5.17 pp) | -0.05173 (-5.17 pp) | 0.08280 | 0.08280 | **EXACT MATCH** |
| **Stretch-big 3PA share (eligible $N=40$)** | +0.00718 (+0.72 pp) | +0.00718 (+0.72 pp) | 0.14910 | 0.14910 | **EXACT MATCH** |
| **Points per game** | +0.12000 | +0.12000 | 15.94228 | 15.94228 | **EXACT MATCH** |
| **Possessions per game** | -0.40500 | -0.40500 | 7.45984 | 7.45984 | **EXACT MATCH** |
| **eFG%** | +0.00174 (+0.17 pp) | +0.00174 (+0.17 pp) | 0.03381 | 0.03381 | **EXACT MATCH** |
| **Team 3PA/FGA share** | -0.00545 (-0.55 pp) | -0.00545 (-0.55 pp) | 0.02850 | 0.02850 | **EXACT MATCH** |
| **Turnovers per 100 poss** | +0.11232 | +0.11232 | 2.09545 | 2.09545 | **EXACT MATCH** |
| **Free throw attempts** | -0.70500 | -0.70500 | 9.25018 | 9.25018 | **EXACT MATCH** |

**Accounting & Reducer Pass Rate:** 200/200 games (100.0%) in both arms passed reducer validation and maintained exact box score reconciliation.

**Verdict:** The Stage A development pilot results are 100% deterministically reproducible.
