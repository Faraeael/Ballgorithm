import 'dart:math';

import 'package:test/test.dart';

/// Pure, deterministic implementation of Holm step-down testing for M006.
Map<String, ({double pValue, int rank, double alphaThreshold, bool rejected})>
holmStepDown(Map<String, double> pValues, {double alpha = 0.05}) {
  final entries = pValues.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));

  final results =
      <
        String,
        ({double pValue, int rank, double alphaThreshold, bool rejected})
      >{};
  var stopped = false;
  final kTotal = pValues.length;

  for (var i = 0; i < entries.length; i++) {
    final rank = i + 1;
    final threshold = alpha / (kTotal - rank + 1);
    final pVal = entries[i].value;
    final rejected = !stopped && pVal <= threshold;
    if (!rejected) {
      stopped = true;
    }
    results[entries[i].key] = (
      pValue: pVal,
      rank: rank,
      alphaThreshold: threshold,
      rejected: rejected,
    );
  }
  return results;
}

/// Two One-Sided Tests (TOST) equivalence rule at alpha=0.05 (90% CI).
bool tostEquivalence({
  required double meanDiff,
  required double sdDiff,
  required int n,
  required double delta,
}) {
  final se = sdDiff / sqrt(n);
  const zAlpha = 1.6448536; // 90% CI critical value for alpha=0.05
  final ciLow = meanDiff - zAlpha * se;
  final ciHigh = meanDiff + zAlpha * se;
  return ciLow >= -delta && ciHigh <= delta;
}

void main() {
  group('M006-T06C Statistical Corrections Validation', () {
    test('Holm step-down sorts dynamically by observed p-value', () {
      final pValues = {
        'endpoint_A': 0.020,
        'endpoint_B': 0.001,
        'endpoint_C': 0.040,
        'endpoint_D': 0.005,
      };

      final results = holmStepDown(pValues, alpha: 0.05);

      // endpoint_B has lowest p (0.001) -> rank 1, threshold 0.05/4 = 0.0125 -> rejected
      expect(results['endpoint_B']!.rank, 1);
      expect(results['endpoint_B']!.alphaThreshold, closeTo(0.0125, 1e-6));
      expect(results['endpoint_B']!.rejected, isTrue);

      // endpoint_D has 2nd lowest p (0.005) -> rank 2, threshold 0.05/3 = 0.01667 -> rejected
      expect(results['endpoint_D']!.rank, 2);
      expect(results['endpoint_D']!.alphaThreshold, closeTo(0.0166667, 1e-6));
      expect(results['endpoint_D']!.rejected, isTrue);

      // endpoint_A has 3rd lowest p (0.020) -> rank 3, threshold 0.05/2 = 0.025 -> rejected
      expect(results['endpoint_A']!.rank, 3);
      expect(results['endpoint_A']!.alphaThreshold, closeTo(0.025, 1e-6));
      expect(results['endpoint_A']!.rejected, isTrue);

      // endpoint_C has 4th lowest p (0.040) -> rank 4, threshold 0.05/1 = 0.05 -> rejected
      expect(results['endpoint_C']!.rank, 4);
      expect(results['endpoint_C']!.alphaThreshold, closeTo(0.05, 1e-6));
      expect(results['endpoint_C']!.rejected, isTrue);
    });

    test('Holm step-down halts rejection cascade on first non-rejection', () {
      final pValues = {
        'endpoint_1': 0.001, // rank 1: 0.001 <= 0.0125 -> rejected
        'endpoint_2': 0.020, // rank 2: 0.020 > 0.01667 -> NOT rejected (halts!)
        'endpoint_3':
            0.021, // rank 3: 0.021 <= 0.025, but MUST NOT be rejected due to halt!
        'endpoint_4':
            0.030, // rank 4: 0.030 <= 0.050, but MUST NOT be rejected due to halt!
      };

      final results = holmStepDown(pValues, alpha: 0.05);

      expect(results['endpoint_1']!.rejected, isTrue);
      expect(results['endpoint_2']!.rejected, isFalse);
      expect(results['endpoint_3']!.rejected, isFalse);
      expect(results['endpoint_4']!.rejected, isFalse);
    });

    test('TOST equivalence correctly bounds 90% CI inside margin', () {
      // Points example: margin = 3.0, sd = 15.942, n = 500
      // se = 15.942 / sqrt(500) = 0.71295
      // half-width = 1.64485 * 0.71295 = 1.1727
      // mean = 0.12 -> CI is [-1.0527, 1.2927], strictly inside [-3.0, 3.0] -> pass
      expect(
        tostEquivalence(meanDiff: 0.12, sdDiff: 15.942, n: 500, delta: 3.0),
        isTrue,
      );

      // mean = 2.0 -> CI is [0.827, 3.173], upper bound exceeds 3.0 -> fail
      expect(
        tostEquivalence(meanDiff: 2.0, sdDiff: 15.942, n: 500, delta: 3.0),
        isFalse,
      );

      // FTA example at draft margin 1.75: mean = -0.705, sd = 9.25, n = 500
      // se = 9.25 / sqrt(500) = 0.41367
      // half-width = 1.64485 * 0.41367 = 0.6804
      // mean = -1.10 -> CI is [-1.78, -0.42], lower bound exceeds -1.75 -> fail
      expect(
        tostEquivalence(meanDiff: -1.10, sdDiff: 9.25, n: 500, delta: 1.75),
        isFalse,
      );

      // Under refined margin 2.25: mean = -1.10 -> CI [-1.78, -0.42] is inside [-2.25, 2.25] -> pass
      expect(
        tostEquivalence(meanDiff: -1.10, sdDiff: 9.25, n: 500, delta: 2.25),
        isTrue,
      );
    });

    test(
      'Zero-denominator handling preserves undefined per-game differences',
      () {
        final v6Attempts = [0, 5, 10, 0];
        final v6Makes = [0, 2, 4, 0];
        final v7Attempts = [0, 6, 8, 4];
        final v7Makes = [0, 3, 3, 1];

        final perGameDiffs = <double>[];
        var undefinedCount = 0;

        for (var i = 0; i < v6Attempts.length; i++) {
          if (v6Attempts[i] == 0 || v7Attempts[i] == 0) {
            undefinedCount++;
          } else {
            final r6 = v6Makes[i] / v6Attempts[i];
            final r7 = v7Makes[i] / v7Attempts[i];
            perGameDiffs.add(r7 - r6);
          }
        }

        expect(undefinedCount, 2);
        expect(perGameDiffs.length, 2);

        // Check difference between per-game mean and pooled ratio
        final perGameMean =
            perGameDiffs.reduce((a, b) => a + b) / perGameDiffs.length;

        final pooledV6 =
            v6Makes.reduce((a, b) => a + b) /
            v6Attempts.reduce((a, b) => a + b);
        final pooledV7 =
            v7Makes.reduce((a, b) => a + b) /
            v7Attempts.reduce((a, b) => a + b);
        final pooledDiff = pooledV7 - pooledV6;

        expect(perGameMean, isNot(equals(pooledDiff)));
      },
    );

    test('Seed range disjointness check confirms zero collision', () {
      final diagSeeds = List.generate(400, (i) => i + 1).toSet();
      final stageASeeds = List.generate(200, (i) => 2001 + i).toSet();
      final stageBDevSeeds = List.generate(200, (i) => 3001 + i).toSet();
      final contextASeeds = List.generate(500, (i) => 10001 + i).toSet();
      final contextBSeeds = List.generate(250, (i) => 11001 + i).toSet();

      expect(contextASeeds.intersection(diagSeeds), isEmpty);
      expect(contextASeeds.intersection(stageASeeds), isEmpty);
      expect(contextASeeds.intersection(stageBDevSeeds), isEmpty);

      expect(contextBSeeds.intersection(diagSeeds), isEmpty);
      expect(contextBSeeds.intersection(stageASeeds), isEmpty);
      expect(contextBSeeds.intersection(stageBDevSeeds), isEmpty);
      expect(contextBSeeds.intersection(contextASeeds), isEmpty);
    });
  });
}
