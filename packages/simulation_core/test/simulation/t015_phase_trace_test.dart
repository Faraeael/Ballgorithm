import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

String digest(GameResult result) =>
    sha256.convert(utf8.encode(jsonEncode(result.ledger.toJson()))).toString();

void main() {
  group('passive A1 trace', () {
    test('observer-off and observer-on ledgers are byte-identical', () {
      for (final seed in [1, 42, 99]) {
        final input = buildInput(seed: seed);
        final plain = GameSimulator().simulate(input);
        final records = <PhaseTraceRecord>[];
        final traced = GameSimulator(onPhaseTrace: records.add).simulate(input);
        expect(
          jsonEncode(traced.ledger.toJson()),
          jsonEncode(plain.ledger.toJson()),
        );
        expect(traced.homeScore, plain.homeScore);
        expect(traced.awayScore, plain.awayScore);
        expect(digest(traced), digest(plain));
        expect(records, isNotEmpty);
      }
    });

    test('records capture sampled phases and their resolutions', () {
      final records = <PhaseTraceRecord>[];
      final input = buildInput(seed: 42);
      final result = GameSimulator(onPhaseTrace: records.add).simulate(input);
      final brackets = {
        'transition': [2, 7],
        'earlyOffense': [5, 11],
        'halfCourt': [10, 22],
      };
      final resolutions = <PhaseResolution, int>{};
      for (final record in records) {
        expect(brackets.keys, contains(record.kind));
        expect(
          record.plannedSeconds,
          inInclusiveRange(
            brackets[record.kind]![0],
            brackets[record.kind]![1],
          ),
        );
        expect(record.period, inInclusiveRange(1, result.periodsPlayed));
        expect(record.gameClockBefore, greaterThanOrEqualTo(0));
        expect(record.shotClockBefore, inInclusiveRange(0, 24));
        resolutions[record.resolution] =
            (resolutions[record.resolution] ?? 0) + 1;
        if (record.resolution == PhaseResolution.shotClockOvershoot) {
          expect(record.plannedSeconds, greaterThan(record.shotClockBefore));
          expect(record.shotClockBefore, lessThan(record.gameClockBefore));
        }
        if (record.resolution == PhaseResolution.shotClockExpiryNoAttempt) {
          expect(record.plannedSeconds, record.shotClockBefore);
        }
        if (record.resolution == PhaseResolution.simultaneousExpiry) {
          expect(record.gameClockBefore, record.shotClockBefore);
        }
      }
      expect(
        records.map((r) => r.sequence),
        List.generate(records.length, (i) => i + 1),
      );
      expect(resolutions[PhaseResolution.legalShot], greaterThan(0));
      expect(records.length, greaterThan(result.possessions));
    });

    test('one-second periods use the final-tick path with no A1 records', () {
      final rules = GameRules(
        periodSeconds: 1,
        overtimeSeconds: 1,
        shotClockSeconds: 1,
        offensiveReboundResetSeconds: 1,
        nonBonusFoulResetFloorSeconds: 1,
        maxOvertimes: 2,
      );
      final records = <PhaseTraceRecord>[];
      final result = GameSimulator(
        onPhaseTrace: records.add,
      ).simulate(buildInput(seed: 3, rules: rules));
      expect(result.events, isNotEmpty);
      expect(records, isEmpty, reason: 'final-tick actions are not A1 draws');
    });

    test('exact shot-clock expiry matches duration == shot clock', () {
      final exact = <PhaseTraceRecord>[];
      for (var seed = 1; seed <= 60 && exact.isEmpty; seed++) {
        final records = <PhaseTraceRecord>[];
        GameSimulator(
          onPhaseTrace: records.add,
        ).simulate(buildInput(seed: seed));
        exact.addAll(
          records.where(
            (record) =>
                record.resolution == PhaseResolution.shotClockExpiryNoAttempt,
          ),
        );
      }
      expect(exact, isNotEmpty, reason: 'expected at least one exact expiry');
      for (final record in exact) {
        expect(record.plannedSeconds, record.shotClockBefore);
      }
    });
  });
}
