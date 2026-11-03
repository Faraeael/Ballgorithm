import 'dart:math' as math;

import 'package:test/test.dart';

import '../../tool/t08_common.dart';

void main() {
  group('frozen T08 allocation', () {
    test('200 unique seeds, 50 per matchup, balanced seed parity', () {
      final slots = t08Slots();
      expect(slots, hasLength(200));
      expect(() => validateT08Slots(slots), returnsNormally);
      expect(slots.map((slot) => slot.seed).toSet(), hasLength(200));
      expect(slots.first.seed, 20001);
      expect(slots.last.seed, 20200);
      for (var m = 0; m < 4; m++) {
        final group = slots.where((slot) => slot.matchup == m).toList();
        expect(group, hasLength(50), reason: 'matchup $m');
        expect(group.where((slot) => slot.seed.isEven), hasLength(25));
        expect(group.where((slot) => slot.seed.isOdd), hasLength(25));
      }
    });

    test('manifest CSV round-trips and detects tampering', () {
      final slots = parseT08Manifest(t08ManifestCsv());
      expect(slots, hasLength(200));
      for (var i = 0; i < slots.length; i++) {
        expect(slots[i].slot, i);
        expect(slots[i].seed, 20001 + i);
        expect(slots[i].matchup, (i ~/ 2) % 4);
      }
      final broken = [...slots];
      broken[0] = const T08Slot(
        slot: 0,
        matchup: 1,
        seed: 20001,
        homeTeamId: 'team-1',
        awayTeamId: 'team-2',
      );
      expect(() => validateT08Slots(broken), throwsStateError);
    });
  });

  group('frozen T08 statistics', () {
    test('paired summary uses the registered formulas', () {
      final values = [for (var i = 0; i < 200; i++) ((i % 5) - 2).toDouble()];
      final summary = t08Describe(values);
      expect(summary['n'], 200);
      expect(summary['mean'], 0.0);
      final sampleSd = _sqrt(400 / 199);
      expect(summary['sd'], closeTo(sampleSd, 1e-12));
      final se = sampleSd / _sqrt(200);
      expect(summary['se'], closeTo(se, 1e-12));
      const tCritical = 1.9719565;
      expect(summary['ci95Low'], closeTo(-tCritical * se, 1e-12));
      expect(summary['ci95High'], closeTo(tCritical * se, 1e-12));
      expect(summary['negative'], 80);
      expect(summary['zero'], 40);
      expect(summary['positive'], 80);
      expect(summary['min'], -2.0);
      expect(summary['max'], 2.0);
      expect(summary['median'], 0.0);
    });

    test('type-7 quantiles match the repository convention', () {
      final values = [1.0, 2.0, 3.0, 4.0];
      expect(t08Quantile(values, 0.0), 1.0);
      expect(t08Quantile(values, 0.25), 1.75);
      expect(t08Quantile(values, 0.5), 2.5);
      expect(t08Quantile(values, 0.75), 3.25);
      expect(t08Quantile(values, 1.0), 4.0);
    });

    test('registered t critical values are fixed', () {
      expect(t08Critical95(199), 1.9719565);
      expect(t08Critical95(49), 2.009575);
      expect(() => t08Critical95(198), throwsArgumentError);
    });
  });
}

double _sqrt(num value) => math.sqrt(value.toDouble());
