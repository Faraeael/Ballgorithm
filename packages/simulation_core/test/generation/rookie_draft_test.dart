import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

void main() {
  const service = CareerSetupService();
  const draftGen = DraftGenerator();
  const seed = 20261028;

  group('M008-T05: Opening Rookie Draft Ecosystem', () {
    late CareerSetupResult setupTanking;
    late CareerSetupResult setupPlayIn;
    late CareerSetupResult setupPlayoff;
    late CareerSetupResult setupContender;

    setUpAll(() {
      setupTanking = service.generate(
        const CareerSetupRequest(
          selectedTeamId: TeamId('team-1'),
          selectedSituation: FranchiseSituation.tanking,
          seed: seed,
        ),
      );
      setupPlayIn = service.generate(
        const CareerSetupRequest(
          selectedTeamId: TeamId('team-2'),
          selectedSituation: FranchiseSituation.playIn,
          seed: seed,
        ),
      );
      setupPlayoff = service.generate(
        const CareerSetupRequest(
          selectedTeamId: TeamId('team-3'),
          selectedSituation: FranchiseSituation.playoff,
          seed: seed,
        ),
      );
      setupContender = service.generate(
        const CareerSetupRequest(
          selectedTeamId: TeamId('team-4'),
          selectedSituation: FranchiseSituation.contender,
          seed: seed,
        ),
      );
    });

    test('1. exactly 90 unique generated prospects with all 5 positions', () {
      final draftClass = draftGen.generateDraftClass(
        league: setupTanking.league,
        seed: seed,
      );

      expect(draftClass.length, 90);
      expect(draftClass.prospects.length, 90);

      final ids = <String>{};
      final names = <String>{};
      final ranks = <int>{};
      final positionCounts = <Position, int>{};

      for (final p in draftClass.prospects) {
        expect(
          ids.add(p.id.value),
          isTrue,
          reason: 'Duplicate ID: ${p.id.value}',
        );
        expect(
          names.add(p.fullName),
          isTrue,
          reason: 'Duplicate name: ${p.fullName}',
        );
        expect(
          ranks.add(p.projectedRank),
          isTrue,
          reason: 'Duplicate rank: ${p.projectedRank}',
        );
        positionCounts[p.position] = (positionCounts[p.position] ?? 0) + 1;
      }

      expect(ids.length, 90);
      expect(ranks, containsAll([for (var i = 1; i <= 90; i++) i]));

      for (final pos in Position.values) {
        expect(
          positionCounts[pos],
          greaterThanOrEqualTo(10),
          reason: 'Position ${pos.shortName} must be adequately represented',
        );
      }
    });

    test('2. exactly 60 unique draft selections across 2 rounds', () {
      final order = draftGen.generateDraftOrder(
        league: setupTanking.league,
        seed: seed,
        userTeamId: const TeamId('team-1'),
        userSituation: FranchiseSituation.tanking,
      );

      expect(order.totalPicks, 60);
      expect(order.round1Picks.length, 30);
      expect(order.round2Picks.length, 30);

      final overallPicks = order.picks.map((p) => p.overallPick).toSet();
      expect(overallPicks.length, 60);
      expect(overallPicks, containsAll([for (var i = 1; i <= 60; i++) i]));
    });

    test('3. exactly 30 teams represented in both rounds', () {
      final order = draftGen.generateDraftOrder(
        league: setupTanking.league,
        seed: seed,
        userTeamId: const TeamId('team-1'),
        userSituation: FranchiseSituation.tanking,
      );

      final r1Teams = order.round1Picks
          .map((p) => p.originalOwnerTeamId.value)
          .toSet();
      final r2Teams = order.round2Picks
          .map((p) => p.originalOwnerTeamId.value)
          .toSet();

      expect(r1Teams.length, 30);
      expect(r2Teams.length, 30);

      final leagueTeamIds = setupTanking.league.teams
          .map((t) => t.id.value)
          .toSet();
      expect(r1Teams, equals(leagueTeamIds));
      expect(r2Teams, equals(leagueTeamIds));

      // Round 2 mirrors Round 1 ordering initially
      for (var i = 0; i < 30; i++) {
        expect(
          order.round2Picks[i].originalOwnerTeamId,
          equals(order.round1Picks[i].originalOwnerTeamId),
        );
      }
    });

    test('4. correct guaranteed user selections for all four situations', () {
      // Tanking -> User guaranteed #1 in Round 1, #31 in Round 2
      final tankingOrder = draftGen.generateDraftOrder(
        league: setupTanking.league,
        seed: seed,
        userTeamId: const TeamId('team-1'),
        userSituation: FranchiseSituation.tanking,
      );
      expect(tankingOrder.pickAt(1).currentOwnerTeamId, const TeamId('team-1'));
      expect(
        tankingOrder.pickAt(31).currentOwnerTeamId,
        const TeamId('team-1'),
      );

      // Play-In -> User guaranteed #12 in Round 1, #42 in Round 2
      final playInOrder = draftGen.generateDraftOrder(
        league: setupPlayIn.league,
        seed: seed,
        userTeamId: const TeamId('team-2'),
        userSituation: FranchiseSituation.playIn,
      );
      expect(playInOrder.pickAt(12).currentOwnerTeamId, const TeamId('team-2'));
      expect(playInOrder.pickAt(42).currentOwnerTeamId, const TeamId('team-2'));

      // Playoff -> User guaranteed #20 in Round 1, #50 in Round 2
      final playoffOrder = draftGen.generateDraftOrder(
        league: setupPlayoff.league,
        seed: seed,
        userTeamId: const TeamId('team-3'),
        userSituation: FranchiseSituation.playoff,
      );
      expect(
        playoffOrder.pickAt(20).currentOwnerTeamId,
        const TeamId('team-3'),
      );
      expect(
        playoffOrder.pickAt(50).currentOwnerTeamId,
        const TeamId('team-3'),
      );

      // Contender -> User guaranteed #30 in Round 1, #60 in Round 2
      final contenderOrder = draftGen.generateDraftOrder(
        league: setupContender.league,
        seed: seed,
        userTeamId: const TeamId('team-4'),
        userSituation: FranchiseSituation.contender,
      );
      expect(
        contenderOrder.pickAt(30).currentOwnerTeamId,
        const TeamId('team-4'),
      );
      expect(
        contenderOrder.pickAt(60).currentOwnerTeamId,
        const TeamId('team-4'),
      );
    });

    test('5. deterministic generation for identical inputs', () {
      final class1 = draftGen.generateDraftClass(
        league: setupTanking.league,
        seed: seed,
      );
      final class2 = draftGen.generateDraftClass(
        league: setupTanking.league,
        seed: seed,
      );

      expect(jsonEncode(class1.toJson()), equals(jsonEncode(class2.toJson())));

      final order1 = draftGen.generateDraftOrder(
        league: setupTanking.league,
        seed: seed,
        userTeamId: const TeamId('team-1'),
        userSituation: FranchiseSituation.tanking,
      );
      final order2 = draftGen.generateDraftOrder(
        league: setupTanking.league,
        seed: seed,
        userTeamId: const TeamId('team-1'),
        userSituation: FranchiseSituation.tanking,
      );

      expect(jsonEncode(order1.toJson()), equals(jsonEncode(order2.toJson())));
    });

    test(
      '6. different valid career seeds produce different prospect classes',
      () {
        final classA = draftGen.generateDraftClass(
          league: setupTanking.league,
          seed: 11111,
        );
        final classB = draftGen.generateDraftClass(
          league: setupTanking.league,
          seed: 99999,
        );

        expect(
          classA.rankedFirst.fullName,
          isNot(equals(classB.rankedFirst.fullName)),
        );
        expect(
          classA.prospects.map((p) => p.fullName).toList(),
          isNot(equals(classB.prospects.map((p) => p.fullName).toList())),
        );
      },
    );

    test('7. prospect ratings conform to existing simulation model', () {
      final draftClass = draftGen.generateDraftClass(
        league: setupTanking.league,
        seed: seed,
      );

      for (final p in draftClass.prospects) {
        expect(p.age, inInclusiveRange(19, 22));
        final attrs = p.attributes;

        for (final entry in attrs.asMap.entries) {
          expect(entry.value, inInclusiveRange(0, 100));
        }

        final sum = attrs.asMap.values.fold(0, (a, b) => a + b);
        final expectedOverall = (sum / 12).round();
        expect(p.overallRating, equals(expectedOverall));

        // Potential ceiling invariant: must be >= overall and <= 100
        expect(p.potential, greaterThanOrEqualTo(p.overallRating));
        expect(p.potential, lessThanOrEqualTo(100));
      }
    });

    test(
      '8. projected ranking is not identical to sorting by hidden true potential',
      () {
        final draftClass = draftGen.generateDraftClass(
          league: setupTanking.league,
          seed: seed,
        );

        final ranksByProjected = draftClass.prospects
            .map((p) => p.id.value)
            .toList();

        final sortedByPotential = List<RookieProspect>.from(
          draftClass.prospects,
        )..sort((a, b) => b.potential.compareTo(a.potential));
        final ranksByPotential = sortedByPotential
            .map((p) => p.id.value)
            .toList();

        // Imperfect scouting evaluation guarantees ranking uncertainty
        expect(
          ranksByProjected,
          isNot(equals(ranksByPotential)),
          reason:
              'Projected ranking must not perfectly mirror hidden potential sorting',
        );

        // Verify presence of high-potential projects and underrated/overrated prospects
        final projects = draftClass.prospects.where(
          (p) => p.projectedRank > 15 && p.potential >= 82,
        );
        expect(
          projects.isNotEmpty,
          isTrue,
          reason: 'Must have high-potential sleeper projects',
        );

        final overrated = draftClass.prospects.where(
          (p) => p.projectedRank <= 10 && p.potential < 80,
        );
        final underrated = draftClass.prospects.where(
          (p) => p.projectedRank >= 30 && p.potential >= 78,
        );
        expect(
          overrated.isNotEmpty || underrated.isNotEmpty,
          isTrue,
          reason:
              'Scouting noise must create realistic draft evaluation variance',
        );
      },
    );

    test('9. prospect IDs never collide with existing league player IDs', () {
      final leaguePlayerIds = {
        for (final team in setupTanking.league.teams)
          for (final player in team.players) player.id.value,
      };

      final draftClass = draftGen.generateDraftClass(
        league: setupTanking.league,
        seed: seed,
      );

      for (final p in draftClass.prospects) {
        expect(
          leaguePlayerIds.contains(p.id.value),
          isFalse,
          reason:
              'Prospect ID ${p.id.value} must not collide with league player IDs',
        );
      }
    });

    test('10. save/load preserves full class and order', () {
      final career = GmCareer.fromSetupResult(setupTanking);
      final encoded = GmCareerCodec.encode(career);
      final decoded = GmCareerCodec.decode(encoded);

      expect(decoded.schemaVersion, GmCareer.currentSchemaVersion);
      expect(decoded.draftOrder.totalPicks, 60);
      expect(decoded.draftClass.length, 90);

      // Verify all 60 picks match exactly
      for (var i = 0; i < 60; i++) {
        final origPick = career.draftOrder.picks[i];
        final decPick = decoded.draftOrder.picks[i];
        expect(decPick.round, origPick.round);
        expect(decPick.pickInRound, origPick.pickInRound);
        expect(decPick.overallPick, origPick.overallPick);
        expect(decPick.originalOwnerTeamId, origPick.originalOwnerTeamId);
        expect(decPick.currentOwnerTeamId, origPick.currentOwnerTeamId);
      }

      // Verify all 90 prospects match exactly
      for (var i = 0; i < 90; i++) {
        final origP = career.draftClass.prospects[i];
        final decP = decoded.draftClass.prospects[i];
        expect(decP.id, origP.id);
        expect(decP.fullName, origP.fullName);
        expect(decP.position, origP.position);
        expect(decP.age, origP.age);
        expect(decP.overallRating, origP.overallRating);
        expect(decP.potential, origP.potential);
        expect(decP.trajectory, origP.trajectory);
        expect(decP.projectedRank, origP.projectedRank);
        expect(decP.estimatedPotentialGrade, origP.estimatedPotentialGrade);
        expect(decP.estimatedPotentialRange, origP.estimatedPotentialRange);
      }
    });

    test(
      '11. v1-to-v2 migration preserves existing career data and synthesizes draft class',
      () {
        final careerV2 = GmCareer.fromSetupResult(setupTanking);
        final v2Map =
            jsonDecode(GmCareerCodec.encode(careerV2)) as Map<String, dynamic>;

        // Synthesize a valid v1 JSON by stripping draftOrder and draftClass and setting schemaVersion to 1
        final v1Map = Map<String, dynamic>.from(v2Map)
          ..['schemaVersion'] = 1
          ..remove('draftOrder')
          ..remove('draftClass');

        final v1Json = jsonEncode(v1Map);

        // Decode v1 string
        final migratedCareer = GmCareerCodec.decode(v1Json);

        // Verify migration preserves all original data
        expect(migratedCareer.schemaVersion, GmCareer.currentSchemaVersion);
        expect(migratedCareer.id, careerV2.id);
        expect(migratedCareer.generationSeed, careerV2.generationSeed);
        expect(migratedCareer.userFranchiseId, careerV2.userFranchiseId);
        expect(migratedCareer.originalSituation, careerV2.originalSituation);
        expect(migratedCareer.currentYear, careerV2.currentYear);
        expect(migratedCareer.phase, careerV2.phase);
        expect(
          migratedCareer.userOpeningDraftPick,
          careerV2.userOpeningDraftPick,
        );
        expect(migratedCareer.league.teams.length, 30);
        expect(migratedCareer.careerProfiles.length, 360);

        // Verify synthesized draft order and class
        expect(migratedCareer.draftOrder.totalPicks, 60);
        expect(migratedCareer.draftClass.length, 90);
        expect(
          migratedCareer.draftOrder.pickAt(1).currentOwnerTeamId,
          careerV2.userFranchiseId,
        );

        // Re-encoding v2 preserves synthesized draft data
        final reEncoded = GmCareerCodec.encode(migratedCareer);
        final reDecoded = GmCareerCodec.decode(reEncoded);
        expect(
          reDecoded.draftClass.rankedFirst.fullName,
          equals(migratedCareer.draftClass.rankedFirst.fullName),
        );
      },
    );
  });
}
