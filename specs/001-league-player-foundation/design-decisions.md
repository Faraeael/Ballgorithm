# Design Decisions 001

Status: implemented as defaults; open for human review (T012).

## D1. PRNG

`DeterministicRandom` implements xorshift32 (Marsaglia 2003), id
`xorshift32-v1`, in `packages/simulation_core/lib/src/generation/deterministic_random.dart`.

- `dart:math` `Random(seed)` is not used: its algorithm is not a language guarantee and may change between SDK releases.
- All state stays inside 32 bits; every step uses only mask/shift/xor, so results are identical on VM and JS backends.
- Bounded integers use rejection sampling, not modulo, to avoid bias.
- Changing the algorithm requires a new `prngImplementationId` and re-baselining snapshots.
- The seed `0` is normalised to `0x9E3779B9` because xorshift is undefined for zero state.
- The usable seed space is 32 bits: seeds are masked with `0xFFFFFFFF`, so seeds that differ only above bit 31 produce the same roster content (league id still reflects the raw seed).
- `nextInt(max)` supports `1..0x100000000`. Larger bounds throw `ArgumentError`: a single 32-bit draw cannot be rejection-sampled above `2^32` without an unbounded loop.
- Pinned vectors in `test/deterministic_random_test.dart` detect accidental drift.

## D2. Rating distribution

Per position archetype: `baseRating = 52` plus a fixed per-attribute positional
offset (`_positionOffsets` in the generator) plus Irwin-Hall(3) noise scaled to
about ±27, then rounded and clamped to 0..100.

Rationale: no external dependency, symmetric distribution, position archetypes
produce plausible relative strengths. This is a design choice, **not** a realism
claim; ratings are uncalibrated against real basketball data.

## D3. Name corpus

40 fictional first names × 40 last names = 1600 pairs, shuffled without
replacement per league. Default league uses 96, so all player names are unique
and no real league/player branding is used (constitution rule 10).
`teamCatalog` holds 8 fictional teams with 3-letter abbreviations.

Capacity is derived from the corpus (`namePairCapacity`, currently 1600). The
generator rejects `teamCount * playersPerTeam > namePairCapacity` with
`nameCapacityExceeded`; there are no duplicated magic numbers.

## D4. Position coverage

Hard constraint. Positions are assigned by cycling `PG, SG, SF, PF, C` across
the roster, then deterministically shuffled. `LeagueValidator` rejects any team
missing a position. Config allows `teamCount 1..8` and `playersPerTeam >= 5`
so tests can build small leagues; the milestone default remains 8 × 12.

## D5. Persistence

No database, file IO or network. `League.toJson()` / `League.fromJson()` define
snapshot conventions: `schemaVersion` (currently `1`), `engineVersion`,
`generation` block (seed, counts, engine version, PRNG id), then teams, rosters,
players. Attribute JSON is a flat name→int map in `PlayerAttributes.attributeNames`
order. Unknown/malformed data is rejected with a typed code, never coerced.
Snapshot import/export to disk is deferred to a later milestone.

Decoding rules (compatibility policy):

- The embedded `generation` config must pass `GenerationConfig.validate()` and its `engineVersion` must equal `coreEngineVersion`; old or unknown engine versions are rejected (`engineVersionMismatch`), not silently reinterpreted.
- Team `id`, `name` and `abbreviation` must be JSON strings. Null, numeric, boolean and missing values are rejected with `malformedJson`, never stringified.
- `League` has no public constructor; `League.create` and `League.fromJson` are the only paths and both validate the config and the aggregate.

## D6. Validation contract

- Constructors reject per-entity violations: attribute bounds, empty team id/name, invalid abbreviation, duplicate player ids within a roster.
- `League.create` and `League.fromJson` run `LeagueValidator` for aggregate rules: team count, roster size, position coverage, duplicate team ids, a player on two teams.
- Failures are `DomainValidationException` carrying `ValidationIssue`s with a stable `ValidationCode`; message text is not part of the contract.
- `generation.engineVersion` must equal `coreEngineVersion`; otherwise generation is refused (`engineVersionMismatch`).

## D7. Layering

- Domain: `packages/simulation_core`, pure Dart; `test/domain_isolation_test.dart` scans sources for Flutter/Flame/DB/network imports.
- Presentation: `lib/features/league`, `lib/features/roster`; screen-local labels only, no domain logic.
- The league is generated once in `lib/main.dart` with a fixed seed and passed down by constructor; no state-management dependency.

## Known limitations

- Attribute realism is unverified; tests assert determinism and bounds only.
- Snapshot compatibility is only tested within one engine version; no migration fixtures yet.
- No golden-image/visual regression tests; widget tests verify structure and navigation.
