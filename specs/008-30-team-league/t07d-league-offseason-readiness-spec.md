# M008-T07D Specification — AI Signing Workflow & League Readiness

Status: implemented on `feat/m008-t07d-league-offseason-readiness` (baseline `8100cc4`).
Scope: workflow integration and read-only reporting over the accepted T07C engine.

## 1. Objective

Expose the deterministic AI signing engine as an explicit Opening Offseason action and give the
GM a league-wide readiness view. No new AI policy, no new save schema, no automatic execution.

## 2. Activation

After the draft completes, the offseason overview shows `card-league-signings`:

- AI franchises participating (distinct current rights owners excluding the human).
- Total AI-owned draft rights from current `DraftRights`.
- Evaluated decisions and remaining unevaluated rights.
- Standard / two-way / deferred breakdown of committed decisions.
- `btn-resolve-league-signings` labelled **Resolve League Rookie Signings** (or
  **Resume League Rookie Signings** when partially processed, disabled when complete).
- Recovery state: `btn-league-signings-reload` appears when a save is uncertain.

Confirmation dialog (`confirm-resolve-signings` / `cancel-resolve-signings`) restates the counts
and explains that franchises may sign standard, sign two-way, or keep rights unsigned.
Cancel performs zero writes. Confirm calls `GmCareerController.advanceAiRookieSigning()`.

Nothing runs on app launch, save load, draft board, signing screen, standings or roster views.

## 3. Progress and resumption

All numbers derive from `GmCareer`:

```
totalAiRights    = draftRights where owningTeamId != userFranchiseId
evaluated        = those rights with an AiSigningDecision
remaining        = totalAiRights - evaluated
standard/twoWay/deferred = decisions of that type for AI rights
```

States: not started (0 evaluated), partial, complete (0 remaining), recovery required.
Each decision is written before the controller publishes it; navigating away keeps committed
progress. Resume continues from persisted state without replaying decisions.

## 4. League Readiness Report (domain)

`LeagueReadinessReport.fromCareer(career)` provides per-team and aggregate data:

Per team: identity, situation, standard / two-way / camp / total counts, readiness from
`RosterRules.validateRegularSeasonReadiness()`, `standardShortage = max(0, 14 - standard)`,
unsigned drafted-rights count, readiness issues, human flag.

Aggregates: ready / not-ready counts (all 30), total standard shortage, AI standard signings,
AI two-way signings, AI deferred rights, pending AI decisions, total AI rights, AI ready count,
AI below-minimum count, human team row.

Readiness uses only `RosterRules`; two-way players never satisfy the standard minimum.
Deferred decisions are not pending decisions.

## 5. Dashboard

`GmLeagueReadinessScreen` (entry `btn-open-league-readiness`, card `card-league-readiness`):

- Summary card `league-readiness-summary`: ready / not ready, total shortage, AI signing
  breakdown, pending decisions, human franchise line.
- 30 team cards `readiness-team-<teamId>`: name, abbreviation, situation, standard/15,
  two-way/3, total/21, READY or NOT READY, "Needs N standard players" when below 14,
  unsigned drafted rights, YOUR FRANCHISE marker.
- Tapping a card opens `franchise-detail-sheet`: position breakdown, signed drafted rookies
  (category, pick, public grade), remaining unsigned rights (deferred/pending, public grade),
  readiness issues. Read-only; no transaction controls.
- Rookie information uses `PublicProspectScoutingView` only. No hidden potential or trajectory.

## 6. Persistence & Safety

- No new schema; v6 state is authoritative.
- All commands use the serialized controller queue and write-before-publish.
- Failed writes preserve the last committed progress and block further processing until
  `Reload Saved Career`.
- Repeated completion actions create no contracts or decisions.
- Human rights are never signed or decided by this workflow.
- Draft history and existing contracts are never rewritten. No season advancement.

## 7. Acceptance Criteria

- **AC-T07D-01** Activation is hidden before draft completion.
- **AC-T07D-02** Start requires explicit confirmation with AI counts and explanation.
- **AC-T07D-03** Cancel performs zero writes.
- **AC-T07D-04** Processing goes through `GmCareerController.advanceAiRookieSigning`.
- **AC-T07D-05** Human-owned rights are excluded from AI processing and decisions.
- **AC-T07D-06** Progress reflects committed career decisions, not local counters.
- **AC-T07D-07** Signed standard, two-way and deferred totals are accurate.
- **AC-T07D-08** Processing completes every applicable AI right.
- **AC-T07D-09** Repeated execution creates no duplicate changes.
- **AC-T07D-10** Interrupted processing resumes without replay.
- **AC-T07D-11** Failed writes require reload reconciliation.
- **AC-T07D-12** Persisted decisions survive app restart.
- **AC-T07D-13** The dashboard lists all 30 franchises.
- **AC-T07D-14** Readiness derives from `RosterRules.validateRegularSeasonReadiness`.
- **AC-T07D-15** Standard roster shortages are computed correctly.
- **AC-T07D-16** Two-way players do not satisfy the 14-standard minimum.
- **AC-T07D-17** Deferred and pending rights are distinguishable.
- **AC-T07D-18** Franchise details show accurate roster counts.
- **AC-T07D-19** Hidden scouting information is never displayed.
- **AC-T07D-20** All four human starting situations work.
- **AC-T07D-21** Existing draft and signing flows remain functional.
- **AC-T07D-22** M007 storage remains isolated.
- **AC-T07D-23** 360x640 and 393x852 render without overflow.

## 8. Non-goals

New AI policy, free agency, waivers, cuts, salaries, cap, negotiations, expiration, conversion,
staff, facilities, development, season advancement, full offseason calendar, fake Continue Season.
