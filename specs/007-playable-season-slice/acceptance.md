# M007 Acceptance Criteria — Single-Season Playable Vertical Slice

- **Status:** APPROVED CRITERIA MATRIX.
- **Verification Gate:** All criteria must pass deterministic tests before milestone completion.

---

## Acceptance Matrix

| ID | Category | Criterion Description | Verification Method |
|---|---|---|---|
| **AC-007-01** | Schedule | Exactly 56 unique scheduled fixtures across 14 rounds of 4 games each | `schedule_test.dart` asserting counts and uniqueness |
| **AC-007-02** | Schedule | Each team plays exactly 14 games: 7 home, 7 away; exactly 2 meetings per pair | Matrix assertion on all $8 \times 7$ pairings |
| **AC-007-03** | Schedule | Each team plays exactly once per round; no team is idle or scheduled twice | Round roster coverage test |
| **AC-007-04** | Schedule | Fixture seeds are unique, deterministic, and derived from league seed | Seed collision scan |
| **AC-007-05** | Standings | Standings accurately record wins, losses, win%, points for/against, diff, streak | Mathematical property test comparing box scores to standings |
| **AC-007-06** | Standings | Tie-break follows documented order: Wins $\to$ Diff $\to$ Points For $\to$ Team ID | Unit test with tied records |
| **AC-007-07** | Statistics | Player season totals equal the sum of completed game box scores | Reconciliation audit across all 56 games |
| **AC-007-08** | Statistics | Zero-denominator rates return null and never crash with divide-by-zero | Unit test on 0-attempt players |
| **AC-007-09** | Strategy | Saved starting five and rotation targets persist and auto-apply to games | `season_strategy_test.dart` asserting input request matches saved strategy |
| **AC-007-10** | Progression | Simulating a round runs the user game plus 3 background games via simulator | Integration test verifying 4 completed games per round |
| **AC-007-11** | Transaction | Round commit is atomic and idempotent; completed rounds cannot be re-simulated | Re-submission rejection test |
| **AC-007-12** | Persistence | Season state saves and loads cleanly across app restarts with schema version 1 | Save/load round-trip test |
| **AC-007-13** | Persistence | Corrupt or invalid save data returns an error without deleting player data | Malformed JSON test |
| **AC-007-14** | End-of-Season | After Round 14, no further games schedule; champion and final record display | Automated 14-round execution test |
| **AC-007-15** | Playable Loop | End-to-end playable loop works without overflow on mobile viewports (360x640) | Flutter flow test with `tester.view.physicalSize` |
