# M003+ — Deferred Basketball Realism Backlog

> **Date:** 2026-10-31
> **Status:** PLANNING INPUT ONLY. No item here is assigned to a frozen milestone, authorized for implementation, or scheduled. Nothing in this file is started.
> **Origin:** conditions attached to `M002-OWNER-ACCEPTANCE.md` ("M002 — ACCEPTED WITH CONDITIONS — TECHNICAL POSSESSION-ENGINE FOUNDATION ONLY") plus the T019 human review and the advisory JEV evaluation.
> **Relationship to M002:** these are **future requirements**, not newly discovered M002 failures. Every item below lies outside the frozen M002 acceptance matrix (AC01–AC13). No historical M002 result is re-opened by listing them.

Owner priority ordering is preserved. Within a priority the items are unordered.

---

## Priority 1 — Player decision-making

| # | Requirement | Why it matters | M002 state |
|---|---|---|---|
| P1-1 | **Role-sensitive shot selection** | Shot choice currently derives from zone/usage weightings that are not role-aware; the advisory JEV flagged shot selection as the largest residual blocker (17%). | Not modelled |
| P1-2 | **Prevent weak three-point shooters from routine inappropriate perimeter volume** | Perimeter volume should respond to demonstrated shooting ability and role, not only to positional base weights. | Partially implicit; not role-gated |
| P1-3 | **Preserve viable stretch-big archetypes** | Any fix for P1-2 must not eliminate legitimate perimeter-shooting bigs — the constraint that makes P1-2 non-trivial. | Not modelled |
| P1-4 | **Evaluate per-player shot profiles and usage** | Requires per-player shot-location and usage data, which no committed M002 artifact stores (T019 flagged this as UNAVAILABLE). | Not measured |

## Priority 2 — Player participation

| # | Requirement | Why it matters | M002 state |
|---|---|---|---|
| P2-1 | **Foul-out rules** | A player can currently accumulate unlimited fouls; P3 of the T019 packet recorded a player with 9 personal fouls. | Not modelled |
| P2-2 | **Substitutions and rotations** | Every team fields one fixed five for the whole game. | Not modelled |
| P2-3 | **Player minutes** | T019 emits `minutes: NOT_MODELED`; per-player totals are shares of team production, not rates. | Not modelled |
| P2-4 | **Fatigue / stamina effects** | `stamina` exists as a rating but does not degrade performance; a 6-period double-overtime game costs players nothing (T019 P6). | Rating present, unused |

## Priority 3 — Player roles

| # | Requirement | Why it matters | M002 state |
|---|---|---|---|
| P3-1 | **Ball-handling exposure** | Live-turnover attribution is `exposure × hazard`; a HAN-16 centre still drew 16.3% of attribution in T019 P2. Design question, not a defect. | Implemented, review open |
| P3-2 | **Turnover distribution** | Roll-ups by cause exist per game, but no cross-player calibration of turnover share vs archetype. | Evidence gap |
| P3-3 | **Assist distribution** | T019 P1 showed a near-uniform assist spread (PG 8, C 8, SG 7, SF 6, PF 5); realism unverified. | Evidence gap |
| P3-4 | **Offensive roles and decision-making** | No role model (primary handler vs off-ball vs post) beyond positional weighting. | Not modelled |
| P3-5 | **Additional league-fixture validation** | All M002 evidence uses one generated league (seed 20261028) with eight rosters; generalization is unmeasured. | Single fixture |
| P3-6 | **Offensive-foul clamp-floor binding frequency** | The `[100, 1000]` bp clamp floor's binding rate was never measured (M002 limitation L5). | NOT MEASURED |
| P3-7 | **Inside-vs-midrange shot-zone distribution** | Held-out rows record FGA/FGM and 3PA/3PM only; the 2-point zone split is not measured (M002 limitation L6). | NOT MEASURED |
| P3-8 | **Historical evidence gaps** | Amendment 003 held-out per-game artifacts are absent from the repository; those figures are cited in downstream prose only (M002 limitation L9). Any future re-use must re-establish them or cite them as reported-only. | Evidence gap |

## Priority 4 — Mobile

| # | Requirement | Why it matters | M002 state |
|---|---|---|---|
| P4-1 | **Flutter isolate integration** | `GameSimulator.simulate` is synchronous and CPU-bound; on the UI isolate it would block frames for the whole game. | Not implemented |
| P4-2 | **Android performance testing** | AC12 was measured on desktop AOT only; Android is **NOT MEASURED** (no device, emulator or profile run). | NOT MEASURED |
| P4-3 | **Device memory and battery considerations** | Memory evidence is RSS-based on desktop (22–23 MiB incremental); no mobile heap, thermal or battery data exists. | NOT MEASURED |

---

## Retained M002 limitations (carried forward, not resolved)

| # | Limitation | M002 classification |
|---|---|---|
| L1 | Single generated league, eight rosters | Owner decision |
| L4 | RSS-based memory measurement; AOT GC not forceable | Owner decision |
| L5 | Offensive-foul clamp-floor binding unmeasured | Owner decision → see P3-6 |
| L6 | Inside-vs-midrange shot-zone split unmeasured | Owner decision → see P3-7 |
| L7 | Remaining NBA realism differences (TOV/100 ≈ 17.43 held-out; ~4.17 shot-clock violations/game) | Owner decision |
| L8 | Historical Amendment 003 guardrail failures preserved | Owner decision |
| L9 | Amendment 003 held-out raw evidence absent from repo | Owner decision → see P3-8 |
| L10 | Amendment 004 D1 qualified procedural exception | Owner decision, recorded |
| L12 | Player-level stat lines absent from committed evidence | Owner decision → see P1-4 |

## Constraints on any future work in this backlog

1. **M001 preservation remains inviolable** — league generation, snapshot format, PRNG vectors and `coreEngineVersion` must not change as a side effect.
2. **Determinism and contract versioning** — any change to draw order, coefficients, brackets or event serialization requires impact analysis, new version identifiers and a specification amendment; historical fixtures are never re-baselined to make a failure pass.
3. **Pre-registration** — statistical claims need a frozen protocol, separated development and held-out seeds, and recorded decisions made before results are seen.
4. **No retroactive rewrites** — Amendment 003's guardrail failures, T015's band breach, T014 v1's E4 inconclusive result and the D1 exception remain in the record permanently.
5. **No milestone assignment here** — authorizing, sequencing and scoping any of these items requires a separate owner decision.
