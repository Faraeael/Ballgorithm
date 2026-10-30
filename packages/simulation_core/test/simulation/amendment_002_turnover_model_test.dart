import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'probability_support.dart';
import 'support.dart';

Matcher throwsCode(GameValidationCode code) => throwsA(
  isA<GameValidationException>().having(
    (error) => error.codes,
    'codes',
    contains(code),
  ),
);

void main() {
  final model = BasketballProbabilityModel();
  final permissiveDefense = teamOnCourt('away');

  group('positive allocation contract', () {
    test('min-one allocation keeps every slot positive and sums to 10000', () {
      final shares = BasketballProbabilityModel.allocatePositiveWeights([
        1,
        10000,
        10000,
        10000,
        10000,
      ], 10000);
      expect(shares, [1, 2500, 2500, 2500, 2499]);
      expect(shares.reduce((a, b) => a + b), 10000);
      expect(shares.every((share) => share >= 1), isTrue);
    });

    test('error obeys the proven (−k, +2) window, not a 2 bp claim', () {
      final raw = [29988000, 150, 150, 150, 150];
      final shares = BasketballProbabilityModel.allocatePositiveWeights(
        raw,
        10000,
      );
      final total = raw.reduce((a, b) => a + b);
      final exact = raw[0] * 10000 / total;
      final error = shares[0] - exact;
      expect(error, lessThan(0));
      expect(-error, lessThan(5));
      expect(-error, greaterThan(3), reason: 'the old 2 bp bound was false');
      expect(shares.reduce((a, b) => a + b), 10000);
    });

    test('ties are deterministic and canonical-index ordered', () {
      final first = BasketballProbabilityModel.allocatePositiveWeights([
        1,
        1,
        1,
        1,
        1,
      ], 10000);
      final second = BasketballProbabilityModel.allocatePositiveWeights([
        1,
        1,
        1,
        1,
        1,
      ], 10000);
      expect(first, second);
      expect(first[0] + first[1] + first[2] + first[3] + first[4], 10000);
      expect(first[0], greaterThanOrEqualTo(first[4]));
    });

    test('rejects non-positive weights and too small budgets', () {
      expect(
        () => BasketballProbabilityModel.allocatePositiveWeights([0, 1], 10000),
        throwsArgumentError,
      );
      expect(
        () => BasketballProbabilityModel.allocatePositiveWeights([1, 1, 1], 2),
        throwsArgumentError,
      );
    });
  });

  group('exposure', () {
    test('exposure is positive, sums to 10000 and ignores ballHandling', () {
      final lineup = teamOnCourt('home').lineup;
      final weights = model.exposureWeights(lineup);
      expect(weights.reduce((a, b) => a + b), 10000);
      expect(weights.every((weight) => weight >= 1), isTrue);

      final handlerChanged = teamOnCourt(
        'home',
        overrides: {Position.pg: attrs(ballHandling: 100)},
      ).lineup;
      expect(model.exposureWeights(handlerChanged), weights);
    });

    test('passing and basketballIQ raise involvement', () {
      final lineup = teamOnCourt('home').lineup;
      final baseline = model.exposureWeights(lineup);
      final improved = model.exposureWeights(
        teamOnCourt(
          'home',
          overrides: {Position.pg: attrs(passing: 90, basketballIQ: 90)},
        ).lineup,
      );
      expect(improved[0], greaterThan(baseline[0]));
      expect(improved.reduce((a, b) => a + b), 10000);
    });
  });

  group('individual hazard', () {
    List<int> hazardsFor(ActiveLineup lineup) => model.playerTurnoverHazards(
      offense: TeamOnCourt(teamId: const TeamId('home'), lineup: lineup),
      defense: permissiveDefense,
      phase: PhaseKind.halfCourt,
    );

    test('ballHandling lowers the hazard at fixed exposure', () {
      final baseline = hazardsFor(teamOnCourt('home').lineup);
      final secure = hazardsFor(
        teamOnCourt(
          'home',
          overrides: {Position.pg: attrs(ballHandling: 72)},
        ).lineup,
      );
      final insecure = hazardsFor(
        teamOnCourt(
          'home',
          overrides: {Position.pg: attrs(ballHandling: 40)},
        ).lineup,
      );
      expect(secure[0], lessThan(baseline[0]));
      expect(insecure[0], greaterThan(baseline[0]));
      expect(secure[1], baseline[1], reason: 'other players unchanged');
    });

    test('passing and IQ lower the hazard at fixed exposure', () {
      final baseline = hazardsFor(teamOnCourt('home').lineup);
      final betterPassing = hazardsFor(
        teamOnCourt(
          'home',
          overrides: {Position.pg: attrs(passing: 90)},
        ).lineup,
      );
      final betterIq = hazardsFor(
        teamOnCourt(
          'home',
          overrides: {Position.pg: attrs(basketballIQ: 90)},
        ).lineup,
      );
      expect(betterPassing[0], lessThan(baseline[0]));
      expect(betterIq[0], lessThan(baseline[0]));
    });

    test('hazards stay inside the clamp at rating extremes', () {
      final allZero = hazardsFor(
        teamOnCourt(
          'home',
          overrides: {
            for (final position in Position.values)
              position: attrs(ballHandling: 0, passing: 0, basketballIQ: 0),
          },
        ).lineup,
      );
      final allMax = hazardsFor(
        teamOnCourt(
          'home',
          overrides: {
            for (final position in Position.values)
              position: attrs(
                ballHandling: 100,
                passing: 100,
                basketballIQ: 100,
              ),
          },
        ).lineup,
      );
      expect(allZero, everyElement(inInclusiveRange(150, 2500)));
      expect(allMax, everyElement(inInclusiveRange(150, 2500)));
      expect(allZero.first, greaterThan(allMax.first));
    });

    test('ceiling clamps over interior handling values near the extremes', () {
      TeamOnCourt offenseOf(ActiveLineup lineup) =>
          TeamOnCourt(teamId: const TeamId('home'), lineup: lineup);
      final pressure = teamOnCourt(
        'away',
        overrides: {
          for (final position in Position.values)
            position: attrs(perimeterDefense: 100, athleticism: 100),
        },
      );
      int hazardAt(int ballHandling) => model.playerTurnoverHazards(
        offense: offenseOf(
          teamOnCourt(
            'home',
            overrides: {
              Position.pg: attrs(
                ballHandling: ballHandling,
                passing: 0,
                basketballIQ: 0,
              ),
            },
          ).lineup,
        ),
        defense: pressure,
        phase: PhaseKind.transition,
      )[0];

      expect(hazardAt(24), 2500);
      expect(hazardAt(25), lessThan(2500));
      expect(hazardAt(1), 2500);
    });
  });

  group('team hazard and actor posterior', () {
    final offense = teamOnCourt('home');
    final defense = teamOnCourt('away');

    test('H is the integer floor of the exposure-weighted mixture', () {
      final exposure = model.exposureWeights(offense.lineup);
      final hazards = model.playerTurnoverHazards(
        offense: offense,
        defense: defense,
        phase: PhaseKind.halfCourt,
      );
      var sum = 0;
      for (var i = 0; i < exposure.length; i++) {
        sum += exposure[i] * hazards[i];
      }
      final expected = sum ~/ 10000;
      final actual = model.turnoverBasisPoints(
        offense: offense,
        defense: defense,
        phase: PhaseKind.halfCourt,
      );
      expect(actual, inInclusiveRange(150, 2500));
      expect(actual, expected.clamp(150, 2500));
      expect((sum - expected * 10000).abs(), lessThan(10000));
    });

    test('category windows stay inside the draw domain', () {
      for (final phase in PhaseKind.values) {
        final turnover = model.turnoverBasisPoints(
          offense: offense,
          defense: defense,
          phase: phase,
        );
        final offensiveFoul = model.offensiveFoulBasisPoints(
          offense: offense,
          defense: defense,
        );
        final nonShooting = model.nonShootingFoulBasisPoints(
          offense: offense,
          defense: defense,
        );
        expect(turnover, lessThanOrEqualTo(2500));
        expect(offensiveFoul + nonShooting, lessThanOrEqualTo(3200));
        expect(turnover + offensiveFoul + nonShooting, lessThan(10000));
      }
    });

    test('actor weights are positive, normalized and respond to security', () {
      final weights = model.turnoverActorWeights(
        offense: offense,
        defense: defense,
        phase: PhaseKind.halfCourt,
      );
      expect(weights.reduce((a, b) => a + b), 10000);
      expect(weights.every((weight) => weight >= 1), isTrue);

      final secure = model.turnoverActorWeights(
        offense: teamOnCourt(
          'home',
          overrides: {Position.pg: attrs(ballHandling: 92)},
        ),
        defense: defense,
        phase: PhaseKind.halfCourt,
      );
      expect(secure[0], lessThan(weights[0]));
    });

    test('higher involvement can raise crediting while hazard falls', () {
      final lowUsage = model.turnoverActorWeights(
        offense: offense,
        defense: defense,
        phase: PhaseKind.halfCourt,
      );
      final lowUsageHazard = model.playerTurnoverHazards(
        offense: offense,
        defense: defense,
        phase: PhaseKind.halfCourt,
      );
      final morePassing = teamOnCourt(
        'home',
        overrides: {Position.c: attrs(passing: 90, basketballIQ: 90)},
      );
      final weights = model.turnoverActorWeights(
        offense: morePassing,
        defense: defense,
        phase: PhaseKind.halfCourt,
      );
      final hazards = model.playerTurnoverHazards(
        offense: morePassing,
        defense: defense,
        phase: PhaseKind.halfCourt,
      );
      expect(hazards[4], lessThan(lowUsageHazard[4]));
      expect(weights[4], greaterThan(lowUsage[4]));
    });
  });

  group('draw schedule and integration', () {
    test('live turnover consumes category, actor, steal-share draws', () {
      var turnovers = 0;
      for (var seed = 1; seed <= 40; seed++) {
        final replay = DeterministicRandom(seed);
        final category = replay.nextInt(10000);
        final turnover = model.turnoverBasisPoints(
          offense: teamOnCourt('home'),
          defense: teamOnCourt('away'),
          phase: PhaseKind.halfCourt,
        );
        if (category >= turnover) continue;
        turnovers++;
        final actorDraw = replay.nextInt(10000);
        final weights = model.turnoverActorWeights(
          offense: teamOnCourt('home'),
          defense: teamOnCourt('away'),
          phase: PhaseKind.halfCourt,
        );
        var cumulative = 0;
        var expectedIndex = weights.length - 1;
        for (var i = 0; i < weights.length; i++) {
          cumulative += weights[i];
          if (actorDraw < cumulative) {
            expectedIndex = i;
            break;
          }
        }
        final action =
            model.selectAction(
                  offense: teamOnCourt('home'),
                  defense: teamOnCourt('away'),
                  phase: PhaseKind.halfCourt,
                  rng: DeterministicRandom(seed),
                )
                as TurnoverAction;
        expect(
          action.playerId.value,
          'home-${Position.values[expectedIndex].shortName}',
        );
      }
      expect(turnovers, greaterThan(0));
    });

    test('full game replays, reconciles and keeps v2 accounting intact', () {
      final input = buildInput(seed: 42);
      final result = GameSimulator().simulate(input);
      final validated = GameEventReducer.validate(input, result.ledger);
      expect(validated.state.ended, isTrue);
      for (final team in [input.homeTeamId, input.awayTeamId]) {
        final box = result.boxScore.teams[team.value]!;
        var playerTurnovers = 0;
        for (final player in input.lineupFor(team).players) {
          playerTurnovers +=
              result.boxScore.players[player.id.value]!.turnovers;
        }
        expect(playerTurnovers, box.turnovers);
      }
      final subtypeCounts = {
        TurnoverReason.steal: 0,
        TurnoverReason.nonSteal: 0,
        TurnoverReason.shotClock: 0,
        TurnoverReason.offensiveFoul: 0,
      };
      for (final turnover in result.events.whereType<Turnover>()) {
        subtypeCounts[turnover.reason] = subtypeCounts[turnover.reason]! + 1;
      }
      expect(
        subtypeCounts.values.reduce((a, b) => a + b),
        result.events.whereType<Turnover>().length,
      );
    });

    test('shot-clock and offensive-foul policies are unchanged', () {
      final input = buildInput(seed: 7);
      final result = GameSimulator().simulate(input);
      for (final turnover in result.events.whereType<Turnover>()) {
        if (turnover.reason == TurnoverReason.shotClock) {
          expect(
            turnover.playerId,
            input.lineupFor(TeamId(turnover.teamId)).players.first.id.value,
          );
          expect(turnover.stolenById, isNull);
        }
        if (turnover.reason == TurnoverReason.offensiveFoul) {
          expect(turnover.stolenById, isNull);
        }
      }
    });

    test('identical inputs stay byte-identical', () {
      final input = buildInput(seed: 42);
      final first = GameSimulator().simulate(input);
      final second = GameSimulator().simulate(input);
      expect(second.events.length, first.events.length);
      expect(second.homeScore, first.homeScore);
      expect(second.ledger.inputFingerprint, first.ledger.inputFingerprint);
    });
  });
}
