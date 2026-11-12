# M008-T08D Acceptance — Free-Agent Acquisition Engine & Market Lifecycle

Status: **implemented, verified; owner acceptance pending**.
Date: 2026-11-12. Baseline:
`fix/m008-t08c-p1-contract-integrity` at
`d07f632a5ae64c583d3a54895ed9d4f3f6b9241c`.
Branch: `feat/m008-t08d-free-agent-acquisition`.

## 1. Lifecycle architecture

- `FreeAgentPool` stores current entries, frozen `initialPlayerIds` (90), and a
  `FreeAgentAcquisitionLedger`.
- Initial generation still produces 90 entries with ≥12 per position in
  `FreeAgentGenerator`; ongoing market validation permits shrinkage.
- Structural invariants: unique current IDs; current ⊆ initial; acquired IDs
  absent from available entries; every initial ID is exactly one of available or
  acquired.
- `FreeAgentAcquisitionService.acquire` is the only acquisition command. It
  moves the existing `Player` and `PlayerCareerProfile` without PRNG, adds one
  `freeAgent` contract through `FinancialTransactions.addContract`, records the
  ledger entry and shrinks the pool.
- Controller persists before publishing and blocks after failed writes.

## 2. Identity and ledger guarantees

- Initial snapshot: 90 IDs; unchanged by acquisition.
- Transaction ID: `free-agent-acquisition-<playerId>-<season>`.
- Ledger records player, team, contract, season, category and origin.
- Duplicate transaction/player, unknown identity, still-available acquired
  player, missing roster/contract/schedule/profile and unexplained removal are
  rejected.

## 3. Contract and salary integration

- Standard: explicit first-year salary 400–8,000; 5% annual raise; every
  scheduled year must remain ≤8,000.
- Two-way: exactly 250 per year.
- Duration 1–4 standard, 1–2 two-way (T08E shared rule); existing longer
  two-way agreements remain valid.
- Cap: standard cap payroll + new salary ≤41,000; two-way does not consume cap.
- Cash: current-year projection must stay ≥0.
- Roster: standard ≤15, two-way ≤3, total ≤21 in the opening offseason.
- No waivers, conversions, relief or implicit salary.

## 4. Deterministic evidence

`tool/t08d_market_evidence.dart`, seed `20261028`, team-1, explicit 400 CU/1-year
test terms (not market prices):

| Situation | Pool | After 1 | After 2 | Cap delta | Cash delta | Shortage |
|---|---|---|---|---|---|---|
| Tanking | 90 | 89 | 88 | +800 | −800 | 2 → 0 |
| Play-In | 90 | 89 | 88 | +800 | −800 | 2 → 0 |
| Playoff | 90 | 89 | 88 | +800 | −800 | 2 → 0 |
| Contender | 90 | 89 | 88 | +800 | −800 | 2 → 0 |

Full output: `t08d-market-evidence.md`. Identity, profile, ledger and round-trip
were asserted in the tool for every situation.

Rejected examples in the same evidence: contender team-19 2,000 CU offer →
`capBreach`; two-way 251 CU → `salaryOutOfBounds`.

## 5. Save and migration

- Career schema v9; native v9 requires `initialPlayerIds` and `acquisitions`.
- v1–v8 migration preserves every existing pool entry exactly, derives the
  initial snapshot from those entries and starts an empty ledger.
- Save/load is byte-stable for acquired careers.
- Controller restart preserves the acquisition exactly; duplicate submissions
  acquire once; failed writes keep the prior career and require reload.

## 6. Readiness and UI

- Standard acquisition reduces the standard shortage by one.
- Two-way acquisition leaves the standard shortage unchanged and does not make a
  team season-ready.
- Read-only board shows name, position, age, overall and observable attributes;
  filters and sorts; hides potential/trajectory; has no offer or sign action.
- Layout tests pass at 360×640 and 393×852.

## 7. Verification

- Core `dart analyze`: clean.
- Core `dart test`: **869 passed**.
- Root `flutter analyze`: clean.
- Root `flutter test`: **221 passed**.
- T08C financial audit: unchanged; 24 leagues, 0 over-cap rosters, one 600-room
  minimum-roster case.
- Existing rookie signing and AI signing suites pass.
- M007 save isolation and storage suites pass.

## 8. JEV review

`jev-latest`: disappearance 0.92, financial integrity 0.92, replay/migration
0.91. Recommendation GO 0.57 with low confidence 0.35 (conditional 0.32). The
judge review is advisory; test evidence is authoritative. Residual confidence is
driven by the still-unimplemented offer/valuation policy and AI acquisition
policy, not by a found integrity defect.

## 9. Remaining risks

- The caller supplies salary terms; no market acceptance/valuation exists.
- AI free-agent acquisition is not implemented.
- Two-way conversion, waivers, trades, renewal, expiry, retirement and season
  advancement remain unimplemented.
- Staff commitments are still one-year records.
- Free-agent position counts may legitimately fall below 12.
- No financial dashboard or shared free-agent market view beyond the read-only
  board.

## 10. Recommendation

**GO for owner acceptance of T08D.** The acquisition engine is atomic,
financially validated, identity-preserving and replay-safe. A later milestone may
add offer valuation and AI acquisition policy on top of this boundary.
