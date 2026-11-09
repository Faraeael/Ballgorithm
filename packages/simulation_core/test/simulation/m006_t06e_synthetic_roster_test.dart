import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../../tool/m006_pilot_runner.dart';

void main() {
  group('M006-T06E Synthetic Roster Verification', () {
    final baseLeague = const LeagueGenerator().generate(
      const GenerationConfig(seed: 20261028),
    );
    final synLeague = buildSyntheticStretchFiveLeague(baseLeague);

    test('exact registered attributes for Team 1 Center (player-1-8)', () {
      final team1 = synLeague.teams.firstWhere((t) => t.id.value == 'team-1');
      final c1 = team1.players.firstWhere((p) => p.id.value == 'player-1-8');

      expect(c1.position, Position.c);
      final attr = c1.attributes;
      expect(attr.insideScoring, 75);
      expect(attr.midrange, 55);
      expect(attr.threePoint, 80);
      expect(attr.freeThrow, 75);
      expect(attr.passing, 60);
      expect(attr.ballHandling, 55);
      expect(attr.perimeterDefense, 50);
      expect(attr.interiorDefense, 65);
      expect(attr.rebounding, 70);
      expect(attr.athleticism, 60);
      expect(attr.stamina, 70);
      expect(attr.basketballIQ, 62);
    });

    test('exact registered attributes for Team 2 Center (player-2-5)', () {
      final team2 = synLeague.teams.firstWhere((t) => t.id.value == 'team-2');
      final c2 = team2.players.firstWhere((p) => p.id.value == 'player-2-5');

      expect(c2.position, Position.c);
      final attr = c2.attributes;
      expect(attr.insideScoring, 70);
      expect(attr.midrange, 65);
      expect(attr.threePoint, 78);
      expect(attr.freeThrow, 75);
      expect(attr.passing, 55);
      expect(attr.ballHandling, 50);
      expect(attr.perimeterDefense, 50);
      expect(attr.interiorDefense, 65);
      expect(attr.rebounding, 70);
      expect(attr.athleticism, 65);
      expect(attr.stamina, 70);
      expect(attr.basketballIQ, 60);
    });

    test('exactly two players are modified across the entire league', () {
      var diffCount = 0;
      for (final team in synLeague.teams) {
        final baseTeam = baseLeague.teams.firstWhere(
          (t) => t.id.value == team.id.value,
        );
        for (var i = 0; i < team.players.length; i++) {
          final pSyn = team.players[i];
          final pBase = baseTeam.players[i];
          expect(pSyn.id, pBase.id);
          expect(pSyn.position, pBase.position);
          expect(pSyn.firstName, pBase.firstName);
          expect(pSyn.lastName, pBase.lastName);

          if (pSyn.attributes.toJson().toString() !=
              pBase.attributes.toJson().toString()) {
            diffCount++;
            expect(
              pSyn.id.value == 'player-1-8' || pSyn.id.value == 'player-2-5',
              isTrue,
              reason: 'Only player-1-8 and player-2-5 should be modified',
            );
          }
        }
      }
      expect(diffCount, 2);
    });

    test(
      'both modified centers start in Slot 4 (Center) in default lineups',
      () {
        final home = synLeague.teams.firstWhere((t) => t.id.value == 'team-1');
        final away = synLeague.teams.firstWhere((t) => t.id.value == 'team-2');

        final homeLineup = CourtLineup.defaultFor(home);
        final awayLineup = CourtLineup.defaultFor(away);

        expect(homeLineup.slotAt(4), Position.c);
        expect(homeLineup.playerAtSlotIndex(4).id.value, 'player-1-8');

        expect(awayLineup.slotAt(4), Position.c);
        expect(awayLineup.playerAtSlotIndex(4).id.value, 'player-2-5');
      },
    );

    test('balanced rotation plan conserves minutes for synthetic league', () {
      final home = synLeague.teams.firstWhere((t) => t.id.value == 'team-1');
      final homeLineup = CourtLineup.defaultFor(home);
      final rules = GameRules.standard;

      final targets = RotationPlan.expandPreset(
        preset: RotationPreset.balanced,
        team: home,
        lineup: homeLineup,
        rules: rules,
      );

      final totalSeconds = targets.values.reduce((a, b) => a + b);
      expect(totalSeconds, 5 * 48 * 60); // 14400 seconds
      expect(
        targets[PlayerId('player-1-8')],
        greaterThan(25 * 60),
      ); // starter minutes
    });
  });
}
