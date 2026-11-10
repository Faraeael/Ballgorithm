import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _generator = LeagueGenerator();
const _config30 = GenerationConfig(seed: 20261028, teamCount: 30);

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

double _averageStarterRating(Team team) {
  var total = 0;
  var count = 0;
  for (var p = 0; p < 5; p++) {
    for (final rating in team.players[p].attributes.asMap.values) {
      total += rating;
      count++;
    }
  }
  return total / count;
}

void main() {
  group('M008-T01: 30-Team League Generation', () {
    test('AC-008-01: generates exactly 30 unique teams', () {
      final league = _generator.generate(_config30);
      expect(league.teams.length, 30);

      final teamIds = {for (final t in league.teams) t.id.value};
      expect(teamIds.length, 30);

      final abbreviations = {for (final t in league.teams) t.abbreviation};
      expect(abbreviations.length, 30);
    });

    test(
      'AC-008-02: generates valid 12-player rosters covering all 5 positions',
      () {
        final league = _generator.generate(_config30);
        final validation = LeagueValidator.validate(league);
        expect(
          validation.isValid,
          isTrue,
          reason: validation.issues.toString(),
        );

        for (final team in league.teams) {
          expect(team.players.length, 12);
          final positions = {for (final p in team.players) p.position};
          expect(positions.length, 5);
          expect(positions, containsAll(Position.values));
        }
      },
    );

    test('AC-008-03: all 360 player IDs and full names are unique', () {
      final league = _generator.generate(_config30);
      final playerIds = <String>{};
      final playerNames = <String>{};

      for (final team in league.teams) {
        for (final player in team.players) {
          expect(playerIds.add(player.id.value), isTrue);
          expect(playerNames.add(player.fullName), isTrue);
        }
      }

      expect(playerIds.length, 360);
      expect(playerNames.length, 360);
    });

    test(
      'AC-008-04: all 4 franchise situations are represented with correct counts',
      () {
        final league = _generator.generate(_config30);
        final counts = <FranchiseSituation, int>{};

        for (final team in league.teams) {
          expect(team.situation, isNotNull);
          counts[team.situation!] = (counts[team.situation!] ?? 0) + 1;
        }

        expect(counts[FranchiseSituation.contender], 5);
        expect(counts[FranchiseSituation.playoff], 9);
        expect(counts[FranchiseSituation.playIn], 9);
        expect(counts[FranchiseSituation.tanking], 7);
        expect(counts.values.fold(0, (a, b) => a + b), 30);
      },
    );

    test(
      'AC-008-05: roster ratings strictly stratify across competitive tiers',
      () {
        final league = _generator.generate(_config30);

        final tierTeamAverages = <FranchiseSituation, List<double>>{
          for (final s in FranchiseSituation.values) s: [],
        };
        final tierStarterAverages = <FranchiseSituation, List<double>>{
          for (final s in FranchiseSituation.values) s: [],
        };

        for (final team in league.teams) {
          tierTeamAverages[team.situation!]!.add(_averageTeamRating(team));
          tierStarterAverages[team.situation!]!.add(
            _averageStarterRating(team),
          );
        }

        double mean(List<double> list) =>
            list.fold(0.0, (a, b) => a + b) / list.length;

        final contenderMean = mean(
          tierTeamAverages[FranchiseSituation.contender]!,
        );
        final playoffMean = mean(tierTeamAverages[FranchiseSituation.playoff]!);
        final playInMean = mean(tierTeamAverages[FranchiseSituation.playIn]!);
        final tankingMean = mean(tierTeamAverages[FranchiseSituation.tanking]!);

        // Strict tier hierarchy: Contender > Playoff > Play-In > Tanking
        expect(contenderMean, greaterThan(playoffMean));
        expect(playoffMean, greaterThan(playInMean));
        expect(playInMean, greaterThan(tankingMean));

        // Starters strict hierarchy
        final contenderStarterMean = mean(
          tierStarterAverages[FranchiseSituation.contender]!,
        );
        final playoffStarterMean = mean(
          tierStarterAverages[FranchiseSituation.playoff]!,
        );
        final playInStarterMean = mean(
          tierStarterAverages[FranchiseSituation.playIn]!,
        );
        final tankingStarterMean = mean(
          tierStarterAverages[FranchiseSituation.tanking]!,
        );

        expect(contenderStarterMean, greaterThan(playoffStarterMean));
        expect(playoffStarterMean, greaterThan(playInStarterMean));
        expect(playInStarterMean, greaterThan(tankingStarterMean));

        // Realistic basketball bounds
        expect(contenderMean, inInclusiveRange(58.0, 68.0));
        expect(tankingMean, inInclusiveRange(38.0, 48.0));
      },
    );

    test(
      'AC-008-06: teams within the same tier exhibit attribute variance',
      () {
        final league = _generator.generate(_config30);

        for (final situation in FranchiseSituation.values) {
          final teamsInTier = league.teams
              .where((t) => t.situation == situation)
              .toList();
          final starterThreePointAverages = [
            for (final t in teamsInTier)
              t.players
                      .take(5)
                      .map((p) => p.attributes.threePoint)
                      .reduce((a, b) => a + b) /
                  5,
          ];

          // Ensure non-zero variance across teams in the same tier
          final min3P = starterThreePointAverages.reduce(
            (a, b) => a < b ? a : b,
          );
          final max3P = starterThreePointAverages.reduce(
            (a, b) => a > b ? a : b,
          );
          expect(
            max3P - min3P,
            greaterThan(2.0),
            reason: 'Tier $situation should have style variance',
          );
        }
      },
    );

    test('AC-008-07: same seed yields byte-identical 30-team snapshot', () {
      final league1 = _generator.generate(_config30);
      final league2 = _generator.generate(_config30);

      expect(jsonEncode(league1.toJson()), jsonEncode(league2.toJson()));
    });

    test('AC-008-08: 30-team league round-trips through JSON cleanly', () {
      final league = _generator.generate(_config30);
      final encoded = jsonEncode(league.toJson());
      final decoded = League.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );

      expect(jsonEncode(decoded.toJson()), encoded);
      expect(decoded.teams.length, 30);
      for (var t = 0; t < 30; t++) {
        expect(decoded.teams[t].situation, league.teams[t].situation);
      }
    });

    test(
      'AC-008-09: GenerationConfig validates 30 teams and rejects out of range',
      () {
        expect(
          const GenerationConfig(teamCount: 30).validate().isValid,
          isTrue,
        );
        expect(const GenerationConfig(teamCount: 8).validate().isValid, isTrue);

        for (final invalidCount in [0, 9, 29, 31]) {
          final result = GenerationConfig(
            seed: 1,
            teamCount: invalidCount,
          ).validate();
          expect(
            result.codes,
            contains(ValidationCode.teamCountOutOfRange),
            reason: 'teamCount=$invalidCount must be out of range',
          );
        }
      },
    );

    test(
      'AC-008-10: franchise situations define correct draft pick contracts',
      () {
        expect(FranchiseSituation.tanking.targetDraftPick, 1);
        expect(FranchiseSituation.playIn.targetDraftPick, 12);
        expect(FranchiseSituation.playoff.targetDraftPick, 20);
        expect(FranchiseSituation.contender.targetDraftPick, 30);
      },
    );
  });
}
