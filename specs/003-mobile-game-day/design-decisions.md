# Design Decisions 003 — Mobile Game Day

> **Status:** **FROZEN — OWNER-APPROVED 2026-11-02**. DD-MGD-01…DD-MGD-07 are approved decisions; the
> isolate transport decision (DD-MGD-02) remains contingent on the T021 gate.
> **Frozen at:** `develop/m002`, baseline `6ca43b632e9229216a49966b35bb660c6651c2e8`.

---

## DD-MGD-01 — Milestone naming and roadmap re-sequencing

**Decision (proposed):**

| Milestone | Name | Status |
|---|---|---|
| M003 | **Mobile Game Day** | **FROZEN, owner-approved 2026-11-02.** T020 complete; implementation not authorized (T021–T025 pending). |
| M004 | **Player Participation** (candidate) | Not specified, not numbered as a commitment, not frozen. Carries backlog Priority 2 plus the "future lineup provider interface" concept from M002 RG-03. |
| Later | **Basketball Decision-Making** | Backlog Priority 1. Unassigned to any milestone number. |

**Why this is re-sequencing, not an alteration of M002:**

1. The frozen M002 material uses "M003" as a *forward-looking pointer* to work intentionally left
   out of M002 scope — substitutions, bench minutes, fatigue, foul-outs and tactics
   (`specs/002-possession-simulation/spec.md` §4; `design-decisions.md` D03, OD-09/OD-13; plan §"Probability
   model"). It does not define an M003 specification, acceptance matrix or contract that this
   proposal could contradict.
2. M002's accepted contracts are the versioned simulation rules, event schema, fingerprint,
   PRNG draw order and AC01–AC13 evidence. None of them is named, renumbered, edited or re-scored
   here.
3. No frozen M002 document is rewritten. The pointer remains historically accurate: the participation
   concept is still the next *engine* milestone, now labelled M004.
4. `M003-BACKLOG.md` explicitly states that no item is assigned to a milestone and that assignment
   requires a separate owner decision. Re-sequencing is that decision; the backlog itself is
   unchanged.
5. Repository convention numbers spec directories by milestone (`001-…`, `002-…`). Keeping the
   directory number aligned with the milestone number avoids a second, silent numbering scheme.

**Trade-off accepted:** the oldest unfinished realism work (backlog Priority 1, role-sensitive shot
selection) is not next. It stays mandatory before any full-realism claim, but it is invisible to a
player until a game screen exists, and it requires a new simulation version plus a fresh statistical
gate. Acting on it first would spend the next milestone on evidence no user can see.

---

## DD-MGD-02 — Result transport: return `GameResult` across the isolate boundary

**Decision (proposed):** Option A from `plan.md` §3.2 — the worker returns the `GameResult` itself;
there is no UI-specific DTO and no parallel result model.

**Rationale:**

- Static inspection of the whole graph (`plan.md` §3.1) found only values, enums, strings, ints,
  bools and unmodifiable lists/maps. Nothing on the graph is native-backed or closure-typed.
- `lib/` already passes core models into widgets (`RosterScreen(team:)`,
  `PlayerProfileScreen(player:)`), so a DTO would introduce a second convention, not consistency.
- A DTO would need a mapping layer, an equivalence test and ongoing maintenance, and would create a
  second place where a score can be wrong.

**Condition:** this decision is contingent on the T021 parity test. If any graph member fails to
cross the boundary, fall back to Option B (DTO) and record the failure as design evidence.

**Status of the evidence:** object-graph sendability is a **static hypothesis**, not an empirical PASS.
No isolate has been run against `GameInput`/`GameResult` for this milestone. T021 must prove transport
before T022–T024 are authorized. A failure stops the sequence and returns to the owner; the design is
not changed silently.

---

## DD-MGD-03 — Execution mechanism: Flutter `compute()`

**Decision (proposed):** run `GameSimulator.simulate` through `compute()` from
`package:flutter/foundation.dart`, behind a `GameRunner` interface.

**Rationale:**

- `compute` uses a separate isolate on mobile and desktop, which is the frame-blocking fix.
- On web it runs the callback inline instead of throwing, preserving the documented
  `flutter run -d chrome` development path. Raw `Isolate.run` would require an explicit `kIsWeb`
  branch for the same result.
- `flutter test` uses the Dart VM, so parity tests genuinely exercise isolate message passing.

**Constraints recorded:**

- The callback must be a top-level or static function; it constructs a fresh `GameSimulator` per run.
  No simulator instance or mutable state is shared across the boundary.
- The worker is short-lived per game. No isolate pool, no warm worker, no cancellation protocol —
  a bounded, measured cost on desktop, and an unmeasured one on mobile.
- Web inline execution means a web debug build can jank for the duration of one game. This is a
  development limitation, not a product claim.
- **No synchronous native fallback** is permitted without a separate owner decision supported by
  measurements. If T021 fails, the next step is the DTO fallback (Option B), not removal of the worker.

---

## DD-MGD-04 — Deterministic game seed and rematch sequence

**Decision (proposed):**

```text
teamIndex  = position of the team in league.teams            (0..7 for the default league)
gameSeed   = (league.config.seed
              ^ (homeIndex << 16)
              ^ (awayIndex << 8)
              ^ (rematchIndex & 0xFF)) & 0x7FFFFFFF
rematchIndex starts at 0 and advances modulo 256
```

Rules:

- Pure integer arithmetic; no ambient randomness, no `dart:math Random`.
- **31-bit domain.** The mask yields `0..0x7FFFFFFF` on both the VM and web (Dart web ints have only
  53-bit precision, so the mask must stay well inside it). No derived value can exceed what the core
  will mask, and no derived value can equal `0x9E3779B9`.
- **Rematch index is masked to 8 bits** before mixing. Unmasked, its higher bits would overlap the
  `awayIndex` (bits 8–10) and `homeIndex` (bits 16–18) fields and silently produce seeds belonging to
  a different matchup.
- Home and away are not interchangeable: swapping them yields a different seed.
- Indices are taken from `league.teams` order, which is deterministic for a given generation seed.
- **No normalization aliasing.** The core maps raw `0` to `0x9E3779B9`
  (`GameInput.normalizedSeed`). Every derived seed **except zero** normalizes to itself; a derived zero
  normalizes to `0x9E3779B9`, which is the one value no derived seed can take because it lies outside
  `0..0x7FFFFFFF`. The derived → normalized mapping is therefore injective over the bounded
  `(homeIndex, awayIndex, rematchIndex)` domain: two different bounded inputs can never play the same
  PRNG stream.
- A derived `gameSeed == 0` is legal. It displays as `0`, plays as `0x9E3779B9`, and the setup screen
  states that mapping so the number on screen matches the number the core used.
- The seed used is displayed with the result and on the setup screen before running.

**Bounds and limits (documented, not hidden):**

- Exactly 256 rematch seeds exist per matchup. The masking makes the sequence precisely periodic with
  period 256: rematch 256 repeats rematch 0. The UI bounds the counter to `0..255` and states the
  repeat rather than letting it appear as a fresh fixture.
- `shortcut: rematch seed cycle repeats after 256 games in one matchup, upgrade to a hashed derivation if rematch history ever becomes persistent or unbounded.`
- Different seeds change the PRNG stream; they do **not** guarantee a different scoreboard. Two seeds
  can coincidentally yield equal scores, periods and box scores. Acceptance asserts seed distinctness
  and reproducibility, never outcome difference.

**Tests (T021/T022):** deterministic sequence; equal inputs give equal seeds; swapped roles give
different seeds; consecutive rematches `0..255` give pairwise distinct seeds; every derived value is
within `0..0x7FFFFFFF` and never `0x9E3779B9`; normalized seeds are pairwise distinct over the bounded
domain sample (no alias with the `0 → 0x9E3779B9` rule).

**Exhaustive verification at freeze (2026-11-02):** all 16,384 `(homeIndex, awayIndex, rematchIndex)`
combinations were enumerated for each of eight league seeds — `20261028`, `0`, `1`, `0x7FFFFFFF`,
`0xFFFFFFFF`, `0x9E3779B9`, `0xDEADBEEF`, `12345`. Every case produced 16,384 distinct derived seeds
and 16,384 distinct normalized seeds; no derived seed equalled `0x9E3779B9`; the rematch sequence had
minimal period 256; swapped home/away always differed. `0x9E3779B9 = 2654435769`. This verifies the
integer contract only; it makes no claim about simulation outcomes.

---

## DD-MGD-05 — No simulation change, no version bump

**Decision (proposed):** M003 introduces no change to `packages/simulation_core/lib/**` simulation
behavior, coefficients, clocks, rules, event vocabulary, serialization, PRNG draw order, or any
version identifier (`gameSimulationVersion` stays 4, rules 2, event schema 2, fingerprint 2,
duration model 2, PRNG `xorshift32-v1`, `coreEngineVersion` `1.0.0`).

**Rationale:** the accepted M002 evidence is version-scoped. Leaving the engine untouched means the
accepted evidence continues to describe exactly the code that ships. Any future behavior change
(M004/M005) requires its own version, its own fixtures and its own pre-registered evidence; it does
not retroactively invalidate the v4 record.

**Consequence:** no new calibration cohort is required for M003, and none may be run under this
authorization.

---

## DD-MGD-06 — Mandatory fixed-lineup disclosure

**Decision (proposed):** the result screen must state that each team fields one fixed five-player
lineup, that minutes, substitutions, fatigue and foul-outs are not modelled, that per-player totals
are whole-game totals, and that the output is a deterministic simulation rather than a realism claim.

**Rationale:** the box score visually resembles a real one. Without the disclosure, a plausible-
looking table implies minutes and rotation it did not model. `t019-review-packet.md` documents
`minutes: NOT_MODELED`; `M002-OWNER-ACCEPTANCE.md` §6 lists player minutes under NOT MEASURED and
forbids production or realism claims. The disclosure keeps the presentation honest without changing
the engine.

---

## DD-MGD-07 — Results are ephemeral in this milestone

**Decision (proposed):** a played game exists only as route state. Nothing is persisted; returning to
the league discards the result; there is no results history, no standings and no save format.

**Rationale:** persistence is a separate versioned contract (`snapshotSchemaVersion`, TD-02/TD-03
migration debt) and is out of scope. Adding a save format here would create an untested migration
surface.

**Consequence:** the milestone can be accepted without any persistence or migration evidence. Game
history becomes a later milestone decision, not accidental debt.
