# Specification 004 — Foundational Player Participation

> **Status:** **DRAFT — NOT FROZEN.** Prepared for owner review under `BALLGORITHM — M004 T01 SPECIFICATION DRAFT`.
> Nothing here authorizes implementation. Proposed version numbers are targets, not applied constants.
> **Baseline:** `develop/m002` at `125e1e652baa41db17f3684242bbd73683f9602b` (M003 accepted and closed).
> **Predecessors:** M002 possession contracts (frozen), M003 Mobile Game Day (accepted), `M003-BACKLOG.md` (planning input).

## 1. Purpose

Give the accepted possession engine a rule-driven notion of **who is on the court**. Today each team
fields one fixed five for the whole game; a player can commit unlimited fouls, and no player has
minutes. M004 makes participation a first-class, replayed fact:

- a team's five may change during a game;
- a sixth personal foul disqualifies a player;
- the disqualified player is replaced at a lawful substitution window;
- when no eligible bench player remains, the disqualified player continues;
- every player's seconds are derived from the ledger.

M004 does **not** change probability coefficients, draw structure, event ordering semantics, clock
rules, or the PRNG implementation.

## 2. What must be true

1. The five active players per team are always exactly five distinct roster players in five canonical
   slots (PG, SG, SF, PF, C).
2. The active five is reconstructible from `GameStarted` plus `Substitution` events, with the starting
   five supplied by input.
3. A player's primary position is independent of the slot they occupy.
3a. `GameInput` holds the **immutable starting lineups**; it is never updated during a game.
3b. The reducer reconstructs each team's **current five** from `GameStarted` plus every
    `Substitution`; eligibility after the first substitution is checked against that current five,
    never against the starting lineup alone.
4. A sixth personal foul disqualifies immediately; the player may still shoot an awarded free-throw
   group but takes no further live action **unless depleted-roster continuation applies (§6)**. Under
   continuation the player keeps playing, their foul count keeps rising, and no technical foul is
   assessed.
5. Replacement occurs only at a lawful window; missing a mandatory replacement while an eligible bench
   player exists is a validation failure.
6. Seconds played reconcile exactly to team elapsed time.
7. Same input, seed and versions ⇒ identical ledger and identical derived totals.
8. No historical M001/M002/M003 artifact changes meaning.
9. For default lineups, v5 and v4 follow the same event path up to the first `Substitution`;
   divergence after that point is intended and is not an equivalence failure.
10. Every roster player has a box-score row, including players who never enter; team totals
    reconcile across starters and substitutes.
11. Results list the starting five and every substitute who entered, tagged and with minutes;
    players who never entered are not listed, and the screen states that explicitly. Their zero box
    rows still exist in the box model, so no production is omitted and no row is silently missing.

## 3. Court lineup contract

```text
CourtSlot  { Position slot; PlayerId playerId }     // slot ∈ PG..C
CourtLineup{ List<CourtSlot> slots }                // exactly 5, canonical order
```

- `CourtLineup.defaultFor(Team)`: each player from `ActiveLineup`-style selection placed in their own
  primary-position slot. For generated leagues this is slot-identical to the player's position, so
  pre-substitution behaviour matches v4.
- `CourtLineup.create(...)`: validates size, canonical slot order, unique players, roster ownership.
  Slot ≠ player primary position is **legal**.
- Accessors: `playerAt(Position)`, `slotOf(PlayerId)`, `playerIds` (slot order), `toJson` as
  `[{slot, playerId}]`.
- `GameInput`/`GameResult` carry `CourtLineup`; the input lineups are the **starting** lineups only.
- `GameInput.isActive` currently means "in the starting lineup". Under the v5 public transition it must
  be removed or renamed (for example `isStartingPlayer`) so no caller can mistake it for current
  eligibility; the reducer's eligibility check uses its reconstructed current five.
- `ActiveLineup` is replaced, not aliased.

Model rule: **positional bonuses use the occupied slot; attributes use the player.** Nine existing
`player.position.index` lookups move to slot index. No coefficient changes.

## 4. Event contract

```text
Substitution(sequence, period, gameClock, shotClock,
             teamId, playerOutId, playerInId, reason)
reason ∈ { foulOut, tactical }
```

Rules:

- No slot field: the vacated slot is derived from the active out-player.
- No clock or shot-clock change; no possession, possession id, offense team, free-throw group, or
  pending-outcome change.
- `tactical` is a **legal ledger event** from v5; the M004 simulator emits only `foulOut`.
- Substitution events are excluded from the zero-time-event guard, but they are bounded (§4.1).
- Unknown event types remain rejected by the schema dispatcher.

### 4.1 Administrative loop bound

Per team, within one substitution window, each player may appear at most once (either as out or in).
A player leaving may not re-enter during the same window. This makes window-local event count finite
and testable; global event count is still bounded by `maxEvents`.

## 5. Substitution windows

A window is opened by one specific event and closed by the first non-substitution event after it.
Multiple substitutions may occur inside one window, from either team, each independently valid.

| Window | Opened by | Notes |
|---|---|---|
| **W0** | `PersonalFoul` that awards free throws, when the committing defender is disqualified | Only the disqualified defender's team; must precede the first `FreeThrowAttempt`; group id, shooter, attempt count and total untouched. Closed at `gameClock == 0`. |
| **W1** | `PersonalFoul` by the defense with `freeThrowsAwarded == 0` (retained non-bonus foul) | Possession stays open; the pending shot-clock ceiling must survive. Closed at `gameClock == 0`. |
| **W2** | `PossessionEnded(madeFinalFreeThrow)` | Closed at `gameClock == 0`. |
| **W4** | `PossessionEnded(turnover)` whose turnover follows the pending offensive foul | Must follow both the turnover and the possession-end event. Closed at `gameClock == 0`. |
| **W5** | `PeriodStarted` | Before that period's first possession; carries `gameClock = periodLength(period)`, `shotClock: null`. |

Explicitly not windows: after `PossessionEnded(madeFieldGoal)` (NBA Rule 3.V.10 forbids it and this
engine models no inbound), after `PossessionEnded(defensiveRebound)`, after a steal or live turnover,
inside a free-throw group opened for another reason, after `DeadBallMiss`, after `PeriodEnded`, after
`GameEnded`.

### 5.1 Horn and game-end resolution

- No substitution may carry `gameClock == 0`, with no exception.
- A disqualifying foul at the horn: the player is ineligible immediately; awarded free throws are
  resolved by the awarded shooter; no substitution is emitted or accepted at clock 0; replacement is
  mandatory at W5 of the next period if the game continues, and unnecessary if the game ends.
- The reducer records a **pending replacement obligation** for that team. The obligation survives
  `PeriodEnded`. It is satisfied only by a lawful W5 `Substitution` at the next `PeriodStarted`; if
  `GameEnded` follows instead, the obligation is void and no replacement event is required.
- While an obligation is pending, the window-close check treats the over-limit active player as
  authorized **only** because of that obligation. It is not a general exception: an over-limit active
  player with an eligible substitute and no pending obligation remains invalid.
- The obligation must be satisfied before the next period's first `PossessionStarted`; any other event
  while an obligation is pending and an eligible substitute exists is invalid.
- If the team is depleted, no obligation arises (continuation is legal) and the over-limit player may
  continue playing.
- A buzzer non-bonus foul disqualifies identically and defers to W5.
- Missed final free throws at clock 0 resolve as `DeadBallMiss`, never a live rebound, so no live
  action involves the disqualified player.
- This defers identity only; the player's seconds end at 0 either way.

## 6. Eligibility, disqualification and depletion

- `foulOutLimit = 6` (proposed default; configurability is an owner decision).
- Disqualification is derived: `personalFouls >= foulOutLimit` after the foul event. No stored flag,
  no separate event.
- Mandatory replacement at the first window available to the team (W0, W1, W4 or W5 as applicable).
- Continuation is legal **only** when no eligible inactive roster player remains. "No same-position
  candidate" is not depletion; it only changes the ranking.
- A continuing disqualified player remains active for the rest of the game, accumulates fouls
  normally, and is shown as disqualified-but-continuing. Bench eligibility never recovers in M004.
- **No technical foul** is simulated for continuation. This is a deliberate departure from NBA Rule
  3, Section I.1, which assesses a technical foul and a team foul; it must be disclosed in the app.
- With a legal five-player roster the bench is empty from tip-off, so the first disqualification
  continues immediately and no substitution occurs in that game.
- After a window closes, any over-limit active player must be accompanied by an empty eligible bench
  **or** by a recorded pending replacement obligation from a clock-0 disqualification; otherwise the
  ledger is invalid. The obligation never authorises any other over-limit continuation.

## 7. Replacement ranking (deterministic, no PRNG)

1. Eligible candidates: inactive roster players, not disqualified.
2. Prefer candidates whose primary position equals the vacated slot.
3. Order candidates by stable roster index (league order) and take the first.
4. No random draw, no attribute ranking in M004.
5. The chosen replacement is recorded in the event; replay never re-derives it.

## 8. Minutes

- `EventAccounting.aggregate` initializes **every roster player** of both teams with zero values
  before processing events; today it initializes only the starting five, which would reject a
  substitute's event as uncredited.
- Substitute events are credited to the substituting player, not to the player they replaced.
- Players who never enter remain at zero seconds and zero production.
- `PlayerBoxScore.secondsPlayed` (additive field) is derived only from validated ledger timestamps.
- Interval: a player accumulates `clock(start) − clock(end)` within each period; substitutions close
  and open intervals at the same timestamp.
- Conservation, exact and integer: for each team,
  `Σ player.secondsPlayed == 5 × Σ periodLength(played periods)`.
- No negative intervals, no double counting, no simulator-maintained minutes state.
- A W1 substitution splits an open possession; both intervals are counted.
- Box validation fails if the team total does not reconcile, or if any event credits a player who is
  not on that team's roster.
- Conservation alone is not sufficient evidence of correct participation: a ledger missing a
  substitution can still conserve team seconds if the outgoing player's interval simply extends.
  Per-player interval assertions are required (see `verification-plan.md`).

## 9. Versioning (proposed, not applied)

| Identifier | Target |
|---|---|
| `gameSimulationVersion` | 5 |
| `gameRulesVersion` | 3 (adds `foulOutLimit`, `substitutionPolicyVersion`) |
| `gameEventSchemaVersion` | 3 (adds `Substitution`) |
| `gameFingerprintVersion` | 3 (slot-player pairs; rules payload grows) |
| `gameActionDurationModelVersion` | 2 (unchanged) |
| PRNG | `xorshift32-v1` (unchanged) |
| `coreEngineVersion` / `snapshotSchemaVersion` | unchanged |

A new canonical v5 fixture is required; v1–v4 fixtures, mutation suites and M002 evidence are kept
unchanged.

### 9.1 Historical compatibility

- Historical M001–M003 source evidence and fixtures remain byte-identical and keep their own pinned
  verification; nothing is rebaselined.
- `GameEventLedger.fromJson` compares the ledger's schema version to the running constant for exact
  equality, so a v5 build rejects a v4 ledger with the typed
  `unsupportedEventSchemaVersion` code. **v5 does not transparently parse historical ledgers**, and
  this specification does not require it.
- A v4/v5 statistical comparison runs the two pinned engine builds side by side; each build reads its
  own inputs and produces its own fingerprint. Comparison uses normalized configurations — same
  league, team ids, seed and rules — not a shared fingerprint representation.
- Any future schema migration needs its own specification and migration fixtures.

## 10. UI

- Participant display is derived from the **starting lineups plus substitution events** — never from
  minutes and never from the starting five alone.
- Results screen lists the starting five (slot order, marked as starters) followed by players who
  **entered** (order of entry, marked as substitutes), each with minutes.
- Participation is defined by entry, never by `secondsPlayed > 0`: a player who enters and is
  substituted again at the same clock has zero seconds but may already have recorded production and
  must remain visible.
- Players who never enter are **hidden** from the results table. This is a documented display choice,
  not an omission of production: those players generated no events and their zero rows remain in the
  box model. The screen states that non-participants are not listed.
- Disqualification and continuation indicators per player.
- Disclosure adds: foul-outs are modelled; technical-foul penalties are not; a disqualified player may
  continue when no eligible bench player remains; rotations and fatigue are not modelled.
- No lineup editing, no tactical substitution UI.

## 11. Non-goals

Regular rotations, fatigue/stamina effects, coaching AI, user-controlled lineups, technical fouls,
injuries/ejections, re-entry rules, timeouts, post-basket substitutions, persistence, seasons, trades,
contracts, tactics, shot-selection tuning, any probability-coefficient change, any M001–M003 contract
change other than the v5 lineup type replacing `ActiveLineup`.

## 12. Traceability

Acceptance criteria: `acceptance-matrix.md`. Design rationale: `design-decisions.md`. Verification:
`verification-plan.md`. Task breakdown: `tasks.md`.
