import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

Matcher throwsCode(GameValidationCode code) => throwsA(
  isA<GameValidationException>().having(
    (e) => e.codes,
    'codes',
    contains(code),
  ),
);

const standardSeeds = <int>[
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  27,
  28,
  29,
  30,
  31,
  32,
  33,
  34,
  35,
  42,
  99,
  100,
  20261029,
];

GameRules tinyRules({int maxOvertimes = 10}) => GameRules(
  periodSeconds: 1,
  overtimeSeconds: 1,
  shotClockSeconds: 1,
  offensiveReboundResetSeconds: 1,
  nonBonusFoulResetFloorSeconds: 1,
  maxOvertimes: maxOvertimes,
);

String digest(GameResult result) =>
    sha256.convert(utf8.encode(jsonEncode(result.ledger.toJson()))).toString();

int maxZeroTimeRun(GameResult result) {
  var best = 1;
  var run = 1;
  var clock = result.events.first.gameClock;
  var period = result.events.first.period;
  for (final event in result.events.skip(1)) {
    if (event.period == period && event.gameClock == clock) {
      run++;
    } else {
      run = 1;
      clock = event.gameClock;
      period = event.period;
    }
    if (run > best) best = run;
  }
  return best;
}

/// Independent ledger and accounting audit for one completed game.
void auditGame(GameInput input, GameResult result) {
  final events = result.events;
  final validated = GameEventReducer.validate(input, result.ledger);
  expect(validated.state.ended, isTrue);
  expect(events.first, isA<GameStarted>());
  expect(events.last, isA<GameEnded>());
  expect(events.whereType<GameStarted>().length, 1);
  expect(events.whereType<GameEnded>().length, 1);
  expect(
    events.whereType<GameEnded>().single.finalPeriod,
    result.periodsPlayed,
  );

  var activePeriod = 0;
  for (var i = 0; i < events.length; i++) {
    expect(events[i].sequence, i + 1);
    if (i > 0) {
      expect(events[i].period, greaterThanOrEqualTo(events[i - 1].period));
    }
    if (events[i] is PeriodStarted) {
      activePeriod = events[i].period;
    } else if (events[i] is! GameStarted) {
      expect(events[i].period, activePeriod);
    }
  }
  final lastPeriodEnd = events.lastIndexWhere((event) => event is PeriodEnded);
  for (var i = lastPeriodEnd + 1; i < events.length; i++) {
    expect(events[i], isNot(isA<PossessionStarted>()));
  }

  final periods = events.whereType<PeriodStarted>().toList();
  expect(
    periods.map((p) => p.period),
    List.generate(result.periodsPlayed, (i) => i + 1),
  );
  for (final period in periods) {
    final expectedLength = period.period > input.rules.periods
        ? input.rules.overtimeSeconds
        : input.rules.periodSeconds;
    expect(period.gameClock, expectedLength);
    expect(period.shotClock, isNull);
    final starter = period.period.isOdd
        ? input.startingTeamId
        : input.opponentOf(input.startingTeamId);
    expect(period.startingTeamId, starter.value);
  }
  final ended = events.whereType<PeriodEnded>().toList();
  expect(
    ended.map((p) => p.period),
    List.generate(result.periodsPlayed, (i) => i + 1),
  );
  for (final period in ended) {
    expect(period.gameClock, 0);
  }

  String? openPossession;
  String? openOffense;
  var openPossessionPeriod = 0;
  for (var i = 0; i < events.length; i++) {
    final event = events[i];
    if (event is PossessionStarted) {
      expect(openPossession, isNull, reason: 'nested possession');
      expect(event.gameClock, greaterThan(0));
      expect(event.shotClock, input.rules.shotClockSeconds);
      openPossession = event.possessionId;
      openOffense = event.offenseTeamId;
      openPossessionPeriod = event.period;
    } else if (event is PossessionEnded) {
      expect(event.possessionId, openPossession);
      expect(event.offenseTeamId, openOffense);
      expect(event.period, openPossessionPeriod);
      openPossession = null;
      openOffense = null;
    } else if (event is PeriodStarted) {
      expect(openPossession, isNull);
    } else if (event is GameEnded) {
      expect(openPossession, isNull);
    }
    if (event is GameEnded) {
      expect(i, events.length - 1);
    }
  }
  expect(openPossession, isNull);

  int? clock;
  for (final event in events) {
    if (event is PeriodStarted) {
      clock = event.gameClock;
      continue;
    }
    if (clock != null && event.gameClock > clock) {
      fail('game clock increased at sequence ${event.sequence}');
    }
    expect(event.gameClock, greaterThanOrEqualTo(0));
    if (event.shotClock != null) {
      expect(
        event.shotClock,
        inInclusiveRange(0, input.rules.shotClockSeconds),
      );
    }
  }

  expect(result.homeScore, isNot(result.awayScore));
  expect(result.winnerTeamId, isNot(result.loserTeamId));
  final homeBox = result.boxScore.teams[input.homeTeamId.value]!;
  final awayBox = result.boxScore.teams[input.awayTeamId.value]!;
  expect(homeBox.points, result.homeScore);
  expect(awayBox.points, result.awayScore);
  expect(
    result.homePeriodScores.values.fold(0, (a, b) => a + b),
    result.homeScore,
  );
  expect(
    result.awayPeriodScores.values.fold(0, (a, b) => a + b),
    result.awayScore,
  );

  for (final team in [input.homeTeamId, input.awayTeamId]) {
    final box = result.boxScore.teams[team.value]!;
    expect(box.fgm, box.twoPm + box.threePm);
    expect(box.fga, box.twoPa + box.threePa);
    expect(box.points, 2 * box.twoPm + 3 * box.threePm + box.ftm);
    expect(box.rebounds, box.oreb + box.dreb);
    expect(box.ftm, lessThanOrEqualTo(box.fta));
    expect(box.fgm, lessThanOrEqualTo(box.fga));
    var playerPoints = 0;
    var playerTurnovers = 0;
    var playerFouls = 0;
    for (final player in input.lineupFor(team).players) {
      final stats = result.boxScore.players[player.id.value]!;
      expect(stats.teamId, team.value);
      playerPoints += stats.points;
      playerTurnovers += stats.turnovers;
      playerFouls += stats.personalFouls;
    }
    expect(playerPoints, box.points);
    expect(playerTurnovers, box.turnovers);
    expect(playerFouls, box.personalFouls);
  }

  // Overtime begins only after a tied period.
  var homePoints = 0;
  var awayPoints = 0;
  for (var period = 1; period < result.periodsPlayed; period++) {
    for (final event in events) {
      if (event.period != period) continue;
      if (event is FieldGoalAttempt && event.made) {
        if (event.teamId == input.homeTeamId.value) {
          homePoints += event.shotValue;
        }
        if (event.teamId == input.awayTeamId.value) {
          awayPoints += event.shotValue;
        }
      }
      if (event is FreeThrowAttempt && event.made) {
        if (event.teamId == input.homeTeamId.value) {
          homePoints++;
        }
        if (event.teamId == input.awayTeamId.value) {
          awayPoints++;
        }
      }
    }
    if (period >= input.rules.periods) {
      expect(homePoints, awayPoints, reason: 'overtime after non-tied period');
    }
  }
}

void main() {
  group('complete-game lifecycle', () {
    test('40 standard seeds finish, replay and reconcile', () {
      var games = 0;
      for (final seed in standardSeeds) {
        final input = buildInput(seed: seed);
        final result = GameSimulator().simulate(input);
        auditGame(input, result);
        expect(result.periodsPlayed, greaterThanOrEqualTo(4));
        expect(result.homeScore + result.awayScore, greaterThan(0));
        games++;
      }
      expect(games, standardSeeds.length);
    });

    test('required published seeds keep their canonical digests', () {
      const expected = {
        1: '839d7e50f1664a49cdae0d37e0d464e061d926414250a96968c673b4fd317d92',
        42: 'dc8c06cedd10d3cff938e023e11e520c09a667ac12edc2b2469953eea0371fab',
        99: '238c78a8b36d02ba750b28c6e23d74ecd782486b38d8ff01e66da9cb03ea9438',
        20261029:
            'aabf12782a45d6b1efdfe7d17b62961919012437b94fc712ccf4eac27baf3219',
      };
      for (final entry in expected.entries) {
        final input = buildInput(seed: entry.key);
        final result = GameSimulator().simulate(input);
        expect(digest(result), entry.value, reason: 'seed ${entry.key}');
        auditGame(input, result);
      }
    });
  });

  group('determinism and reentrancy', () {
    test('identical input reproduces the exact ledger and result', () {
      final input = buildInput(seed: 7);
      final first = GameSimulator().simulate(input);
      final firstJson = jsonEncode(first.ledger.toJson());
      for (var run = 0; run < 5; run++) {
        final next = GameSimulator().simulate(input);
        expect(jsonEncode(next.ledger.toJson()), firstJson);
        expect(next.homeScore, first.homeScore);
        expect(next.awayScore, first.awayScore);
        expect(
          jsonEncode(next.boxScore.players.keys.toList()),
          jsonEncode(first.boxScore.players.keys.toList()),
        );
        expect(next.winnerTeamId, first.winnerTeamId);
      }
    });

    test('one simulator is reusable and interleaving does not leak state', () {
      final simulator = GameSimulator();
      final a1 = buildInput(seed: 11);
      final b1 = buildInput(seed: 12);
      final firstA = jsonEncode(simulator.simulate(a1).ledger.toJson());
      final firstB = jsonEncode(simulator.simulate(b1).ledger.toJson());
      final secondA = jsonEncode(simulator.simulate(a1).ledger.toJson());
      expect(secondA, firstA);

      final interleaved = GameSimulator();
      final againA = jsonEncode(interleaved.simulate(a1).ledger.toJson());
      final againB = jsonEncode(interleaved.simulate(b1).ledger.toJson());
      expect(againA, firstA);
      expect(againB, firstB);
    });

    test('different seeds produce different ledgers', () {
      final first = GameSimulator().simulate(buildInput(seed: 21));
      final second = GameSimulator().simulate(buildInput(seed: 22));
      expect(
        jsonEncode(first.ledger.toJson()),
        isNot(jsonEncode(second.ledger.toJson())),
      );
    });

    test('simulation does not mutate the input league, lineups or rules', () {
      final input = buildInput(seed: 5);
      final leagueBefore = jsonEncode(input.league.toJson());
      final homeIds = List<String>.of(input.homeLineup.playerIds);
      final awayIds = List<String>.of(input.awayLineup.playerIds);
      final rulesBefore = jsonEncode(input.rules.toJson());
      GameSimulator().simulate(input);
      expect(jsonEncode(input.league.toJson()), leagueBefore);
      expect(input.homeLineup.playerIds, homeIds);
      expect(input.awayLineup.playerIds, awayIds);
      expect(jsonEncode(input.rules.toJson()), rulesBefore);
    });

    test('sequential games with different A1 configurations stay isolated', () {
      final simulator = GameSimulator();
      final custom = GameRules(
        periodSeconds: 30,
        overtimeSeconds: 15,
        phaseWeights: const [5000, 2500, 2500],
        phaseDurations: const [
          [2, 2],
          [3, 3],
          [4, 4],
        ],
      );
      final inputs = [
        buildInput(seed: 13),
        buildInput(seed: 14, rules: custom),
        buildInput(seed: 13),
      ];
      final ledgers = <String>[];
      for (final input in inputs) {
        ledgers.add(jsonEncode(simulator.simulate(input).ledger.toJson()));
      }
      expect(ledgers[2], ledgers[0]);
      expect(ledgers[1], isNot(ledgers[0]));
      expect(
        ledgers[1],
        jsonEncode(GameSimulator().simulate(inputs[1]).ledger.toJson()),
      );
    });

    test('matching injected model is deterministic; mismatch is rejected', () {
      final custom = GameRules(
        periodSeconds: 30,
        overtimeSeconds: 15,
        phaseWeights: const [5000, 2500, 2500],
        phaseDurations: const [
          [2, 2],
          [3, 3],
          [4, 4],
        ],
      );
      final input = buildInput(seed: 15, rules: custom);
      final a = GameSimulator(
        probabilityModel: BasketballProbabilityModel(rules: custom),
      ).simulate(input);
      final b = GameSimulator().simulate(input);
      expect(jsonEncode(a.ledger.toJson()), jsonEncode(b.ledger.toJson()));

      expect(
        () => GameSimulator(
          probabilityModel: BasketballProbabilityModel(),
        ).simulate(input),
        throwsCode(GameValidationCode.invalidRules),
      );
    });
  });

  group('overtime termination', () {
    test('a game at the configured overtime limit is accepted', () {
      final input = buildInput(seed: 26, rules: tinyRules(maxOvertimes: 2));
      final result = GameSimulator().simulate(input);
      expect(result.overtimes, 2);
      expect(result.periodsPlayed, 6);
      expect(result.homeScore, isNot(result.awayScore));
      auditGame(input, result);
      final periods = result.events.whereType<PeriodStarted>().where(
        (p) => p.period > 4,
      );
      for (final period in periods) {
        expect(period.gameClock, 1);
        final expected = period.period.isOdd
            ? input.startingTeamId
            : input.opponentOf(input.startingTeamId);
        expect(period.startingTeamId, expected.value);
      }
    });

    test('a tie beyond the overtime limit fails without a winner', () {
      expect(
        () => GameSimulator().simulate(
          buildInput(seed: 26, rules: tinyRules(maxOvertimes: 1)),
        ),
        throwsCode(GameValidationCode.overtimeLimitExceeded),
      );
      expect(
        () => GameSimulator().simulate(
          buildInput(seed: 1, rules: tinyRules(maxOvertimes: 2)),
        ),
        throwsCode(GameValidationCode.overtimeLimitExceeded),
      );
      expect(
        () => GameSimulator().simulate(
          buildInput(seed: 1, rules: tinyRules(maxOvertimes: 0)),
        ),
        throwsCode(GameValidationCode.overtimeLimitExceeded),
      );
    });
  });

  group('execution bounds', () {
    test('exact event limit succeeds and one fewer fails', () {
      final baseline = GameSimulator().simulate(buildInput(seed: 42));
      final count = baseline.events.length;
      final exact = GameSimulator().simulate(
        buildInput(seed: 42, rules: GameRules(maxEvents: count)),
      );
      expect(exact.events.length, count);
      expect(
        jsonEncode([for (final e in exact.events) e.toJson()]),
        jsonEncode([for (final e in baseline.events) e.toJson()]),
      );

      expect(
        () => GameSimulator().simulate(
          buildInput(seed: 42, rules: GameRules(maxEvents: count - 1)),
        ),
        throwsCode(GameValidationCode.eventLimitExceeded),
      );
    });

    test('exact zero-time limit succeeds and one fewer fails', () {
      final baseline = GameSimulator().simulate(buildInput(seed: 42));
      final limit = maxZeroTimeRun(baseline);
      expect(limit, greaterThan(1));
      final exact = GameSimulator().simulate(
        buildInput(seed: 42, rules: GameRules(maxZeroTimeEvents: limit)),
      );
      expect(
        jsonEncode([for (final e in exact.events) e.toJson()]),
        jsonEncode([for (final e in baseline.events) e.toJson()]),
      );
      expect(
        () => GameSimulator().simulate(
          buildInput(seed: 42, rules: GameRules(maxZeroTimeEvents: limit - 1)),
        ),
        throwsCode(GameValidationCode.zeroTimeEventLimitExceeded),
      );
    });

    test('tiny event and zero-time limits fail with typed errors', () {
      expect(
        () => GameSimulator().simulate(
          buildInput(seed: 1, rules: GameRules(maxEvents: 5)),
        ),
        throwsCode(GameValidationCode.eventLimitExceeded),
      );
      expect(
        () => GameSimulator().simulate(
          buildInput(seed: 1, rules: GameRules(maxZeroTimeEvents: 1)),
        ),
        throwsCode(GameValidationCode.zeroTimeEventLimitExceeded),
      );
    });
  });

  group('adversarial configurations', () {
    test('configured stress matrix classifies every outcome', () {
      final configs = <GameRules>[
        GameRules(
          periodSeconds: 1,
          overtimeSeconds: 1,
          shotClockSeconds: 1,
          offensiveReboundResetSeconds: 1,
          nonBonusFoulResetFloorSeconds: 1,
          maxOvertimes: 2,
        ),
        GameRules(
          periodSeconds: 2,
          overtimeSeconds: 2,
          shotClockSeconds: 2,
          offensiveReboundResetSeconds: 1,
          nonBonusFoulResetFloorSeconds: 1,
          maxOvertimes: 2,
        ),
        GameRules(
          periodSeconds: 5,
          overtimeSeconds: 5,
          shotClockSeconds: 2,
          offensiveReboundResetSeconds: 2,
          nonBonusFoulResetFloorSeconds: 1,
          maxOvertimes: 2,
        ),
        GameRules(
          periodSeconds: 24,
          overtimeSeconds: 12,
          shotClockSeconds: 5,
          offensiveReboundResetSeconds: 3,
          nonBonusFoulResetFloorSeconds: 2,
          maxOvertimes: 2,
        ),
        GameRules(
          periodSeconds: 60,
          overtimeSeconds: 30,
          shotClockSeconds: 24,
          offensiveReboundResetSeconds: 14,
          nonBonusFoulResetFloorSeconds: 14,
          maxOvertimes: 2,
          bonusRegulationFouls: 1,
          bonusOvertimeFouls: 1,
        ),
        GameRules(
          periodSeconds: 30,
          overtimeSeconds: 15,
          phaseWeights: const [2500, 2500, 5000],
          phaseDurations: const [
            [2, 3],
            [4, 6],
            [7, 10],
          ],
          maxOvertimes: 2,
        ),
      ];
      final seeds = [1, 2, 3];
      var successes = 0;
      var expectedFailures = 0;
      for (final rules in configs) {
        for (final seed in seeds) {
          try {
            final input = buildInput(seed: seed, rules: rules);
            final result = GameSimulator().simulate(input);
            auditGame(input, result);
            successes++;
          } on GameValidationException catch (error) {
            if (error.codes.every(
              (c) => c == GameValidationCode.overtimeLimitExceeded,
            )) {
              expectedFailures++;
              continue;
            }
            fail(
              'unexpected ${error.codes} for rules=${jsonEncode(rules.toJson())} seed=$seed',
            );
          }
        }
      }
      expect(successes, greaterThan(0));
      expect(expectedFailures, greaterThan(0));
      expect(successes + expectedFailures, configs.length * seeds.length);
    });
  });
}
