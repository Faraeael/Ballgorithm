import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// M004 T08 fixed design constants. Frozen before execution; do not vary.
const int t08FirstSeed = 20001;
const int t08PairCount = 200;
const int t08MatchupCount = 4;

/// One registered matched game pair.
final class T08Slot {
  const T08Slot({
    required this.slot,
    required this.matchup,
    required this.seed,
    required this.homeTeamId,
    required this.awayTeamId,
  });

  final int slot;
  final int matchup;
  final int seed;
  final String homeTeamId;
  final String awayTeamId;

  String get gameId => 'm004-t08-m$matchup-$seed';

  Map<String, Object?> toJson() => {
    'slot': slot,
    'matchup': matchup,
    'seed': seed,
    'gameId': gameId,
    'homeTeamId': homeTeamId,
    'awayTeamId': awayTeamId,
  };
}

const List<List<String>> t08Matchups = [
  ['team-1', 'team-2'],
  ['team-3', 'team-4'],
  ['team-5', 'team-6'],
  ['team-7', 'team-8'],
];

/// Registered allocation: `seed = 20001 + s`, `matchup = (s ~/ 2) % 4`.
List<T08Slot> t08Slots() => [
  for (var s = 0; s < t08PairCount; s++)
    T08Slot(
      slot: s,
      matchup: (s ~/ 2) % t08MatchupCount,
      seed: t08FirstSeed + s,
      homeTeamId: t08Matchups[(s ~/ 2) % t08MatchupCount][0],
      awayTeamId: t08Matchups[(s ~/ 2) % t08MatchupCount][1],
    ),
];

const String t08ManifestHeader =
    'slot,matchup,seed,gameId,homeTeamId,awayTeamId';

String t08ManifestCsv() {
  final buffer = StringBuffer()..writeln(t08ManifestHeader);
  for (final slot in t08Slots()) {
    buffer.writeln(
      '${slot.slot},${slot.matchup},${slot.seed},${slot.gameId},'
      '${slot.homeTeamId},${slot.awayTeamId}',
    );
  }
  return buffer.toString();
}

List<T08Slot> parseT08Manifest(String csv) {
  final lines = const LineSplitter().convert(csv.trimRight());
  if (lines.isEmpty || lines.first != t08ManifestHeader) {
    throw const FormatException('manifest header mismatch');
  }
  final slots = <T08Slot>[];
  for (final line in lines.skip(1)) {
    final parts = line.split(',');
    if (parts.length != 6) {
      throw FormatException('malformed manifest row: $line');
    }
    slots.add(
      T08Slot(
        slot: int.parse(parts[0]),
        matchup: int.parse(parts[1]),
        seed: int.parse(parts[2]),
        homeTeamId: parts[4],
        awayTeamId: parts[5],
      ),
    );
  }
  return slots;
}

/// Structural validation of the frozen allocation; throws on any violation.
void validateT08Slots(List<T08Slot> slots) {
  if (slots.length != t08PairCount) {
    throw StateError('expected $t08PairCount slots, got ${slots.length}');
  }
  final seeds = <int>{};
  final ids = <String>{};
  final perMatchup = <int, List<int>>{};
  for (final slot in slots) {
    if (!seeds.add(slot.seed)) {
      throw StateError('duplicate seed ${slot.seed}');
    }
    final expectedSeed = t08FirstSeed + slot.slot;
    if (slot.seed != expectedSeed) {
      throw StateError('slot ${slot.slot}: seed ${slot.seed} != $expectedSeed');
    }
    final expectedMatchup = (slot.slot ~/ 2) % t08MatchupCount;
    if (slot.matchup != expectedMatchup) {
      throw StateError('slot ${slot.slot}: matchup mismatch');
    }
    final matchups = t08Matchups[slot.matchup];
    if (slot.homeTeamId != matchups[0] || slot.awayTeamId != matchups[1]) {
      throw StateError('slot ${slot.slot}: matchup teams mismatch');
    }
    if (!ids.add(slot.gameId)) {
      throw StateError('duplicate game id ${slot.gameId}');
    }
    perMatchup.putIfAbsent(slot.matchup, () => <int>[]).add(slot.seed);
  }
  if (seeds.length != t08PairCount) {
    throw StateError('expected $t08PairCount unique seeds');
  }
  for (var m = 0; m < t08MatchupCount; m++) {
    final group = perMatchup[m];
    if (group == null || group.length != 50) {
      throw StateError('matchup $m must have 50 slots');
    }
    final even = group.where((seed) => seed.isEven).length;
    if (even != 25) {
      throw StateError('matchup $m must have 25 even seeds, got $even');
    }
  }
}

String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

double t08Mean(List<double> values) {
  if (values.isEmpty) throw ArgumentError('mean of empty sample');
  return values.reduce((a, b) => a + b) / values.length;
}

double t08SampleSd(List<double> values) {
  if (values.length < 2) throw ArgumentError('sd needs n >= 2');
  final mean = t08Mean(values);
  final sum = values.fold<double>(0, (acc, v) => acc + (v - mean) * (v - mean));
  return (sum / (values.length - 1)) == 0
      ? 0
      : _sqrt(sum / (values.length - 1));
}

double _sqrt(double value) => math.sqrt(value);

/// Two-sided 95% Student-t critical values for the degrees of freedom used by
/// the frozen T08 design (primary n = 200; matchup breakdown n = 50).
double t08Critical95(int degreesOfFreedom) => switch (degreesOfFreedom) {
  49 => 2.009575,
  199 => 1.9719565,
  _ => throw ArgumentError(
    'no pre-registered t critical value for df $degreesOfFreedom',
  ),
};

/// Type-7 quantile, matching the repository's existing metric convention.
double t08Quantile(List<double> values, double q) {
  if (values.isEmpty) throw ArgumentError('quantile of empty sample');
  final sorted = [...values]..sort();
  final position = (sorted.length - 1) * q;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final weight = position - lower;
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}

/// Descriptive distribution without a confidence interval. Used for minutes by
/// roster rank and per-matchup frequency summaries where no t critical value is
/// pre-registered.
Map<String, Object?> t08Distribution(List<double> values) {
  final mean = t08Mean(values);
  final sd = values.length > 1 ? t08SampleSd(values) : 0.0;
  return {
    'n': values.length,
    'mean': mean,
    'sd': sd,
    'min': values.reduce((a, b) => a < b ? a : b),
    'q05': t08Quantile(values, 0.05),
    'q25': t08Quantile(values, 0.25),
    'median': t08Quantile(values, 0.5),
    'q75': t08Quantile(values, 0.75),
    'q95': t08Quantile(values, 0.95),
    'max': values.reduce((a, b) => a > b ? a : b),
    'zeros': values.where((v) => v == 0).length,
  };
}

Map<String, Object?> t08Describe(List<double> values) {
  final mean = t08Mean(values);
  final sd = values.length > 1 ? t08SampleSd(values) : 0.0;
  final se = values.length > 1 ? sd / _sqrt(values.length.toDouble()) : 0.0;
  final delta = t08Critical95(values.length - 1) * se;
  final negative = values.where((v) => v < 0).length;
  final zero = values.where((v) => v == 0).length;
  return {
    'n': values.length,
    'mean': mean,
    'sd': sd,
    'se': se,
    'ci95Low': mean - delta,
    'ci95High': mean + delta,
    'min': values.reduce((a, b) => a < b ? a : b),
    'q05': t08Quantile(values, 0.05),
    'q25': t08Quantile(values, 0.25),
    'median': t08Quantile(values, 0.5),
    'q75': t08Quantile(values, 0.75),
    'q95': t08Quantile(values, 0.95),
    'max': values.reduce((a, b) => a > b ? a : b),
    'negative': negative,
    'zero': zero,
    'positive': values.where((v) => v > 0).length,
  };
}
