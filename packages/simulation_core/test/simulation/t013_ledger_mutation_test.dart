import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

Matcher throwsCode(GameValidationCode code) => throwsA(
  isA<GameValidationException>().having(
    (error) => error.codes,
    'codes',
    contains(code),
  ),
);

void main() {
  final input = buildInput();
  final offense = input.startingTeamId;
  final defense = input.opponentOf(offense);
  final offensePg = playerAt(input, offense, Position.pg);
  final defensePg = playerAt(input, defense, Position.pg);

  GameScript start() => GameScript(input)
    ..startGame()
    ..startPeriod(1, offense);

  /// Shot miss plus defensive rebound and the next possession.
  GameScript missScript() => start()
    ..startPossession('p1', offense, clock: 700, shotClock: 24)
    ..fga(
      team: offense,
      shooter: offensePg,
      made: false,
      clock: 690,
      shotClock: 14,
    )
    ..rebound(
      team: defense,
      player: defensePg,
      offensive: false,
      missedEventSequence: 4,
      clock: 690,
      shotClock: 24,
    )
    ..endPossession(
      possessionId: 'p1',
      team: offense,
      reason: PossessionEndReason.defensiveRebound,
      clock: 690,
      shotClock: 24,
    )
    ..startPossession('p2', defense, clock: 690, shotClock: 24);

  /// Steal turnover followed by the possession end.
  GameScript stealScript() => start()
    ..startPossession('p1', offense, clock: 700, shotClock: 24)
    ..turnover(
      team: offense,
      player: offensePg,
      reason: TurnoverReason.steal,
      stolenBy: defensePg,
      clock: 690,
      shotClock: 14,
    )
    ..endPossession(
      possessionId: 'p1',
      team: offense,
      reason: PossessionEndReason.turnover,
      clock: 690,
      shotClock: 14,
    );

  /// Zero-clock miss resolved as a dead ball.
  GameScript deadBallScript() => start()
    ..startPossession('p1', offense, clock: 24, shotClock: 24)
    ..fga(
      team: offense,
      shooter: offensePg,
      made: false,
      clock: 0,
      shotClock: 0,
    )
    ..deadBall(team: offense, missedEventSequence: 4, clock: 0, shotClock: 0)
    ..endPossession(
      possessionId: 'p1',
      team: offense,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 0,
    );

  /// Two awarded free throws, both made.
  GameScript freeThrowScript() => start()
    ..startPossession('p1', offense, clock: 20, shotClock: 24)
    ..foul(
      team: defense,
      player: defensePg,
      kind: FoulKind.shooting,
      freeThrows: 2,
      drawnBy: offensePg,
      clock: 10,
      shotClock: 14,
    )
    ..ft(
      team: offense,
      shooter: offensePg,
      groupId: 'g',
      index: 1,
      total: 2,
      made: true,
      clock: 10,
      shotClock: 14,
    )
    ..ft(
      team: offense,
      shooter: offensePg,
      groupId: 'g',
      index: 2,
      total: 2,
      made: true,
      clock: 10,
      shotClock: 14,
    );

  Map<String, Object?> copyOf(GameScript script) =>
      jsonDecode(jsonEncode(script.ledger().toJson())) as Map<String, Object?>;

  /// Applies one controlled JSON defect and expects a typed rejection.
  void expectRejected(
    GameScript script,
    void Function(List<Object?> events) mutate,
    GameValidationCode code, {
    String? reason,
  }) {
    final json = copyOf(script);
    final events = json['events']! as List<Object?>;
    mutate(events);
    final ledger = GameEventLedger.fromJson(json);
    expect(
      () => GameEventReducer.validate(input, ledger),
      throwsCode(code),
      reason: reason,
    );
  }

  void renumber(List<Object?> events) {
    for (var i = 0; i < events.length; i++) {
      (events[i]! as Map<String, Object?>)['sequence'] = i + 1;
    }
  }

  Map<String, Object?> at(List<Object?> events, int index) =>
      events[index]! as Map<String, Object?>;

  group('A. sequence corruption', () {
    test('duplicate sequence is rejected', () {
      expectRejected(missScript(), (events) {
        at(events, 2)['sequence'] = at(events, 1)['sequence'];
      }, GameValidationCode.invalidEventSequence);
    });

    test('skipped sequence is rejected', () {
      expectRejected(missScript(), (events) {
        at(events, 2)['sequence'] = 9;
      }, GameValidationCode.invalidEventSequence);
    });

    test('out-of-order events are rejected', () {
      expectRejected(missScript(), (events) {
        final second = at(events, 1);
        events[1] = at(events, 2);
        events[2] = second;
      }, GameValidationCode.invalidEventSequence);
    });
  });

  group('B. lifecycle corruption', () {
    test('an event before GameStarted is rejected', () {
      expectRejected(missScript(), (events) {
        events.removeAt(0);
        renumber(events);
      }, GameValidationCode.eventBeforeGameStarted);
    });

    test('a second GameStarted is rejected', () {
      expectRejected(missScript(), (events) {
        final copy = Map<String, Object?>.of(at(events, 0));
        copy['sequence'] = events.length + 1;
        copy['gameClock'] = at(events, events.length - 1)['gameClock'];
        events.add(copy);
      }, GameValidationCode.duplicateGameStarted);
    });

    test('a period end with an open possession is rejected', () {
      expectRejected(missScript(), (events) {
        events.removeRange(events.length - 2, events.length);
        events.add(<String, Object?>{
          'sequence': events.length + 1,
          'type': 'PeriodEnded',
          'period': 1,
          'gameClock': 0,
          'shotClock': null,
        });
      }, GameValidationCode.periodEndInvalid);
    });
  });

  group('C. clock corruption', () {
    test('an increasing game clock is rejected', () {
      expectRejected(missScript(), (events) {
        at(events, 4)['gameClock'] = 720;
      }, GameValidationCode.gameClockIncreased);
    });

    test('a shot clock above the configured maximum is rejected', () {
      expectRejected(missScript(), (events) {
        at(events, 2)['shotClock'] = 25;
      }, GameValidationCode.invalidShotClock);
    });

    test('a rebound resolved at a different clock is rejected', () {
      expectRejected(missScript(), (events) {
        at(events, 4)['gameClock'] = 689;
      }, GameValidationCode.deadBallClockAdvanced);
    });
  });

  group('D. possession corruption', () {
    test('a field goal by the defense is rejected', () {
      expectRejected(missScript(), (events) {
        at(events, 3)['teamId'] = defense.value;
      }, GameValidationCode.wrongTeam);
    });

    test('a live action without an open possession is rejected', () {
      expectRejected(missScript(), (events) {
        events.removeAt(2);
        renumber(events);
      }, GameValidationCode.noOpenPossession);
    });
  });

  group('E. foul and free-throw corruption', () {
    test('a duplicated free-throw index is rejected', () {
      expectRejected(freeThrowScript(), (events) {
        at(events, 5)['attemptIndex'] = 1;
      }, GameValidationCode.freeThrowSequenceInvalid);
    });

    test('a free throw by the defending team is rejected', () {
      expectRejected(freeThrowScript(), (events) {
        at(events, 5)['teamId'] = defense.value;
      }, GameValidationCode.freeThrowSequenceInvalid);
    });

    test('an orphan free throw without an award is rejected', () {
      expectRejected(freeThrowScript(), (events) {
        events.removeAt(3);
        renumber(events);
      }, GameValidationCode.freeThrowSequenceInvalid);
    });

    test('a non-bonus foul awarding free throws is rejected', () {
      expectRejected(freeThrowScript(), (events) {
        at(events, 3)['kind'] = 'nonShooting';
        at(events, 3)['freeThrowsAwarded'] = 2;
        at(events, 3)['bonus'] = false;
      }, GameValidationCode.freeThrowsInvalid);
    });
  });

  group('F. rebound corruption', () {
    test('a second rebound of one miss is rejected', () {
      expectRejected(missScript(), (events) {
        final rebound = Map<String, Object?>.of(at(events, 4));
        events.insert(5, rebound);
        renumber(events);
      }, GameValidationCode.reboundDuplicate);
    });

    test('a rebound of an unknown miss is rejected', () {
      expectRejected(missScript(), (events) {
        at(events, 4)['missedEventSequence'] = 99;
      }, GameValidationCode.reboundInvalid);
    });

    test('an offensive-team defensive rebound is rejected', () {
      expectRejected(missScript(), (events) {
        at(events, 4)['teamId'] = offense.value;
        at(events, 4)['playerId'] = offensePg;
      }, GameValidationCode.reboundWrongTeam);
    });

    test('a rebound after a made shot is rejected', () {
      expectRejected(missScript(), (events) {
        at(events, 3)['made'] = true;
      }, GameValidationCode.reboundInvalid);
    });

    test('a rebound after a zero-clock dead ball is rejected', () {
      expectRejected(deadBallScript(), (events) {
        final rebound = <String, Object?>{
          'sequence': 6,
          'type': 'Rebound',
          'period': 1,
          'gameClock': 0,
          'shotClock': 0,
          'teamId': defense.value,
          'playerId': defensePg,
          'offensive': false,
          'missedEventSequence': 4,
        };
        events.insert(5, rebound);
        renumber(events);
      }, GameValidationCode.reboundDuplicate);
    });
  });

  group('G. turnover corruption', () {
    test('a non-steal turnover carrying a stealer is rejected', () {
      expectRejected(stealScript(), (events) {
        at(events, 3)['reason'] = 'nonSteal';
      }, GameValidationCode.turnoverInvalid);
    });

    test('a steal without a stealer is rejected', () {
      expectRejected(stealScript(), (events) {
        at(events, 3)['stolenById'] = null;
      }, GameValidationCode.stealInvalid);
    });

    test('a turnover charged to the defense is rejected', () {
      expectRejected(stealScript(), (events) {
        at(events, 3)['teamId'] = defense.value;
      }, GameValidationCode.wrongTeam);
    });

    test('an offensive-foul turnover without a foul is rejected', () {
      expectRejected(stealScript(), (events) {
        at(events, 3)['reason'] = 'offensiveFoul';
        at(events, 3)['stolenById'] = null;
        at(events, 3)['shotClock'] = 14;
      }, GameValidationCode.turnoverInvalid);
    });
  });
}
