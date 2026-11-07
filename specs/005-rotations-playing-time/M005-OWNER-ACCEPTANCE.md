# M005 — Owner Acceptance Record

> **Decision:** **PASS — M005 Rotations & Playing-Time Management is accepted.**
> **Date:** 2026-11-07
> **Owner authority:** explicit owner decision of 2026-11-07, recorded in the M005 integration
> request. This file replaces the provisional acceptance status of
> `M005-T06-ACCEPTANCE-REPORT.md`; that report is preserved unchanged as historical review
> evidence.
> **Baseline before integration:** `develop/m002` at `f1aa16adbe75c6d872f1eeec3ee5b79e39a9f243`.
> **Accepted implementation:** `fix/m005-slider-stable-scale` at
> `68018db98cd033b3008513ff7e6d174eaa81f09f`.

## 1. Decision

The owner accepts M005 as **PASS**. The accepted scope is the delivered rotation system: the
validated rotation-plan contract, the deterministic playing-time policy, simulator tactical
substitutions across W1/W2/W4/W5 with mandatory-first precedence, overtime allocation, the v6
canonical fixture and no-plan v5 equivalence, and the Flutter setup, transport, results and
rematch surfaces.

This acceptance is not a claim of basketball realism, calibration, Android performance or store
readiness.

## 2. Approved evidence substitution

The owner explicitly approves **Chrome** as the substitute for the M005 physical Android
walkthrough. Consequently AC-M005-33 is satisfied by the recorded browser evidence plus the owner's
personal verification, not by a physical-device run.

Android performance, physical-device behavior, memory usage, battery behavior and large-text
accessibility remain **NOT MEASURED**.

## 3. Final correction included in the acceptance

The final accepted build resolves the owner-reported slider coupling defect at
`68018db98cd033b3008513ff7e6d174eaa81f09f`:

- every rotation slider uses a fixed **0–48 minute** scale (0–2,880 seconds) that never changes
  with the shared budget;
- the team budget is a hard **240 minute** (14,400 player-second) limit enforced in the state
  handler, with drag proposals clamped and fine adjustments rejected outside the legal bound;
- only the edited player's allocation changes; unrelated sliders keep their value, scale and thumb
  position;
- the owner personally verified the corrected sliders and confirmed that the simulated results show
  the correct player minutes.

## 4. Evidence classes

| Class | What it covers |
|---|---|
| Earlier end-to-end browser evidence | The T06 Chromium walkthrough on the pre-slider build: setup, presets, custom editing, invalid-total blocking, a completed game, target-versus-actual minutes, exact 14,400-second conservation, repeat-run determinism and rematch preservation (`M005-T06-ACCEPTANCE-REPORT.md`, §3–§4, local screenshots). |
| Final-version browser observations | Chromium on `68018db` at 393 dp and 360 dp: one drag moved several minutes on the edited slider only; an untouched player's slider stayed at 31:19 with an unchanged thumb; the fine `+10s` control changed only the edited player; no horizontal overflow at 360 dp. The final-version reallocation-to-240:00 and confirm step could not be replayed in the headless accessibility session because the automation harness stopped delivering pointer events to canvas sliders after scrolling; that limitation is recorded, not repaired by assumption. |
| Automated regressions | Flutter widget tests, core VM suite and Chrome-compatible core suite listed in §6. These cover full-budget enforcement, independent slider adjustment, clamping, integer precision, preset-to-custom preservation, transport, rematch and layouts at 360/393/430 dp. |
| Owner observations | Personal review of the corrected rotation editor and of the simulated player minutes, as stated in the 2026-11-07 owner decision. |
| Not observed | No final-build owner-observed rematch run exists. Rematch preservation is verified by the automated tests and the earlier browser evidence; this record does not invent a final-build owner rematch observation. |

## 5. AC-M005-33 reconciliation

**AC-M005-33 — PASS.** The requirement demands a physical-device walkthrough *or an
owner-approved substitute*. The owner approved Chrome as that substitute. The recorded evidence
shows legal tactical substitutions, bench participation, deterministic repeat, plan-preserving
rematch and a visibly different preset (earlier end-to-end run), and the final build's independent
slider behaviour (final-version observation and automated tests). No test is claimed that was not
executed; the one unexecuted final-build step is named in §4.

All other acceptance rows remain as recorded in the implementation evidence referenced by
`M005-T06-ACCEPTANCE-REPORT.md`: AC-M005-01…32 and 34–35 are supported by the automated suites and
the walkthrough evidence described there. The T06 report's "NOT RUN" value for AC-33 is superseded
by this owner-approved substitution.

## 6. Verification at integration time

| Command | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 111 passed, 0 failed |
| `dart analyze` (core) | No issues found |
| `dart format --set-exit-if-changed lib test` (core) | 78 files, 0 changed |
| `dart test` (core VM) | 547 passed, 0 failed |
| `dart test -p chrome …` (IO isolation test excluded) | 546 passed, 0 failed |
| `dart format --output=none --set-exit-if-changed lib test` (app) | 22 files, 0 changed |

## 7. Preservation and integration

- Frozen M005 specification files are unchanged.
- Historical M001–M004 acceptance records are unchanged.
- `M005-T06-ACCEPTANCE-REPORT.md` is preserved byte-for-byte as written before this decision; it
  is superseded only for acceptance status, never deleted or rewritten.
- The accepted implementation was integrated into `develop/m002` by a normal fast-forward from
  `f1aa16adbe75c6d872f1eeec3ee5b79e39a9f243` to the integration commit; no force push, no merge
  commit, no rebase of published history.
- `main` remains `a431aeb5a652b134ce40cf442c7d9ffee874fe79`.

## 8. Remaining non-claims

- No NBA or calibrated realism claim.
- AC09/AC10 are not re-certified.
- Android performance, memory, battery, physical-device behaviour and large-text accessibility:
  NOT MEASURED.
- No M006 work has started. No release has been produced.
