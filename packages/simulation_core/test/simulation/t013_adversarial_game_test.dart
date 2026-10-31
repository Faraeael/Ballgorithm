import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';
import 't012_canonical_ledger_fixture_v3.dart';
import 't013_support.dart';
import 't011_game_reliability_test.dart' as t011;

Matcher throwsCode(GameValidationCode code) => throwsA(
  isA<GameValidationException>().having(
    (error) => error.codes,
    'codes',
    contains(code),
  ),
);

String digest(GameResult result) =>
    sha256.convert(utf8.encode(jsonEncode(result.ledger.toJson()))).toString();

/// Runs one game and audits lifecycle, accounting and causality.
GameResult simulateAndAudit(GameInput input) {
  final result = GameSimulator().simulate(input);
  t011.auditGame(input, result);
  auditAccounting(input, result);
  auditCausality(input, result);
  return result;
}

/// Finds the first normalized seed whose A1 type draw equals [target].
int seedWithTypeDraw(int target) {
  for (var seed = 1; seed < 2000000; seed++) {
    if (DeterministicRandom(seed).nextInt(10000) == target) return seed;
  }
  fail('no seed produces A1 type draw $target');
}

void main() {
  group('A1 draw boundaries', () {
    test(
      'type draws 0/1499/1500/4499/4500/9999 land in the approved phase',
      () {
        const boundaries = {
          0: PhaseKind.transition,
          1499: PhaseKind.transition,
          1500: PhaseKind.earlyOffense,
          4499: PhaseKind.earlyOffense,
          4500: PhaseKind.halfCourt,
          9999: PhaseKind.halfCourt,
        };
        final model = BasketballProbabilityModel();
        for (final entry in boundaries.entries) {
          final seed = seedWithTypeDraw(entry.key);
          final phase = model.drawPhaseDuration(DeterministicRandom(seed));
          expect(
            phase.kind,
            entry.value,
            reason: 'draw ${entry.key} via seed $seed',
          );
          final bracket = GameRules.standard.phaseDurations[entry.value.index];
          expect(
            phase.seconds,
            inInclusiveRange(bracket[0], bracket[1]),
            reason: 'draw ${entry.key} bracket ${bracket[0]}..${bracket[1]}',
          );
        }
      },
    );
  });

  group('200-seed property corpus', () {
    test('seeds 1..200 complete, replay and reconcile', () {
      var games = 0;
      var overtimeGames = 0;
      var expectedFailures = 0;
      var minEvents = 1 << 30;
      var maxEvents = 0;
      var totalEvents = 0;
      final failures = <String>[];

      for (final seed in t013Seeds) {
        final input = standardInput(seed);
        try {
          final result = simulateAndAudit(input);
          games++;
          if (result.overtimes > 0) overtimeGames++;
          final count = result.events.length;
          if (count < minEvents) minEvents = count;
          if (count > maxEvents) maxEvents = count;
          totalEvents += count;
        } on GameValidationException catch (error) {
          if (error.codes.every(
            (code) =>
                code == GameValidationCode.overtimeLimitExceeded ||
                code == GameValidationCode.eventLimitExceeded ||
                code == GameValidationCode.zeroTimeEventLimitExceeded,
          )) {
            expectedFailures++;
            continue;
          }
          failures.add(
            'seed=$seed codes=${error.codes} gameId=${input.gameId} '
            'rules=${jsonEncode(input.rules.toJson())} '
            'events=${input.rules.maxEvents} issue=${error.issues.first}',
          );
        } on TestFailure catch (error) {
          failures.add(
            'seed=$seed assertion: ${error.message} '
            'rules=${jsonEncode(input.rules.toJson())}',
          );
        }
      }

      expect(failures, isEmpty, reason: failures.join('\n'));
      expect(games, 200);
      expect(expectedFailures, 0);
      expect(minEvents, greaterThan(400));
      expect(maxEvents, lessThanOrEqualTo(GameRules.standard.maxEvents));
      // Recorded for the T013 report, not an acceptance threshold.
      print(
        'T013 corpus: games=$games overtimeGames=$overtimeGames '
        'events=$minEvents..$maxEvents avg=${(totalEvents / games).toStringAsFixed(1)}',
      );
    });
  });

  group('determinism properties', () {
    test('20 identical simulations of the pinned input are byte-identical', () {
      final input = standardInput(42);
      final first = GameSimulator().simulate(input);
      final expected = jsonEncode(first.ledger.toJson());
      final fingerprint = GameFingerprint.of(input);
      for (var run = 0; run < 19; run++) {
        final next = GameSimulator().simulate(input);
        expect(jsonEncode(next.ledger.toJson()), expected, reason: 'run $run');
        expect(GameFingerprint.of(input), fingerprint);
        expect(next.homeScore, first.homeScore);
        expect(next.awayScore, first.awayScore);
        expect(next.periodsPlayed, first.periodsPlayed);
      }
      expect(
        sha256.convert(utf8.encode(expected)).toString(),
        sha256.convert(utf8.encode(t012CanonicalLedgerV3Json)).toString(),
        reason: 'T012 golden must remain the canonical seed-42 ledger',
      );
    });

    test('pinned T012 seeds still reproduce their published digests', () {
      const published = {
        1: '074d2116645b899b427101e8aecf5b9cd0c693bad4839160bc19c0b69130ba76',
        42: '2baefd7d605ec65225c470f938fb45218db50d78a0d9ae75548e2e6646c276ac',
        99: 'e895fb231ee74ca9abe4321cc8867aae6ab1010baa7e58b3b8817524f3e1e2e8',
        20261029:
            '501c2e0e5e91c8490e8956a1b79f2141842bff9790b2e4bf44aa46b9e6ef80a5',
      };
      for (final entry in published.entries) {
        final input = standardInput(entry.key);
        expect(digest(simulateAndAudit(input)), entry.value);
      }
    });

    test('different seeds produce different ledgers', () {
      final digests = <String>{};
      for (var seed = 1; seed <= 25; seed++) {
        digests.add(digest(GameSimulator().simulate(standardInput(seed))));
      }
      expect(digests, hasLength(25));
    });
  });

  group('input adversarial validation', () {
    late GameInput base;

    setUp(() {
      base = standardInput(42);
    });

    GameInput rebuild({
      String? gameId,
      League? league,
      TeamId? homeTeamId,
      ActiveLineup? homeLineup,
      GameRules? rules,
    }) => GameInput.create(
      gameId: gameId ?? base.gameId,
      league: league ?? base.league,
      homeTeamId: homeTeamId ?? base.homeTeamId,
      awayTeamId: base.awayTeamId,
      homeLineup: homeLineup ?? base.homeLineup,
      awayLineup: base.awayLineup,
      seed: base.seed,
      rules: rules ?? base.rules,
    );

    test(
      'same team, unknown team and foreign lineup fail with typed codes',
      () {
        expect(
          () => GameInput.create(
            gameId: 'game-1',
            league: base.league,
            homeTeamId: base.homeTeamId,
            awayTeamId: base.homeTeamId,
            homeLineup: base.homeLineup,
            awayLineup: base.awayLineup,
            seed: 42,
            rules: GameRules.standard,
          ),
          throwsCode(GameValidationCode.teamsNotDistinct),
        );
        expect(
          () => rebuild(homeTeamId: const TeamId('team-99')),
          throwsCode(GameValidationCode.teamNotFound),
        );
        expect(
          () => rebuild(homeLineup: base.awayLineup),
          throwsCode(GameValidationCode.foreignLineupPlayer),
        );
      },
    );

    test('lineup size, order, duplicates and empty game id are rejected', () {
      final players = base.homeLineup.players;
      expect(
        () => ActiveLineup.create(players.take(4).toList()),
        throwsCode(GameValidationCode.invalidLineupSize),
      );
      expect(
        () => ActiveLineup.create([
          players[1],
          players[0],
          players[2],
          players[3],
          players[4],
        ]),
        throwsCode(GameValidationCode.invalidLineupPositions),
      );
      expect(
        () => ActiveLineup.create([
          players[0],
          players[1],
          players[2],
          players[3],
          players[3],
        ]),
        throwsCode(GameValidationCode.duplicateLineupPlayer),
      );
      expect(
        () => rebuild(gameId: '   '),
        throwsCode(GameValidationCode.emptyGameId),
      );
    });

    test('unsupported or invalid rules are rejected before gameplay', () {
      expect(
        () => rebuild(rules: GameRules(rulesVersion: 3)),
        throwsCode(GameValidationCode.unsupportedRulesVersion),
      );
      for (final rules in [
        GameRules(periodSeconds: 0),
        GameRules(shotClockSeconds: 25),
        GameRules(maxOvertimes: 11),
        GameRules(bonusRegulationFouls: 0),
        GameRules(phaseWeights: const [1500, 3000, 5000]),
        GameRules(
          phaseDurations: const [
            [0, 7],
            [5, 11],
            [10, 22],
          ],
        ),
      ]) {
        expect(
          () => rebuild(rules: rules),
          throwsCode(GameValidationCode.invalidRules),
          reason: jsonEncode(rules.toJson()),
        );
      }
    });

    test('malformed ledger headers are rejected with typed codes', () {
      final result = GameSimulator().simulate(base);
      final valid = result.ledger.toJson();

      Map<String, Object?> corrupt(void Function(Map<String, Object?> json) f) {
        final copy = jsonDecode(jsonEncode(valid)) as Map<String, Object?>;
        f(copy);
        return copy;
      }

      expect(
        () => GameEventLedger.fromJson(
          corrupt((json) => json['gameSimulationVersion'] = 1),
        ),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.unsupportedSimulationVersion),
          ),
        ),
      );
      expect(
        () => GameEventLedger.fromJson(
          corrupt((json) => json['eventSchemaVersion'] = 3),
        ),
        throwsCode(GameValidationCode.unsupportedEventSchemaVersion),
      );
      expect(
        () => GameEventLedger.fromJson(
          corrupt((json) => json['inputFingerprint'] = 'not-a-hash'),
        ),
        throwsCode(GameValidationCode.invalidFingerprint),
      );
      expect(
        () => GameEventLedger.fromJson(
          corrupt((json) => json['events'] = 'nope'),
        ),
        throwsCode(GameValidationCode.malformedEventJson),
      );
      expect(
        () => GameEventLedger.fromJson(
          corrupt((json) {
            (json['events']! as List<Object?>)[0] = {
              ...(json['events']! as List<Object?>)[0]! as Map<String, Object?>,
              'type': 'BogusEvent',
            };
          }),
        ),
        throwsCode(GameValidationCode.unsupportedEventType),
      );
    });
  });

  group('seed policy', () {
    test('seed zero falls back to the documented constant and starts away', () {
      final input = standardInput(0);
      expect(input.seed, 0);
      expect(input.normalizedSeed, 0x9E3779B9);
      expect(input.normalizedSeed.isOdd, isTrue);
      expect(input.homeStarts, isFalse);
      expect(input.startingTeamId, input.awayTeamId);
      simulateAndAudit(input);
    });

    test('even seeds start home and odd seeds start away', () {
      for (final seed in [2, 4, 42, 100]) {
        final input = standardInput(seed);
        expect(input.normalizedSeed.isEven, isTrue);
        expect(input.startingTeamId, input.homeTeamId);
        expect(simulateAndAudit(input).events.first, isA<GameStarted>());
      }
      for (final seed in [1, 3, 99, 101]) {
        final input = standardInput(seed);
        expect(input.normalizedSeed.isOdd, isTrue);
        expect(input.startingTeamId, input.awayTeamId);
      }
    });

    test(
      'negative and wide raw seeds are accepted per the documented policy',
      () {
        final negative = standardInput(-1);
        expect(negative.normalizedSeed, 0xFFFFFFFF);
        expect(negative.homeStarts, isFalse);
        simulateAndAudit(negative);

        final wide = standardInput(0x1FFFFFFFF);
        expect(wide.normalizedSeed, 0xFFFFFFFF);
        expect(wide.homeStarts, isFalse);
        expect(GameFingerprint.of(wide), isNot(GameFingerprint.of(negative)));
      },
    );

    test('raw seed aliases share gameplay and differ in fingerprint', () {
      final canonical = standardInput(42);
      final aliased = standardInput(42 + 4294967296);
      expect(aliased.normalizedSeed, canonical.normalizedSeed);
      expect(GameFingerprint.of(aliased), isNot(GameFingerprint.of(canonical)));

      final first = simulateAndAudit(canonical);
      final second = simulateAndAudit(aliased);
      expect(
        jsonEncode([for (final event in second.events) event.toJson()]),
        jsonEncode([for (final event in first.events) event.toJson()]),
      );
      expect(second.homeScore, first.homeScore);
    });
  });

  group('configurable rules matrix', () {
    final configs = <String, GameRules>{
      'one-second clocks': GameRules(
        periodSeconds: 1,
        overtimeSeconds: 1,
        shotClockSeconds: 1,
        offensiveReboundResetSeconds: 1,
        nonBonusFoulResetFloorSeconds: 1,
        maxOvertimes: 2,
      ),
      'two-second clocks': GameRules(
        periodSeconds: 2,
        overtimeSeconds: 2,
        shotClockSeconds: 2,
        offensiveReboundResetSeconds: 1,
        nonBonusFoulResetFloorSeconds: 1,
        maxOvertimes: 2,
      ),
      'five-second periods': GameRules(
        periodSeconds: 5,
        overtimeSeconds: 5,
        shotClockSeconds: 2,
        offensiveReboundResetSeconds: 2,
        nonBonusFoulResetFloorSeconds: 1,
        maxOvertimes: 2,
      ),
      'short-shot-clock floor': GameRules(
        periodSeconds: 24,
        overtimeSeconds: 12,
        shotClockSeconds: 5,
        offensiveReboundResetSeconds: 3,
        nonBonusFoulResetFloorSeconds: 2,
        maxOvertimes: 2,
      ),
      'aggressive bonus': GameRules(
        periodSeconds: 60,
        overtimeSeconds: 30,
        shotClockSeconds: 24,
        bonusRegulationFouls: 1,
        bonusOvertimeFouls: 1,
        maxOvertimes: 2,
      ),
      'custom A1 durations': GameRules(
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
      'one-second phase brackets': GameRules(
        periodSeconds: 30,
        overtimeSeconds: 15,
        phaseDurations: const [
          [1, 1],
          [1, 2],
          [1, 3],
        ],
        maxOvertimes: 2,
      ),
      'zero overtimes': GameRules(maxOvertimes: 0),
      'ten-overtime cap': GameRules(maxOvertimes: 10),
    };

    // Pinned outcome per configuration and seed (seeds 1, 2, 3).
    // 'ok' means a complete audited game; any other value is the exact typed
    // bound. Sub-three-second periods tie at one-second granularity, so the
    // two-overtime configurations legitimately exhaust their limit; the
    // zero-overtime configuration fails only on the tied seed.
    // Pinned for simulation v2 (Amendment 002). v1 had a fifth overtime bound
    // at zero-overtime seed 3; the v2 hazard mix no longer ties that game.
    final expected = <String, List<String>>{
      'one-second clocks': ['overtimeLimitExceeded', 'ok', 'ok'],
      'two-second clocks': [
        'overtimeLimitExceeded',
        'overtimeLimitExceeded',
        'overtimeLimitExceeded',
      ],
      'five-second periods': ['ok', 'ok', 'ok'],
      'short-shot-clock floor': ['ok', 'ok', 'ok'],
      'aggressive bonus': ['ok', 'ok', 'ok'],
      'custom A1 durations': ['ok', 'ok', 'ok'],
      'one-second phase brackets': ['ok', 'ok', 'ok'],
      'zero overtimes': ['ok', 'ok', 'ok'],
      'ten-overtime cap': ['ok', 'ok', 'ok'],
    };

    test('every configuration/seed outcome matches verified expectations', () {
      expect(expected.keys, unorderedEquals(configs.keys));
      final observed = <String>[];
      var successes = 0;
      var bounds = 0;

      for (final entry in configs.entries) {
        final cases = expected[entry.key]!;
        for (var index = 0; index < cases.length; index++) {
          final seed = index + 1;
          final input = standardInput(seed, rules: entry.value);
          final wanted = cases[index];
          if (wanted == 'ok') {
            final result = simulateAndAudit(input);
            observed.add('${entry.key} seed=$seed ok ot=${result.overtimes}');
            successes++;
            continue;
          }
          try {
            final result = simulateAndAudit(input);
            fail(
              '${entry.key} seed=$seed expected $wanted but completed '
              '(score ${result.homeScore}-${result.awayScore})',
            );
          } on GameValidationException catch (error) {
            expect(
              error.codes.map((code) => code.name),
              contains(wanted),
              reason: '${entry.key} seed=$seed',
            );
            // A bound failure must be justified by the configured limit.
            if (wanted == 'overtimeLimitExceeded') {
              expect(entry.value.maxOvertimes, lessThanOrEqualTo(2));
            }
            if (wanted == 'eventLimitExceeded') {
              expect(
                entry.value.maxEvents,
                lessThan(GameRules.standard.maxEvents),
              );
            }
            if (wanted == 'zeroTimeEventLimitExceeded') {
              expect(
                entry.value.maxZeroTimeEvents,
                lessThan(GameRules.standard.maxZeroTimeEvents),
              );
            }
            observed.add(
              '${entry.key} seed=$seed $wanted maxOT=${entry.value.maxOvertimes}',
            );
            bounds++;
          }
        }
      }

      expect(successes, 23);
      expect(bounds, 4);
      expect(successes + bounds, configs.length * 3);
      print('T013 rules matrix:\n  ${observed.join('\n  ')}');
    });

    test('intentional bounds fail without returning a result', () {
      expect(
        () => GameSimulator().simulate(
          standardInput(1, rules: GameRules(maxEvents: 200)),
        ),
        throwsCode(GameValidationCode.eventLimitExceeded),
      );
      expect(
        () => GameSimulator().simulate(
          standardInput(1, rules: GameRules(maxZeroTimeEvents: 1)),
        ),
        throwsCode(GameValidationCode.zeroTimeEventLimitExceeded),
      );
      expect(
        () => GameSimulator().simulate(
          standardInput(1, rules: GameRules(maxOvertimes: 0)),
        ),
        anyOf(
          returnsNormally,
          throwsCode(GameValidationCode.overtimeLimitExceeded),
        ),
      );
    });
  });

  group('execution bounds layers', () {
    test('default caps are the frozen OD-14 values', () {
      final rules = GameRules.standard;
      expect(rules.maxEvents, 50000);
      expect(rules.maxZeroTimeEvents, 64);
      expect(rules.maxOvertimes, 10);
    });

    test('reducer rejects a ledger longer than maxEvents', () {
      final input = GameInput.create(
        gameId: 'game-1',
        league: standardInput(42).league,
        homeTeamId: standardInput(42).homeTeamId,
        awayTeamId: standardInput(42).awayTeamId,
        homeLineup: standardInput(42).homeLineup,
        awayLineup: standardInput(42).awayLineup,
        seed: 42,
        rules: GameRules(maxEvents: 1),
      );
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId);
      expect(
        () => GameEventReducer.validate(input, script.ledger()),
        throwsCode(GameValidationCode.eventLimitExceeded),
      );
    });

    test('simulator and reducer agree that a legal bound is inclusive', () {
      final input = standardInput(42);
      final baseline = GameSimulator().simulate(input);
      final count = baseline.events.length;
      final atCap = GameSimulator().simulate(
        standardInput(42, rules: GameRules(maxEvents: count)),
      );
      expect(atCap.events.length, count);
      expect(
        () => GameSimulator().simulate(
          standardInput(42, rules: GameRules(maxEvents: count - 1)),
        ),
        throwsCode(GameValidationCode.eventLimitExceeded),
      );
    });
  });
}
