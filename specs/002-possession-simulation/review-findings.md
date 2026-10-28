# M002 Specification Review Findings — Frozen Baseline

Status: **FROZEN — READY FOR IMPLEMENTATION AUTHORIZATION**
Frozen: 2026-10-28. Implementation remains **NOT AUTHORIZED**.
Baseline: `main` at `a431aeb5a652b134ce40cf442c7d9ffee874fe79` (M001 GO/closed).

This document preserves the original audit findings F01–F22 and records their
final disposition after the owner approved A1/A2 and adopted OD-01…OD-14.

## Verdict

No blocking contradiction remains in the M002 specification pack. A1 (duration
distribution) and A2 (`package:crypto`) are owner-approved; OD-01…OD-14 are the
adopted M002 design baseline; `spec.md`, `plan.md`, `design-decisions.md`,
`calibration-plan.md`, `acceptance-matrix.md` and `tasks.md` are frozen for
implementation authorization. M002 implementation is still not authorized.

## ID legend

- **RG-01…RG-05** — review gates in `spec.md` §7.
- **D01…D09** — proposal table in `design-decisions.md`.
- **OD-01…OD-14** — adopted owner decisions in `design-decisions.md`.
- **A1/A2** — owner-approved specification decisions (duration model, SHA-256).
- **F01–F22** — original audit findings.

## A1 adoption evidence (owner-approved 2026-10-28)

Live offensive phases use integer basis-point weights and uniform brackets:

| Phase type | Basis points | Share | Duration |
|------------|--------------|-------|----------|
| Transition | 1500 | 15% | 2–7 s |
| Early offense | 3000 | 30% | 5–11 s |
| Half-court | 5500 | 55% | 10–22 s |

- Per normal phase, exactly two PRNG draws: `nextInt(10000)` for the type, then
  `nextInt(count)` (6/7/13) for the duration offset.
- A possession may contain multiple phases after offensive rebounds or retained
  possession; each new phase draws again.
- Final-tick attempts consume no type/duration draws.
- Durations are phase durations, not per-event delays; dead balls and FTs consume
  zero game time.
- Overshoot is classified, never clamped: shot-clock expiry → turnover; game-clock
  expiry → period end, no shot/TOV/rebound; simultaneous expiry → horn precedence.
- Only a deliberate final-tick attempt (`Rg == 1`) or `D == Rg` may release at
  clock zero, consistent with OD-02.
- `gameActionDurationModelVersion = 1`; provisional and uncalibrated; weight or
  bracket changes require a rules-version bump.
- Fixtures: type boundaries 0/1499/1500/4499/4500/9999; bracket minima/maxima;
  all expiry cases; draw-order determinism (`acceptance-matrix.md — AC04b`).

## A2 adoption evidence (owner-approved 2026-10-28)

`package:crypto` is approved for SHA-256 input fingerprints:

- pure Dart, browser-compatible, no network, no native cryptography;
- deterministic ordered UTF-8 canonical serialization;
- identical fingerprint output on Dart VM and Chrome;
- resolved dependency lockfile-pinned at implementation time;
- first runtime dependency of `simulation_core`, recorded as an AC11 exception;
- no `pubspec.yaml` change or install in this documentation pass.

## Original findings and dispositions

| ID | Original finding | Disposition | Where resolved |
|----|------------------|-------------|----------------|
| F01 | Timing model undefined beyond ">=1 tick" | **RESOLVED (OD-02 + A1)**; ticks, periods, OT, shot clock, freeze, last-second/simultaneous expiry, buzzer/FT completion and the approved duration distribution with expiry classification. | `design-decisions.md — OD-02/A1`, `plan.md — Clock and possession mechanics`, `spec.md — Clock` |
| F02 | Opening possession undefined | **RESOLVED (OD-01)**; normalized-seed parity, zero fallback, alternation each period, no PRNG draw. | `design-decisions.md — OD-01`, `acceptance-matrix.md — AC02b` |
| F03 | Canonical input fingerprint undefined | **RESOLVED (OD-06 + A2)**; ordered UTF-8 JSON, full league snapshot, teams, lineups, seeds, rules (incl. A1), versions, SHA-256, VM/Chrome fixture. | `plan.md — Fingerprint`, `design-decisions.md — OD-06/A2` |
| F04 | Stat/possession semantics unresolved | **RESOLVED**: offensive foul (OD-03), zero-clock FTs (OD-04), player-only TOV equality (OD-05). | `design-decisions.md — OD-03/04/05`, `spec.md — Normative definitions` |
| F05 | Event boundary/order unresolved | **RESOLVED (OD-07)**; explicit game/period/possession events, and-one ordering, integer-only payloads, field schemas. | `plan.md — Event ledger schema`, `plan.md — Canonical ordering` |
| F06 | Shot-clock resets incomplete | **RESOLVED (OD-12)**; made basket/DREB/TOV 24, ORB 14, FT-ORB 14 live only, non-bonus foul reset. | `design-decisions.md — OD-12`, `acceptance-matrix.md — AC04` |
| F07 | AC12 performance target missing | **RESOLVED (OD-08)**; 60 s/1,000 games, p95 100 ms, 128 MiB, environment record. | `design-decisions.md — OD-08`, `spec.md — AC12` |
| F08 | Global event cap missing | **RESOLVED (OD-14)**; 10 OT, 50,000 events, 64 consecutive zero-clock events; typed failures. | `design-decisions.md — OD-14`, `acceptance-matrix.md — AC08` |
| F09 | `stamina` unused / `midrange` implicit | **RESOLVED (OD-09)**; midrange explicit, stamina M003, pre-registered sensitivity. | `design-decisions.md — OD-09`, `calibration-plan.md — AC09` |
| F10 | Home advantage absent vs reporting | **RESOLVED (OD-10)**; labels only, report bias, future rules version. | `design-decisions.md — OD-10`, `spec.md — Out of scope` |
| F11 | Bonus scope ambiguous | **RESOLVED (OD-11)**; 5th regulation / 4th OT, resets, shooting fouls count, offensive fouls do not, and-one exempt. | `design-decisions.md — OD-11`, `acceptance-matrix.md — AC07` |
| F12 | Lineup position semantics ambiguous | **RESOLVED (OD-13)**; one matching primary position each, canonical order, roster ownership, no subs/foul-outs. | `design-decisions.md — OD-13`, `spec.md — Normative definitions` |
| F13 | `GameInput` retention vs snapshot | **RESOLVED (OD-06)**; retains `League`, result stores fingerprint/versions, no duplicate rosters. | `plan.md — Public API` |
| F14 | "Fuzzed inputs" vague for typed API | **RESOLVED**; invalid typed-object construction/fuzz in AC02. | `spec.md — AC02`, `acceptance-matrix.md — AC02` |
| F15 | Possession counting undefined | **RESOLVED**; started/completed/estimated possessions defined separately. | `calibration-plan.md — Mandatory reporting` |
| F16 | No pre-registered AC09 statistics | **RESOLVED**; 200 paired seeds, 95% bootstrap CI excluding zero, effect size, Holm correction. | `calibration-plan.md — AC09`, `spec.md — AC09` |
| F17 | No bands for BLK/STL/pace | **OPEN (non-blocking)**; report-only until owner sets bands at AC10 review. | `calibration-plan.md — Provisional bands` |
| F18 | Unbounded PF under fixed lineups | **LIMITATION**; documented in AC13/report; no foul-outs. | `spec.md — Out of scope`, `acceptance-matrix.md — Accounting corner cases` |
| F19 | No out-of-bounds/team rebounds | **DECLARED SIMPLIFICATION**; one player rebound or `DeadBallMiss`; OREB denominator defined. | `spec.md — Out of scope`, `calibration-plan.md — Mandatory reporting` |
| F20 | Reducer/accounting duplication risk | **RESOLVED**; one accounting implementation shared by reducer and totals. | `plan.md — Replay reducer invariants`, `plan.md — Accounting` |
| F21 | TD-01/02/03 interplay | **ACKNOWLEDGED**; uncalibrated ratings, persistence out of M002. | `specs/technical-debt.md` |
| F22 | New validation codes could alter M001 contract | **RESOLVED**; new `GameValidationCode`, additive exports, approved dependency only. | `plan.md — Proposed package structure`, `spec.md — AC11` |

## Adopted decision register

| ID | Decision | Status |
|----|----------|--------|
| OD-01 | Opening possession by normalized-seed parity, alternate periods, no PRNG draw | ADOPTED |
| OD-02 | Integer clocks, 720/300, SC 24, dead ball 0, last-second/simultaneous expiry, buzzer/FT completion | ADOPTED |
| OD-03 | Offensive foul: PF + player TOV, no team bonus, no FGA/points, possession transfer | ADOPTED |
| OD-04 | Zero-clock FTs complete; missed final FT = `DeadBallMiss`; no new live possession | ADOPTED |
| OD-05 | One active player per TOV; `team.TOV == sum(player.TOV)`; PG default for SC violation | ADOPTED |
| OD-06 | Versioned ordered UTF-8 JSON + SHA-256 fingerprint over full league, lineups, seed, rules, versions | ADOPTED |
| OD-07 | Immutable typed events incl. game/period/possession boundaries; integer-only payloads; one accounting path | ADOPTED |
| OD-08 | 1,000 games ≤60 s; p95 ≤100 ms; ≤128 MiB; environment recorded; provisional | ADOPTED |
| OD-09 | Midrange explicit; stamina reserved; twelve-attribute schema unchanged; pre-registered sensitivity | ADOPTED |
| OD-10 | No home advantage; labels only; bias reporting | ADOPTED |
| OD-11 | Bonus: 5th regulation / 4th OT; resets; shooting fouls count; offensive fouls do not; and-one exempt | ADOPTED |
| OD-12 | Shot-clock resets 24/14 as enumerated; no reset after period end | ADOPTED |
| OD-13 | Five unique players, one per PG..C, canonical order, no subs/foul-outs | ADOPTED |
| OD-14 | 10 OT; 50,000 events; 64 consecutive zero-clock events; typed failures | ADOPTED |
| A1 | Phase duration weights 1500/3000/5500 and brackets 2–7/5–11/10–22, versioned/uncalibrated | APPROVED |
| A2 | `package:crypto` SHA-256 dependency, pure Dart/browser/no native, lockfile-pinned at implementation | APPROVED |

## Retained corrections and edge cases

- C1 possession/and-one vs rebound; C2 100 vs 200 seeds; C3 AC09 clarified to
  directional aggregate effects (never per-game monotonicity); C4 test counts;
  C5 team TOV equality; C6 foul field semantics; C7 game-boundary/dead-ball
  events; C8 game clock non-increasing while shot-clock increases only through
  enumerated OD-12 resets; C9 possession after an and-one or shooting-foul FT is
  conditional on made final FT/defensive rebound/zero-clock dead ball — a live
  offensive rebound continues the same possession and starts a new phase.
- N03 seed aliases (`s`, `s+2^32`) produce identical events but distinct
  fingerprints; N04 zero seed starts away; N05 OT bonus at 4th team foul; N06
  offensive foul cannot coexist with a made basket; N07 zero-clock missed FT
  never rebounds; N08 the 64-event zero-time guard must permit legitimate FT
  sequences; N09 full-league fingerprint changes on unrelated roster edits; N10
  no pass/fail bands yet for BLK/STL/pace; N11 performance sign-off depends on a
  reference machine; N12 crypto must stay browser-safe and IO-free; N13 the
  10–22 s half-court bracket against a 14 s offensive-rebound reset will produce
  overshoot shot-clock turnovers, which must be reported as a calibration finding,
  not clamped; N14 the final-tick forced-shot selection/zone must be documented by
  the probability model like any other shot; N15 A2 supersedes the M001-era
  "no runtime dependencies" note for `simulation_core`, while M001 documents stay
  frozen and are amended only by a separate M001 documentation change. N01/N02
  are closed by A1/A2.

## Non-blocking limitations and deferred work

- One-second granularity; no sub-second events.
- Fixed lineups; no substitutions, fatigue, foul-outs or multi-position players.
- No out-of-bounds/team rebounds; every live miss resolves to one player rebound
  or `DeadBallMiss`.
- No home-court advantage.
- No special late-two-minute rules.
- Simplified player-only turnover scorekeeping.
- Ratings remain uncalibrated (TD-01); no realism claim before AC10 owner review.
- BLK/STL/pace bands are not yet defined (F17); AC10 owner review remains.
- Persistence/migration (TD-02/TD-03) out of M002.
- Release packaging and Android performance remain out of scope.

## Repository status

- HEAD `a431aeb5a652b134ce40cf442c7d9ffee874fe79`, branch `main`, tracking
  `origin/main`; nothing committed or pushed.
- Pre-existing `README.md` modification (supplied pack; untouched).
- Untracked `AGENT_PROMPT_SPEC_ONLY.md` and `specs/002-possession-simulation/`.
- No application, simulation, test, dependency, version or M001 document changes.
- All 20 M002 task checkboxes remain unchecked.

## Required next step

Implementation authorization (T003) in a separate instruction. No M002 code may
be written before that.
