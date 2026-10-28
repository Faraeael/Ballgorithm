import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final input = buildInput();
  final home = input.homeTeamId.value;
  final away = input.awayTeamId.value;
  final pg = playerAt(input, input.homeTeamId, Position.pg);
  final awayPg = playerAt(input, input.awayTeamId, Position.pg);
  final pg2 = input.homeLineup.players
      .firstWhere((p) => p.position == Position.sg)
      .id
      .value;

  final events = <GameEvent>[
    GameStarted(
      sequence: 1,
      period: 1,
      gameClock: 720,
      shotClock: null,
      homeTeamId: home,
      awayTeamId: away,
      startingTeamId: input.startingTeamId.value,
    ),
    PeriodStarted(
      sequence: 2,
      period: 1,
      gameClock: 720,
      shotClock: null,
      startingTeamId: input.startingTeamId.value,
    ),
    PossessionStarted(
      sequence: 3,
      period: 1,
      gameClock: 700,
      shotClock: 24,
      possessionId: 'p1',
      offenseTeamId: home,
    ),
    FieldGoalAttempt(
      sequence: 4,
      period: 1,
      gameClock: 690,
      shotClock: 14,
      teamId: home,
      shooterId: pg,
      shotValue: 2,
      made: true,
      andOne: false,
      assistedById: pg2,
    ),
    PersonalFoul(
      sequence: 5,
      period: 1,
      gameClock: 690,
      shotClock: 14,
      committingTeamId: away,
      committingPlayerId: awayPg,
      drawnByPlayerId: pg,
      kind: FoulKind.shooting,
      freeThrowsAwarded: 1,
      bonus: false,
    ),
    FreeThrowAttempt(
      sequence: 6,
      period: 1,
      gameClock: 690,
      shotClock: 14,
      teamId: home,
      shooterId: pg,
      groupId: 'g1',
      attemptIndex: 1,
      attemptsInGroup: 1,
      made: true,
      lastOfGroup: true,
    ),
    Rebound(
      sequence: 7,
      period: 1,
      gameClock: 690,
      shotClock: 24,
      teamId: away,
      playerId: awayPg,
      offensive: false,
      missedEventSequence: 4,
    ),
    DeadBallMiss(
      sequence: 8,
      period: 1,
      gameClock: 0,
      shotClock: 0,
      teamId: home,
      missedEventSequence: 4,
      reason: DeadBallReason.periodEnd,
    ),
    Turnover(
      sequence: 9,
      period: 1,
      gameClock: 0,
      shotClock: 0,
      teamId: home,
      playerId: pg,
      reason: TurnoverReason.shotClock,
    ),
    PossessionEnded(
      sequence: 10,
      period: 1,
      gameClock: 0,
      shotClock: 0,
      possessionId: 'p1',
      offenseTeamId: home,
      reason: PossessionEndReason.madeFinalFreeThrow,
    ),
    PeriodEnded(sequence: 11, period: 1, gameClock: 0, shotClock: null),
    GameEnded(
      sequence: 12,
      period: 1,
      gameClock: 0,
      shotClock: null,
      finalPeriod: 1,
    ),
  ];
  final ledger = buildLedger(input, events);

  test('canonical ledger round trips with stable JSON', () {
    final json = ledger.toJson();
    final decoded = GameEventLedger.fromJson(
      jsonDecode(jsonEncode(json)) as Map<String, Object?>,
    );
    expect(decoded.gameId, input.gameId);
    expect(decoded.inputFingerprint, GameFingerprint.of(input));
    expect(decoded.events, hasLength(events.length));
    expect(jsonEncode(decoded.toJson()), jsonEncode(json));
  });

  test('event payloads contain no floating-point values', () {
    final encoded = jsonEncode(
      ledger.toJson(),
    ).replaceAll(RegExp(r'"[^"]*"'), '""');
    expect(encoded, isNot(matches(RegExp(r'\d\.\d'))));
  });

  test('strict decoding rejects malformed ledgers and events', () {
    final json = ledger.toJson();
    Map<String, Object?> copy() =>
        jsonDecode(jsonEncode(json)) as Map<String, Object?>;

    final badVersion = copy()..['eventSchemaVersion'] = 99;
    expect(
      () => GameEventLedger.fromJson(badVersion),
      throwsA(
        isA<GameValidationException>().having(
          (e) => e.codes,
          'codes',
          contains(GameValidationCode.unsupportedEventSchemaVersion),
        ),
      ),
    );

    final badFingerprint = copy()..['inputFingerprint'] = 'nope';
    expect(
      () => GameEventLedger.fromJson(badFingerprint),
      throwsA(
        isA<GameValidationException>().having(
          (e) => e.codes,
          'codes',
          contains(GameValidationCode.invalidFingerprint),
        ),
      ),
    );

    final badType = copy();
    final list = badType['events']! as List<Object?>;
    (list.first as Map<String, Object?>)['type'] = 'Nope';
    expect(
      () => GameEventLedger.fromJson(badType),
      throwsA(
        isA<GameValidationException>().having(
          (e) => e.codes,
          'codes',
          contains(GameValidationCode.unsupportedEventType),
        ),
      ),
    );

    final badField = copy();
    final fieldList = badField['events']! as List<Object?>;
    (fieldList[3] as Map<String, Object?>)['shotValue'] = '2.0';
    expect(
      () => GameEventLedger.fromJson(badField),
      throwsA(
        isA<GameValidationException>().having(
          (e) => e.codes,
          'codes',
          contains(GameValidationCode.malformedEventJson),
        ),
      ),
    );

    final missing = copy();
    final missingList = missing['events']! as List<Object?>;
    (missingList[0] as Map<String, Object?>).remove('homeTeamId');
    expect(
      () => GameEventLedger.fromJson(missing),
      throwsA(
        isA<GameValidationException>().having(
          (e) => e.codes,
          'codes',
          contains(GameValidationCode.malformedEventJson),
        ),
      ),
    );
  });

  test('each event type decodes to the same runtime type', () {
    final json = ledger.toJson();
    final list = json['events']! as List<Object?>;
    for (var i = 0; i < list.length; i++) {
      final decoded = GameEvent.fromJson(
        (list[i] as Map<String, Object?>),
        path: 'events[$i]',
      );
      expect(decoded.runtimeType, events[i].runtimeType);
      expect(decoded.sequence, i + 1);
    }
  });
}
