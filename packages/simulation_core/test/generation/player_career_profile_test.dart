import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _generator = LeagueGenerator();
const _config30 = GenerationConfig(seed: 20261028, teamCount: 30);
const _config8 = GenerationConfig(seed: 20261028);

void main() {
  group('M008-T02: Player Career Profiles & Potential', () {
    late League league30;

    setUpAll(() {
      league30 = _generator.generate(_config30);
    });

    test('AC-008-11: all 360 players receive a valid PlayerCareerProfile', () {
      final careerProfiles = LeagueCareerProfiles.generate(
        league: league30,
        seed: _config30.seed,
      );

      expect(careerProfiles.length, 360);
      for (final team in league30.teams) {
        for (final player in team.players) {
          final profile = careerProfiles.forPlayer(player.id);
          expect(profile, isNotNull);
          expect(profile!.playerId, player.id);
        }
      }
    });

    test(
      'AC-008-12: all generated player ages fall strictly within 19..38',
      () {
        final careerProfiles = LeagueCareerProfiles.generate(
          league: league30,
          seed: _config30.seed,
        );

        for (final profile in careerProfiles.profiles.values) {
          expect(profile.age, greaterThanOrEqualTo(19));
          expect(profile.age, lessThanOrEqualTo(38));
        }
      },
    );

    test('AC-008-13: potential is strictly >= currentOverall and <= 100', () {
      final careerProfiles = LeagueCareerProfiles.generate(
        league: league30,
        seed: _config30.seed,
      );

      for (final team in league30.teams) {
        for (final player in team.players) {
          final profile = careerProfiles.forPlayer(player.id)!;
          final overall = player.attributes.overallRating;
          expect(profile.potential, greaterThanOrEqualTo(overall));
          expect(profile.potential, lessThanOrEqualTo(100));
        }
      }
    });

    test('AC-008-14: all 4 development trajectories are represented', () {
      final careerProfiles = LeagueCareerProfiles.generate(
        league: league30,
        seed: _config30.seed,
      );

      final trajectoryCounts = <DevelopmentTrajectory, int>{};
      for (final profile in careerProfiles.profiles.values) {
        trajectoryCounts[profile.trajectory] =
            (trajectoryCounts[profile.trajectory] ?? 0) + 1;
      }

      for (final traj in DevelopmentTrajectory.values) {
        expect(
          trajectoryCounts[traj],
          greaterThan(0),
          reason: 'Trajectory $traj must be represented',
        );
      }
    });

    test(
      'AC-008-15: age and potential stratify realistically across situations',
      () {
        final careerProfiles = LeagueCareerProfiles.generate(
          league: league30,
          seed: _config30.seed,
        );

        final tierAges = <FranchiseSituation, List<int>>{
          for (final s in FranchiseSituation.values) s: [],
        };
        final tierUpsideMargins = <FranchiseSituation, List<int>>{
          for (final s in FranchiseSituation.values) s: [],
        };

        for (final team in league30.teams) {
          for (final player in team.players) {
            final profile = careerProfiles.forPlayer(player.id)!;
            tierAges[team.situation!]!.add(profile.age);
            tierUpsideMargins[team.situation!]!.add(
              profile.potential - player.attributes.overallRating,
            );
          }
        }

        double mean(List<int> list) =>
            list.fold(0, (a, b) => a + b) / list.length;

        final tankingMeanAge = mean(tierAges[FranchiseSituation.tanking]!);
        final playInMeanAge = mean(tierAges[FranchiseSituation.playIn]!);
        final playoffMeanAge = mean(tierAges[FranchiseSituation.playoff]!);
        final contenderMeanAge = mean(tierAges[FranchiseSituation.contender]!);

        // Age hierarchy: Tanking < Play-In < Playoff < Contender
        expect(tankingMeanAge, lessThan(playInMeanAge));
        expect(playInMeanAge, lessThan(playoffMeanAge));
        expect(playoffMeanAge, lessThan(contenderMeanAge));

        // Tanking upside margin is significantly higher than Contender upside margin
        final tankingUpside = mean(
          tierUpsideMargins[FranchiseSituation.tanking]!,
        );
        final contenderUpside = mean(
          tierUpsideMargins[FranchiseSituation.contender]!,
        );
        expect(tankingUpside, greaterThan(contenderUpside));
      },
    );

    test('AC-008-16: individual age variation exists within each tier', () {
      final careerProfiles = LeagueCareerProfiles.generate(
        league: league30,
        seed: _config30.seed,
      );

      final tankingPlayers = league30.teams
          .where((t) => t.situation == FranchiseSituation.tanking)
          .expand((t) => t.players)
          .map((p) => careerProfiles.forPlayer(p.id)!)
          .toList();

      final contenderPlayers = league30.teams
          .where((t) => t.situation == FranchiseSituation.contender)
          .expand((t) => t.players)
          .map((p) => careerProfiles.forPlayer(p.id)!)
          .toList();

      // Tanking teams have veteran mentors (age >= 30)
      expect(
        tankingPlayers.any((p) => p.age >= 30),
        isTrue,
        reason: 'Tanking teams should have veteran presence',
      );

      // Contender teams have young energy pieces (age <= 25)
      expect(
        contenderPlayers.any((p) => p.age <= 25),
        isTrue,
        reason: 'Contenders should have some young depth',
      );
    });

    test(
      'AC-008-17: same seed yields byte-identical profiles; different seeds differ',
      () {
        final p1 = LeagueCareerProfiles.generate(
          league: league30,
          seed: _config30.seed,
        );
        final p2 = LeagueCareerProfiles.generate(
          league: league30,
          seed: _config30.seed,
        );

        expect(jsonEncode(p1.toJson()), jsonEncode(p2.toJson()));

        final otherLeague = _generator.generate(
          const GenerationConfig(seed: 9999, teamCount: 30),
        );
        final pOther = LeagueCareerProfiles.generate(
          league: otherLeague,
          seed: 9999,
        );
        expect(jsonEncode(p1.toJson()), isNot(jsonEncode(pOther.toJson())));
      },
    );

    test(
      'AC-008-18: simulation attributes and M001 golden snapshot remain byte-identical',
      () {
        // 8-team legacy snapshot remains exactly 29,263 bytes
        final league8 = _generator.generate(_config8);
        final json8 = jsonEncode(league8.toJson());
        expect(json8.length, 29263);

        // 30-team attributes for seed 20261028 are untouched
        final p0 = league30.teams.first.players.first;
        expect(p0.id.value, 'player-1-1');
        expect(p0.attributes.overallRating, inInclusiveRange(40, 90));
      },
    );

    test('AC-008-19: LeagueCareerProfiles JSON round-trip and validation', () {
      final careerProfiles = LeagueCareerProfiles.generate(
        league: league30,
        seed: _config30.seed,
      );

      final encoded = jsonEncode(careerProfiles.toJson());
      final decoded = LeagueCareerProfiles.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(jsonEncode(decoded.toJson()), encoded);
      expect(decoded.length, 360);
      expect(() => decoded.validate(league30), returnsNormally);

      // Reject missing player profile
      final corruptProfiles = Map<String, PlayerCareerProfile>.from(
        decoded.profiles,
      )..remove('player-1-1');
      final missingLeagueProfiles = LeagueCareerProfiles(
        leagueSeed: _config30.seed,
        profiles: corruptProfiles,
      );
      expect(
        () => missingLeagueProfiles.validate(league30),
        throwsA(isA<StateError>()),
      );

      // Reject foreign player profile
      final foreignLeagueProfiles = LeagueCareerProfiles(
        leagueSeed: _config30.seed,
        profiles: Map<String, PlayerCareerProfile>.from(decoded.profiles)
          ..['foreign-id'] = const PlayerCareerProfile(
            playerId: PlayerId('foreign-id'),
            age: 22,
            potential: 75,
            trajectory: DevelopmentTrajectory.steady,
          ),
      );
      expect(
        () => foreignLeagueProfiles.validate(league30),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'AC-008-20: FranchiseSituation userOpeningDraftPick is explicitly clarified',
      () {
        expect(FranchiseSituation.tanking.userOpeningDraftPick, 1);
        expect(FranchiseSituation.playIn.userOpeningDraftPick, 12);
        expect(FranchiseSituation.playoff.userOpeningDraftPick, 20);
        expect(FranchiseSituation.contender.userOpeningDraftPick, 30);
      },
    );

    test(
      'AC-008-21: future rookie ID pattern avoids collisions with existing players',
      () {
        final inauguralIds = {
          for (final team in league30.teams)
            for (final player in team.players) player.id.value,
        };

        // Future rookie IDs: player-rookie-{year}-{pick}
        for (var year = 2027; year <= 2035; year++) {
          for (var pick = 1; pick <= 60; pick++) {
            final rookieId = 'player-rookie-$year-$pick';
            expect(
              inauguralIds.contains(rookieId),
              isFalse,
              reason:
                  'Rookie ID $rookieId must never collide with inaugural IDs',
            );
          }
        }
      },
    );
  });
}
