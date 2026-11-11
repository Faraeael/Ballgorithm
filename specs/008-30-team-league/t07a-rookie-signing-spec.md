# M008-T07A Specification — Rookie Contracts & Persistent Roster Intake Engine

Status: implemented on `feat/m008-t07a-rookie-signing-engine` (baseline `abdd8fb`).
Scope: domain engine and persistence only. No signing UI, no AI signing decisions, no salary rules.

## 1. Product Objective

Drafted prospects currently exist only as historical draft records plus exclusive
unsigned `DraftRights`. T07A adds the smallest complete domain layer that turns one
owned drafted prospect into a contracted franchise player:

1. A persistent, validated rookie contract record.
2. An atomic signing command usable by any franchise.
3. Roster intake that reuses the prospect's persistent identity and attributes.
4. Career-profile intake that preserves hidden age, potential and trajectory.
5. Strict, signing-aware career validation (replacing the blanket
   "prospect ID may never appear on a roster" rule).
6. Schema v5 persistence with lossless migration from v1–v4.

## 2. Ownership Model

- `DraftRights` remains the **only** authority on which franchise owns an unsigned
  drafted prospect. It is created at selection time and never mutated by signing.
- `RookieSigningLedger` is the **only** authority on which drafted prospects have
  signed. It is a map keyed by prospect `PlayerId`.
- The ledger never re-derives or overrides draft ownership. Every contract must
  repeat the selecting franchise and selection coordinates; validation requires
  that repetition to match `DraftExecutionState` exactly.
- Derived unsigned rights = `DraftExecutionState.draftRights` values whose prospect
  is not present in the signing ledger. This derivation is exposed as
  `GmCareer.unsignedDraftRights` and must never be stored separately.
- `DraftExecutionState.selections` and `draftRights` are immutable after
  completion. Signing does not delete, mutate or reorder draft history.

## 3. Lifecycle

```
draft class prospect (unsigned, unselected)
  → selected           : DraftSelection + DraftRights (franchise owns rights, 0 roster slots)
  → signed             : RookieContract + Player on roster + PlayerCareerProfile
  → [future T07B+]     : expiration, renewal, waiver, conversion, salary, payroll
```

- One prospect may be signed at most once.
- Signing is one-way in T07A: there is no waiver, release or category conversion.
- A signed prospect is no longer an unsigned signing opportunity, but remains
  inspectable as a historical prospect and historical draft selection.
- Undrafted prospects can never be signed or rostered.

## 4. Contract Record (`RookieContract`)

| Field | Type | Meaning |
|---|---|---|
| `id` | `String` | Deterministic contract identity: `rookie-contract-<playerId>` |
| `playerId` | `PlayerId` | Persistent prospect/player identity; never regenerated |
| `teamId` | `TeamId` | Signing franchise; must equal the draft selecting franchise |
| `category` | `RosterCategory` | `standard` or `twoWay` only |
| `startYear` | `int` | Career year the contract starts |
| `durationYears` | `int` | Explicit duration; category-bounded |
| `draftSeasonYear` | `int` | Selection reference: draft class year |
| `overallPick` | `int` | Selection reference: overall pick 1..60 |

Category and duration bounds (Ballgorithm convention, **not** an NBA scale):

- `standard`: 1–4 years.
- `twoWay`: 1–2 years.
- `trainingCamp` is rejected by the signing engine; camp agreements are out of scope.

**Financial boundary:** the record deliberately carries **no** salary, cap hold,
option or guarantee field. Franchise finances and salary rules are not implemented,
so no zero-cost contract is implied and no cap affordability is validated. Later
finances will attach to `RookieContract.id` / `playerId`; they must not change the
roster-intake contract defined here.

`RookieSigningLedger` stores contracts keyed by `playerId`, enforces unique contract
IDs and a single contract per player, and serializes with keys in canonical
`overallPick` order.

## 5. Signing Command

`RookieSigningService.signDraftedRookie({career, teamId, prospectId, category, durationYears})`
is pure and atomic: it returns a new `GmCareer` or throws without producing state.

Validation order and rejection type:

1. Draft completed — `StateError`.
2. Prospect exists in the draft class — `ArgumentError`.
3. Prospect was selected (rights exist) — `StateError`.
4. Requesting franchise owns those rights — `StateError`.
5. Franchise exists in the league — `StateError`.
6. Prospect not already signed — `StateError`.
7. Prospect ID not already on any roster — `StateError`.
8. Category is `standard` or `twoWay` — `ArgumentError`.
9. Duration inside the category bounds — `ArgumentError`.
10. Candidate roster satisfies the phase capacity rules (15 standard / 3 two-way /
    21 total during Opening Offseason) — `StateError`.
11. No pre-existing career profile or identity collision for the prospect — `StateError`.

On success it performs exactly one transition:

- `Player` built from the prospect (`id`, names, position, attributes unchanged).
- `PlayerCareerProfile` built from `age`, `potential`, `trajectory` unchanged.
- Roster gains the player under the contract category.
- Ledger gains exactly one contract.
- `GmCareer` is reconstructed once, so `validate()` observes a fully consistent state.

No automatic waivers, category changes, roster cuts or regular-season readiness
forcing are performed. A team may finish signing with 13 standard players while
still in Opening Offseason.

## 6. Signing-Aware Career Validation

`GmCareer.validate()` keeps every existing invariant and adds:

- Duplicate contract IDs, duplicate player keys or key/ID disagreement — rejected.
- Contract referring to an unknown prospect — rejected.
- Contract referring to an undrafted prospect (no completed selection) — rejected.
- Contract coordinates (`teamId`, `draftSeasonYear`, `overallPick`) that disagree
  with the recorded selection — rejected.
- Contract whose player is absent from any roster — rejected.
- Contract whose roster franchise differs from the contract franchise — rejected.
- Roster category that differs from the contract category — rejected.
- Signed player without a career profile — rejected.
- Draft prospect present on a roster **without** matching signing evidence — rejected.
- Any `trainingCamp` contract category, invalid year, invalid pick or invalid
  duration — rejected.

Draft prospects that remain unsigned are still forbidden from appearing on any
roster. The original "prospect ID must not collide with a league player" rule is
therefore narrowed, not removed: a collision is legal only with exactly one
matching completed selection, one contract, one roster membership and one profile.

## 7. Persistence & Migration

- `GmCareer.currentSchemaVersion` and `GmCareerCodec.currentSchemaVersion` = **5**.
- The writer always emits v5 and always writes `rookieSigningLedger`.
- v5 requires a well-formed `rookieSigningLedger`; missing or malformed data is a
  `FormatException`, not a silent empty ledger.
- v1–v4 saves decode with an **empty** ledger. Existing draft classes, selections,
  rights, rosters, categories and profiles are preserved byte-for-byte through
  re-encoding of unchanged fields.
- Migration never treats existing rights as evidence of signing and never
  regenerates prospects or resets a completed draft.
- Atomic writes, backup recovery and M007 save isolation are unchanged; contracts
  live inside the existing GM career save, not a second file.

## 8. Controller Integration

`GmCareerController.signDraftedRookie({prospectId, category, durationYears, slot})`:

- Runs inside the existing serialized command queue.
- Rejects a stale request when the active career changed before execution.
- Calls the pure signing service, encodes and writes before publishing the new
  career in memory.
- On write failure, keeps the previous in-memory career and sets the existing
  recovery flag, blocking further draft/signing commands until a successful reload
  reconciles the uncertain write.
- Adds no UI control and no separate save file.

## 9. Acceptance Criteria

- **AC-T07A-01** A drafted prospect owned by a franchise can be signed to a
  `standard` contract; roster standard count increases by one and contract,
  roster membership and profile agree.
- **AC-T07A-02** A drafted prospect can be signed to a `twoWay` contract; two-way
  count increases by one and no standard slot is consumed.
- **AC-T07A-03** Undrafted prospects cannot be signed.
- **AC-T07A-04** A prospect owned by another franchise cannot be signed.
- **AC-T07A-05** A prospect cannot be signed twice.
- **AC-T07A-06** Signing is rejected unless the draft is completed.
- **AC-T07A-07** A 16th standard player is rejected.
- **AC-T07A-08** A fourth two-way player is rejected.
- **AC-T07A-09** A 22nd total offseason contracted player is rejected.
- **AC-T07A-10** Signed `PlayerId`, name, position and attributes are identical to
  the prospect record.
- **AC-T07A-11** Signed career profile preserves prospect age, potential and
  trajectory exactly.
- **AC-T07A-12** Draft selections and rights are unchanged by signing.
- **AC-T07A-13** Signed prospects disappear from derived unsigned rights.
- **AC-T07A-14** Remaining unsigned rights are preserved.
- **AC-T07A-15** Orphaned signing, roster or profile records are rejected on decode.
- **AC-T07A-16** Invalid category or duration combinations are rejected.
- **AC-T07A-17** Save/load preserves expanded rosters and contract records.
- **AC-T07A-18** v1, v2, v3 and v4 saves migrate without data loss and with an empty
  ledger.
- **AC-T07A-19** Identical signing commands on identical careers produce identical
  encoded state.
- **AC-T07A-20** The controller rejects duplicate and stale signing submissions.
- **AC-T07A-21** A failed save preserves the previously committed career.
- **AC-T07A-22** M007 season saves remain untouched.
- **AC-T07A-23** The existing rookie draft flow remains functional.
- **AC-T07A-24** Core and Flutter regression suites remain passing.

## 10. Non-Goals

Rookie signing UI, AI signing decisions, salary negotiation, salary cap, rookie
salary scale, free agency, draft trading, waivers, automatic cuts, development,
coaching, facilities, finances, season advancement and game-day lineups.
