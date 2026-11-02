/// Deterministic game-seed derivation (M003 DD-MGD-04).
///
/// The three inputs occupy disjoint bit fields — home index in bits 16–18,
/// away index in bits 8–10, rematch index in bits 0–7 — and rematch is masked
/// so its higher bits cannot alias a different matchup. The result is masked to
/// 31 bits: it stays inside Dart's web-safe integer range, and no derived seed
/// can equal `0x9E3779B9`, the value the core substitutes for a raw seed of
/// zero. Normalized seeds are therefore distinct across the bounded input
/// domain.
///
/// The rematch cycle is exactly 256 games per ordered matchup.
int deriveGameSeed({
  required int leagueSeed,
  required int homeIndex,
  required int awayIndex,
  required int rematchIndex,
}) {
  return (leagueSeed ^
          (homeIndex << 16) ^
          (awayIndex << 8) ^
          (rematchIndex & 0xFF)) &
      0x7FFFFFFF;
}

/// Display text for the seed the engine will consume. The core normalizes a raw
/// seed of zero to `0x9E3779B9` (`2654435769`), so both values are shown.
String describeGameSeed(int seed) =>
    seed == 0 ? '0 (normalized 2654435769)' : '$seed';
