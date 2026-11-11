# M008-T07B Specification — Rookie Signing & Roster Intake UI

Status: implemented on `feat/m008-t07b-rookie-signing-ui` (baseline `b832204`).
Scope: player-facing signing flow over the accepted T07A domain. No finances, no AI signing, no waivers.

## 1. Objective

Make the T07A rookie signing engine usable by the human GM:

1. A Rookie Signing entry in Opening Offseason, available only after the draft completes.
2. An owned-rights screen listing only the human franchise's drafted prospects with signing status.
3. Category and duration selection bounded by `RookieContract`, with live roster-capacity preview.
4. Explicit confirmation that routes through `GmCareerController.signDraftedRookie`.
5. Correct signed/unsigned presentation on the offseason overview and draft history.
6. No disclosure of hidden potential or development trajectory on any public rookie surface.

## 2. Surfaces

### 2.1 Opening Offseason overview
- `card-rookie-signing` renders only when the draft is completed.
- Shows drafted count, signed count, unsigned count, and standard / two-way / total occupancy.
- `btn-open-rookie-signing` opens the signing screen.
- Before completion, no signing UI is rendered at all.

### 2.2 Rookie Signing screen (`GmRookieSigningScreen`)
- Summary card: drafted / signed / unsigned and occupancy vs `RosterRules` offseason limits.
- Lists only `DraftSelection`s whose `selectingTeamId` equals the user franchise, ordered by pick.
- Each card: name, position, age, OVR, round, overall pick, projected rank, public estimate,
  and a status label from `rookieSigningStatus` (`Unsigned rights`, `Signed — Standard`,
  `Signed — Two-Way`).
- `Sign` exists only for unsigned players while no save recovery is pending.
- Recovery card with `Reload Saved Career` when a write is uncertain.

### 2.3 Signing sheet
- Title names the rookie; shows franchise, round and pick.
- Category chips: Standard, Two-Way. Disabled with a visible reason when that category is full.
- Duration chips derived from `RookieContract.minDurationYears` / `maxDurationFor(category)`.
- Capacity: current standard / two-way counts, plus projected counts after signing,
  or the specific rejection reason.
- Financial note: no salary, cap or negotiation model exists in this build.
- `Cancel` and `Confirm Signing`; confirm is disabled while pending, stale, or over capacity.

## 3. State transitions

```
draft not completed  → signing entry absent
draft completed      → summary card + owned rights list (status per player)
unsigned player      → Sign opens sheet (category = Standard, duration = max standard)
sheet confirm        → controller.signDraftedRookie (queued, write-before-publish)
write succeeds       → sheet closes, list shows Signed, roster counts increase
write fails          → previous career kept, recovery flag set, reload offered
reload succeeds      → signed state reflects disk; sheet closes if the player signed
category/duration    → sheet only; never mutates the career
cancel               → sheet closes, zero writes
```

Duplicate taps are blocked by an in-sheet pending guard and by the controller's
stale/duplicate rejection. A signing never shows success before the controller has
persisted it.

## 4. Public scouting protection

- Owned-rights cards and the signing sheet use only `PublicProspectScoutingView`
  (grade and range), never `RookieProspect.potential` or `trajectory`.
- The offseason roster list previously rendered `POT` and trajectory for every
  roster player. Signed rookies now render `Est. <grade>` and `Rookie • <category>`
  instead, so signing does not disclose hidden ceiling or trajectory.
- `PlayerProfileScreen` shows attribute rows only and needs no change.
- Hidden values stay in `PlayerCareerProfile` for future development.

## 5. Draft history

- The 60 selections, rights map and 90-prospect class are never modified by signing.
- Draft results still list the user's drafted prospects; the header now counts
  `unsigned` and `signed` separately and each card appends the signing status.
- Signed players can never be signed twice and are never presented as signable.

## 6. Acceptance criteria

- **AC-T07B-01** Signing entry and controls are absent before draft completion.
- **AC-T07B-02** A completed draft shows the user's unsigned rights in the offseason summary.
- **AC-T07B-03** The signing screen lists only the human franchise's drafted prospects.
- **AC-T07B-04** Prospect cards show name, position, age, OVR, round, pick, projected rank,
  public grade and signing status.
- **AC-T07B-05** A standard contract can be signed from the sheet.
- **AC-T07B-06** A two-way contract can be signed from the sheet.
- **AC-T07B-07** Duration chips follow `RookieContract`: standard 1–4, two-way 1–2.
- **AC-T07B-08** The sheet shows current capacity and projected capacity after signing.
- **AC-T07B-09** A full category is disabled with an explicit reason and blocked confirmation.
- **AC-T07B-10** Cancel performs zero writes and leaves the career unchanged.
- **AC-T07B-11** Confirmed signing succeeds through the controller and persists before publish.
- **AC-T07B-12** The signed rookie appears on the contracted roster with its category.
- **AC-T07B-13** Roster counts update in the offseason summary.
- **AC-T07B-14** A signed rookie is no longer listed as unsigned and has no Sign action.
- **AC-T07B-15** Draft selections and results remain intact after signing.
- **AC-T07B-16** Repeated signing of the same rookie is impossible from the UI.
- **AC-T07B-17** Duplicate/stale submissions are rejected; rapid double taps sign once.
- **AC-T07B-18** A failed write keeps the previous career and offers reload reconciliation.
- **AC-T07B-19** Restarting the app preserves signings, contracts and roster state.
- **AC-T07B-20** Hidden potential and trajectory never appear on public rookie surfaces.
- **AC-T07B-21** The existing draft flow remains functional.
- **AC-T07B-22** M007 season saves remain isolated.
- **AC-T07B-23** 360x640 and 393x852 render without overflow.

## 7. Non-goals

AI signing decisions, salary/cap/negotiation, waivers, free agency, draft trading,
automatic cuts, contract expiry or renewal, development, coaching, facilities,
finances, season advancement and another milestone's work.
