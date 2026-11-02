import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';
import 't012_canonical_ledger_fixture_v4.dart';
import 't012_canonical_ledger_fixture_v5.dart';

void main() {
  group('Substitution event contract', () {
    final event = Substitution(
      sequence: 7,
      period: 2,
      gameClock: 431,
      shotClock: 12,
      teamId: 'team-1',
      playerOutId: 'player-1-2',
      playerInId: 'player-1-9',
      reason: SubstitutionReason.foulOut,
    );

    test('round-trips canonical JSON', () {
      final json = event.toJson();
      expect(json['type'], 'Substitution');
      expect(json['reason'], 'foulOut');
      final decoded = GameEvent.fromJson(json);
      expect(decoded, isA<Substitution>());
      final copy = decoded as Substitution;
      expect(copy.teamId, event.teamId);
      expect(copy.playerOutId, event.playerOutId);
      expect(copy.playerInId, event.playerInId);
      expect(copy.reason, SubstitutionReason.foulOut);
      expect(copy.toJson(), json);
    });

    test('accepts the tactical reason', () {
      final tactical = SubstitutionReason.parse('tactical', 'reason');
      expect(tactical, SubstitutionReason.tactical);
    });

    test('rejects an unknown reason with a typed error', () {
      final json = event.toJson()..['reason'] = 'injury';
      expect(
        () => GameEvent.fromJson(json),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.unsupportedEventType),
          ),
        ),
      );
    });

    test('rejects a missing player id', () {
      final json = event.toJson()..remove('playerInId');
      expect(
        () => GameEvent.fromJson(json),
        throwsA(isA<GameValidationException>()),
      );
    });

    test('reducer rejects Substitution explicitly until T04', () {
      final input = buildInput();
      final ledger = GameEventLedger(
        gameId: input.gameId,
        inputFingerprint: GameFingerprint.of(input),
        events: [
          GameStarted(
            sequence: 1,
            period: 1,
            gameClock: input.rules.periodSeconds,
            shotClock: null,
            homeTeamId: input.homeTeamId.value,
            awayTeamId: input.awayTeamId.value,
            startingTeamId: input.startingTeamId.value,
          ),
          PeriodStarted(
            sequence: 2,
            period: 1,
            gameClock: input.rules.periodSeconds,
            shotClock: null,
            startingTeamId: input.startingTeamId.value,
          ),
          Substitution(
            sequence: 3,
            period: 1,
            gameClock: input.rules.periodSeconds,
            shotClock: null,
            teamId: input.homeTeamId.value,
            playerOutId: event.playerOutId,
            playerInId: event.playerInId,
            reason: SubstitutionReason.foulOut,
          ),
        ],
      );
      expect(
        () => GameEventReducer.validate(input, ledger),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.toString(),
            'message',
            contains('not accepted until T04'),
          ),
        ),
      );
    });
  });

  group('v5 versions and rules', () {
    test('version identifiers are the frozen T03 values', () {
      expect(gameSimulationVersion, 5);
      expect(gameRulesVersion, 3);
      expect(gameEventSchemaVersion, 3);
      expect(gameFingerprintVersion, 3);
      expect(gameActionDurationModelVersion, 2);
      expect(GameRules.standard.foulOutLimit, 6);
      expect(GameRules.standard.substitutionPolicyVersion, 1);
    });

    test('rules serialize and validate the new fields', () {
      final json = GameRules.standard.toJson();
      expect(json['foulOutLimit'], 6);
      expect(json['substitutionPolicyVersion'], 1);
      GameRules(foulOutLimit: 6).validate();
      for (final value in [0, 5, 7]) {
        expect(
          () => GameRules(foulOutLimit: value).validate(),
          throwsA(isA<GameValidationException>()),
          reason: 'foulOutLimit $value must be rejected',
        );
      }
      expect(
        () => GameRules(substitutionPolicyVersion: 2).validate(),
        throwsA(isA<GameValidationException>()),
      );
    });

    test('a v4 ledger header is rejected by the v5 reader', () {
      final input = buildInput();
      final json = GameEventLedger(
        gameId: input.gameId,
        inputFingerprint: GameFingerprint.of(input),
        events: const [],
      ).toJson();
      json['eventSchemaVersion'] = 2;
      expect(
        () => GameEventLedger.fromJson(json),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.unsupportedEventSchemaVersion),
          ),
        ),
      );
    });
  });

  test('fingerprint uses ordered slot/player-id pairs', () {
    final input = buildInput();
    final payload = GameFingerprint.canonicalPayload(input);
    for (final key in ['homeLineup', 'awayLineup']) {
      final pairs = payload[key]! as List<Object?>;
      expect(pairs, hasLength(5));
      for (var i = 0; i < 5; i++) {
        final pair = pairs[i]! as Map<String, Object?>;
        expect(pair.keys.toSet(), {'slot', 'playerId'});
        expect(pair['slot'], Position.values[i].shortName);
      }
    }
  });

  test('v5 event array matches the pinned v4 baseline exactly', () {
    Map<String, Object?> headerOf(String json) =>
        jsonDecode(json) as Map<String, Object?>;
    final v4 = headerOf(t012CanonicalLedgerV4Json);
    final v5 = headerOf(t012CanonicalLedgerV5Json);
    expect(v5['events'], v4['events']);
    expect(v5['gameId'], v4['gameId']);
    expect(v5['eventSchemaVersion'], isNot(v4['eventSchemaVersion']));
    expect(v5['inputFingerprint'], isNot(v4['inputFingerprint']));
  });

  test('simulator emits no Substitution yet', () {
    final result = GameSimulator().simulate(buildInput(seed: 7));
    expect(result.events.whereType<Substitution>(), isEmpty);
    expect(result.simulationVersion, 5);
    expect(result.eventSchemaVersion, 3);
  });
}
