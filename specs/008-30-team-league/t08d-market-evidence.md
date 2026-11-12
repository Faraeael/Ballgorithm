# T08D market evidence (generated)

Seed 20261028, human team-1, explicit terms: standard 400 CU / 1 year. Terms are test inputs, not market prices.

| Situation | Pool before | Initial IDs | Acquired | Pool after 1 | Pool after 2 | Cap delta | Cash delta | Shortage before → after |
|---|---|---|---|---|---|---|---|---|
| Tanking / Rebuilding | 90 | 90 | 2 | 89 | 88 | +800 | -800 | 2 → 0 |
| Play-In Contender | 90 | 90 | 2 | 89 | 88 | +800 | -800 | 2 → 0 |
| Playoff Team | 90 | 90 | 2 | 89 | 88 | +800 | -800 | 2 → 0 |
| Championship Contender | 90 | 90 | 2 | 89 | 88 | +800 | -800 | 2 → 0 |

## Rejected examples

- Cap: contender team-19, 2,000 CU offer → `capBreach`.
- Two-way salary: 251 CU offer → `salaryOutOfBounds`.

All four situations preserve identity, ledger, snapshot and round-trip. Existing contracts are not rewritten.
