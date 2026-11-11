# M008-T07C Specification — AI Franchise Rookie Signing

Status: implemented on `feat/m008-t07c-ai-rookie-signing` (baseline `a4a16e4`).
Scope: deterministic AI decisions for non-human franchises. No UI, no salaries, no waivers, no season advancement.

## 1. Objective

Every non-human franchise must decide what to do with its own drafted prospects after the
draft completes: sign a standard contract, sign a two-way contract, or defer and keep the
rights unsigned. Decisions must be public-information only, deterministic, auditable,
persisted one at a time, and safe to resume.

## 2. Decision Policy (pre-registered)

Inputs are restricted to `PublicProspectScoutingView`, the franchise roster, the franchise
situation and the draft pick. No PRNG, no hash codes, no hidden prospect fields.

### 2.1 Scores (0..100)

```
quality  = overallRating
upside   = midpoint(estimatedPotentialRange)          // e.g. "85–91" → 88
youth    = (22 - age).clamp(0, 3) / 3 * 100
need     = (3 - positionDepth).clamp(0, 3) / 3 * 100  // depth = roster players at position
fit      = wQuality*quality + wUpside*upside + wYouth*youth + wNeed*need
fit     += 6 when overallPick <= 30                   // first-round preservation
```

Situation weights:

| Situation | quality | upside | youth | need |
|---|---|---|---|---|
| Tanking / Rebuilding | 0.25 | 0.45 | 0.20 | 0.10 |
| Play-In Contender | 0.40 | 0.30 | 0.15 | 0.15 |
| Playoff Team | 0.55 | 0.15 | 0.05 | 0.25 |
| Championship Contender | 0.65 | 0.05 | 0.00 | 0.30 |

### 2.2 Choice

```
if totalContracted >= 21                      → defer(rosterFull)
if fit >= standardThreshold:
    if standardCount < 15                     → standard
    else                                      → defer(noStandardSlot)
developmental = age <= 20 || upside - quality >= 10
if developmental && fit >= twoWayThreshold:
    if twoWayCount < 3                        → twoWay
    else                                      → defer(noTwoWaySlot)
else                                          → defer(lowFit)
```

Thresholds:

| Situation | standardThreshold | twoWayThreshold |
|---|---|---|
| Tanking / Rebuilding | 55 | 45 |
| Play-In Contender | 60 | 50 |
| Playoff Team | 65 | 55 |
| Championship Contender | 70 | 60 |

Durations (project convention, inside `RookieContract` bounds):

| Situation | standard | two-way |
|---|---|---|
| Tanking / Rebuilding | 4 | 2 |
| Play-In Contender | 3 | 2 |
| Playoff Team | 2 | 1 |
| Championship Contender | 2 | 1 |

Reason codes: `signedStandardNeed`, `signedStandardQuality`, `signedTwoWayDevelopment`,
`deferredLowFit`, `deferredNoStandardSlot`, `deferredNoTwoWaySlot`, `deferredRosterFull`,
`signedExistingContract` (backfilled migration evidence).

## 3. Decision State

`AiRookieSigningState` is a map keyed by prospect `PlayerId` of
`AiSigningDecision(teamId, prospectId, draftSeasonYear, overallPick, decision, reason, contractId)`.

- Decision types: `signedStandard`, `signedTwoWay`, `deferred`.
- Deferred and unprocessed are distinct: deferred has a record, unprocessed has none.
- Signed decisions must reference an existing ledger contract with the same franchise and category.
- Deferred decisions must not have a ledger contract.
- A franchise with no decision has not been evaluated.
- Decisions are processed in overall-pick order across all rights not owned by the human.
- Ownership comes from `DraftRights.owningTeamId`, not from a fixed pick count.

## 4. Service Operations

`RookieAiSigningService`:

1. `initialize(career)` — requires a completed draft; backfills `signedExistingContract`
   decisions for AI-franchise contracts that predate the decision state (v5 saves or manual
   signings), without creating or altering contracts.
2. `pendingRights(career)` — AI-owned rights without a decision, in pick order.
3. `applyNextDecision(career)` — evaluates exactly one pending right; signs through
   `RookieSigningService` or records a deferral; returns a new validated career. No pending
   rights returns the same career.
4. `advanceAll(career)` — initializes, then applies decisions until none remain.

Human-owned rights are never evaluated or signed. No automatic trigger exists; only the
controller operation starts the process.

## 5. Persistence & Migration

- Schema v6 adds `aiRookieSigning`. v6 requires it; malformed data is rejected.
- v1–v5 decode with an empty decision state; no signed rookie becomes unsigned, no draft
  history or contract changes.
- Backfill on initialize recognizes existing AI contracts instead of signing twice.
- Validation rejects: unknown/undrafted prospect decisions, pick/year mismatch, franchise
  mismatch with current rights, signed decisions without a matching contract, deferred
  decisions with a contract, decisions for human-owned rights, duplicate decisions,
  inconsistent reason codes, and any decision while the draft is incomplete.
- Atomic writes, backup recovery and M007 isolation are unchanged.

## 6. Controller Safety

`GmCareerController.advanceAiRookieSigning()` runs in the serialized queue, writes after
each decision before publishing it, blocks on an unresolved save, and leaves prior committed
decisions intact on failure. Reload reconciles an uncertain write; completion is idempotent.

## 7. Acceptance Criteria

- **AC-T07C-01** Every AI-owned draft right receives exactly one decision.
- **AC-T07C-02** Human-owned rights are never auto-signed and receive no AI decision.
- **AC-T07C-03** Every decision is standard, two-way, or deferred.
- **AC-T07C-04** Category limits (15 standard / 3 two-way / 21 total) are never bypassed.
- **AC-T07C-05** Contract durations stay within `RookieContract` bounds.
- **AC-T07C-06** Roster composition changes the decision for identical public prospects.
- **AC-T07C-07** Competitive situation changes the decision for identical public prospects.
- **AC-T07C-08** Hidden potential and trajectory cannot change any AI decision.
- **AC-T07C-09** A deferred prospect stays unsigned and keeps its draft rights.
- **AC-T07C-10** Deferred and unprocessed decisions are distinguishable.
- **AC-T07C-11** Signed rookies join the correct franchise roster.
- **AC-T07C-12** `PlayerId` and career profile values are preserved.
- **AC-T07C-13** Draft selections, rights and the 90-prospect class are unchanged.
- **AC-T07C-14** Repeated processing creates no duplicate contracts or decisions.
- **AC-T07C-15** Save/load preserves decisions and contracts.
- **AC-T07C-16** Interrupted evaluation resumes without replay.
- **AC-T07C-17** Invalid commands mutate nothing.
- **AC-T07C-18** Existing human contracts and rosters are unchanged.
- **AC-T07C-19** v1–v5 saves migrate without corrupting contracts or draft history.
- **AC-T07C-20** Existing draft and signing UI remains functional.
- **AC-T07C-21** M007 saves remain untouched.
- **AC-T07C-22** Core and Flutter regression suites pass.

## 8. Non-goals

Human signing UI changes, full offseason calendar, free agency, waivers, cuts, salaries,
salary cap, negotiations, expiration, draft trades, coaching, facilities, development,
season advancement, automatic startup signing, and physical device changes without approval.
