# Documentation debt — operational status corrections

> **Status:** **APPLIED 2026-11-02** under the M003 T020 freeze authorization. The proposals below are
> retained as the approved baseline for the applied text.
> **Scope:** operational status text only. No frozen specification, plan, design-decision,
> calibration, review or probability-model document was touched.

## Applied edits

| File | Change |
|---|---|
| `AGENTS.md` §3 | Checkpoint re-dated 2026-11-02; single authoritative status pointer declared; M002 recorded as T001–T019 complete and ACCEPTED WITH CONDITIONS; AC09/AC10 status corrected; T016–T019 closed; M003 recorded as FROZEN with T020 complete; M004/Decision-Making recorded as unassigned; stale "worktree was missing this file" note and historical T015 commit pointer removed from the status list. |
| `specs/002-possession-simulation/tasks.md` | Title re-stated as `T001–T019 COMPLETE; M002 ACCEPTED WITH CONDITIONS (2026-10-31)`; stale AC09/AC10/authorization paragraph replaced; stale "no task may start before T003" sentence corrected. Per-task entries, evidence and dates untouched. |
| `README.md` | Added milestone status list (001 accepted, 002 accepted with conditions, 003 frozen not implemented), status-pointer line, layout entries for `specs/002-…` and `specs/003-…`, and a no-realism/Android-claim statement. |

Deliberately **not** changed: `specs/002-…/{spec,plan,design-decisions,calibration-plan,review-findings,probability-model}.md`
headers ("Implementation remains NOT AUTHORIZED" — original frozen status, per `AGENTS.md` §2),
`acceptance-report.md` AC09/AC10 `PENDING OWNER REVIEW` labels (as-of-T018 record),
`t017-closeout-addendum.md` statuses, and `specs/001-…/acceptance-report.md` historical milestones.

`AGENT_PROMPT.md` (Milestone 001 onboarding prompt) remains stale; it was optional and was not
included in this authorization.

## Why these were stale

The table below records the state on 2026-11-02 **before** the applied edits above; it is kept so the
corrected text can be audited against what it replaced.

The proposal blocks that follow are the submitted wording. Where a block describes M003 as draft or
not frozen, the applied text above and the frozen `specs/003-mobile-game-day/` set govern.

M002 closed on 2026-10-31 (`M002-OWNER-ACCEPTANCE.md`) and was published to
`origin/develop/m002` at `6ca43b632e9229216a49966b35bb660c6651c2e8`. Several operational documents
still describe the pre-closeout state. Frozen historical documents that describe their own original
status are **not** in scope and must not be rewritten.

| File | Current text | Problem |
|---|---|---|
| `AGENTS.md` §3 | checkpoint dated 2026-10-31; "M002 is **not closed**"; "T016–T019 remain unauthorized"; AC09/AC10 described as unsigned | Contradicts the acceptance record |
| `specs/002-possession-simulation/tasks.md` | title "…; T016–T019 NOT AUTHORIZED"; paragraph ending "T016–T019 remain unauthorized and unchecked." | Contradicts the checked T016–T019 entries in the same file |
| `README.md` | describes Milestone 001 only; layout lists only `specs/001-…` | No project status, no M002/M003 mention |
| `AGENT_PROMPT.md` | "AI Coding Agent — Milestone 001" | Onboarding prompt for a finished milestone (optional, owner's call) |

Deliberately **not** changed: `specs/002-…/{spec,plan,design-decisions,calibration-plan,review-findings,probability-model}.md`
headers ("Implementation remains NOT AUTHORIZED" — original frozen status, per `AGENTS.md` §2),
`acceptance-report.md` AC09/AC10 `PENDING OWNER REVIEW` labels (as-of-T018 record),
`t017-closeout-addendum.md` statuses, and `specs/001-…/acceptance-report.md` historical milestones.

---

## Proposed patch 1 — `AGENTS.md` §3

### 1a. Heading

```text
## 3. Current project checkpoint (2026-11-02; reverify before acting)
```

### 1b. Replace the M002 status bullets

Current:

```text
- M002 possession simulation: **T004–T015 have been implemented/executed** according to `specs/002-possession-simulation/tasks.md`; M002 is **not closed**.
- T014 / **AC09:** historical v1 E4 ball-handling experiment was inconclusive; a v2 development rerun passed, but do **not** silently rewrite the frozen result or declare overall AC09 signed off.
- T015 / **AC10:** 1,120-game calibration was executed, but owner acceptance remains pending. Recorded issues include 24.76 turnovers/100 possessions and 14.65 shot-clock violations/game; the A1 duration-after-14-second-reset interaction warrants design review. These are diagnostic observations, **not approval to tune parameters**.
```

Proposed:

```text
- M002 possession simulation: **T001–T019 complete; M002 ACCEPTED WITH CONDITIONS** on 2026-10-31 (`specs/002-possession-simulation/M002-OWNER-ACCEPTANCE.md`). Accepted scope is the technical possession-engine foundation only — simulation v4, rules 2, event schema 2, fingerprint 2, duration model 2, PRNG `xorshift32-v1`.
- T014 / **AC09:** ACCEPTED by the owner for simulation v4 on 6/6 fresh held-out sensitivity experiments. The historical v1 E4 `INCONCLUSIVE` result and its numbers remain unchanged in `t014-sensitivity-report.md` and must never be re-scored.
- T015 / **AC10:** CONDITIONALLY ACCEPTED for the limited M002 foundation. Historical observations remain: v2 `tovPer100Completed` 24.7594 above the `[7, 24]` band, and 14.65 shot-clock violations/game with the documented A1 14-second-reset interaction. These are preserved FAILs/diagnostics, **not approval to tune parameters**.
```

### 1c. Replace the authorization bullet

Current:

```text
- **T016–T019 remain unauthorized** until the owner explicitly approves them. No M002 completion/GO claim.
```

Proposed:

```text
- **T016–T019 are complete and closed.** T016 closed after the provenance correction; T017 closed after blocker resolution; T018 produced the AC01–AC13 evidence report; T019 closed on human owner acceptance. M002 is **not** a production, realism, store-readiness or Android-performance approval — see the conditions in `M002-OWNER-ACCEPTANCE.md` §7.
- M003 (Mobile Game Day) is **design draft only** in `specs/003-mobile-game-day/`; the specification is **not frozen** and no implementation is authorized. M004+ candidates remain unassigned planning input in `M003-BACKLOG.md`.
```

### 1d. Keep, but re-verify, the commit bullet

Current text already says the recorded T015 commit is a historical checkpoint, not current HEAD.
Proposed addition only:

```text
- Fresh checkpoint: `develop/m002` at `6ca43b632e9229216a49966b35bb660c6651c2e8`, pushed to `origin` on 2026-11-02. Re-verify before acting.
```

---

## Proposed patch 2 — `specs/002-possession-simulation/tasks.md` header

Only the title line and the stale status paragraph change. The per-task entries, their evidence and
their text stay exactly as they are.

### 2a. Title line

Current:

```text
# Tasks 002 — PHASE 1, T008, AMENDMENT 001, T009–T015 EXECUTED; T016–T019 NOT AUTHORIZED
```

Proposed:

```text
# Tasks 002 — T001–T019 COMPLETE; M002 ACCEPTED WITH CONDITIONS (2026-10-31)
```

### 2b. Stale paragraph

Current:

```text
The AC09 statistical gate is NOT passed on the historical v1 data (E4 v1 was
inconclusive; the v2 development rerun passed). T015 execution is complete and
AC10 is READY FOR OWNER REVIEW (not passed): the passive A1 trace closed the last
mandatory measurement gap. T016–T019 remain unauthorized and unchecked.
```

Proposed:

```text
The AC09 gate was resolved by the owner on 2026-10-31 for simulation v4; the
historical v1 E4 inconclusive result is preserved unchanged in
`t014-sensitivity-report.md`. AC10 is CONDITIONALLY ACCEPTED for the limited M002
foundation. T016 closed after the provenance correction, T017 closed after the
blocker was resolved, T018 delivered the AC01–AC13 report, and T019 closed on
human owner acceptance. M002 is ACCEPTED WITH CONDITIONS — the decision record is
`M002-OWNER-ACCEPTANCE.md`, which does not rewrite any earlier task text.
```

History note: the earlier sentences are replaced because they assert a *current* authorization state,
not a historical one. Every dated per-task entry beneath them remains untouched.

---

## Proposed patch 3 — `README.md`

### 3a. Opening paragraph

Current:

```text
Offline-first basketball manager prototype. Milestone 001: deterministic
fictional league generation and a read-only roster UI.
```

Proposed:

```text
Offline-first basketball manager prototype.

- Milestone 001 — deterministic fictional league generation and a read-only roster UI. Accepted.
- Milestone 002 — deterministic, event-sourced possession-simulation engine (simulation v4).
  Accepted with conditions; see `specs/002-possession-simulation/M002-OWNER-ACCEPTANCE.md`.
- Milestone 003 — Mobile Game Day. Design draft only, not frozen, not implemented.
```

### 3b. Layout bullets

Current:

```text
- `specs/001-league-player-foundation/` — spec, plan, tasks, design decisions, acceptance report.
```

Proposed:

```text
- `specs/001-league-player-foundation/` — spec, plan, tasks, design decisions, acceptance report.
- `specs/002-possession-simulation/` — frozen M002 specification, evidence, calibration records and the owner acceptance record.
- `specs/003-mobile-game-day/` — DRAFT Mobile Game Day specification. Not frozen; nothing implemented.
```

### 3c. Optional status line

```text
Simulation status: M002 accepted for the possession-engine foundation only. No NBA-level realism,
release-readiness or Android performance claim has been made or measured.
```

---

## Proposed patch 4 (optional) — `AGENT_PROMPT.md`

Rename the heading to reflect the current milestone and point agents at `AGENTS.md` instead of
restating Milestone 001 rules. Suggested replacement first lines:

```text
# AI Coding Agent — Current Milestone

Read `AGENTS.md`, `.specify/memory/constitution.md`, and the active milestone
documents under `specs/` before changing code. For M002 work see
`specs/002-possession-simulation/`; M003 is design-only until its specification is
frozen and authorized.
```

This file is not required for correctness; it is listed so the stale onboarding prompt is not
mistaken for current instructions.

---

## Application rules

1. Applied once under the 2026-11-02 T020 authorization. Any further change to these documents needs a
   new owner GO.
2. Edits were limited to the blocks above. Frozen M002 specification material, acceptance matrices,
   evidence files and `M003-BACKLOG.md` were not touched.
3. Committed separately from implementation work, with a message identifying the status correction.
4. After patching, re-read `AGENTS.md` §3 in a fresh session and confirm the checkpoint date, the
   acceptance statement and the M003 frozen/T021-pending statement are the loaded context.
