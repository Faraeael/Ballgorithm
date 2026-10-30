/// Deterministic statistics helpers for the T014 sensitivity analysis.
///
/// Deliberately dependency-free and independent of the game simulation PRNG:
/// the analysis uses its own `xorshift32-v1` stream so bootstrap and permutation
/// draws can never be influenced by gameplay draws.
library;

import 'dart:math' as math;

/// Minimal reimplementation of the game's `xorshift32-v1` generator.
final class AnalysisRandom {
  AnalysisRandom(int seed) : _state = _normalize(seed);

  static int _normalize(int seed) {
    final masked = seed & 0xFFFFFFFF;
    return masked == 0 ? 0x9E3779B9 : masked;
  }

  int _state;

  int nextUint32() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state;
  }

  /// Uniform double in `[0, 1)` from 32 random bits.
  double nextDouble() => nextUint32() / 4294967296.0;

  bool nextBool() => nextUint32().isOdd;
}

double mean(Iterable<double> values) {
  final list = values.toList(growable: false);
  if (list.isEmpty) throw ArgumentError('mean of empty sample');
  var total = 0.0;
  for (final value in list) {
    total += value;
  }
  return total / list.length;
}

double median(Iterable<double> values) {
  final list = values.toList()..sort();
  if (list.isEmpty) throw ArgumentError('median of empty sample');
  final middle = list.length ~/ 2;
  if (list.length.isOdd) return list[middle];
  return (list[middle - 1] + list[middle]) / 2;
}

/// Sample standard deviation with `n - 1` denominator; 0 for `n < 2`.
double sampleStandardDeviation(Iterable<double> values) {
  final list = values.toList(growable: false);
  if (list.length < 2) return 0;
  final average = mean(list);
  var sumSquares = 0.0;
  for (final value in list) {
    final diff = value - average;
    sumSquares += diff * diff;
  }
  return math.sqrt(sumSquares / (list.length - 1));
}

/// Type-7 (linear interpolation) quantile of a sorted-able sample.
double quantile(Iterable<double> values, double q) {
  final list = values.toList()..sort();
  if (list.isEmpty) throw ArgumentError('quantile of empty sample');
  if (q <= 0) return list.first;
  if (q >= 1) return list.last;
  final position = (list.length - 1) * q;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return list[lower];
  final weight = position - lower;
  return list[lower] * (1 - weight) + list[upper] * weight;
}

/// Paired percentile bootstrap confidence interval for the mean.
({double low, double high}) bootstrapMeanInterval(
  List<double> deltas, {
  int resamples = 10000,
  int seed = 20261029,
  double confidence = 0.95,
}) {
  if (deltas.isEmpty) throw ArgumentError('bootstrap of empty sample');
  final random = AnalysisRandom(seed);
  final means = List<double>.filled(resamples, 0);
  for (var i = 0; i < resamples; i++) {
    var total = 0.0;
    for (var j = 0; j < deltas.length; j++) {
      total += deltas[random.nextUint32() % deltas.length];
    }
    means[i] = total / deltas.length;
  }
  final tail = (1 - confidence) / 2;
  return (low: quantile(means, tail), high: quantile(means, 1 - tail));
}

/// Two-sided paired sign-flip permutation test on the mean difference.
double pairedPermutationP(
  List<double> deltas, {
  int permutations = 10000,
  int seed = 424242,
}) {
  if (deltas.isEmpty) throw ArgumentError('permutation of empty sample');
  final observed = mean(deltas).abs();
  final random = AnalysisRandom(seed);
  var atLeastAsExtreme = 0;
  for (var i = 0; i < permutations; i++) {
    var total = 0.0;
    for (final delta in deltas) {
      total += random.nextBool() ? delta : -delta;
    }
    if ((total / deltas.length).abs() >= observed - 1e-12) {
      atLeastAsExtreme++;
    }
  }
  return (1 + atLeastAsExtreme) / (permutations + 1);
}

/// Per-seed rate in the experiment's reporting unit (`scale` = 1 or 100).
///
/// Returns null when the denominator is zero; a missing opportunity is never
/// encoded as a rate of zero.
double? scaledRate(int numerator, int denominator, double scale) =>
    denominator > 0 ? numerator / denominator * scale : null;

/// Paired difference in the same reporting unit as [scaledRate].
///
/// Returns null when either arm lacks an opportunity. Callers must verify
/// `pairedScaledDifference(...) == intervention - baseline` for valid rows; the
/// T014 runner asserts this for every row it writes.
double? pairedScaledDifference(
  int baselineNumerator,
  int baselineDenominator,
  int interventionNumerator,
  int interventionDenominator,
  double scale,
) {
  final baseline = scaledRate(baselineNumerator, baselineDenominator, scale);
  final intervention = scaledRate(
    interventionNumerator,
    interventionDenominator,
    scale,
  );
  if (baseline == null || intervention == null) return null;
  return intervention - baseline;
}

/// Fixed verdict rule shared by the experiment runner and its tests.
///
/// `expectedSign` is +1 for an expected increase and -1 for a decrease.
/// A result is `PASSED` only when enough pairs contribute, the p-value
/// (adjusted when supplied) is below 0.05, the percentile interval excludes
/// zero in the expected direction, and the mean difference agrees with that
/// direction. A significant interval in the opposite direction is `FAILED`;
/// everything else is `INCONCLUSIVE`.
String pairedVerdict({
  required int validPairs,
  required int minimumValidPairs,
  required int expectedSign,
  required double meanDifference,
  required double ciLow,
  required double ciHigh,
  required double pValue,
  double? holmAdjustedP,
}) {
  if (validPairs < minimumValidPairs) return 'INCONCLUSIVE';
  final adjusted = holmAdjustedP ?? pValue;
  if (adjusted >= 0.05 || pValue >= 0.05) return 'INCONCLUSIVE';
  final int intervalSign;
  if (ciLow > 0) {
    intervalSign = 1;
  } else if (ciHigh < 0) {
    intervalSign = -1;
  } else {
    return 'INCONCLUSIVE';
  }
  final int meanSign;
  if (meanDifference > 0) {
    meanSign = 1;
  } else if (meanDifference < 0) {
    meanSign = -1;
  } else {
    return 'INCONCLUSIVE';
  }
  if (meanSign != intervalSign) return 'INCONCLUSIVE';
  return intervalSign == expectedSign ? 'PASSED' : 'FAILED';
}

/// Holm–Bonferroni adjusted p-values in input order.
List<double> holmAdjust(List<double> pValues) {
  final order = List<int>.generate(pValues.length, (index) => index)
    ..sort((a, b) => pValues[a].compareTo(pValues[b]));
  final adjusted = List<double>.filled(pValues.length, 1);
  var running = 0.0;
  for (var rank = 0; rank < order.length; rank++) {
    final index = order[rank];
    final scaled = (pValues[index] * (order.length - rank))
        .clamp(0.0, 1.0)
        .toDouble();
    running = scaled > running ? scaled : running;
    adjusted[index] = running;
  }
  return adjusted;
}
