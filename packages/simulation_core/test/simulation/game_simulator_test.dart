import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

GameRules customA1A() => GameRules(
  periodSeconds: 30,
  overtimeSeconds: 15,
  phaseWeights: const [5000, 2500, 2500],
  phaseDurations: const [
    [2, 2],
    [3, 3],
    [4, 4],
  ],
  orebPhaseDurations: const [
    [2, 2],
    [3, 3],
    [4, 4],
  ],
  retainedFoulPhaseDurations: const [
    [2, 2],
    [3, 3],
    [4, 4],
  ],
);

GameRules customA1B() => GameRules(
  periodSeconds: 30,
  overtimeSeconds: 15,
  phaseWeights: const [2500, 2500, 5000],
  phaseDurations: const [
    [2, 3],
    [4, 6],
    [7, 10],
  ],
  orebPhaseDurations: const [
    [2, 3],
    [4, 6],
    [7, 10],
  ],
  retainedFoulPhaseDurations: const [
    [2, 3],
    [4, 6],
    [7, 10],
  ],
);

/// A1 phase durations inferred from terminal-attempt clock deltas. The explicit
/// `gameClock == 1` final-tick path produces a delta of one and is excluded.
List<int> sampledA1Durations(GameResult result) {
  final durations = <int>[];
  for (var i = 1; i < result.events.length; i++) {
    final event = result.events[i];
    if (event is! FieldGoalAttempt) continue;
    final delta = result.events[i - 1].gameClock - event.gameClock;
    if (delta <= 1) continue;
    durations.add(delta);
  }
  return durations;
}

String ledgerDigest(GameResult result) =>
    sha256.convert(utf8.encode(jsonEncode(result.ledger.toJson()))).toString();

GameRules tinyRules({
  int maxOvertimes = 10,
  int maxEvents = 50000,
  int maxZeroTimeEvents = 64,
}) => GameRules(
  periodSeconds: 1,
  overtimeSeconds: 1,
  shotClockSeconds: 1,
  offensiveReboundResetSeconds: 1,
  nonBonusFoulResetFloorSeconds: 1,
  maxOvertimes: maxOvertimes,
  maxEvents: maxEvents,
  maxZeroTimeEvents: maxZeroTimeEvents,
);

GameResult simulateSeed(int seed, {GameRules? rules}) =>
    GameSimulator().simulate(buildInput(seed: seed, rules: rules));

Matcher throwsCode(GameValidationCode code) => throwsA(
  isA<GameValidationException>().having(
    (e) => e.codes,
    'codes',
    contains(code),
  ),
);

Iterable<PossessionStarted> possessionsOf(GameEventLedger ledger) =>
    ledger.events.whereType<PossessionStarted>();

String possessionIdAt(List<GameEvent> events, int index) {
  for (var i = index; i >= 0; i--) {
    final event = events[i];
    if (event is PossessionStarted) return event.possessionId;
  }
  throw StateError('no possession before event $index');
}

TeamId offenseAt(List<GameEvent> events, int index) {
  for (var i = index; i >= 0; i--) {
    final event = events[i];
    if (event is PossessionStarted) return TeamId(event.offenseTeamId);
  }
  throw StateError('no possession before event $index');
}

void main() {
  group('complete games', () {
    test('simulates a legal four-quarter game with two M001 teams', () {
      final input = buildInput(seed: 42);
      final result = GameSimulator().simulate(input);

      expect(result.periodsPlayed, 4);
      expect(result.overtimes, 0);
      expect(result.state.ended, isTrue);
      expect(result.state.hasOpenPossession, isFalse);
      expect(result.homeScore, isNot(result.awayScore));
      expect(result.winnerTeamId, isNot(result.loserTeamId));

      final periods = result.events.whereType<PeriodStarted>().toList();
      expect(periods.map((event) => event.period), [1, 2, 3, 4]);
      for (final event in periods) {
        expect(event.gameClock, GameRules.standard.periodSeconds);
        expect(event.shotClock, isNull);
      }
      final ended = result.events.whereType<PeriodEnded>().toList();
      expect(ended.map((event) => event.period), [1, 2, 3, 4]);
      for (final event in ended) {
        expect(event.gameClock, 0);
      }
      final gameEnded = result.events.whereType<GameEnded>().single;
      expect(gameEnded.finalPeriod, 4);
      expect(result.events.last, isA<GameEnded>());

      final home = result.boxScore.teams[input.homeTeamId.value]!;
      final away = result.boxScore.teams[input.awayTeamId.value]!;
      expect(home.points, greaterThan(0));
      expect(away.points, greaterThan(0));
      expect(home.points, result.homeScore);
      expect(away.points, result.awayScore);
      expect(
        result.homePeriodScores.values.fold(0, (a, b) => a + b),
        result.homeScore,
      );
      expect(
        result.awayPeriodScores.values.fold(0, (a, b) => a + b),
        result.awayScore,
      );
      expect(result.inputFingerprint, GameFingerprint.of(input));
      expect(result.eventSchemaVersion, 2);
      expect(result.simulationVersion, gameSimulationVersion);
      expect(result.rulesVersion, gameRulesVersion);
      expect(result.prngImplementationId, 'xorshift32-v1');
      expect(result.possessions, possessionsOf(result.ledger).length);
    });

    test('repeats identically for the same input and seed', () {
      final input = buildInput(seed: 7);
      final first = GameSimulator().simulate(input);
      final firstJson = jsonEncode(first.ledger.toJson());
      for (var i = 0; i < 20; i++) {
        final next = GameSimulator().simulate(input);
        expect(jsonEncode(next.ledger.toJson()), firstJson, reason: 'run $i');
        expect(next.homeScore, first.homeScore);
        expect(next.awayScore, first.awayScore);
        expect(next.periodsPlayed, first.periodsPlayed);
      }
    });

    test('different seeds produce different event streams', () {
      final first = simulateSeed(11);
      final second = simulateSeed(12);
      expect(
        jsonEncode(first.ledger.toJson()),
        isNot(jsonEncode(second.ledger.toJson())),
      );
    });

    test('twenty seeded games reconcile every accounting equation', () {
      for (var seed = 1; seed <= 20; seed++) {
        final input = buildInput(seed: seed);
        final result = GameSimulator().simulate(input);
        expect(result.homeScore, isNot(result.awayScore), reason: 'seed $seed');

        for (final team in [input.homeTeamId, input.awayTeamId]) {
          final box = result.boxScore.teams[team.value]!;
          var pg = 0;
          var playerSum = 0;
          var playerTov = 0;
          var playerPf = 0;
          for (final player in input.lineupFor(team).players) {
            final stats = result.boxScore.players[player.id.value]!;
            expect(stats.fgm, stats.twoPm + stats.threePm);
            expect(stats.fga, stats.twoPa + stats.threePa);
            expect(stats.rebounds, stats.oreb + stats.dreb);
            expect(
              stats.points,
              2 * stats.twoPm + 3 * stats.threePm + stats.ftm,
            );
            expect(stats.twoPm, lessThanOrEqualTo(stats.twoPa));
            expect(stats.threePm, lessThanOrEqualTo(stats.threePa));
            expect(stats.ftm, lessThanOrEqualTo(stats.fta));
            pg += stats.points;
            playerSum += stats.turnovers;
            playerTov += stats.turnovers;
            playerPf += stats.personalFouls;
          }
          expect(pg, box.points);
          expect(playerSum, box.turnovers);
          expect(playerTov, box.turnovers);
          expect(playerPf, box.personalFouls);
          expect(box.fgm, lessThanOrEqualTo(box.fga));
          expect(box.ftm, lessThanOrEqualTo(box.fta));
          expect(
            box.points,
            result.boxScore.periodPoints[team.value]!.values.fold(
              0,
              (a, b) => a + b,
            ),
          );
        }
        expect(
          result.homeScore + result.awayScore,
          result.boxScore.teams.values.fold(0, (a, team) => a + team.points),
        );
      }
    });
  });

  group('A1 configuration integrity', () {
    test('default simulator samples the custom A1 brackets from GameInput', () {
      final rules = customA1A();
      final seen = <int>{};
      for (var seed = 1; seed <= 5; seed++) {
        final result = simulateSeed(seed, rules: rules);
        final durations = sampledA1Durations(result);
        expect(durations, isNotEmpty);
        for (final duration in durations) {
          expect(
            duration,
            inInclusiveRange(2, 4),
            reason: 'seed $seed sampled duration $duration',
          );
          seen.add(duration);
        }
      }
      expect(seen, containsAll(<int>[2, 3, 4]));
    });

    test('matching injected model produces the same ledger as the default', () {
      final input = buildInput(seed: 3, rules: customA1A());
      final defaulted = GameSimulator().simulate(input);
      final injected = GameSimulator(
        probabilityModel: BasketballProbabilityModel(rules: customA1A()),
      ).simulate(input);
      expect(
        jsonEncode(injected.ledger.toJson()),
        jsonEncode(defaulted.ledger.toJson()),
      );
      expect(injected.homeScore, defaulted.homeScore);
      expect(injected.awayScore, defaulted.awayScore);
    });

    test('mismatched injected model is rejected with invalidRules', () {
      final input = buildInput(seed: 4, rules: customA1A());
      final simulator = GameSimulator(
        probabilityModel: BasketballProbabilityModel(),
      );
      expect(
        () => simulator.simulate(input),
        throwsA(
          isA<GameValidationException>()
              .having(
                (e) => e.codes,
                'codes',
                contains(GameValidationCode.invalidRules),
              )
              .having((e) => e.issues.first.path, 'path', 'rules.phaseWeights'),
        ),
      );
      // The rejected simulator is still usable with a compatible input.
      final standardInput = buildInput(seed: 4);
      final result = simulator.simulate(standardInput);
      expect(result.events, isNotEmpty);
    });

    test(
      'one simulator reuses different valid A1 configurations in sequence',
      () {
        final simulator = GameSimulator();
        for (final entry in <(int, GameRules)>[
          (5, customA1A()),
          (6, customA1B()),
          (7, customA1A()),
        ]) {
          final input = buildInput(seed: entry.$1, rules: entry.$2);
          final sequential = simulator.simulate(input);
          final fresh = GameSimulator().simulate(input);
          expect(
            jsonEncode(sequential.ledger.toJson()),
            jsonEncode(fresh.ledger.toJson()),
            reason: 'seed ${entry.$1}',
          );
          final durations = sampledA1Durations(sequential);
          expect(durations, isNotEmpty);
          final min = entry.$2.phaseDurations.first.first;
          final max = entry.$2.phaseDurations.last.last;
          for (final duration in durations) {
            expect(duration, inInclusiveRange(min, max));
          }
        }
      },
    );

    test('phase-weights-only mismatch is rejected', () {
      final input = buildInput(
        seed: 8,
        rules: GameRules(phaseWeights: const [2500, 2500, 5000]),
      );
      final simulator = GameSimulator(
        probabilityModel: BasketballProbabilityModel(
          rules: GameRules(phaseWeights: const [5000, 2500, 2500]),
        ),
      );
      expect(
        () => simulator.simulate(input),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.issues.first.path,
            'path',
            'rules.phaseWeights',
          ),
        ),
      );
    });

    test('duration-bracket-only mismatch is rejected', () {
      final input = buildInput(
        seed: 9,
        rules: GameRules(
          phaseDurations: const [
            [3, 3],
            [4, 4],
            [5, 5],
          ],
        ),
      );
      final simulator = GameSimulator(
        probabilityModel: BasketballProbabilityModel(
          rules: GameRules(
            phaseDurations: const [
              [2, 2],
              [3, 3],
              [4, 4],
            ],
          ),
        ),
      );
      expect(
        () => simulator.simulate(input),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.issues.first.path,
            'path',
            'rules.phaseDurations',
          ),
        ),
      );
    });

    test('duration-model version mismatch cannot be constructed validly', () {
      expect(
        () => GameRules(actionDurationModelVersion: 3).validate(),
        throwsCode(GameValidationCode.unsupportedRulesVersion),
      );
    });

    test(
      'standard A1 ledgers remain byte-identical to the published checkpoint',
      () {
        const expected = {
          1: '839d7e50f1664a49cdae0d37e0d464e061d926414250a96968c673b4fd317d92',
          42: 'dc8c06cedd10d3cff938e023e11e520c09a667ac12edc2b2469953eea0371fab',
          99: '238c78a8b36d02ba750b28c6e23d74ecd782486b38d8ff01e66da9cb03ea9438',
          20261029:
              'aabf12782a45d6b1efdfe7d17b62961919012437b94fc712ccf4eac27baf3219',
        };
        for (final entry in expected.entries) {
          final result = simulateSeed(entry.key);
          expect(
            ledgerDigest(result),
            entry.value,
            reason: 'seed ${entry.key}',
          );
          expect(
            result.events.whereType<GameEnded>().length,
            1,
            reason: 'seed ${entry.key}',
          );
        }
      },
    );
  });

  group('clocks, possessions and event legality', () {
    test('validates every generated ledger with the reducer', () {
      for (var seed = 1; seed <= 10; seed++) {
        final input = buildInput(seed: seed);
        final result = GameSimulator().simulate(input);
        final validated = GameEventReducer.validate(input, result.ledger);
        expect(validated.state.ended, isTrue);
        expect(validated.events, result.events);
      }
    });

    test('every period opens with the alternating starter', () {
      final input = buildInput(seed: 13);
      final result = GameSimulator().simulate(input);
      final periods = result.events.whereType<PeriodStarted>().toList();
      for (final period in periods) {
        final expected = period.period.isOdd
            ? input.startingTeamId
            : input.opponentOf(input.startingTeamId);
        expect(period.startingTeamId, expected.value);
      }
      final firstPossessions = <int, String>{};
      for (final event in result.events) {
        if (event is! PossessionStarted) continue;
        firstPossessions.putIfAbsent(event.period, () => event.offenseTeamId);
      }
      for (final entry in firstPossessions.entries) {
        final expected = entry.key.isOdd
            ? input.startingTeamId
            : input.opponentOf(input.startingTeamId);
        expect(entry.value, expected.value, reason: 'period ${entry.key}');
      }
    });

    test('emits legal shot-clock violations charged to the ballhandler', () {
      var found = 0;
      for (var seed = 1; seed <= 40 && found < 5; seed++) {
        final input = buildInput(seed: seed);
        final result = GameSimulator().simulate(input);
        final events = result.events;
        for (var i = 0; i < events.length; i++) {
          final event = events[i];
          if (event is! Turnover) continue;
          if (event.reason != TurnoverReason.shotClock) continue;
          found++;
          expect(event.shotClock, 0);
          expect(event.gameClock, greaterThan(0));
          final offense = offenseAt(events, i);
          expect(event.teamId, offense.value);
          final lineup = input.lineupFor(offense);
          expect(event.playerId, lineup.players.first.id.value);
        }
      }
      expect(found, greaterThan(0));
    });

    test('non-steal turnovers use the schema-v2 reason without a stealer', () {
      var found = 0;
      for (var seed = 1; seed <= 20 && found < 5; seed++) {
        final result = simulateSeed(seed);
        for (final event in result.events.whereType<Turnover>()) {
          if (event.reason != TurnoverReason.nonSteal) continue;
          found++;
          expect(event.stolenById, isNull);
          expect(event.gameClock, greaterThan(0));
        }
      }
      expect(found, greaterThan(0));
    });

    test('steal turnovers credit an opponent of the offense', () {
      var found = 0;
      for (var seed = 1; seed <= 30 && found < 5; seed++) {
        final input = buildInput(seed: seed);
        final result = GameSimulator().simulate(input);
        final events = result.events;
        for (var i = 0; i < events.length; i++) {
          final event = events[i];
          if (event is! Turnover || event.reason != TurnoverReason.steal) {
            continue;
          }
          found++;
          final offense = offenseAt(events, i);
          final defense = input.opponentOf(offense);
          expect(event.teamId, offense.value);
          expect(event.stolenById, isNotNull);
          expect(
            input.lineupFor(defense).playerIds,
            contains(event.stolenById),
          );
        }
      }
      expect(found, greaterThan(0));
    });

    test('offensive fouls produce a foul and turnover without an FGA', () {
      var found = 0;
      for (var seed = 1; seed <= 40 && found < 5; seed++) {
        final result = simulateSeed(seed);
        final events = result.events;
        for (var i = 0; i < events.length - 1; i++) {
          final foul = events[i];
          if (foul is! PersonalFoul || foul.kind != FoulKind.offensive) {
            continue;
          }
          found++;
          expect(foul.bonus, isFalse);
          expect(foul.freeThrowsAwarded, 0);
          final turnover = events[i + 1];
          expect(turnover, isA<Turnover>());
          expect((turnover as Turnover).reason, TurnoverReason.offensiveFoul);
          expect(turnover.playerId, foul.committingPlayerId);
          expect(turnover.teamId, foul.committingTeamId);
          expect(turnover.stolenById, isNull);
        }
      }
      expect(found, greaterThan(0));
    });

    test(
      'possession changes after scores, turnovers and defensive rebounds',
      () {
        final input = buildInput(seed: 5);
        final result = GameSimulator().simulate(input);
        final events = result.events;
        for (var i = 0; i < events.length; i++) {
          final event = events[i];
          if (event is! PossessionEnded) continue;
          if (event.reason == PossessionEndReason.periodEnd) continue;
          final expected = input.opponentOf(TeamId(event.offenseTeamId));
          for (var j = i + 1; j < events.length; j++) {
            final next = events[j];
            if (next is PeriodStarted || next is GameEnded) break;
            if (next is PossessionStarted) {
              expect(next.offenseTeamId, expected.value);
              break;
            }
          }
        }
      },
    );

    test('offensive rebounds continue the same possession at 14 seconds', () {
      var found = 0;
      for (var seed = 1; seed <= 20 && found < 3; seed++) {
        final result = simulateSeed(seed);
        final events = result.events;
        for (var i = 0; i < events.length - 1; i++) {
          final event = events[i];
          if (event is! Rebound || !event.offensive) continue;
          found++;
          expect(event.shotClock, 14);
          final possessionId = possessionIdAt(events, i);
          for (var j = i + 1; j < events.length; j++) {
            if (events[j] is PossessionStarted) {
              fail('new possession started before the OREB possession ended');
            }
            if (events[j] is PossessionEnded) {
              expect((events[j] as PossessionEnded).possessionId, possessionId);
              break;
            }
            if (events[j] is PeriodEnded) break;
          }
        }
      }
      expect(found, greaterThan(0));
    });

    test('defensive rebounds end the possession and transfer it', () {
      var found = 0;
      for (var seed = 1; seed <= 10 && found < 3; seed++) {
        final result = simulateSeed(seed);
        final events = result.events;
        for (var i = 0; i < events.length - 1; i++) {
          final event = events[i];
          if (event is! Rebound || event.offensive) continue;
          found++;
          expect(event.shotClock, 24);
          final end = events[i + 1];
          expect(end, isA<PossessionEnded>());
          expect(
            (end as PossessionEnded).reason,
            PossessionEndReason.defensiveRebound,
          );
          expect(end.gameClock, event.gameClock);
          expect(end.shotClock, 24);
        }
      }
      expect(found, greaterThan(0));
    });

    test('free throws and dead-ball bookkeeping never advance the clock', () {
      var groups = 0;
      for (var seed = 1; seed <= 20 && groups < 5; seed++) {
        final result = simulateSeed(seed);
        final events = result.events;
        for (var i = 0; i < events.length; i++) {
          final event = events[i];
          if (event is! PersonalFoul) continue;
          if (event.freeThrowsAwarded == 0) continue;
          groups++;
          var clock = event.gameClock;
          var shotClock = event.shotClock;
          for (var j = i + 1; j < events.length; j++) {
            final next = events[j];
            if (next is! FreeThrowAttempt) break;
            expect(next.gameClock, clock);
            expect(next.shotClock, shotClock);
          }
        }
      }
      expect(groups, greaterThan(0));
    });
  });

  group('terminal fouls at the boundary', () {
    test('bonus non-shooting foul at the horn completes free throws', () {
      final rules = GameRules(bonusRegulationFouls: 1);
      var found = 0;
      for (var seed = 1; seed <= 80; seed++) {
        final result = simulateSeed(seed, rules: rules);
        final events = result.events;
        for (var i = 0; i < events.length; i++) {
          final event = events[i];
          if (event is! PersonalFoul) continue;
          if (event.kind != FoulKind.nonShooting) continue;
          if (event.gameClock != 0) continue;
          found++;
          expect(event.bonus, isTrue);
          expect(event.freeThrowsAwarded, 2);
          final first = events[i + 1];
          final second = events[i + 2];
          expect(first, isA<FreeThrowAttempt>());
          expect(second, isA<FreeThrowAttempt>());
          final firstAttempt = first as FreeThrowAttempt;
          final secondAttempt = second as FreeThrowAttempt;
          expect(firstAttempt.gameClock, 0);
          expect(secondAttempt.gameClock, 0);
          expect(secondAttempt.attemptsInGroup, 2);
          expect(secondAttempt.lastOfGroup, isTrue);
          final resolution = events[i + 3];
          expect(
            resolution,
            anyOf(isA<DeadBallMiss>(), isA<PossessionEnded>()),
          );
          expect(events.skip(i).whereType<PeriodEnded>().isNotEmpty, isTrue);
        }
      }
      expect(found, greaterThan(0));
    });

    test(
      'non-bonus non-shooting foul at the horn is recorded before period end',
      () {
        final rules = GameRules(bonusRegulationFouls: 10);
        var found = 0;
        for (var seed = 1; seed <= 250 && found < 3; seed++) {
          final result = simulateSeed(seed, rules: rules);
          final events = result.events;
          for (var i = 0; i < events.length; i++) {
            final event = events[i];
            if (event is! PersonalFoul) continue;
            if (event.kind != FoulKind.nonShooting) continue;
            if (event.bonus) continue;
            if (event.gameClock != 0) continue;
            found++;
            expect(event.freeThrowsAwarded, 0);
            final next = events[i + 1];
            expect(next, isA<PossessionEnded>());
            expect(
              (next as PossessionEnded).reason,
              PossessionEndReason.periodEnd,
            );
            expect(next.gameClock, 0);
            expect(events[i + 2], isA<PeriodEnded>());
          }
        }
        expect(found, greaterThan(0));
      },
    );

    test('bonus non-shooting foul at shot-clock zero resolves free throws', () {
      final rules = GameRules(bonusRegulationFouls: 1);
      var found = 0;
      for (var seed = 1; seed <= 80 && found < 3; seed++) {
        final result = simulateSeed(seed, rules: rules);
        final events = result.events;
        for (var i = 0; i < events.length; i++) {
          final event = events[i];
          if (event is! PersonalFoul) continue;
          if (event.kind != FoulKind.nonShooting) continue;
          if (event.gameClock == 0 || event.shotClock != 0) continue;
          if (!event.bonus) continue;
          found++;
          expect(event.freeThrowsAwarded, 2);
          expect(events[i + 1], isA<FreeThrowAttempt>());
          expect(events[i + 2], isA<FreeThrowAttempt>());
          expect((events[i + 1] as FreeThrowAttempt).shotClock, 0);
          expect((events[i + 2] as FreeThrowAttempt).shotClock, 0);
        }
      }
      expect(found, greaterThan(0));
    });

    test('a non-bonus foul at shot-clock zero never survives as a foul', () {
      final rules = GameRules(bonusRegulationFouls: 10);
      for (var seed = 1; seed <= 40; seed++) {
        final result = simulateSeed(seed, rules: rules);
        for (final event in result.events.whereType<PersonalFoul>()) {
          if (event.kind != FoulKind.nonShooting) continue;
          if (event.gameClock == 0) continue;
          if (event.shotClock != 0) continue;
          expect(
            event.bonus,
            isTrue,
            reason: 'non-bonus foul cannot be emitted at shot-clock zero',
          );
        }
      }
    });
  });

  group('buzzer and overtime', () {
    test('resolves zero-clock attempts before the period ends', () {
      final rules = tinyRules();
      var foundShots = 0;
      var foundFreeThrows = 0;
      for (var seed = 1; seed <= 20; seed++) {
        final result = simulateSeed(seed, rules: rules);
        final events = result.events;
        for (var i = 0; i < events.length; i++) {
          final event = events[i];
          if (event.gameClock != 0) continue;
          if (event is FieldGoalAttempt) foundShots++;
          if (event is FreeThrowAttempt) {
            foundFreeThrows++;
            expect(event.shotClock, isNotNull);
            expect(
              events.whereType<Rebound>().where((r) => r.gameClock == 0),
              isEmpty,
            );
            final groupId = event.groupId;
            var last = i;
            while (last + 1 < events.length &&
                events[last + 1] is FreeThrowAttempt &&
                (events[last + 1] as FreeThrowAttempt).groupId == groupId) {
              last++;
            }
            expect(last, greaterThanOrEqualTo(i));
            final resolution = events[last + 1];
            expect(
              resolution,
              anyOf(isA<DeadBallMiss>(), isA<PossessionEnded>()),
            );
            final periodEndIndex = events.indexWhere(
              (candidate) => candidate is PeriodEnded,
              last + 1,
            );
            expect(periodEndIndex, greaterThan(last));
          }
          if (event is PeriodEnded) {
            expect(
              events.sublist(0, i).whereType<PossessionStarted>().isNotEmpty,
              isTrue,
            );
          }
        }
      }
      expect(foundShots, greaterThan(0));
      expect(foundFreeThrows, greaterThan(0));
    });

    test('overtime starts only after a tied period and ends non-tied', () {
      final rules = tinyRules();
      GameResult? otGame;
      GameInput? otInput;
      for (var seed = 1; seed <= 10 && otGame == null; seed++) {
        final input = buildInput(seed: seed, rules: rules);
        final result = GameSimulator().simulate(input);
        if (result.overtimes > 0) {
          otGame = result;
          otInput = input;
        }
      }
      expect(otGame, isNotNull);
      final result = otGame!;
      final input = otInput!;
      expect(result.periodsPlayed, greaterThan(4));
      expect(result.homeScore, isNot(result.awayScore));
      final periods = result.events.whereType<PeriodStarted>().toList();
      expect(periods.length, result.periodsPlayed);
      for (final period in periods.where((p) => p.period > 4)) {
        expect(period.gameClock, 1);
        final expected = period.period.isOdd
            ? input.startingTeamId
            : input.opponentOf(input.startingTeamId);
        expect(period.startingTeamId, expected.value);
      }
    });

    test('repeated overtime is representable', () {
      final rules = tinyRules();
      final result = simulateSeed(1, rules: rules);
      expect(result.overtimes, greaterThanOrEqualTo(2));
      expect(result.periodsPlayed, greaterThanOrEqualTo(6));
      expect(result.homeScore, isNot(result.awayScore));
      expect(
        result.events.whereType<GameEnded>().single.finalPeriod,
        result.periodsPlayed,
      );
    });

    test(
      'enforces event, zero-time and overtime bounds with typed failures',
      () {
        expect(
          () => simulateSeed(1, rules: tinyRules(maxEvents: 5)),
          throwsCode(GameValidationCode.eventLimitExceeded),
        );
        expect(
          () => simulateSeed(1, rules: tinyRules(maxZeroTimeEvents: 1)),
          throwsCode(GameValidationCode.zeroTimeEventLimitExceeded),
        );
        expect(
          () => simulateSeed(1, rules: tinyRules(maxOvertimes: 0)),
          throwsCode(GameValidationCode.overtimeLimitExceeded),
        );
        expect(
          () => simulateSeed(1, rules: tinyRules(maxOvertimes: 1)),
          throwsCode(GameValidationCode.overtimeLimitExceeded),
        );
      },
    );

    test('never opens a possession after the horn', () {
      for (var seed = 1; seed <= 10; seed++) {
        final result = simulateSeed(seed, rules: tinyRules());
        final events = result.events;
        for (var i = 0; i < events.length; i++) {
          if (events[i] is! PeriodEnded) continue;
          final next = i + 1 < events.length ? events[i + 1] : null;
          if (next == null) continue;
          expect(next, anyOf(isA<PeriodStarted>(), isA<GameEnded>()));
        }
        for (final possession in possessionsOf(result.ledger)) {
          if (possession.gameClock == 0) {
            fail('possession started at the horn: ${possession.toJson()}');
          }
        }
      }
    });
  });
}
