# M006 — Specification Erratum: Early-Phase Three-Point Reference Figures

> **Status:** documentation erratum recorded under owner authorization for M006-T04
> (2026-11-07). The frozen specification, its acceptance thresholds, the frozen design branch and
> the owner decision record are **not** modified.

## 1. What is wrong

`spec.md` §3.3 ends its audit with a phase check. Its two below-50 three-point figures were not
updated when the owner approved the 70/30 piecewise curve, so they describe an earlier draft.

| Archetype (early phase) | Spec text (v7) | Correct value under the frozen formula |
|---|---|---|
| Weak PG (40/45/30, ath 55) | 39.9 % | **36.30 %** |
| Non-shooting C (80/35/20, ath 65) | 16.9 % | **9.21 %** |
| High-three C (75/55/80, ath 60) | 36.4 % | 36.45 % (reproduces) |

The same line also lists the v6 values 43.9 % and 25.1 %, which both reproduce exactly.

## 2. Why the frozen formula is right and the text is wrong

The approved curve is `ability(p) = 70·(p − 50)` below 50 and `30·(p − 50)` otherwise, with
`three = max(200, 3600 + ability + slotThree + phaseThree)`. With early-phase `phaseThree = 0`:

- Weak PG, slot 0 (`slotThree = 250`): `3600 − 1400 + 250 = 2450`; raw vector
  `1830 / 2470 / 2450`; normalized three share `2450 / 6750 = 36.30 %`.
- Non-shooting C, slot 4 (`slotThree = −900`): `3600 − 2100 − 900 = 600`; raw vector
  `4110 / 1810 / 600`; normalized three share `600 / 6520 = 9.21 %`.

The spec's 39.9 % and 16.9 % are reproducible only with a 50-point below-average slope. Because the
six half-court audit vectors reproduce exactly under 70/30 (39.3 / 40.1 / 12.3 / 38.5 / 40.3 /
45.2 %), and the high-three phase figure reproduces under 70/30 while the two weak-shooter phase
figures do not, the discrepancy is a stale-draft residual in the phase-check sentence, not a policy
question.

## 3. Effect on acceptance

No acceptance criterion depends on the phase-check figures:

- AC-M006-10 tests the 70/30 curve itself.
- AC-M006-11 and AC-M006-12 use the half-court vectors, which reproduce.
- The `verification-plan.md` §4 controlled table is half-court only.

Therefore no threshold, matrix row or decision changes. The corrected figures are pinned in
`packages/simulation_core/test/simulation/m006_t03_shot_preference_test.dart` and recorded with the
raw vectors in `t03-implementation-evidence.md` and `t04-implementation-evidence.md`.

## 4. What remains unchanged

- `spec.md` — not rewritten; its frozen text keeps the original figures with this erratum as the
  dated correction, matching the repository rule that frozen specification text records the state at
  freeze time.
- `acceptance-matrix.md`, `verification-plan.md`, `design-decisions.md`, `tasks.md`,
  `M006-OWNER-DESIGN-FREEZE.md` — untouched.
- The frozen design branch `design/m006-role-aware-shot-selection` — untouched.
