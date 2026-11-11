import 'dart:math';

/// Signature for career seed generation functions.
typedef CareerSeedProvider = int Function();

/// Generates a fresh non-zero 31-bit integer seed appropriate for new career generation.
///
/// Uses [Random.secure] for high-entropy generation across platforms, with fallback
/// to bit-mixed timestamps if secure RNG is unavailable.
int generateCareerSeed([Random? random]) {
  try {
    final rng = random ?? Random.secure();
    // 0x7FFFFFFE is 2^31 - 2. Adding 1 yields [1, 2^31 - 1], guaranteed non-zero positive 31-bit int.
    final seed = rng.nextInt(0x7FFFFFFE) + 1;
    return seed;
  } catch (_) {
    final now = DateTime.now().microsecondsSinceEpoch;
    // Mix high and low bits to avoid short-window microsecond repetition
    final mixed = ((now ^ (now >> 16)) & 0x7FFFFFFE) + 1;
    return mixed;
  }
}
