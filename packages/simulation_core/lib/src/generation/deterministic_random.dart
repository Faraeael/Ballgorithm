import '../domain_versions.dart';

/// Deterministic PRNG, stable across Dart VM and web.
///
/// `dart:math` `Random(seed)` is intentionally avoided: its algorithm is not
/// part of the language contract. This xorshift32 variant keeps every value
/// inside 32 bits, so results do not depend on int width or JS double math.
///
/// Algorithm: xorshift32 (Marsaglia 2003). Output stability is promised for
/// [prngImplementationId] `xorshift32-v1` only; changing the algorithm requires
/// a new id and a constitution check on snapshots.
final class DeterministicRandom {
  DeterministicRandom(int seed) : _state = _normalizeSeed(seed);

  static const int _mask32 = 0xFFFFFFFF;
  static const int _zeroSeedFallback = 0x9E3779B9;

  final String implementationId = prngImplementationId;

  int _state;

  static int _normalizeSeed(int seed) {
    final state = seed & _mask32;
    return state == 0 ? _zeroSeedFallback : state;
  }

  /// Uniform 32-bit value in `0..2^32-1`.
  int nextUint32() {
    var x = _state;
    x ^= (x << 13) & _mask32;
    x ^= x >>> 17;
    x ^= (x << 5) & _mask32;
    _state = x & _mask32;
    return _state;
  }

  /// Uniform integer in `0..max-1` via rejection sampling (no modulo bias).
  int nextInt(int max) {
    // Above 2^32 a single 32-bit draw cannot be rejection-sampled without
    // wrapping limit to zero and looping forever.
    if (max <= 0 || max > 0x100000000) {
      throw ArgumentError.value(max, 'max', 'must be in 1..0x100000000');
    }
    final limit = 0x100000000 - (0x100000000 % max);
    var value = nextUint32();
    while (value >= limit) {
      value = nextUint32();
    }
    return value % max;
  }

  /// Uniform double in `[0, 1)`.
  double nextDouble() => nextUint32() / 0x100000000;

  /// In-place Fisher-Yates shuffle using [nextInt].
  void shuffle<T>(List<T> items) {
    for (var i = items.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = items[i];
      items[i] = items[j];
      items[j] = tmp;
    }
  }
}
