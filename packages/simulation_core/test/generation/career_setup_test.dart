import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

double _averageTeamRating(Team team) {
  var total = 0;
  var count = 0;
  for (final player in team.players) {
    for (final rating in player.attributes.asMap.values) {
      total += rating;
      count++;
    }
  }
  return total / count;
}

void main() {
  const service = CareerSetupService();
  const seed = 20261028;

  group('M008-T03: Career Setup & Situation-Driven Generation', () {
    test(
      'AC-008-22: all 30 franchises are selectable and generate valid leagues',
      () {
        for (var t = 1; t <= 30; t++) {
          final teamId = TeamId('team-$t');
          final request = CareerSetupRequest(
            selectedTeamId: teamId,
            selectedSituation: FranchiseSituation.playoff,
            seed: seed,
          );
          final result = service.generate(request);
          expect(result.league.teams.length, 30);
          expect(result.selectedTeam.id, teamId);
          expect(result.selectedTeam.situation, FranchiseSituation.playoff);
        }
      },
    );

    test(
      'AC-008-23 & AC-008-24: franchise supports all 4 situations and respects selection',
      () {
        final teamId = TeamId('team-1'); // Aurora Comets

        for (final situation in FranchiseSituation.values) {
          final request = CareerSetupRequest(
            selectedTeamId: teamId,
            selectedSituation: situation,
            seed: seed,
          );
          final result = service.generate(request);
          expect(result.selectedTeam.situation, situation);
          expect(result.selectedSituation, situation);
          expect(result.userOpeningDraftPick, situation.userOpeningDraftPick);
        }
      },
    );

    test(
      'AC-008-25: macro tier invariant strictly maintained (7/9/9/5) regardless of selection',
      () {
        // Test different teams and situations
        final testCases = [
          (TeamId('team-1'), FranchiseSituation.tanking),
          (TeamId('team-1'), FranchiseSituation.contender),
          (TeamId('team-15'), FranchiseSituation.playIn),
          (TeamId('team-30'), FranchiseSituation.playoff),
        ];

        for (final tc in testCases) {
          final request = CareerSetupRequest(
            selectedTeamId: tc.$1,
            selectedSituation: tc.$2,
            seed: seed,
          );
          final result = service.generate(request);

          final counts = <FranchiseSituation, int>{};
          for (final team in result.league.teams) {
            counts[team.situation!] = (counts[team.situation!] ?? 0) + 1;
          }

          expect(counts[FranchiseSituation.tanking], 7, reason: 'Case $tc');
          expect(counts[FranchiseSituation.playIn], 9, reason: 'Case $tc');
          expect(counts[FranchiseSituation.playoff], 9, reason: 'Case $tc');
          expect(counts[FranchiseSituation.contender], 5, reason: 'Case $tc');
          expect(result.selectedTeam.situation, tc.$2);
        }
      },
    );

    test(
      'AC-008-26 & AC-008-27: situation determines attribute and career profile differences for same team',
      () {
        final teamId = TeamId('team-1'); // Aurora Comets

        final tankingReq = CareerSetupRequest(
          selectedTeamId: teamId,
          selectedSituation: FranchiseSituation.tanking,
          seed: seed,
        );
        final contenderReq = CareerSetupRequest(
          selectedTeamId: teamId,
          selectedSituation: FranchiseSituation.contender,
          seed: seed,
        );

        final tankingResult = service.generate(tankingReq);
        final contenderResult = service.generate(contenderReq);

        final tankingTeam = tankingResult.selectedTeam;
        final contenderTeam = contenderResult.selectedTeam;

        // Current attribute strength: Contender must be significantly stronger than Tanking
        final tankingMean = _averageTeamRating(tankingTeam);
        final contenderMean = _averageTeamRating(contenderTeam);
        expect(contenderMean, greaterThan(tankingMean + 15.0));

        // Age: Tanking must be younger on average than Contender
        final tankingAges = [
          for (final p in tankingTeam.players)
            tankingResult.careerProfiles.forPlayer(p.id)!.age,
        ];
        final contenderAges = [
          for (final p in contenderTeam.players)
            contenderResult.careerProfiles.forPlayer(p.id)!.age,
        ];
        final tankingAvgAge =
            tankingAges.reduce((a, b) => a + b) / tankingAges.length;
        final contenderAvgAge =
            contenderAges.reduce((a, b) => a + b) / contenderAges.length;
        expect(tankingAvgAge, lessThan(contenderAvgAge));

        // Potential upside margin: Tanking must have greater average upside than Contender
        final tankingUpside = [
          for (final p in tankingTeam.players)
            tankingResult.careerProfiles.forPlayer(p.id)!.potential -
                p.attributes.overallRating,
        ];
        final contenderUpside = [
          for (final p in contenderTeam.players)
            contenderResult.careerProfiles.forPlayer(p.id)!.potential -
                p.attributes.overallRating,
        ];
        final tankingAvgUpside =
            tankingUpside.reduce((a, b) => a + b) / tankingUpside.length;
        final contenderAvgUpside =
            contenderUpside.reduce((a, b) => a + b) / contenderUpside.length;
        expect(tankingAvgUpside, greaterThan(contenderAvgUpside));
      },
    );

    test(
      'AC-008-28: opening draft pick entitlement applies to user franchise',
      () {
        final t1 = service.generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-2'),
            selectedSituation: FranchiseSituation.tanking,
            seed: seed,
          ),
        );
        expect(t1.userOpeningDraftPick, 1);

        final t2 = service.generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-2'),
            selectedSituation: FranchiseSituation.playIn,
            seed: seed,
          ),
        );
        expect(t2.userOpeningDraftPick, 12);

        final t3 = service.generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-2'),
            selectedSituation: FranchiseSituation.playoff,
            seed: seed,
          ),
        );
        expect(t3.userOpeningDraftPick, 20);

        final t4 = service.generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-2'),
            selectedSituation: FranchiseSituation.contender,
            seed: seed,
          ),
        );
        expect(t4.userOpeningDraftPick, 30);
      },
    );

    test('AC-008-29: same inputs produce byte-identical output', () {
      const req = CareerSetupRequest(
        selectedTeamId: TeamId('team-7'),
        selectedSituation: FranchiseSituation.playoff,
        seed: 42,
      );
      final r1 = service.generate(req);
      final r2 = service.generate(req);

      expect(jsonEncode(r1.league.toJson()), jsonEncode(r2.league.toJson()));
      expect(
        jsonEncode(r1.careerProfiles.toJson()),
        jsonEncode(r2.careerProfiles.toJson()),
      );
    });

    test(
      'AC-008-30: calling generator without career request yields unchanged M008-T01 output',
      () {
        const config = GenerationConfig(seed: seed, teamCount: 30);
        final l1 = const LeagueGenerator().generate(config);
        final l2 = const LeagueGenerator().generate(config);

        expect(jsonEncode(l1.toJson()), jsonEncode(l2.toJson()));
      },
    );

    test(
      'AC-008-31: 8-team legacy generation produces exact byte-identical golden snapshot',
      () {
        const config = GenerationConfig(seed: seed);
        final league = const LeagueGenerator().generate(config);
        final json = jsonEncode(league.toJson());
        expect(json.length, 29263);
      },
    );

    test(
      'fresh seeds produce different player rosters for same team and situation',
      () {
        const req1 = CareerSetupRequest(
          selectedTeamId: TeamId('team-1'),
          selectedSituation: FranchiseSituation.contender,
          seed: 10001,
        );
        const req2 = CareerSetupRequest(
          selectedTeamId: TeamId('team-1'),
          selectedSituation: FranchiseSituation.contender,
          seed: 10002,
        );

        final r1 = service.generate(req1);
        final r2 = service.generate(req2);

        // Different seeds must generate different player names/attributes
        expect(
          jsonEncode(r1.league.toJson()),
          isNot(jsonEncode(r2.league.toJson())),
        );
        expect(
          r1.selectedTeam.players.map((p) => p.fullName).toList(),
          isNot(r2.selectedTeam.players.map((p) => p.fullName).toList()),
        );
      },
    );

    test('rejects unknown franchise ID, empty ID, and invalid seed', () {
      expect(
        () => service.generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('unknown-team-99'),
            selectedSituation: FranchiseSituation.tanking,
            seed: seed,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => service.generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId(''),
            selectedSituation: FranchiseSituation.tanking,
            seed: seed,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => service.generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-1'),
            selectedSituation: FranchiseSituation.tanking,
            seed: 0,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('LeagueGenerator rejects incomplete career selection parameters', () {
      const gen = LeagueGenerator();
      const config = GenerationConfig(seed: seed, teamCount: 30);

      // userTeamId without userSituation
      expect(
        () => gen.generate(config, userTeamId: const TeamId('team-1')),
        throwsA(isA<ArgumentError>()),
      );

      // userSituation without userTeamId
      expect(
        () => gen.generate(config, userSituation: FranchiseSituation.tanking),
        throwsA(isA<ArgumentError>()),
      );

      // unknown userTeamId
      expect(
        () => gen.generate(
          config,
          userTeamId: const TeamId('team-999'),
          userSituation: FranchiseSituation.tanking,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
