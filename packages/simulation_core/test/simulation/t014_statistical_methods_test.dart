import 'package:test/test.dart';

import '../../tool/t014_stats.dart';

void main() {
  group('descriptive statistics', () {
    test('mean, median and sample standard deviation', () {
      final values = [1.0, 2.0, 3.0, 4.0];
      expect(mean(values), 2.5);
      expect(median(values), 2.5);
      expect(sampleStandardDeviation(values), closeTo(1.2909944, 1e-6));
      expect(median([3.0, 1.0, 2.0]), 2.0);
      expect(sampleStandardDeviation([5.0]), 0);
    });

    test(
      'standardized effect is mean over sample SD and undefined at zero SD',
      () {
        final deltas = [0.5, 1.0, 1.5, 2.0];
        final sd = sampleStandardDeviation(deltas);
        expect(mean(deltas) / sd, closeTo(1.9364917, 1e-6));
        expect(sampleStandardDeviation([2.0, 2.0, 2.0]), 0);
      },
    );

    test('type-7 quantiles interpolate', () {
      final values = [1.0, 2.0, 3.0, 4.0, 5.0];
      expect(quantile(values, 0), 1.0);
      expect(quantile(values, 0.25), 2.0);
      expect(quantile(values, 0.5), 3.0);
      expect(quantile(values, 0.75), 4.0);
      expect(quantile(values, 1), 5.0);
      expect(quantile([0.0, 10.0], 0.5), 5.0);
    });
  });

  group('paired bootstrap', () {
    test('is deterministic for a fixed seed and resamples whole pairs', () {
      final deltas = [0.1, 0.2, 0.15, 0.05, -0.02];
      final first = bootstrapMeanInterval(deltas, resamples: 2000, seed: 7);
      final second = bootstrapMeanInterval(deltas, resamples: 2000, seed: 7);
      expect(first.low, second.low);
      expect(first.high, second.high);
      final other = bootstrapMeanInterval(deltas, resamples: 2000, seed: 8);
      expect(other.low, isNot(first.low));
    });

    test('degenerate constant sample has a zero-width interval', () {
      final interval = bootstrapMeanInterval(
        [0.25, 0.25, 0.25],
        resamples: 500,
        seed: 1,
      );
      expect(interval.low, closeTo(0.25, 1e-12));
      expect(interval.high, closeTo(0.25, 1e-12));
    });

    test('all-positive sample keeps the interval above zero', () {
      final interval = bootstrapMeanInterval(
        [0.5, 0.7, 0.6, 0.8, 0.55],
        resamples: 2000,
        seed: 3,
      );
      expect(interval.low, greaterThan(0));
    });
  });

  group('permutation test', () {
    test('strong consistent effect gives a small p-value', () {
      final deltas = [
        1.0,
        1.1,
        0.9,
        1.2,
        1.05,
        0.95,
        1.02,
        0.98,
        1.08,
        0.92,
        1.01,
        0.99,
      ];
      final p = pairedPermutationP(deltas, permutations: 2000, seed: 11);
      expect(p, lessThan(0.01));
      expect(p, greaterThan(0));
    });

    test('symmetric noise gives a large p-value', () {
      final deltas = [1.0, -1.0, 1.0, -1.0, 1.0, -1.0];
      final p = pairedPermutationP(deltas, permutations: 2000, seed: 12);
      expect(p, greaterThan(0.5));
    });

    test('deterministic for a fixed seed and never reports zero', () {
      final deltas = [0.3, 0.2, 0.25, 0.1];
      final first = pairedPermutationP(deltas, permutations: 500, seed: 21);
      final second = pairedPermutationP(deltas, permutations: 500, seed: 21);
      expect(first, second);
      expect(first, greaterThan(0));
    });
  });

  group('Holm adjustment', () {
    test('applies the step-down correction in input order', () {
      final adjusted = holmAdjust([0.01, 0.04, 0.03]);
      expect(adjusted[0], closeTo(0.03, 1e-12));
      expect(adjusted[1], closeTo(0.06, 1e-12));
      expect(adjusted[2], closeTo(0.06, 1e-12));
    });

    test('keeps identical p-values identical and clamped at one', () {
      final adjusted = holmAdjust([0.2, 0.2, 0.2]);
      for (final value in adjusted) {
        expect(value, closeTo(0.6, 1e-12));
      }
      final clamped = holmAdjust([0.9, 0.95]);
      expect(clamped[0], 1.0);
      expect(clamped[1], 1.0);
    });

    test('is monotonic in the sorted p-values', () {
      final adjusted = holmAdjust([0.001, 0.02, 0.5]);
      expect(adjusted[0], lessThanOrEqualTo(adjusted[1]));
      expect(adjusted[1], lessThanOrEqualTo(adjusted[2]));
    });
  });

  group('artifact metric scaling', () {
    test('scaled rate matches the reporting unit and never fakes zero', () {
      expect(scaledRate(1, 10, 1), closeTo(0.1, 1e-12));
      expect(scaledRate(23, 200, 100), closeTo(11.5, 1e-12));
      expect(scaledRate(0, 10, 1), 0.0);
      expect(scaledRate(1, 0, 1), isNull);
      expect(scaledRate(0, 0, 100), isNull);
    });

    test(
      'paired difference equals intervention minus baseline after scaling',
      () {
        final baseline = scaledRate(22, 200, 100);
        final intervention = scaledRate(37, 200, 100);
        final difference = pairedScaledDifference(22, 200, 37, 200, 100);
        expect(baseline, closeTo(11.0, 1e-12));
        expect(intervention, closeTo(18.5, 1e-12));
        expect(difference, closeTo(intervention! - baseline!, 1e-12));
        expect(difference, closeTo(7.5, 1e-12));
      },
    );

    test(
      'paired difference is undefined when either arm has no opportunity',
      () {
        expect(pairedScaledDifference(0, 0, 3, 10, 1), isNull);
        expect(pairedScaledDifference(3, 10, 0, 0, 1), isNull);
        expect(pairedScaledDifference(0, 0, 0, 0, 1), isNull);
      },
    );
  });

  group('verdict rule', () {
    String decide({
      int validPairs = 200,
      int expectedSign = 1,
      required double meanDifference,
      required double ciLow,
      required double ciHigh,
      required double pValue,
      double? holmAdjustedP,
    }) => pairedVerdict(
      validPairs: validPairs,
      minimumValidPairs: 100,
      expectedSign: expectedSign,
      meanDifference: meanDifference,
      ciLow: ciLow,
      ciHigh: ciHigh,
      pValue: pValue,
      holmAdjustedP: holmAdjustedP,
    );

    test(
      'passes only for a significant interval in the expected direction',
      () {
        expect(
          decide(meanDifference: 0.1, ciLow: 0.02, ciHigh: 0.2, pValue: 0.001),
          'PASSED',
        );
        expect(
          decide(
            expectedSign: -1,
            meanDifference: -0.1,
            ciLow: -0.2,
            ciHigh: -0.02,
            pValue: 0.001,
          ),
          'PASSED',
        );
      },
    );

    test(
      'fails when the significant effect is opposite to the expectation',
      () {
        expect(
          decide(meanDifference: 0.1, ciLow: 0.02, ciHigh: 0.2, pValue: 0.001),
          'PASSED',
        );
        expect(
          decide(
            expectedSign: -1,
            meanDifference: 0.1,
            ciLow: 0.02,
            ciHigh: 0.2,
            pValue: 0.001,
          ),
          'FAILED',
        );
      },
    );

    test(
      'is inconclusive for wide intervals, weak p or sparse opportunities',
      () {
        expect(
          decide(meanDifference: 0.1, ciLow: -0.05, ciHigh: 0.2, pValue: 0.2),
          'INCONCLUSIVE',
        );
        expect(
          decide(meanDifference: 0.1, ciLow: 0.02, ciHigh: 0.2, pValue: 0.2),
          'INCONCLUSIVE',
        );
        expect(
          decide(
            validPairs: 40,
            meanDifference: 0.1,
            ciLow: 0.02,
            ciHigh: 0.2,
            pValue: 0.001,
          ),
          'INCONCLUSIVE',
        );
        expect(
          decide(
            meanDifference: 0.1,
            ciLow: 0.02,
            ciHigh: 0.2,
            pValue: 0.001,
            holmAdjustedP: 0.09,
          ),
          'INCONCLUSIVE',
        );
      },
    );

    test('zero differences stay inconclusive', () {
      expect(
        decide(meanDifference: 0, ciLow: 0, ciHigh: 0, pValue: 0.001),
        'INCONCLUSIVE',
      );
    });
  });
}
