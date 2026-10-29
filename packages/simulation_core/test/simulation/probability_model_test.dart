import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'probability_support.dart';

void main() {
  final model = BasketballProbabilityModel();
  final offense = teamOnCourt('home');
  final defense = teamOnCourt('away');

  group('A1 phase duration', () {
    test('uses the approved weights and brackets', () {
      expect(GameRules.standard.phaseWeights, [1500, 3000, 5500]);
      expect(GameRules.standard.phaseDurations, [
        [2, 7],
        [5, 11],
        [10, 22],
      ]);
    });

    test('phase types land near the approved distribution', () {
      final rng = DeterministicRandom(7);
      final counts = {for (final kind in PhaseKind.values) kind: 0};
      const draws = 10000;
      for (var i = 0; i < draws; i++) {
        final phase = model.drawPhaseDuration(rng);
        counts[phase.kind] = counts[phase.kind]! + 1;
      }
      expect(counts[PhaseKind.transition]! / draws, closeTo(0.15, 0.02));
      expect(counts[PhaseKind.earlyOffense]! / draws, closeTo(0.30, 0.02));
      expect(counts[PhaseKind.halfCourt]! / draws, closeTo(0.55, 0.02));
    });

    test('durations stay inside their bracket and hit both bounds', () {
      final rng = DeterministicRandom(20261029);
      final seenMin = {for (final kind in PhaseKind.values) kind: 1 << 30};
      final seenMax = {for (final kind in PhaseKind.values) kind: 0};
      for (var i = 0; i < 6000; i++) {
        final phase = model.drawPhaseDuration(rng);
        final bracket = GameRules.standard.phaseDurations[phase.kind.index];
        expect(phase.seconds, inInclusiveRange(bracket[0], bracket[1]));
        if (phase.seconds < seenMin[phase.kind]!) {
          seenMin[phase.kind] = phase.seconds;
        }
        if (phase.seconds > seenMax[phase.kind]!) {
          seenMax[phase.kind] = phase.seconds;
        }
      }
      for (final kind in PhaseKind.values) {
        final bracket = GameRules.standard.phaseDurations[kind.index];
        expect(seenMin[kind], bracket[0], reason: '${kind.name} minimum');
        expect(seenMax[kind], bracket[1], reason: '${kind.name} maximum');
      }
    });

    test('consumes exactly the type draw then the offset draw', () {
      for (final seed in [1, 2, 3, 42, 999, 20261029]) {
        final replay = DeterministicRandom(seed);
        final typeDraw = replay.nextInt(10000);
        final index = typeDraw < 1500
            ? PhaseKind.transition.index
            : (typeDraw < 4500
                  ? PhaseKind.earlyOffense.index
                  : PhaseKind.halfCourt.index);
        final bracket = GameRules.standard.phaseDurations[index];
        final offset = replay.nextInt(bracket[1] - bracket[0] + 1);
        final expected = bracket[0] + offset;

        final actual = model.drawPhaseDuration(DeterministicRandom(seed));
        expect(actual.kind.index, index, reason: 'seed $seed');
        expect(actual.seconds, expected, reason: 'seed $seed');
      }
    });
  });

  group('final-tick behaviour', () {
    test('consumes no A1 or category draws', () {
      for (final seed in [1, 2, 3, 7, 42, 999]) {
        final action = model.selectFinalTickAction(
          offense: offense,
          defense: defense,
          rng: DeterministicRandom(seed),
        );

        final replay = DeterministicRandom(seed);
        final usage = model.shotUsageWeights(offense.lineup);
        final shooterIndex = indexForDraw(usage, replay.nextInt(10000));
        final expectedShooter = offense.lineup.players[shooterIndex];
        expect(action.shooterId, expectedShooter.id, reason: 'seed $seed');

        final zoneWeights = model.shotZoneWeights(
          shooter: expectedShooter,
          phase: PhaseKind.halfCourt,
        );
        final zoneDraw = replay.nextInt(10000);
        final expectedZone = zoneDraw < zoneWeights[0]
            ? ShotZone.inside
            : (zoneDraw < zoneWeights[0] + zoneWeights[1]
                  ? ShotZone.midrange
                  : ShotZone.three);
        expect(action.zone, expectedZone, reason: 'seed $seed');
        expect(action.shotValue, expectedZone.shotValue);
      }
    });
  });

  group('draw order', () {
    test('a normal action starts with the category draw', () {
      final checked = <int>[];
      for (var seed = 1; seed <= 80; seed++) {
        final replay = DeterministicRandom(seed);
        final category = replay.nextInt(10000);
        final turnover = model.turnoverBasisPoints(
          offense: offense,
          defense: defense,
          phase: PhaseKind.halfCourt,
        );
        final offensiveFoul = model.offensiveFoulBasisPoints(
          offense: offense,
          defense: defense,
        );
        final nonShootingFoul = model.nonShootingFoulBasisPoints(
          offense: offense,
          defense: defense,
        );
        if (category < turnover + offensiveFoul + nonShootingFoul) continue;

        final action =
            model.selectAction(
                  offense: offense,
                  defense: defense,
                  phase: PhaseKind.halfCourt,
                  rng: DeterministicRandom(seed),
                )
                as ShotAttemptAction;

        final usage = model.shotUsageWeights(offense.lineup);
        final shooter =
            offense.lineup.players[indexForDraw(usage, replay.nextInt(10000))];
        expect(action.shooterId, shooter.id, reason: 'seed $seed');

        final zoneWeights = model.shotZoneWeights(
          shooter: shooter,
          phase: PhaseKind.halfCourt,
        );
        final zoneDraw = replay.nextInt(10000);
        final zone = zoneDraw < zoneWeights[0]
            ? ShotZone.inside
            : (zoneDraw < zoneWeights[0] + zoneWeights[1]
                  ? ShotZone.midrange
                  : ShotZone.three);
        expect(action.zone, zone, reason: 'seed $seed');

        final defender =
            defense.lineup.players[offense.lineup.players.indexOf(shooter)];
        final makeBp = model.shotMakeBasisPoints(
          shooter: shooter,
          defender: defender,
          zone: zone,
          offense: offense.lineup,
        );
        expect(action.made, replay.nextInt(10000) < makeBp);
        checked.add(seed);
      }
      expect(checked.length, greaterThan(20));
    });
  });

  group('probability bounds', () {
    test('clamp helper enforces 0..10000', () {
      expect(BasketballProbabilityModel.clampBasisPoints(-5), 0);
      expect(BasketballProbabilityModel.clampBasisPoints(10005), 10000);
      expect(BasketballProbabilityModel.clampBasisPoints(1234), 1234);
      expect(
        () => BasketballProbabilityModel.clampBasisPoints(5, min: 10, max: 5),
        throwsArgumentError,
      );
    });

    test('every probability stays inside 0..10000 for extreme ratings', () {
      for (final value in [0, 50, 100]) {
        final extreme = attrs(
          insideScoring: value,
          midrange: value,
          threePoint: value,
          freeThrow: value,
          passing: value,
          ballHandling: value,
          perimeterDefense: value,
          interiorDefense: value,
          rebounding: value,
          athleticism: value,
          basketballIQ: value,
        );
        final shooter = playerOf(Position.pg, attributes: extreme);
        final defender = playerOf(
          Position.pg,
          attributes: extreme,
          teamPrefix: 'away',
        );
        final lineup = lineupOf(
          overrides: {
            for (final position in Position.values) position: extreme,
          },
        );
        final squad = TeamOnCourt(teamId: const TeamId('home'), lineup: lineup);
        final opposing = teamOnCourt('away');
        final probabilities = <int>[
          model.freeThrowMakeBasisPoints(shooter),
          model.assistBasisPoints(lineup),
          model.shootingFoulBasisPoints(shooter: shooter, defender: defender),
          model.andOneBasisPoints(shooter: shooter, defender: defender),
          for (final zone in ShotZone.values)
            model.shotMakeBasisPoints(
              shooter: shooter,
              defender: defender,
              zone: zone,
              offense: lineup,
            ),
          for (final zone in ShotZone.values)
            model.blockBasisPoints(
              shooter: shooter,
              defender: defender,
              zone: zone,
            ),
          model.turnoverBasisPoints(
            offense: squad,
            defense: opposing,
            phase: PhaseKind.halfCourt,
          ),
          model.stealShareBasisPoints(ballhandler: shooter, defense: opposing),
          model.offensiveFoulBasisPoints(offense: squad, defense: opposing),
          model.nonShootingFoulBasisPoints(offense: squad, defense: opposing),
          model.offensiveReboundBasisPoints(
            offense: squad,
            defense: opposing,
            zone: ShotZone.three,
          ),
        ];
        for (final bp in probabilities) {
          expect(bp, inInclusiveRange(0, 10000));
          expect(bp, isA<int>());
        }
      }
    });
  });

  group('determinism', () {
    test('identical seed and input reproduce identical decisions', () {
      for (final seed in [1, 2, 3, 42, 20261029]) {
        final first = model.selectAction(
          offense: offense,
          defense: defense,
          phase: PhaseKind.transition,
          rng: DeterministicRandom(seed),
        );
        final second = BasketballProbabilityModel().selectAction(
          offense: offense,
          defense: defense,
          phase: PhaseKind.transition,
          rng: DeterministicRandom(seed),
        );
        expect(_describe(first), _describe(second));
        expect(
          _describeRebound(
            model.resolveRebound(
              offense: offense,
              defense: defense,
              zone: ShotZone.midrange,
              rng: DeterministicRandom(seed),
            ),
          ),
          _describeRebound(
            model.resolveRebound(
              offense: offense,
              defense: defense,
              zone: ShotZone.midrange,
              rng: DeterministicRandom(seed),
            ),
          ),
        );
      }
    });
  });

  group('shooter usage', () {
    test('stronger offensive players receive a larger usage share', () {
      final balanced = model.shotUsageWeights(offense.lineup);
      expect(balanced.fold(0, (a, b) => a + b), 10000);
      expect(balanced[0], greaterThan(balanced[4]));

      final star = lineupOf(
        overrides: {
          Position.pg: attrs(
            insideScoring: 100,
            threePoint: 100,
            ballHandling: 100,
            basketballIQ: 100,
          ),
        },
      );
      final weights = model.shotUsageWeights(star);
      expect(weights.fold(0, (a, b) => a + b), 10000);
      expect(weights[0], greaterThan(balanced[0]));
      expect(weights[0], lessThan(6000), reason: 'no automatic monopoly');
    });

    test('no single player monopolizes aggregate shot selection', () {
      final starSquad = teamOnCourt(
        'home',
        overrides: {
          Position.pg: attrs(
            insideScoring: 100,
            threePoint: 100,
            ballHandling: 100,
            basketballIQ: 100,
          ),
        },
      );
      final counts = <String, int>{};
      for (var seed = 1; seed <= 100; seed++) {
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < 20; i++) {
          final action = model.selectAction(
            offense: starSquad,
            defense: defense,
            phase: PhaseKind.halfCourt,
            rng: rng,
          );
          final actor = action is ShotAttemptAction
              ? action.shooterId.value
              : (action is TurnoverAction ? action.playerId.value : 'none');
          counts[actor] = (counts[actor] ?? 0) + 1;
        }
      }
      final pgShots = counts['home-PG'] ?? 0;
      final total = counts.values.fold(0, (a, b) => a + b);
      expect(pgShots / total, greaterThan(0.2));
      expect(pgShots / total, lessThan(0.6));
      expect(counts.keys.where((id) => id.startsWith('home-')).length, 5);
    });
  });

  group('shot-zone selection', () {
    test('midrange rating drives midrange selection', () {
      final cold = model.shotZoneWeights(
        shooter: playerOf(Position.sg, attributes: attrs(midrange: 0)),
        phase: PhaseKind.halfCourt,
      );
      final hot = model.shotZoneWeights(
        shooter: playerOf(Position.sg, attributes: attrs(midrange: 100)),
        phase: PhaseKind.halfCourt,
      );
      expect(cold.fold(0, (a, b) => a + b), 10000);
      expect(hot[1], greaterThan(cold[1]));
    });

    test('three-point rating drives three-point selection', () {
      final cold = model.shotZoneWeights(
        shooter: playerOf(Position.pg, attributes: attrs(threePoint: 0)),
        phase: PhaseKind.halfCourt,
      );
      final hot = model.shotZoneWeights(
        shooter: playerOf(Position.pg, attributes: attrs(threePoint: 100)),
        phase: PhaseKind.halfCourt,
      );
      expect(hot[2], greaterThan(cold[2]));
    });

    test('position changes the zone mix', () {
      final guard = model.shotZoneWeights(
        shooter: playerOf(Position.pg),
        phase: PhaseKind.halfCourt,
      );
      final center = model.shotZoneWeights(
        shooter: playerOf(Position.c),
        phase: PhaseKind.halfCourt,
      );
      expect(center[0], greaterThan(guard[0]));
      expect(guard[2], greaterThan(center[2]));
    });

    test('aggregate three-point attempts rise with threePoint rating', () {
      final cold = teamOnCourt(
        'home',
        overrides: {Position.pg: attrs(threePoint: 0)},
      );
      final hot = teamOnCourt(
        'home',
        overrides: {Position.pg: attrs(threePoint: 100)},
      );
      int threes(TeamOnCourt squad) {
        var count = 0;
        for (var seed = 1; seed <= 100; seed++) {
          final rng = DeterministicRandom(seed);
          for (var i = 0; i < 20; i++) {
            final action = model.selectFinalTickAction(
              offense: squad,
              defense: defense,
              rng: rng,
            );
            if (action.zone == ShotZone.three) count++;
          }
        }
        return count;
      }

      expect(threes(hot), greaterThan(threes(cold)));
    });
  });

  group('conversion and defence', () {
    test('zone ratings and defender ratings move conversion', () {
      final shooter = playerOf(Position.sg, attributes: attrs(threePoint: 80));
      final weak = playerOf(
        Position.sg,
        attributes: attrs(perimeterDefense: 0),
        teamPrefix: 'away',
      );
      final strong = playerOf(
        Position.sg,
        attributes: attrs(perimeterDefense: 100),
        teamPrefix: 'away',
      );
      int three(Player defender, Player shooter) => model.shotMakeBasisPoints(
        shooter: shooter,
        defender: defender,
        zone: ShotZone.three,
        offense: lineupOf(),
      );

      expect(
        three(weak, playerOf(Position.sg, attributes: attrs(threePoint: 100))),
        greaterThan(
          three(weak, playerOf(Position.sg, attributes: attrs(threePoint: 0))),
        ),
      );
      expect(three(strong, shooter), lessThan(three(weak, shooter)));
    });

    test('interior defence resists inside shots and raises blocks', () {
      final shooter = playerOf(
        Position.c,
        attributes: attrs(insideScoring: 80),
      );
      final soft = playerOf(
        Position.c,
        attributes: attrs(interiorDefense: 0),
        teamPrefix: 'away',
      );
      final wall = playerOf(
        Position.c,
        attributes: attrs(interiorDefense: 100),
        teamPrefix: 'away',
      );
      int rim(Player defender) => model.shotMakeBasisPoints(
        shooter: shooter,
        defender: defender,
        zone: ShotZone.inside,
        offense: lineupOf(),
      );

      expect(rim(wall), lessThan(rim(soft)));
      expect(
        model.blockBasisPoints(
          shooter: shooter,
          defender: wall,
          zone: ShotZone.inside,
        ),
        greaterThan(
          model.blockBasisPoints(
            shooter: shooter,
            defender: soft,
            zone: ShotZone.inside,
          ),
        ),
      );
    });

    test(
      'aggregate opponent conversion falls against better perimeter defence',
      () {
        final shooterSquad = teamOnCourt('home');
        final soft = teamOnCourt('away');
        final strong = teamOnCourt(
          'away',
          overrides: {
            for (final position in Position.values)
              position: attrs(perimeterDefense: 90),
          },
        );
        (int, int) threePointShooting(TeamOnCourt defenders) {
          var attempts = 0;
          var makes = 0;
          for (var seed = 1; seed <= 100; seed++) {
            final rng = DeterministicRandom(seed);
            for (var i = 0; i < 20; i++) {
              final action = model.selectFinalTickAction(
                offense: shooterSquad,
                defense: defenders,
                rng: rng,
              );
              if (action.zone != ShotZone.three) continue;
              attempts++;
              if (action.made) makes++;
            }
          }
          return (attempts, makes);
        }

        final (softAttempts, softMakes) = threePointShooting(soft);
        final (strongAttempts, strongMakes) = threePointShooting(strong);
        expect(softAttempts, greaterThan(100));
        expect(strongAttempts, greaterThan(100));
        expect(
          softMakes / softAttempts,
          greaterThan(strongMakes / strongAttempts),
        );
      },
    );
  });

  group('turnovers', () {
    test('every turnover belongs to an active offensive player', () {
      final samples = <TurnoverAction>[];
      for (var seed = 1; seed <= 200; seed++) {
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < 20; i++) {
          final action = model.selectAction(
            offense: offense,
            defense: defense,
            phase: PhaseKind.halfCourt,
            rng: rng,
          );
          if (action is TurnoverAction) samples.add(action);
        }
      }
      expect(samples, isNotEmpty);
      final homeIds = {for (final p in offense.lineup.players) p.id.value};
      final awayIds = {for (final p in defense.lineup.players) p.id.value};
      for (final turnover in samples) {
        expect(homeIds, contains(turnover.playerId.value));
        if (turnover.kind == TurnoverKind.steal) {
          expect(turnover.stolenById, isNotNull);
          expect(awayIds, contains(turnover.stolenById!.value));
        } else {
          expect(turnover.stolenById, isNull);
        }
      }
      expect(samples.where((s) => s.kind == TurnoverKind.steal), isNotEmpty);
      expect(samples.where((s) => s.kind == TurnoverKind.nonSteal), isNotEmpty);
    });

    test('ball security lowers turnover probability and steal share', () {
      final careless = playerOf(
        Position.pg,
        attributes: attrs(ballHandling: 0, passing: 0, basketballIQ: 0),
      );
      final careful = playerOf(
        Position.pg,
        attributes: attrs(ballHandling: 100, passing: 100, basketballIQ: 100),
      );
      final sloppySquad = teamOnCourt(
        'home',
        overrides: {
          for (final position in Position.values)
            position: attrs(ballHandling: 0, passing: 0, basketballIQ: 0),
        },
      );
      final tidySquad = teamOnCourt(
        'home',
        overrides: {
          for (final position in Position.values)
            position: attrs(ballHandling: 100, passing: 100, basketballIQ: 100),
        },
      );
      expect(
        model.turnoverBasisPoints(
          offense: tidySquad,
          defense: defense,
          phase: PhaseKind.halfCourt,
        ),
        lessThan(
          model.turnoverBasisPoints(
            offense: sloppySquad,
            defense: defense,
            phase: PhaseKind.halfCourt,
          ),
        ),
      );
      expect(
        model.stealShareBasisPoints(ballhandler: careful, defense: defense),
        lessThan(
          model.stealShareBasisPoints(ballhandler: careless, defense: defense),
        ),
      );
    });
  });

  group('fouls', () {
    test(
      'shooting, and-one, offensive and non-shooting fouls are representable',
      () {
        final shootingFouls = <ShotAttemptAction>[];
        final andOnes = <ShotAttemptAction>[];
        final offensiveFouls = <OffensiveFoulAction>[];
        final nonShootingFouls = <NonShootingFoulAction>[];
        final homeIds = {for (final p in offense.lineup.players) p.id.value};
        final awayIds = {for (final p in defense.lineup.players) p.id.value};

        for (var seed = 1; seed <= 300; seed++) {
          final rng = DeterministicRandom(seed);
          for (var i = 0; i < 20; i++) {
            final action = model.selectAction(
              offense: offense,
              defense: defense,
              phase: PhaseKind.halfCourt,
              rng: rng,
            );
            if (action is ShotAttemptAction) {
              if (!action.made && action.freeThrowsAwarded > 0) {
                shootingFouls.add(action);
              }
              if (action.made && action.andOne) andOnes.add(action);
            } else if (action is OffensiveFoulAction) {
              offensiveFouls.add(action);
            } else if (action is NonShootingFoulAction) {
              nonShootingFouls.add(action);
            }
          }
        }

        expect(shootingFouls, isNotEmpty);
        for (final shot in shootingFouls) {
          expect(shot.made, isFalse);
          expect(shot.freeThrowsAwarded, shot.zone.shotValue);
          expect(shot.foulingDefenderId, isNotNull);
          expect(awayIds, contains(shot.foulingDefenderId!.value));
          expect(homeIds, contains(shot.shooterId.value));
        }

        expect(andOnes, isNotEmpty);
        for (final shot in andOnes) {
          expect(shot.made, isTrue);
          expect(shot.freeThrowsAwarded, 1);
          expect(shot.foulingDefenderId, isNotNull);
        }

        expect(offensiveFouls, isNotEmpty);
        for (final foul in offensiveFouls) {
          expect(homeIds, contains(foul.playerId.value));
          expect(awayIds, contains(foul.victimId.value));
        }

        expect(nonShootingFouls, isNotEmpty);
        for (final foul in nonShootingFouls) {
          expect(awayIds, contains(foul.committingPlayerId.value));
          expect(homeIds, contains(foul.drawnByPlayerId.value));
        }
      },
    );
  });

  group('free throws', () {
    test('freeThrow rating drives accuracy', () {
      final poor = playerOf(Position.c, attributes: attrs(freeThrow: 0));
      final elite = playerOf(Position.c, attributes: attrs(freeThrow: 100));
      expect(model.freeThrowMakeBasisPoints(poor), 2750);
      expect(model.freeThrowMakeBasisPoints(elite), 9250);

      final poorSquad = teamOnCourt(
        'home',
        overrides: {Position.c: attrs(freeThrow: 0)},
      );
      final eliteSquad = teamOnCourt(
        'home',
        overrides: {Position.c: attrs(freeThrow: 100)},
      );
      int madeFor(TeamOnCourt squad) {
        var total = 0;
        for (var seed = 1; seed <= 100; seed++) {
          final group = model.resolveFreeThrows(
            offense: squad,
            shooter: squad.lineup.players[4],
            attempts: 2,
            rng: DeterministicRandom(seed),
          );
          total += group.madeCount;
        }
        return total;
      }

      expect(madeFor(eliteSquad), greaterThan(madeFor(poorSquad)));
    });

    test('group results are typed and bounded', () {
      final group = model.resolveFreeThrows(
        offense: offense,
        shooter: offense.lineup.players[0],
        attempts: 3,
        rng: DeterministicRandom(11),
      );
      expect(group.attempts, 3);
      expect(group.madeByAttempt.length, 3);
      expect(group.madeCount, inInclusiveRange(0, 3));
      expect(group.shooterId, offense.lineup.players[0].id);
    });
  });

  group('rebounds', () {
    test('resolves one team and one active rebounder', () {
      var offensive = 0;
      for (var seed = 1; seed <= 200; seed++) {
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < 20; i++) {
          final rebound = model.resolveRebound(
            offense: offense,
            defense: defense,
            zone: ShotZone.midrange,
            rng: rng,
          );
          final side = rebound.offensive ? offense : defense;
          expect(rebound.teamId, side.teamId);
          expect(side.lineup.playerIds, contains(rebound.playerId.value));
          expect(rebound.continuesPossession, rebound.offensive);
          if (rebound.offensive) offensive++;
        }
      }
      final share = offensive / 4000;
      expect(share, inInclusiveRange(0.05, 0.6));
    });

    test('rebounding strength shifts the offensive share', () {
      final strongOffense = teamOnCourt(
        'home',
        overrides: {
          for (final position in Position.values)
            position: attrs(rebounding: 100, athleticism: 100),
        },
      );
      final weakOffense = teamOnCourt(
        'home',
        overrides: {
          for (final position in Position.values)
            position: attrs(rebounding: 0, athleticism: 0),
        },
      );
      expect(
        model.offensiveReboundBasisPoints(
          offense: strongOffense,
          defense: defense,
          zone: ShotZone.inside,
        ),
        greaterThan(
          model.offensiveReboundBasisPoints(
            offense: weakOffense,
            defense: defense,
            zone: ShotZone.inside,
          ),
        ),
      );
    });

    test('missed final free throw can be rebounded', () {
      final rebound = model.resolveRebound(
        offense: offense,
        defense: defense,
        rng: DeterministicRandom(5),
      );
      expect(offense.lineup.playerIds, contains(rebound.playerId.value));
    });
  });

  group('assists and blocks', () {
    test('attribution respects made/missed and team rules', () {
      var assists = 0;
      var blocks = 0;
      final awayIds = {for (final p in defense.lineup.players) p.id.value};
      for (var seed = 1; seed <= 200; seed++) {
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < 20; i++) {
          final action = model.selectFinalTickAction(
            offense: offense,
            defense: defense,
            rng: rng,
          );
          if (action.assistedById != null) {
            expect(action.made, isTrue);
            expect(action.assistedById, isNot(action.shooterId));
            expect(
              offense.lineup.playerIds,
              contains(action.assistedById!.value),
            );
            assists++;
          }
          if (action.blockedById != null) {
            expect(action.made, isFalse);
            expect(action.foulingDefenderId, isNull);
            expect(awayIds, contains(action.blockedById!.value));
            blocks++;
          }
        }
      }
      expect(assists, greaterThan(100));
      expect(blocks, greaterThan(10));
    });
  });

  group('actor validation', () {
    test('rejects an inactive free-throw shooter', () {
      final foreign = playerOf(Position.pg, teamPrefix: 'foreign');
      expect(
        () => model.resolveFreeThrows(
          offense: offense,
          shooter: foreign,
          attempts: 2,
          rng: DeterministicRandom(1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid award sizes', () {
      expect(
        () => model.resolveFreeThrows(
          offense: offense,
          shooter: offense.lineup.players[0],
          attempts: 0,
          rng: DeterministicRandom(1),
        ),
        throwsArgumentError,
      );
      expect(
        () => model.resolveFreeThrows(
          offense: offense,
          shooter: offense.lineup.players[0],
          attempts: 4,
          rng: DeterministicRandom(1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('extreme ratings', () {
    test('all-zero and all-100 squads stay valid and bounded', () {
      for (final value in [0, 100]) {
        final overrides = {
          for (final position in Position.values)
            position: attrs(
              insideScoring: value,
              midrange: value,
              threePoint: value,
              freeThrow: value,
              passing: value,
              ballHandling: value,
              perimeterDefense: value,
              interiorDefense: value,
              rebounding: value,
              athleticism: value,
              basketballIQ: value,
            ),
        };
        final squad = teamOnCourt('home', overrides: overrides);
        final defending = teamOnCourt('away', overrides: overrides);
        final rng = DeterministicRandom(value + 1);
        for (var i = 0; i < 200; i++) {
          final action = model.selectAction(
            offense: squad,
            defense: defending,
            phase: PhaseKind.halfCourt,
            rng: rng,
          );
          if (action is ShotAttemptAction) {
            expect(action.shotValue, inInclusiveRange(2, 3));
            expect(action.freeThrowsAwarded, inInclusiveRange(0, 3));
          }
          final rebound = model.resolveRebound(
            offense: squad,
            defense: defending,
            zone: ShotZone.inside,
            rng: rng,
          );
          final winner = rebound.offensive ? squad : defending;
          expect(winner.lineup.playerIds, contains(rebound.playerId.value));
        }
        final group = model.resolveFreeThrows(
          offense: squad,
          shooter: squad.lineup.players[2],
          attempts: 3,
          rng: rng,
        );
        expect(group.madeCount, inInclusiveRange(0, 3));
      }
    });
  });

  group('steal weighting', () {
    test('positional steal bonus is guard-leaning, not block-weighted', () {
      final counts = {for (final position in Position.values) position: 0};
      for (var seed = 1; seed <= 400; seed++) {
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < 50; i++) {
          final action = model.selectAction(
            offense: offense,
            defense: defense,
            phase: PhaseKind.halfCourt,
            rng: rng,
          );
          if (action is! TurnoverAction) continue;
          if (action.kind != TurnoverKind.steal) continue;
          final position = Position.values.firstWhere(
            (candidate) =>
                defense.lineup.players[candidate.index].id == action.stolenById,
          );
          counts[position] = counts[position]! + 1;
        }
      }
      final total = counts.values.fold(0, (a, b) => a + b);
      expect(total, greaterThan(400));
      expect(counts[Position.pg]!, greaterThan(counts[Position.c]!));
      final backcourt = counts[Position.pg]! + counts[Position.sg]!;
      final frontcourt = counts[Position.pf]! + counts[Position.c]!;
      expect(backcourt, greaterThan(frontcourt));
      final share = model.stealShareBasisPoints(
        ballhandler: offense.lineup.players[0],
        defense: defense,
      );
      expect(share, inInclusiveRange(0, 10000));
    });

    test('defensive ratings raise steal activity', () {
      final weak = teamOnCourt(
        'away',
        overrides: {
          for (final position in Position.values)
            position: attrs(perimeterDefense: 30, athleticism: 30),
        },
      );
      final strong = teamOnCourt(
        'away',
        overrides: {
          for (final position in Position.values)
            position: attrs(perimeterDefense: 70, athleticism: 70),
        },
      );
      expect(
        model.stealShareBasisPoints(
          ballhandler: offense.lineup.players[0],
          defense: strong,
        ),
        greaterThan(
          model.stealShareBasisPoints(
            ballhandler: offense.lineup.players[0],
            defense: weak,
          ),
        ),
      );

      int steals(TeamOnCourt defenders) {
        var count = 0;
        for (var seed = 1; seed <= 200; seed++) {
          final rng = DeterministicRandom(seed);
          for (var i = 0; i < 50; i++) {
            final action = model.selectAction(
              offense: offense,
              defense: defenders,
              phase: PhaseKind.halfCourt,
              rng: rng,
            );
            if (action is TurnoverAction && action.kind == TurnoverKind.steal) {
              count++;
            }
          }
        }
        return count;
      }

      expect(steals(strong), greaterThan(steals(weak)));
    });

    test('seeded steal selection is deterministic', () {
      List<String> sample() {
        final rng = DeterministicRandom(20261029);
        final result = <String>[];
        for (var i = 0; i < 200; i++) {
          final action = model.selectAction(
            offense: offense,
            defense: defense,
            phase: PhaseKind.halfCourt,
            rng: rng,
          );
          if (action is TurnoverAction && action.kind == TurnoverKind.steal) {
            result.add('${action.playerId.value}->${action.stolenById!.value}');
          }
        }
        return result;
      }

      expect(sample(), sample());
    });
  });

  group('canonical free-throw identity', () {
    test('same-ID clone cannot change seeded free-throw outcomes', () {
      final squad = teamOnCourt('home');
      final canonical = squad.lineup.players[4];
      final clone = playerOf(
        Position.c,
        teamPrefix: 'home',
        attributes: attrs(freeThrow: 100),
      );
      expect(clone.id, canonical.id);

      for (final seed in [1, 2, 7, 42, 999]) {
        final actual = model.resolveFreeThrows(
          offense: squad,
          shooter: canonical,
          attempts: 3,
          rng: DeterministicRandom(seed),
        );
        final impostor = model.resolveFreeThrows(
          offense: squad,
          shooter: clone,
          attempts: 3,
          rng: DeterministicRandom(seed),
        );
        expect(impostor.madeByAttempt, actual.madeByAttempt);
        expect(impostor.shooterId, canonical.id);
      }
    });

    test('canonical lineup rating changes still move outcomes', () {
      final low = teamOnCourt(
        'home',
        overrides: {Position.c: attrs(freeThrow: 0)},
      );
      final high = teamOnCourt(
        'home',
        overrides: {Position.c: attrs(freeThrow: 100)},
      );

      int made(TeamOnCourt squad) {
        var total = 0;
        for (var seed = 1; seed <= 50; seed++) {
          total += model
              .resolveFreeThrows(
                offense: squad,
                shooter: squad.lineup.players[4],
                attempts: 2,
                rng: DeterministicRandom(seed),
              )
              .madeCount;
        }
        return total;
      }

      expect(made(high), greaterThan(made(low)));
    });

    test('resolving free throws never mutates lineup data', () {
      final squad = teamOnCourt('home');
      final before = {
        for (final player in squad.lineup.players)
          player.id.value: player.attributes.asMap,
      };
      final idsBefore = List<String>.of(squad.lineup.playerIds);
      final clone = playerOf(
        Position.c,
        teamPrefix: 'home',
        attributes: attrs(freeThrow: 100),
      );

      model.resolveFreeThrows(
        offense: squad,
        shooter: clone,
        attempts: 3,
        rng: DeterministicRandom(5),
      );

      final after = {
        for (final player in squad.lineup.players)
          player.id.value: player.attributes.asMap,
      };
      expect(after, before);
      expect(squad.lineup.playerIds, idsBefore);
    });
  });

  group('stamina', () {
    test('never affects decisions in M002', () {
      final fresh = teamOnCourt(
        'home',
        overrides: {
          for (final position in Position.values) position: attrs(stamina: 0),
        },
      );
      final tired = teamOnCourt(
        'home',
        overrides: {
          for (final position in Position.values) position: attrs(stamina: 100),
        },
      );
      expect(
        model.shotUsageWeights(fresh.lineup),
        model.shotUsageWeights(tired.lineup),
      );
      expect(
        model.turnoverBasisPoints(
          offense: fresh,
          defense: defense,
          phase: PhaseKind.halfCourt,
        ),
        model.turnoverBasisPoints(
          offense: tired,
          defense: defense,
          phase: PhaseKind.halfCourt,
        ),
      );
      for (var seed = 1; seed <= 20; seed++) {
        expect(
          _describe(
            model.selectAction(
              offense: fresh,
              defense: defense,
              phase: PhaseKind.earlyOffense,
              rng: DeterministicRandom(seed),
            ),
          ),
          _describe(
            model.selectAction(
              offense: tired,
              defense: defense,
              phase: PhaseKind.earlyOffense,
              rng: DeterministicRandom(seed),
            ),
          ),
        );
      }
    });
  });
}

String _describe(OffensiveAction action) {
  if (action is ShotAttemptAction) {
    return 'shot ${action.shooterId.value} ${action.zone.wire} '
        '${action.made} ${action.andOne} ${action.freeThrowsAwarded} '
        '${action.assistedById?.value} ${action.blockedById?.value}'
        '${action.foulingDefenderId?.value}';
  }
  if (action is TurnoverAction) {
    return 'to ${action.playerId.value} ${action.kind.wire} '
        '${action.stolenById?.value}';
  }
  if (action is OffensiveFoulAction) {
    return 'of ${action.playerId.value} ${action.victimId.value}';
  }
  if (action is NonShootingFoulAction) {
    return 'nf ${action.committingPlayerId.value} '
        '${action.drawnByPlayerId.value}';
  }
  return action.runtimeType.toString();
}

String _describeRebound(ReboundIntent rebound) =>
    '${rebound.teamId.value} ${rebound.playerId.value} ${rebound.offensive}';
