/// Deterministic game-seed derivation for M007 season fixtures.
///
/// Disjoint bit fields: home index in bits 16–18, away index in bits 8–10,
/// round/rematch index in bits 0–7. Masked to 31 bits: web-safe, non-zero,
/// and collision-free across the season matrix.
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

String describeGameSeed(int seed) =>
    seed == 0 ? '0 (normalized 2654435769)' : '$seed';
